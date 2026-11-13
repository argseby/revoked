package routes

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// pageSealingHarness runs the page's own decryption against the fixtures the
// app and Go answer to. It is the script as the page carries it, with nothing
// rewritten for the test: WebCrypto, atob and the text codecs exist under the
// same names in a browser and in the runtime below.
const pageSealingHarness = `
var fs = require('fs'), path = require('path');
var dir = process.argv[2];
function fixture(name) { return JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8')); }
function unhex(s) { var out = new Uint8Array(s.length / 2); for (var i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16); return out; }
function hex(b) { return Array.prototype.map.call(b, function(x) { return (x < 16 ? '0' : '') + x.toString(16); }).join(''); }
function same(got, want, what) { if (got !== want) throw new Error(what + ': got ' + JSON.stringify(got) + ', expected ' + JSON.stringify(want)); }
function refused(promise, what) { return promise.then(function() { throw new Error(what + ' opened'); }, function() {}); }
function flip(text, at) { return text.slice(0, at) + (text[at] === 'A' ? 'B' : 'A') + text.slice(at + 1); }

var link = fixture('sealing_link_vectors.json');
var value = fixture('sealing_vectors.json');
var read = fixture('sealing_link_read_vectors.json');

(async function() {
if (!sealSubtle) throw new Error('this runtime has no WebCrypto');

// The formats, one by one, against the vectors the app wrote.
var copyKey = await sealCopyKey(unhex(link.linkKey), link.record);
same(hex(copyKey), link.copyKey, 'copy key');
same(hex(await sealCopyKey(unhex(link.linkKey), link.record + 'x')) === link.copyKey, false, 'copy key of another record');

var wrap = sealBytes(link.viewerWrap);
var seal = await sealOpenViewer(copyKey, wrap, link.record, link.version);
same(hex(seal.valueKey), link.valueKey, 'value key');
same(seal.workspace, link.workspace, 'workspace');
await refused(sealOpenViewer(copyKey, wrap, link.record, link.version + 1), 'another version');
await refused(sealOpenViewer(copyKey, wrap, link.record + 'x', link.version), 'another record');
await refused(sealOpenViewer(unhex(link.valueKey), wrap, link.record, link.version), 'another key');

var sealed = sealBytes(value.sealedValue);
same(await sealOpenValue(unhex(value.valueKey), sealed, value.workspace, value.record, value.recordKey, value.version), value.value, 'value');
await refused(sealOpenValue(unhex(value.valueKey), sealed, value.workspace, value.record, 'other_key', value.version), 'another record key');
await refused(sealOpenValue(unhex(value.valueKey), sealed, value.workspace + 'x', value.record, value.recordKey, value.version), 'another workspace');

// The key as an address carries it.
var key = sealLinkKeyFrom('#k=' + read.linkKey);
same(sealKeyText(key), read.linkKey, 'key text');
same(hex(sealLinkKeyFrom('#x=1&k=' + read.linkKey + '==')), hex(key), 'key beside other parts, padded');
same(sealLinkKeyFrom(''), null, 'no fragment');
same(sealLinkKeyFrom('#k='), null, 'empty key');
same(sealLinkKeyFrom('#k=' + read.linkKey.slice(0, 20)), null, 'part of a key');
same(sealLinkKeyFrom('#k=' + read.linkKey + 'AAAA'), null, 'more than a key');
same(sealLinkKeyFrom('#key=' + read.linkKey), null, 'another name');

// A whole share: from the address and the server's answer to ordinary records.
var plain = { id: 'recplain0000001', key: 'note', label: 'Note', type: 'text', value: 'in the clear' };
var served = { label: 'Shared', records: [read.entry, plain], sections: [{ name: 'One', records: [read.entry.id] }] };
var before = JSON.stringify(served);

var opened = await sealOpenShare(served, key);
same(JSON.stringify(served), before, 'what the server returned');
same(opened.label, 'Shared', 'share label');
same(opened.records[1], plain, 'a plain record');
var r = opened.records[0];
same(r.value, read.content.v, 'opened value');
same(r.label, read.content.l, 'label from inside the ciphertext');
same(r.type, read.content.t, 'type from inside the ciphertext');
same(r.format, read.content.f, 'format from inside the ciphertext');
same(r.id + ' ' + r.key, read.entry.id + ' ' + read.entry.key, 'id and key');
same(r.locked, undefined, 'an opened entry');
same(r.encrypted, true, 'an opened entry is marked');
['sealed', 'sealedValue', 'sealedVersion', 'viewerWrap'].forEach(function(f) { same(f in r, false, f + ' on an opened entry'); });

// Every way an entry stays closed, and that none of them carries a value.
async function closed(entry, withKey, why, what) {
var out = (await sealOpenShare({ records: [entry, plain] }, withKey)).records;
same(out[0].locked, why, what);
same(out[1], plain, what + ': the plain record');
['value', 'sealed', 'sealedValue', 'sealedVersion', 'viewerWrap', 'encrypted'].forEach(function(f) { same(f in out[0], false, what + ': ' + f); });
same(out[0].label, entry.label, what + ': label');
}
function with_(change) { var e = JSON.parse(JSON.stringify(read.entry)); change(e); return e; }

await closed(read.entry, null, 'incomplete', 'no key');
await closed(read.entry, unhex(link.linkKey), 'replaced', 'another key');
await closed(with_(function(e) { e.sealedVersion += 1; }), key, 'replaced', 'a wrap of another version');
await closed(with_(function(e) { e.viewerWrap = flip(e.viewerWrap, 30); }), key, 'replaced', 'a changed wrap');
await closed(with_(function(e) { e.unavailable = true; delete e.sealedValue; delete e.sealedVersion; delete e.viewerWrap; }), key, 'unavailable', 'a link that fell behind');
await closed(with_(function(e) { e.unavailable = true; delete e.sealedValue; delete e.sealedVersion; delete e.viewerWrap; }), null, 'unavailable', 'a link that fell behind, no key');
await closed(with_(function(e) { e.sealedValue = flip(e.sealedValue, 40); }), key, 'damaged', 'a changed value');
await closed(with_(function(e) { e.key = 'api_token'; }), key, 'damaged', 'a value moved under another key');
await closed(with_(function(e) { e.sealedValue = '***'; }), key, 'damaged', 'a value that is not base64url');
await closed(with_(function(e) { delete e.viewerWrap; }), key, 'damaged', 'no wrap');
await closed(with_(function(e) { e.sealedVersion = '6'; }), key, 'damaged', 'a version that is not a number');

// An encrypted file: its name, type and size from inside the seal, then its
// blob opened segment by segment (design/e2ee-sharing.md §7.2).
var file = fixture('sealing_file_vectors.json');
var fileEntry = JSON.parse(JSON.stringify(file.entry));
fileEntry.sealed = true; fileEntry.type = 'file'; fileEntry.label = 'stated by the server';
fileEntry.size = 99; fileEntry.downloadToken = 'token';
var fileKey = sealLinkKeyFrom('#k=' + file.linkKey);
var f = (await sealOpenShare({ records: [fileEntry] }, fileKey)).records[0];
same(f.locked, undefined, 'an opened file');
same(f.type, 'file', 'a file stays a file');
same(f.label, file.content.l, 'file label from inside the ciphertext');
same(f.filename, file.content.x.n, 'file name from inside the ciphertext');
same(f.mime, file.content.x.m, 'media type from inside the ciphertext');
same(f.size, file.content.x.s, 'exact size from inside the ciphertext');
same(f.downloadToken, 'token', 'the download token is kept');
same(f.value, '', 'a file has no value');
var blob = sealBytes(file.blob);
same(blob.length, sealFileBlobLength(f.size), 'blob length');
var bytes = await sealOpenFile(blob, { size: f.size, key: f.fileSeal.key }, f.fileSeal.workspace, f.id);
same(hex(new Uint8Array(await sealSubtle.digest('SHA-256', bytes))), file.plaintextSha256, 'file bytes');
var small = new TextEncoder().encode(file.small.text);
same(new TextDecoder().decode(await sealOpenFile(sealBytes(file.small.blob), { size: small.length, key: f.fileSeal.key }, f.fileSeal.workspace, f.id)), file.small.text, 'a one-segment file');
var seal_ = { size: f.size, key: f.fileSeal.key };
await refused(sealOpenFile(blob, seal_, f.fileSeal.workspace, f.id + 'x'), 'a file of another record');
await refused(sealOpenFile(blob, seal_, f.fileSeal.workspace + 'x', f.id), 'a file of another workspace');
await refused(sealOpenFile(blob, { size: f.size, key: unhex(link.valueKey) }, f.fileSeal.workspace, f.id), 'a file under another key');
var bad = blob.slice(); bad[blob.length - 100] ^= 1;
await refused(sealOpenFile(bad, seal_, f.fileSeal.workspace, f.id), 'a changed file');
bad = blob.slice(); bad[5] ^= 1;
await refused(sealOpenFile(bad, seal_, f.fileSeal.workspace, f.id), 'a changed salt');
await refused(sealOpenFile(blob.subarray(0, 17 + 65552), { size: 65536, key: f.fileSeal.key }, f.fileSeal.workspace, f.id), 'a file cut after a whole segment');
var swapped = sealJoin([blob.subarray(0, 17), blob.subarray(17 + 65552), blob.subarray(17, 17 + 65552)]);
await refused(sealOpenFile(swapped, seal_, f.fileSeal.workspace, f.id), 'reordered segments');
await refused(sealOpenFile(blob, { size: f.size - 1, key: f.fileSeal.key }, f.fileSeal.workspace, f.id), 'a size that leaves data in the padding');
var closedFile = (await sealOpenShare({ records: [fileEntry] }, null)).records[0];
same(closedFile.locked, 'incomplete', 'a file without the key');
same('fileSeal' in closedFile, false, 'a closed file carries no key');

// A page without WebCrypto (plain http) says so instead of failing.
sealSubtle = null;
await closed(read.entry, key, 'insecure', 'no WebCrypto');
await closed(read.entry, null, 'incomplete', 'no WebCrypto and no key');

console.log('ok');
})().catch(function(err) { console.error(err && err.stack || err); process.exit(1); });
`

