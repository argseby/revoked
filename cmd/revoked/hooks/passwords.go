package hooks

import (
	"revoked/util"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// PasswordMask stands in for a stored bcrypt hash in API responses. The hash
// itself never leaves the server, but whether a gate exists is not a secret and
// the owner UI needs it.
const PasswordMask = "********"

// resolvePasswordWrite decides what an incoming write means for a gate.
//
// The mask is what a client last read, so sending it back means "unchanged" —
// the read-modify-write cycle that every REST client performs. Storing it
// verbatim would replace the hash with a string bcrypt can never match, locking
// every recipient out of the link permanently, with nothing in the UI to
// explain why. An empty value is the only way to remove a gate.
func resolvePasswordWrite(rec *core.Record, field string) {
	pw := rec.GetString(field)
	if pw == PasswordMask {
		rec.Set(field, rec.Original().GetString(field))
		return
	}
	if pw == "" || isBcryptHash(pw) {
		return
	}
	hash, err := util.HashPassword(pw)
	if err != nil {
		return
	}
	rec.Set(field, hash)
}

// maskStoredPassword replaces a stored hash with [PasswordMask] on the way out,
// leaving an unset gate empty so clients can tell the two apart.
func maskStoredPassword(rec *core.Record, field string) {
	if rec != nil && strings.TrimSpace(rec.GetString(field)) != "" {
		rec.Set(field, PasswordMask)
	}
}
