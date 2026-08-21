package util

import "github.com/pocketbase/pocketbase/tools/types"

// AuditRedacted replaces secret material in audit snapshots. A constant marker
// rather than a digest: a digest of a low-entropy value (a gate password, a
// short record value) is an offline guessing oracle.
const AuditRedacted = "[redacted]"

// AuditSecretFields catalogues, per collection, the fields whose values must
// never survive into an audit snapshot. Every new secret-bearing field belongs
// here — the audit hook snapshots records verbatim otherwise.
//
// The password fields are listed even though they are stored bcrypt-hashed: an
// update snapshot is taken from the request-bound record, so it can hold the
// submitted plaintext before the hashing hook has run. The token hashes are
// preimage-resistant and never authenticate anything by themselves, but an
// audit row has no use for credential material in any form.
var AuditSecretFields = map[string][]string{
	// A filename is content: "kuendigung_arbeitsvertrag.pdf" tells a reader of
	// the audit row what the file is without ever opening it.
	Coll.Records: {
		Fields.Record.Value,
		Fields.Record.File,
		Fields.Record.Filename,
		Fields.Record.HashSalt,
	},
	Coll.Links:      {Fields.Link.Password, Fields.Link.Data},
	Coll.Requests:   {Fields.Request.Password},
	Coll.ApiKeys:    {Fields.ApiKey.Token},
	Coll.Identities: {Fields.Identity.PrivateKey},
	Coll.Invites:    {Fields.Invite.TokenHash},
	Coll.Handshakes: {Fields.Handshake.TokenHash},
}

// RedactAuditData returns data with the collection's secret fields replaced by
// [AuditRedacted]. The input map is not modified. Empty values stay empty, so a
// snapshot still shows *whether* a secret was set, never what it was.
func RedactAuditData(collection string, data map[string]any) map[string]any {
	if data == nil {
		return nil
	}
	secrets, ok := AuditSecretFields[collection]
	if !ok {
		return data
	}
	out := make(map[string]any, len(data))
	for k, v := range data {
		out[k] = v
	}
	for _, field := range secrets {
		if v, present := out[field]; present && !emptyAuditValue(v) {
			out[field] = AuditRedacted
		}
	}
	return out
}

// emptyAuditValue reports whether an exported field value carries nothing worth
// redacting, across the shapes a snapshot can hold it in: PublicExport gives
// strings and types.JSONRaw, the backfill migration gives re-parsed JSON.
func emptyAuditValue(v any) bool {
	switch t := v.(type) {
	case nil:
		return true
	case string:
		return t == ""
	case types.JSONRaw:
		s := string(t)
		return len(t) == 0 || s == "null" || s == `""` || s == "{}" || s == "[]"
	case []any:
		return len(t) == 0
	case map[string]any:
		return len(t) == 0
	}
	return false
}
