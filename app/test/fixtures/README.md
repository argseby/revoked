`sealing_vectors.json` pins the end-to-end encryption formats from both sides.
`app/test/sealing_test.dart` and `util/sealing_vectors_test.go` both read it, so
a format change in the app fails against Go's `crypto/hpke`. Never regenerate it
to make a test pass: once this ships, a change here means existing data no longer
opens. It was last regenerated before any release, when review tightened the
formats.
