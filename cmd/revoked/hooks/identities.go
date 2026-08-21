package hooks

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// BindIdentitiesHooks issues a server-signed certificate for each new identity
// and anchors it to the server's trust chain, keeps at most one primary identity
// per user and workspace, and never stores or returns a private key.
func BindIdentitiesHooks(app core.App, root *server.RootKey) {
	app.OnRecordCreateRequest(util.Coll.Identities).BindFunc(func(e *core.RecordRequestEvent) error {
		clientPubKeyStr := e.Record.GetString(util.Fields.Identity.PublicKey)
		if clientPubKeyStr == "" {
			return errors.New("missing publicKey from client")
		}

		block, _ := pem.Decode([]byte(clientPubKeyStr))
		if block == nil {
			return errors.New("failed to decode client public key")
		}

		clientPubKey, err := x509.ParsePKIXPublicKey(block.Bytes)
		if err != nil {
			return err
		}

		name := e.Record.GetString(util.Fields.Identity.Name)
		if name == "" {
			name = "Anonymous Identity"
		}

		serverCert, err := util.GetServerCertificate()
		if err != nil {
			return err
		}

		serverPrivBlock, _ := pem.Decode([]byte(serverCert.PrivateKey))
		if serverPrivBlock == nil {
			return errors.New("failed to decode server private key")
		}
		serverPrivKey, err := x509.ParsePKCS1PrivateKey(serverPrivBlock.Bytes)
		if err != nil {
			return err
		}

		serverCertBlock, _ := pem.Decode([]byte(serverCert.Certificate))
		if serverCertBlock == nil {
			return errors.New("failed to decode server certificate")
		}
		serverX509, err := x509.ParseCertificate(serverCertBlock.Bytes)
		if err != nil {
			return err
		}

		serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
		if err != nil {
			return err
		}

		template := x509.Certificate{
			SerialNumber: serialNumber,
			Subject: pkix.Name{
				Organization: []string{"Revoked"},
				CommonName:   name,
			},
			NotBefore:             time.Now(),
			NotAfter:              time.Now().AddDate(10, 0, 0),
			KeyUsage:              x509.KeyUsageDigitalSignature,
			BasicConstraintsValid: true,
			IsCA:                  false,
		}

		certBytes, err := x509.CreateCertificate(rand.Reader, &template, serverX509, clientPubKey, serverPrivKey)
		if err != nil {
			return err
		}

		certPEM := pem.EncodeToMemory(&pem.Block{
			Type:  "CERTIFICATE",
			Bytes: certBytes,
		})

		certPEMStr := string(certPEM)

		h := sha256.New()
		h.Write([]byte(certPEMStr))
		fingerprintBytes := h.Sum(nil)
		fingerprint := fmt.Sprintf("%x", fingerprintBytes)

		e.Record.Set(util.Fields.Identity.Certificate, certPEMStr)
		e.Record.Set(util.Fields.Identity.PrivateKey, "")
		e.Record.Set(util.Fields.Identity.Fingerprint, fingerprint)

		// Signing the fingerprint with the root key and recording the issuing
		// domain is what lets a remote verifier trace identity -> root key -> DNS
		// TXT proof of domain.
		parentSig, err := root.Sign([]byte(fingerprint))
		if err != nil {
			return err
		}
		e.Record.Set(util.Fields.Identity.ParentSignature, hex.EncodeToString(parentSig))
		e.Record.Set(util.Fields.Identity.DomainAtIssue, root.Domain())

		// Set here rather than trusted from the client, so no caller can mint an
		// identity that is born revoked or carries a backdated revocation.
		e.Record.Set(util.Fields.Identity.Status, util.StatusActive)
		e.Record.Set(util.Fields.Identity.RevokedAt, nil)
		e.Record.Set(util.Fields.Identity.RevokedReason, "")

		if err := demotePrimaryIdentities(app, e.Record, ""); err != nil {
			return err
		}

		return e.Next()
	})

	app.OnRecordUpdateRequest(util.Coll.Identities).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := applyRevocationTransition(app, e.Record); err != nil {
			return err
		}
		if err := demotePrimaryIdentities(app, e.Record, e.Record.Id); err != nil {
			return err
		}
		return e.Next()
	})

	// The tombstone must be exactly as durable as the deletion, so it is written
	// inside the same transaction: OnRecordDelete rather than the after-success
	// hook, whose write would survive a rolled-back delete and revoke an identity
	// that still exists.
	app.OnRecordDelete(util.Coll.Identities).BindFunc(func(e *core.RecordEvent) error {
		fingerprint := e.Record.GetString(util.Fields.Identity.Fingerprint)
		domain := e.Record.GetString(util.Fields.Identity.DomainAtIssue)
		reason := e.Record.GetString(util.Fields.Identity.RevokedReason)

		if err := e.Next(); err != nil {
			return err
		}
		return services.WriteIdentityTombstone(e.App, fingerprint, domain, reason)
	})

	// Defense in depth: the private key is stored empty already.
	app.OnRecordViewRequest(util.Coll.Identities).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		e.Record.Set(util.Fields.Identity.PrivateKey, "")
		return nil
	})

	app.OnRecordsListRequest(util.Coll.Identities).BindFunc(func(e *core.RecordsListRequestEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		for _, record := range e.Records {
			record.Set(util.Fields.Identity.PrivateKey, "")
		}
		return nil
	})
}

