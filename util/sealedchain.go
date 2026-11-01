package util

import (
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"math/big"
)

// ErrSealedChainInvalid is an entry that does not follow from the list before it.
var ErrSealedChainInvalid = errors.New("sealed device entry is not valid")

// MaxSealedLiveEntries caps a person's device list. A list that grows without
// limit can be made too large to clean up: removing a device takes one entry
// for everything it added, and every new key is wrapped to every entry.
const MaxSealedLiveEntries = 32

// SealedContext is the app's Sealing.context: strings and byte slices are
// length-prefixed and ints are a fixed eight bytes, so no two different contexts
// encode alike.
func SealedContext(label string, parts ...any) []byte {
	var out []byte
	addBytes := func(b []byte) {
		out = binary.BigEndian.AppendUint32(out, uint32(len(b)))
		out = append(out, b...)
	}
	addBytes([]byte(label))
	for _, part := range parts {
		switch p := part.(type) {
		case string:
			addBytes([]byte(p))
		case []byte:
			addBytes(p)
		case int:
			out = binary.BigEndian.AppendUint64(out, uint64(p))
		default:
			panic("unsupported sealed context part")
		}
	}
	return out
}

// VerifySealedSignature checks a raw low-s ECDSA P-256 signature over SHA-256,
// the only form the app produces.
func VerifySealedSignature(publicKey, message, signature []byte) bool {
	if len(signature) != 64 || !ValidSealedPublicKey(publicKey) {
		return false
	}
	curve := elliptic.P256()
	r := new(big.Int).SetBytes(signature[:32])
	s := new(big.Int).SetBytes(signature[32:])
	if s.Cmp(new(big.Int).Rsh(curve.Params().N, 1)) > 0 {
		return false
	}
	x, y := elliptic.Unmarshal(curve, publicKey) //nolint:staticcheck // ecdsa.Verify needs the coordinates.
	if x == nil {
		return false
	}
	digest := sha256.Sum256(message)
	return ecdsa.Verify(&ecdsa.PublicKey{Curve: curve, X: x, Y: y}, digest[:], r, s)
}

// ValidSealedPublicKey reports whether key is an on-curve uncompressed P-256 point.
func ValidSealedPublicKey(key []byte) bool {
	if len(key) != 65 {
		return false
	}
	_, err := ecdh.P256().NewPublicKey(key)
	return err == nil
}

// SealedChainEntry is one entry on a person's signed device list.
type SealedChainEntry struct {
	User             string
	Seq              int
	Action           string
	Kind             string
	Label            string
	HpkePublicKey    []byte
	SigningPublicKey []byte
	TargetSeq        int
	PreviousHash     []byte
	SignerSeq        int
	AnchorSignature  []byte
	Signature        []byte
}

// Payload is what the entry's signature covers.
func (e SealedChainEntry) Payload() []byte {
	return SealedContext("revoked-device-chain-v1",
		e.User, e.Seq, e.Action, e.Kind, e.Label, e.HpkePublicKey, e.SigningPublicKey,
		e.TargetSeq, e.PreviousHash, e.SignerSeq, e.AnchorSignature)
}

// Hash is what the next entry points back at.
func (e SealedChainEntry) Hash() []byte {
	sum := sha256.Sum256(append(e.Payload(), e.Signature...))
	return sum[:]
}

// SealedRecoveryAnchorPayload is what a recovery key signs when it joins a list.
func SealedRecoveryAnchorPayload(user string, rootHash []byte) []byte {
	return SealedContext("revoked-recovery-anchor-v1", user, rootHash)
}

// SealedWrapPayload is what a device signs when it hands over a workspace key.
func SealedWrapPayload(workspace string, epoch int, recipientHpkeKey []byte, wrap string, chainSeq int) []byte {
	return SealedContext("revoked-wrap-signature-v1", workspace, epoch, recipientHpkeKey, wrap, chainSeq)
}

// SealedUnsealPayload is what a device signs to store a sealed record in plaintext.
func SealedUnsealPayload(user, record string, expectedVersion int, value string) []byte {
	return SealedContext("revoked-unseal-v1", user, record, expectedVersion, value)
}

