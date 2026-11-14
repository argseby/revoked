`sealing_vectors.json` pins the end-to-end encryption formats from both sides.
`app/test/sealing_test.dart` and `util/sealing_vectors_test.go` both read it, so
a format change in the app fails against Go's `crypto/hpke`. Never regenerate it
to make a test pass: once this ships, a change here means existing data no longer
opens. It was last regenerated before any release, when review tightened the
formats.

`sealing_grant_vectors.json` pins how a workspace key is handed to another
member: the app's encryption of it, and the signature this server checks
(`util.SealedGrantPayload`). The same rule applies: never regenerate it.

`sealing_link_vectors.json` pins how an encrypted record is carried on a link
(design/e2ee-sharing.md §3.2): the copy key derived from the link key, what a
viewer and the next writer open, and the link key for its owner's devices.
`util/sealing_vectors_test.go` opens each of them with Go's own primitives.
The same rule applies: never regenerate it.

`sealing_link_read_vectors.json` pins a complete public read, from the key in
the address through the viewer wrap to the authenticated value and metadata.
Dart's share reader, Go's primitives and the actual page WebCrypto script
(`TestPageScriptOpensTheVectors`, when Node is installed) open the same vector.
The same rule applies: never regenerate it.

`sealing_file_vectors.json` pins an encrypted file (design/e2ee-sharing.md
§7.2): a link read through to a sealed value carrying the file descriptor, and
two segmented blobs, one spanning two segments. `sealed_file_test.dart` and
`TestFileVectorOpensInGo` open it. The same rule applies: never regenerate it.