// applyRevocationTransition keeps the status monotonic: an identity may go from
// active to revoked, never back.
//
// Reinstatement is not a missing feature. A revocation is a statement already
// published to verifiers that may have cached it, and if the key was revoked
// because it leaked, whoever took it is still holding it. Rotation is a new
// identity, not a resurrected one.
func applyRevocationTransition(app core.App, rec *core.Record) error {
	original, err := app.FindRecordById(util.Coll.Identities, rec.Id)
	if err != nil || original == nil {
		return nil
	}

	wasActive := services.IdentityIsActive(original)
	nowActive := services.IdentityIsActive(rec)

	if !wasActive {
		// Every revocation field is pinned back to what was recorded, so a
		// caller cannot rewrite the reason or backdate the timestamp either.
		rec.Set(util.Fields.Identity.Status, util.StatusRevoked)
		rec.Set(util.Fields.Identity.RevokedAt, original.GetDateTime(util.Fields.Identity.RevokedAt))
		rec.Set(util.Fields.Identity.RevokedReason, original.GetString(util.Fields.Identity.RevokedReason))
		rec.Set(util.Fields.Identity.IsPrimary, false)
		return nil
	}

	if !nowActive {
		reason := rec.GetString(util.Fields.Identity.RevokedReason)
		if reason == "" {
			reason = util.RevocationManual
		}
		rec.Set(util.Fields.Identity.RevokedAt, types.NowDateTime())
		rec.Set(util.Fields.Identity.RevokedReason, reason)
		rec.Set(util.Fields.Identity.IsPrimary, false)
	}

	return nil
}

// demotePrimaryIdentities clears isPrimary on the user's other identities in the
// same workspace, so at most one stays primary; exceptId is the record being
// saved (empty on create). Its error must be surfaced — a swallowed failure
// leaves two primaries behind.
func demotePrimaryIdentities(app core.App, rec *core.Record, exceptId string) error {
	if !rec.GetBool(util.Fields.Identity.IsPrimary) {
		return nil
	}
	userId := rec.GetString(util.Fields.Identity.User)
	workspaceId := rec.GetString(util.Fields.Identity.Workspace)
	if userId == "" || workspaceId == "" {
		return nil
	}

	match := dbx.HashExp{
		util.Fields.Identity.User:      userId,
		util.Fields.Identity.Workspace: workspaceId,
		util.Fields.Identity.IsPrimary: true,
	}
	var where dbx.Expression = match
	if exceptId != "" {
		where = dbx.And(match, dbx.Not(dbx.HashExp{"id": exceptId}))
	}

	_, err := app.DB().
		Update(util.Coll.Identities, dbx.Params{util.Fields.Identity.IsPrimary: false}, where).
		Execute()
	return err
}