// SealedChain is a device list being checked, entry by entry.
//
// Clients check all of this themselves and trust nothing the server says about
// it. The server checks it too so that a stolen session, which holds no device
// key, cannot post an entry at all: removals delete the only copies of keys, and
// one bad entry would otherwise stop every device from changing the list.
type SealedChain struct {
	entries []SealedChainEntry
	removed map[int]bool
}

// Load adds an entry already checked when it was first appended.
func (c *SealedChain) Load(e SealedChainEntry) {
	c.entries = append(c.entries, e)
	if c.removed == nil {
		c.removed = map[int]bool{}
	}
	if e.Action == SealedActionRemove {
		c.removed[e.TargetSeq] = true
	}
}

// Append checks an entry against the list so far and adds it. The rules match
// VerifiedChain in the app.
func (c *SealedChain) Append(e SealedChainEntry) error {
	if !c.acceptable(e) {
		return ErrSealedChainInvalid
	}
	c.Load(e)
	return nil
}

func (c *SealedChain) acceptable(e SealedChainEntry) bool {
	if e.Seq != c.NextSeq() || string(e.PreviousHash) != string(c.HeadHash()) {
		return false
	}
	if e.Action == SealedActionAdd &&
		(!ValidSealedPublicKey(e.HpkePublicKey) || !ValidSealedPublicKey(e.SigningPublicKey)) {
		return false
	}
	if len(c.entries) == 0 {
		return e.Action == SealedActionAdd && e.Kind == SealedKindDevice && e.SignerSeq == e.Seq &&
			VerifySealedSignature(e.SigningPublicKey, e.Payload(), e.Signature)
	}
	if !c.IsLive(e.SignerSeq) {
		return false
	}
	if !VerifySealedSignature(c.Entry(e.SignerSeq).SigningPublicKey, e.Payload(), e.Signature) {
		return false
	}
	switch e.Action {
	case SealedActionRemove:
		return c.IsLive(e.TargetSeq)
	case SealedActionAdd:
		if len(c.Live()) >= MaxSealedLiveEntries {
			return false
		}
		if e.Kind == SealedKindDevice {
			return true
		}
		return e.Kind == SealedKindRecovery && c.LiveRecovery() == nil &&
			VerifySealedSignature(e.SigningPublicKey,
				SealedRecoveryAnchorPayload(e.User, c.entries[0].Hash()), e.AnchorSignature)
	}
	return false
}

// NextSeq is the seq the next entry must carry.
func (c *SealedChain) NextSeq() int { return len(c.entries) + 1 }

// HeadSeq is the newest entry's seq.
func (c *SealedChain) HeadSeq() int { return len(c.entries) }

// HeadHash is the newest entry's hash, or nothing on an empty list.
func (c *SealedChain) HeadHash() []byte {
	if len(c.entries) == 0 {
		return nil
	}
	return c.entries[len(c.entries)-1].Hash()
}

// Entry returns the entry at seq, or nil.
func (c *SealedChain) Entry(seq int) *SealedChainEntry {
	if seq < 1 || seq > len(c.entries) {
		return nil
	}
	return &c.entries[seq-1]
}

// IsLive reports whether seq names an added entry nothing has removed.
func (c *SealedChain) IsLive(seq int) bool {
	e := c.Entry(seq)
	return e != nil && e.Action == SealedActionAdd && !c.removed[seq]
}

// Live lists the seqs of every live entry.
func (c *SealedChain) Live() []int {
	out := []int{}
	for _, e := range c.entries {
		if c.IsLive(e.Seq) {
			out = append(out, e.Seq)
		}
	}
	return out
}

// LiveRecovery returns the live recovery entry, or nil.
func (c *SealedChain) LiveRecovery() *SealedChainEntry {
	for _, seq := range c.Live() {
		if e := c.Entry(seq); e.Kind == SealedKindRecovery {
			return e
		}
	}
	return nil
}