// The link page is the third reader of the link formats. Its script runs in a
// browser, and nothing in this repository can run one, so the same text is
// run here by Node when the machine has it: Node's WebCrypto is the one a
// browser has. Without Node the test is skipped, not passed.
func TestPageScriptOpensTheVectors(t *testing.T) {
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node is not installed; the page's decryption is not checked against the vectors on this machine")
	}
	fixtures, err := filepath.Abs(filepath.Join("..", "..", "..", "app", "test", "fixtures"))
	if err != nil {
		t.Fatal(err)
	}
	script := filepath.Join(t.TempDir(), "sealing.js")
	if err := os.WriteFile(script, []byte(pageSealingScript+pageSealingHarness), 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command(node, script, fixtures).CombinedOutput()
	if err != nil || strings.TrimSpace(string(out)) != "ok" {
		t.Fatalf("the page script does not open the vectors: %v\n%s", err, out)
	}
}

// The script is spliced into a Go raw string and an html/template: a backtick
// would end the one and an action would be run by the other.
func TestPageScriptIsPlainText(t *testing.T) {
	if strings.Contains(pageSealingScript, "{{") {
		t.Fatal("the page script contains a template action")
	}
	for _, call := range []string{"fetch(", "XMLHttpRequest", "localStorage", "sessionStorage", "document.", "console."} {
		if strings.Contains(pageSealingScript, call) {
			t.Fatalf("the page script reaches for %q; it only computes", call)
		}
	}
}
