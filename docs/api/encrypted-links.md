# Encrypted links and saved keys

An encrypted share address is `https://host/s/slug#k=key` (or
`revoked://s/host/slug#k=key`). The key is 32 bytes, encoded as unpadded
base64url. The fragment never reaches the share server. Password and other
access checks still run before the public resolve returns ciphertext.

`POST /api/public/links/{slug}` returns `sealed: true`, `sealedValue`,
`sealedVersion` and `viewerWrap` for an encrypted entry, with no `value`.
`unavailable: true` replaces the cryptographic fields if the seal is stale.
Entries without a seal are omitted. Short-format exports, CardDAV, request
answers, sign-in grants and tool vault reads do not decrypt these entries.
The browser builds its own exports from values it decrypted locally.

## Opening an entry

1. Derive the copy key with HKDF-SHA256: input key material is the link key,
   salt is empty, info is `ctx("revoked-link-copy-v1", [recordId])`, output 32 bytes.
2. Open `viewerWrap` under that key with
   `ctx("revoked-link-viewer-v1", [recordId, version])`. The plaintext is the
   32-byte value key followed by the workspace id in UTF-8.
3. Open `sealedValue` under the value key with
   `ctx("revoked-record-v1", [workspaceId, recordId, recordKey, version])`.
4. Remove ISO/IEC 7816-4 padding (`0x80`, then zeros; buckets 64, 256, 1024,
   4096, 8192) and decode UTF-8 JSON `{v, l, t, f}`. The inner label, type and
   format are the authenticated metadata used for display and exports.

`ctx` encodes the label and every string with a four-byte big-endian UTF-8
length, followed by its bytes. Integers are eight-byte big-endian.
AEAD envelopes are `0x01 || nonce[12] || AES-256-GCM ciphertext+tag[16]`.
The actual GCM associated data is `0x01 || ctx`. Envelope fields use padded
base64url. The existing Dart/Go fixtures and page script check these formats.

## Writes and key replacement

The sealed routes in the [OpenAPI reference](index.md) attach encrypted
entries, carry existing links through first encryption, and renew their
seals on writes. `expectedWriterWrap` prevents a stale writer undoing key
replacement. Replacing a link key uses owner-only `replaceKey: true` with
`expectedKeyWraps`, every current encrypted-entry seal and every required
scope wrap. The transaction changes all of them together; old addresses
lose access to encrypted entries, while the slug and plain entries remain.

## Bookmarks

The owner-only `bookmarks` collection adds `sealedKey` and `keyEpoch`.
A request bookmark cannot carry them. Either both are empty/zero or the
key is an envelope containing exactly 32 bytes at a positive epoch.
The server validates shape, not cryptographic content; it never follows a
bookmark or learns an address key.

Clients wrap the link key under the viewer's account key using the same
AEAD envelope. Associated data is:

```
ctx("revoked-bookmark-key-v1", [userId, homeServerBaseUrl, origin, slug, epoch])
```

The app uses the normalized lower-case home-server base URL and lower-case
bookmark origin (`""` for the home server); slug is case-sensitive. Account
keys are never shared with workspace members. The app resolves a bookmark
before opening the public view, keeping its key outside router locations.
Without account encryption, only the pointer syncs and the key stays in
platform secure storage, scoped to the same account and server.

For saved shares, local secure storage pins each successfully authenticated
record's highest version and SHA-256 of the decoded `sealedValue` envelope.
An older version, different ciphertext at that version, or an unexpected
plaintext downgrade is hidden. Failed decryption never advances a pin.
Pins remain across restarts and bookmark deletion, are separate for each
account/server/share, and are not synced: a fresh device has no prior
history. They cannot prove that omitted entries or an unseen latest write
exist. A legitimate stop-encrypting operation also triggers the plaintext
check. Browser readers keep no such history.

## Connected tools

Encrypted proposals default to no hand-over. Explicit consent for that one
proposal allows a same-origin callback to receive the complete address in
its `revoked_link` fragment parameter. The key never enters the callback
query or any connection/polling response. The tool then has a capability to
read and copy the values. [Tools](tools.md#explicit-encrypted-link-hand-over)
describes that callback contract and the polling behavior.
