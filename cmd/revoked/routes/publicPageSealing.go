package routes

// pageSealingScript is how the link page opens an end-to-end encrypted record
// (design/e2ee-sharing.md §3). It is the third reader of the formats, after the
// app (app/lib/core/crypto/sealed_formats.dart) and Go's own primitives
// (util/sealing_vectors_test.go), and has to agree with both byte for byte.
//
// It uses only what a browser provides, HKDF and AES-GCM from WebCrypto, so
// the page's policy stays as it is and nothing is fetched. It touches neither
// the document nor the network: publicPage.go hands it what the server
// returned and the key from the address, and gets ordinary records back. That
// also lets a test run exactly this text against the fixtures
// (publicPageSealing_test.go).
//
// No backticks and no template actions in here: it is spliced into the page's
// template as it stands.
const pageSealingScript = `
// ---- End-to-end encrypted records ------------------------------------------
// A record its owner encrypted arrives as ciphertext. The key that opens it is
// the end of the address, after "#k=", which a browser sends to no server. It
// is read here, kept in memory, and never put in a request or in storage.
var SEAL_KEY_LENGTH = 32;
var SEAL_FORMAT = 1;
var sealSubtle = (typeof crypto !== 'undefined' && crypto.subtle) || null;
var sealEncoder = new TextEncoder();

// base64url, with or without padding: an address is retyped and re-wrapped.
function sealBytes(text) {
if (typeof text !== 'string') return null;
var s = text.replace(/=+$/, '');
if (!/^[A-Za-z0-9_-]*$/.test(s) || s.length % 4 === 1) return null;
s = s.replace(/-/g, '+').replace(/_/g, '/');
while (s.length % 4) s += '=';
var bin;
try { bin = atob(s); } catch (e) { return null; }
var out = new Uint8Array(bin.length);
for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
return out;
}

// A link key as it travels in an address: base64url without padding.
function sealKeyText(bytes) {
var bin = '';
for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function sealJoin(chunks) {
var total = 0, i;
for (i = 0; i < chunks.length; i++) total += chunks[i].length;
var out = new Uint8Array(total), at = 0;
for (i = 0; i < chunks.length; i++) { out.set(chunks[i], at); at += chunks[i].length; }
return out;
}

function sealIsVersion(n) {
return typeof n === 'number' && isFinite(n) && n >= 0 && Math.floor(n) === n && n <= 9007199254740991;
}

// What a ciphertext is bound to. Every string carries its length in four
// bytes and every number is eight bytes, both big-endian, so two different
// lists of parts never encode alike.
function sealContext(label, parts) {
var chunks = [];
function addBytes(b) {
var n = new Uint8Array(4);
new DataView(n.buffer).setUint32(0, b.length);
chunks.push(n, b);
}
addBytes(sealEncoder.encode(label));
parts.forEach(function(p) {
if (p instanceof Uint8Array) {
addBytes(p);
} else if (typeof p === 'number') {
var n = new Uint8Array(8), view = new DataView(n.buffer);
view.setUint32(0, Math.floor(p / 4294967296));
view.setUint32(4, p % 4294967296);
chunks.push(n);
} else {
addBytes(sealEncoder.encode(String(p)));
}
});
return sealJoin(chunks);
}

// ISO/IEC 7816-4: the content, a 0x80 marker, then zeros up to the bucket.
function sealUnpad(padded) {
for (var i = padded.length - 1; i >= 0; i--) {
if (padded[i] === 0x80) return padded.subarray(0, i);
if (padded[i] !== 0) break;
}
throw new Error('padding');
}

// format byte, 12-byte nonce, then AES-256-GCM over the content with the
// format byte ahead of the context as associated data.
function sealOpen(keyBytes, aad, sealed) {
if (sealed.length < 1 + 12 + 16 || sealed[0] !== SEAL_FORMAT) return Promise.reject(new Error('format'));
return sealSubtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']).then(function(key) {
return sealSubtle.decrypt({
name: 'AES-GCM',
iv: sealed.subarray(1, 13),
additionalData: sealJoin([sealed.subarray(0, 1), aad]),
tagLength: 128
}, key, sealed.subarray(13));
}).then(function(plain) { return new Uint8Array(plain); });
}

// One key per record, derived from the link key, so being handed one says
// nothing about the link key or the link's other records.
function sealCopyKey(linkKey, record) {
return sealSubtle.importKey('raw', linkKey, 'HKDF', false, ['deriveBits']).then(function(key) {
return sealSubtle.deriveBits({
name: 'HKDF',
hash: 'SHA-256',
salt: new Uint8Array(0),
info: sealContext('revoked-link-copy-v1', [record])
}, key, SEAL_KEY_LENGTH * 8);
}).then(function(bits) { return new Uint8Array(bits); });
}

// What the link holds for a record: this version's value key, then the
// workspace the value is bound to, which the server never names in public.
function sealOpenViewer(copyKey, wrap, record, version) {
return sealOpen(copyKey, sealContext('revoked-link-viewer-v1', [record, version]), wrap).then(function(plain) {
if (plain.length <= SEAL_KEY_LENGTH) throw new Error('wrap');
return {
valueKey: plain.subarray(0, SEAL_KEY_LENGTH),
workspace: new TextDecoder('utf-8', { fatal: true }).decode(plain.subarray(SEAL_KEY_LENGTH))
};
});
}

function sealOpenValue(valueKey, sealed, workspace, record, recordKey, version) {
return sealOpen(valueKey, sealContext('revoked-record-v1', [workspace, record, recordKey, version]), sealed).then(function(padded) {
return new TextDecoder('utf-8', { fatal: true }).decode(sealUnpad(padded));
});
}

// The value with its label, type and format: the ones that were encrypted
// with it, not the copies the server states beside the ciphertext. A file
// carries its name, media type, exact size and key there too, and no value.
function sealContent(text) {
var c = JSON.parse(text);
if (!c || typeof c.v !== 'string' || typeof c.l !== 'string' || typeof c.t !== 'string' || typeof c.f !== 'string') {
throw new Error('content');
}
var out = { value: c.v, label: c.l, type: c.t, format: c.f, file: null };
if (c.t === 'file' || c.x !== undefined) {
var x = c.x;
var key = x && typeof x.k === 'string' ? sealBytes(x.k) : null;
if (c.t !== 'file' || c.v !== '' || !x || typeof x.n !== 'string' || x.n === '' || typeof x.m !== 'string' ||
!sealIsVersion(x.s) || x.s > SEAL_FILE_MAX || !key || key.length !== SEAL_KEY_LENGTH) {
throw new Error('content');
}
out.file = { name: x.n, mime: x.m, size: x.s, key: key };
}
return out;
}

// ---- Encrypted files --------------------------------------------------------
// A file's bytes travel apart from its sealed value, as a blob of 64 KiB
// segments (design/e2ee-sharing.md §7.2):
//   0x01, salt[16], then AES-256-GCM segments under
//   HKDF(file key, revoked-file-v1 [workspace, record, salt]),
//   nonce = segment number in 11 bytes, then 1 for the last segment, else 0.
// The plaintext is padded with zeros to the length below; the sealed value
// states the real size.
var SEAL_FILE_SEGMENT = 65536;
var SEAL_FILE_MAX = 50 * 1024 * 1024;

function sealBitLength(n) { return n <= 0 ? 0 : 32 - Math.clz32(n); }

function sealFilePadded(size) {
if (size <= 1024) return 1024;
var e = sealBitLength(size) - 1;
var s = sealBitLength(e);
var mask = Math.pow(2, e - s) - 1;
return Math.ceil(size / (mask + 1)) * (mask + 1);
}

function sealFileBlobLength(size) {
var padded = sealFilePadded(size);
return 1 + 16 + padded + Math.ceil(padded / SEAL_FILE_SEGMENT) * 16;
}

// Opens an encrypted file's blob into its bytes, or rejects. A blob of
// another record or content, a dropped, reordered or cut segment and padding
// that is not zeros all fail; nothing partial is handed back.
function sealOpenFile(blob, file, workspace, record) {
if (!sealSubtle) return Promise.reject(new Error('insecure'));
if (!(blob instanceof Uint8Array) || blob.length !== sealFileBlobLength(file.size) || blob[0] !== SEAL_FORMAT) {
return Promise.reject(new Error('format'));
}
var salt = blob.subarray(1, 17);
return sealSubtle.importKey('raw', file.key, 'HKDF', false, ['deriveBits']).then(function(key) {
return sealSubtle.deriveBits({
name: 'HKDF',
hash: 'SHA-256',
salt: new Uint8Array(0),
info: sealContext('revoked-file-v1', [workspace, record, salt])
}, key, SEAL_KEY_LENGTH * 8);
}).then(function(bits) {
return sealSubtle.importKey('raw', new Uint8Array(bits), { name: 'AES-GCM' }, false, ['decrypt']);
}).then(function(key) {
var sealedSegment = SEAL_FILE_SEGMENT + 16;
var out = new Uint8Array(sealFilePadded(file.size));
var at = 17, index = 0, written = 0;
function next() {
var last = blob.length - at <= sealedSegment;
var end = last ? blob.length : at + sealedSegment;
var nonce = new Uint8Array(12), view = new DataView(nonce.buffer);
view.setUint32(3, Math.floor(index / 4294967296));
view.setUint32(7, index % 4294967296);
nonce[11] = last ? 1 : 0;
return sealSubtle.decrypt({
name: 'AES-GCM', iv: nonce, additionalData: new Uint8Array([SEAL_FORMAT]), tagLength: 128
}, key, blob.subarray(at, end)).then(function(plain) {
plain = new Uint8Array(plain);
if (written + plain.length > out.length) throw new Error('length');
out.set(plain, written);
written += plain.length;
if (last) return null;
at = end;
index++;
return next();
});
}
return next().then(function() {
if (written !== out.length) throw new Error('length');
for (var i = file.size; i < out.length; i++) if (out[i] !== 0) throw new Error('padding');
return out.subarray(0, file.size);
});
});
}

// The key an address carries, or null: none, or not a whole one.
function sealLinkKeyFrom(hash) {
var parts = String(hash || '').replace(/^#/, '').split('&');
for (var i = 0; i < parts.length; i++) {
if (parts[i].indexOf('k=') !== 0) continue;
var text = parts[i].slice(2);
try { text = decodeURIComponent(text); } catch (e) {}
var key = sealBytes(text);
return key && key.length === SEAL_KEY_LENGTH ? key : null;
}
return null;
}

function sealCopy(r) {
var out = {};
Object.keys(r).forEach(function(k) { out[k] = r[k]; });
delete out.sealed;
delete out.sealedValue;
delete out.sealedVersion;
delete out.viewerWrap;
delete out.unavailable;
delete out.value;
return out;
}

// A record that stays closed says why. It never carries a value.
function sealLocked(r, why) {
var out = sealCopy(r);
out.locked = why;
return out;
}

// One encrypted entry as the server returned it, opened into an ordinary
// record, or closed with the reason:
//   unavailable  the link fell behind the record; nothing was sent to open
//   incomplete   the address carries no key
//   insecure     this page has no WebCrypto (plain http)
//   replaced     the key does not open what the link holds
//   damaged      what was sent is not what the key was made for
function sealOpenRecord(r, linkKey) {
if (r.unavailable) return Promise.resolve(sealLocked(r, 'unavailable'));
if (!linkKey) return Promise.resolve(sealLocked(r, 'incomplete'));
if (!sealSubtle) return Promise.resolve(sealLocked(r, 'insecure'));
var version = r.sealedVersion;
var wrap = sealBytes(r.viewerWrap), sealed = sealBytes(r.sealedValue);
if (typeof r.id !== 'string' || !sealIsVersion(version) || !wrap || !sealed) {
return Promise.resolve(sealLocked(r, 'damaged'));
}
var recordKey = typeof r.key === 'string' ? r.key : '';
return sealCopyKey(linkKey, r.id).then(function(copyKey) {
return sealOpenViewer(copyKey, wrap, r.id, version);
}).then(function(seal) {
return sealOpenValue(seal.valueKey, sealed, seal.workspace, r.id, recordKey, version).then(function(text) {
var content = sealContent(text);
var out = sealCopy(r);
out.value = content.value;
out.label = content.label;
out.type = content.type;
out.format = content.format;
out.encrypted = true;
if (content.file) {
// What the row shows comes from inside the seal; what is needed to open
// the blob stays in memory beside it.
out.filename = content.file.name;
out.mime = content.file.mime;
out.size = content.file.size;
out.fileSeal = { key: content.file.key, workspace: seal.workspace };
} else if (out.type === 'file') {
throw new Error('content');
}
return out;
}).catch(function() { return sealLocked(r, 'damaged'); });
}, function() { return sealLocked(r, 'replaced'); });
}

// The share as the server returned it, with every encrypted entry opened or
// closed. Never rejects, and leaves what it was given untouched, so the same
// answer can be opened again with another key without asking the server.
function sealOpenShare(data, linkKey) {
var records = (data && data.records) || [];
return Promise.all(records.map(function(r) {
if (!r || !r.sealed) return r;
return sealOpenRecord(r, linkKey).catch(function() { return sealLocked(r, 'damaged'); });
})).then(function(opened) {
var out = {};
Object.keys(data || {}).forEach(function(k) { out[k] = data[k]; });
out.records = opened;
return out;
});
}
`
