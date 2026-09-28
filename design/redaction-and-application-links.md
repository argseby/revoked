# Document redaction and application links — implementation spec

Status: ready to build · Owner: you · Last updated: 2026-09-28

This is the build plan for the "rental application folder" feature: a flat
hunter keeps their documents in revoked, redacts their ID before it ever leaves
the phone, and sends each landlord their own watermarked, expiring,
revocable link. The landlord only needs a browser.

Everything here follows `CLAUDE.md` (MobX singletons, no `setState`, one
component per job, rules in migrations, typed errors on both sides). File
paths are relative to the repo root.

---

## 1. User story

> Lena applies for 30 flats. She stores her ID, three payslips, her SCHUFA
> extract and her self-disclosure in revoked once. Before the ID is uploaded
> she blacks out the access number (CAN) and the serial number. For each
> listing she taps **New application**, types the address, and gets a link.
> The landlord opens it in a browser: every file is stamped
> *"Nur für Wohnungsbewerbung Musterstr. 5 · 2026-09-28 · #a3f9c1"*. Lena
> sees "opened 2×". After a rejection she revokes the link; after 14 days it
> expires by itself. When she gets a new payslip she replaces it once and
> every open application shows the new one.

---

## 2. What already exists (do not rebuild)

| Piece | Where | Notes |
|---|---|---|
| File records in the vault | `hooks/records.go`, `app/lib/features/vault/` | Type `file`; server sniffs `mime`; `FILE_MAX_SIZE` / `FILE_MAX_STORAGE` limits |
| Staged uploads | `app/lib/core/files/pending_upload.dart` | `PendingUpload{name,size,open}` — a redacted image becomes one of these |
| Share links | `links` collection, `SharesStore` | `expiresAt`, `maxViews`, `viewCount`, password, identity, revoke/pause |
| **Watermarking** | `cmd/revoked/services/watermark.go`, `routes/publicFiles.go` | `links.watermark` + `watermarkText` (migration 000055). Images + PDFs stamped on every read, other types refused (`file_not_watermarkable`, 415) |
| Stamp line | `services.WatermarkLine` | `<text or label> · <date> · #<tag>`; tag = first 6 chars of link id (`Link.watermarkTag` in the app) |
| Public page | `routes/publicPage.go` | Reveal, in-page preview of stamped files, tiled overlay over text, blue palette |
| Watermark row in share sheet | `share_create_sheet.dart` | Password-style: text set ⇔ watermark on |
| View files | `app/lib/core/widgets/file_view_sheet.dart` (`viewFile`) | Images/text in-app, rest via `openFileOnDevice` |
| Template | `templates/tenant_application.json` | Built-in; extend it (§6.5) rather than adding a second one |

---

## 3. Architecture overview

```
 Applicant (Flutter app)                                Landlord (any browser)
 ───────────────────────                                ──────────────────────
 features/redaction/  ── redacted PNG ──┐                  https://<server>/s/<slug>
   RedactionStore + RedactionEditor     │                          │
                                        ▼                          ▼
 features/vault/  ── upload (existing) ──►  revoked server (Go/PocketBase)
                                          │  records (file)            publicPage.go
 features/applications/                   │  links (+purpose)  ◄──── "application" layout
   ApplicationsStore + ApplySheet ────────►  hooks/links.go:  application ⇒ watermark on
   ApplicationsTab (in Share screen)      │  routes/publicLinks.go: first open ⇒ notification
                                          │  routes/publicFiles.go: stamp on read (exists)
   notifications (existing) ◄─────────────┘
```

Split of work: **redaction is app-only**, **the stamp is server-only
(done)**, **applications are mostly app + a small server slice**.

---

## 4. Part A — Redaction (Flutter only)

### 4.1 Rules that make it safe

1. **The original never leaves the device** when the user chooses to redact.
   Redaction happens on the staged `PendingUpload` *before* the upload call.
2. **Solid, opaque black fill only.** No blur, no pixelation — both can be
   reversed or read by a model. Colour `0xFF000000`, alpha 255.
3. **Flatten on export.** The output is a brand-new PNG rendered from the
   decoded pixels plus the boxes. There are no layers, and EXIF (incl. GPS) is
   gone because nothing is copied from the source file.
4. **Verify the export** before swapping it in: decode the PNG and check the
   centre pixel of every box is black. If not, refuse and keep nothing.

### 4.2 Files to create

```
app/lib/features/redaction/
  store/redaction_store.dart        MobX singleton: image, boxes, draft box, undo, export
  view/redaction_sheet.dart         full-height sheet: editor + toolbar + Done/Cancel
  view/redaction_canvas.dart        StatelessWidget: AspectRatio + GestureDetector + CustomPaint
  redaction_export.dart             pure functions: toPixelRect(), renderRedacted(), verifyRedacted()
app/test/redaction_export_test.dart
```

Register the store in `app/lib/core/stores.dart` as `Stores.redaction`.

### 4.3 Store (sketch)

```dart
class RedactionStore = _RedactionStore with _$RedactionStore;

abstract class _RedactionStore with Store {
  @observable ui.Image? image;                 // decoded source, max edge 4096
  @observable ObservableList<Rect> boxes = ObservableList();   // normalised 0..1
  @observable Rect? draft;                     // box being dragged, normalised
  @observable int? selected;                   // index into boxes
  @observable bool isExporting = false;
  @observable String? error;

  @action Future<bool> load(Uint8List bytes);  // instantiateImageCodec(targetWidth/Height ≤ 4096)
  @action void begin(Offset p);                // draft = Rect.fromPoints(p, p)
  @action void extend(Offset p);               // draft = Rect.fromPoints(draft!.topLeft, p)
  @action void commit();                       // add if ≥ 1% of both sides, clear draft
  @action void select(Offset p);               // hit-test boxes (last on top)
  @action void removeSelected();
  @action void undo();                         // pop last box
  @action void applyPreset(RedactionPreset p); // adds the preset's boxes, user adjusts
  @action Future<Uint8List?> export();         // renderRedacted + verifyRedacted
  @action void reset();                        // dispose image, clear everything
}
```

- Coordinates are **normalised** (0..1 of image width/height) so the layout
  size never matters. Convert in `redaction_export.dart`:
  `Rect toPixelRect(Rect n, int w, int h)` → clamp to image bounds, round
  outward (never inward — a rounding error must not leave a pixel row visible).
- `reset()` must `image?.dispose()`; call it when the sheet closes.

### 4.4 Canvas (no `setState`)

```dart
Observer(builder: (_) {
  final img = Stores.redaction.image;
  return AspectRatio(
    aspectRatio: img.width / img.height,
    child: LayoutBuilder(builder: (_, c) {
      Offset norm(Offset local) => Offset(local.dx / c.maxWidth, local.dy / c.maxHeight);
      return GestureDetector(
        onPanStart: (d) => store.begin(norm(d.localPosition)),
        onPanUpdate: (d) => store.extend(norm(d.localPosition)),
        onPanEnd: (_) => store.commit(),
        onTapUp: (d) => store.select(norm(d.localPosition)),
        child: CustomPaint(painter: _RedactionPainter(img, store.boxes.toList(), store.draft, store.selected)),
      );
    }),
  );
});
```

The painter draws the image, then every box as opaque black, the draft with an
outline, and the selected box with the `primary` outline. It holds no state.
Wrap in `InteractiveViewer` for pinch-zoom only if pan gestures still reach the
detector; otherwise add a zoom toggle (`Local<bool>` is **not** allowed in a
feature view — put the flag in the store).

Toolbar (`AppButton`s, icon-only need `tooltip`): Undo, Delete selected,
Preset ▾ (`AppMenuButton`), Cancel (accent), Done (primary, `busy: isExporting`).

### 4.5 Export

```dart
Future<Uint8List> renderRedacted(ui.Image img, List<Rect> boxes) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawImage(img, Offset.zero, Paint());
  final black = Paint()..color = const Color(0xFF000000)..isAntiAlias = false;
  for (final b in boxes) { canvas.drawRect(toPixelRect(b, img.width, img.height), black); }
  final out = await rec.endRecording().toImage(img.width, img.height);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return png!.buffer.asUint8List();
}

Future<bool> verifyRedacted(Uint8List png, List<Rect> boxes) // decode, sample centres (rawRgba)
```

`Color(0xFF000000)` is a pixel value inside an image, not a UI colour, so the
"no `Colors.*` in views" rule does not apply — keep it in
`redaction_export.dart`, not in a view.

### 4.6 Where it plugs in

1. **Before upload (primary):** in `VaultFileRow`, when the staged file
   `isImage`, show an accent `AppButton(icon: AppIcons.eyeSlash, label:
   'Redact')`. Flow: `pickedFile.readAll()` → `Stores.redaction.load()` →
   `showRedactionSheet()` → on Done, replace the staged file:

   ```dart
   Stores.vault.setPickedFile(PendingUpload(
     name: '${stem(original.name)}-redacted.png',
     size: png.length,
     open: () => Stream.value(png),
   ));
   ```

   The preview updates from the store; the original handle is dropped.
2. **Existing image record (secondary):** action "Replace with redacted copy"
   on image file cards in `vault_screen.dart`: `fetchRecordFileBytes` →
   editor → multipart PATCH of `file` + `filename`. Confirm first with
   `showAppDialog`: *"The unredacted original is deleted from the server."*
   PocketBase removes the replaced file from storage.

### 4.7 Presets (German ID card)

`RedactionPreset` = name + list of normalised rects. Ship
**"Personalausweis – Vorderseite"** (CAN / access number, serial number) and
**"Personalausweis – Rückseite"** (machine-readable zone). Positions are
*approximate starting boxes the user must check* — say so in the sheet
("Check every box covers the number"). Measure them on a real card photo
before shipping; do not guess.

### 4.8 Open checks

- Does `instantiateImageCodec` apply EXIF orientation on Android and iOS for
  camera JPEGs? Test with a portrait photo. If not, apply orientation first
  (port `jpegOrientation`/`orient` from `services/watermark.go`).
- Memory: a 12 MP photo decodes to ~48 MB. `targetWidth/targetHeight` capped
  at 4096 keeps it bounded.

---

## 5. Part B — Application links: server

### 5.1 Migration `000056_add_link_purpose.go`

- `util/schema.go`: `Fields.Link.Purpose = "purpose"`.
- `util/constants.go`: `PurposeApplication = "application"`,
  `LinkPurposes = []string{PurposeApplication}`.
- Migration: add `SelectField{Name: purpose, Values: util.LinkPurposes,
  MaxSelect: 1}` (optional — empty means a plain share). Idempotent, with
  down migration.
- No rule change: links rules already cover the owner.

### 5.2 Invariant: an application is always watermarked

In `hooks/links.go` (create **and** update, model-level `OnRecordCreate/
OnRecordUpdate`):

```go
if rec.GetString(util.Fields.Link.Purpose) == util.PurposeApplication &&
    !rec.GetBool(util.Fields.Link.Watermark) {
    return util.AsFieldValidationError(util.Fields.Link.Watermark, util.Errors.ApplicationNeedsWatermark)
}
```

New error `ApplicationNeedsWatermark` (`application_needs_watermark`) in
`util/errors.go` **and** `app/lib/core/network/app_errors.dart`. Consider
listing it in CLAUDE.md's invariants once shipped.

### 5.3 "Your application was opened" notification

- `util/constants.go`: `NotificationLinkOpened = "link_opened"`; append to
  `NotificationTypes`.
- Migration (same file or `000057`): update the `notifications.type` select
  field's `Values` to `util.NotificationTypes` (the field was created in
  000022 with the old list; without this the insert fails validation).
- `routes/publicLinks.go` POST resolve, after `services.ClaimLinkView`:
  emit **once**, when `currentViews == 1` and purpose is `application`:
  `services.EmitNotification(app, owner, workspace, util.NotificationLinkOpened,
  "Your application was opened", link.label, util.Coll.Links, link.Id)`.
  Only the first open, so 30 reloads are not 30 notifications.
- App: map `link_opened` to an icon and route (Applications tab) wherever
  notification types are switched on.

### 5.4 Landlord page layout (`routes/publicPage.go`)

- `pageData.Purpose` from the link; the resolve JSON (`publicLinks.go` and
  `publicShort.go`) adds `"purpose"`.
- In `render(data)`: when `data.purpose === 'application'`, render
  1. an **Applicant** card from known keys of the tenant template
     (`full_name`, `email`, `phone`, `current_address`, `employer`,
     `occupation`, `net_income`, `move_in_date`, plus §6.5 additions) as a
     label/value list,
  2. a **Documents** card with every file record (existing `View` + `Save`),
  3. anything else in the generic list, so no record is ever hidden.
- Header copy: "Bewerbung · {label}". Keep all text through `el()` /
  `textContent` (no `innerHTML`).
- The watermark overlay (already there) covers all three cards.

---

## 6. Part B — Application links: app

### 6.1 Model and filtering

- `Link.purpose` (`String`, default `''`) + `bool get isApplication`.
- **My links** in `SharesScreen` shows `!isApplication`; the new tab shows the
  rest. The `TableStore` source for My links filters accordingly.

### 6.2 Store `features/applications/store/applications_store.dart`

Singleton `Stores.applications`:

```dart
final ObservableTextController address = ObservableTextController();
@observable ObservableSet<String> selectedRecordIds = ObservableSet();
@observable int expiryDays = 14;          // 7 | 14 | 30
@observable bool isSubmitting = false;

@computed String get stampText => 'Nur für Wohnungsbewerbung ${address.text.trim()}';
@computed bool get canSubmit => address.text.trim().isNotEmpty && selectedRecordIds.isNotEmpty;

@action void startDraft();                // preselect records whose key is in the tenant template + all file records
@action Future<Link?> apply();            // see 6.3
@action Future<bool> extend(Link l);      // expiresAt = max(now, current) + 14 days
```

### 6.3 What `apply()` sends

Through `SharesStore.createShareSpec` (one source of truth for the API
preview), extended with `purpose`:

| Field | Value |
|---|---|
| `slug` | random, same generator as the share sheet — **move `_generateRandomSlug` to `core/utils/` first** so both use one |
| `label` | `Wohnungsbewerbung <address>` |
| `records` / `sections` | selected ids |
| `watermark` / `watermarkText` | `true` / `stampText` |
| `expiresAt` | now + `expiryDays` |
| `identity` | primary identity if any (signed applications read as verified) |
| `purpose` | `application` |

After success: copy the **web URL** (see §8, not the `revoked://` link) and
toast "Link copied — paste it into the listing's message".

### 6.4 UI

- **Share screen tabs:** `My links | Applications | Bookmarks`.
- **Applications tab** (`features/applications/view/applications_tab.dart`):
  top-right `AppButton` "New application" (like "New group" in Bookmarks),
  then one `AppEntityCard` per application:
  - title: address (label without the prefix), date: created
  - tags: `AppBadge(watermark, '#tag')`, `AppBadge(eye, 'Opened N×')` from
    `viewCount`, `AppBadge(clock, 'Expires …')`, status badge
  - actions: Copy link (primary), QR (existing `share_sheet`), Extend 14 days,
    Revoke (destructive, confirm), Delete (destructive, confirm)
- **Apply sheet** (`apply_sheet.dart`, same structure as the share create
  sheet): Address row (`showAppEditSheet`), Documents (`AppCheckRow` per
  vault record, files first), Expiry (`AppSegmented` 7/14/30), a muted preview
  of the stamp line, Cancel / Create. Warn inline when a selected file is not an
  image or PDF: it will be refused on a watermarked share.

### 6.5 Template

Extend `templates/tenant_application.json` (built-ins resync on serve):
`household_size` (number), `pets` (text), `id_document` (file, reason:
"Redact the access number and serial number before uploading"),
`rent_debt_certificate` (file, "Mietschuldenfreiheitsbescheinigung"). Keep
existing keys unchanged — requests may already reference them.

---

## 7. Test plan

**Go (`tests/`)**
- `purpose=application` without `watermark` → 400 with
  `application_needs_watermark`; turning watermark off on an application → 400.
- First resolve of an application emits exactly one `link_opened`
  notification; a second resolve emits none; a plain share emits none.
- `TestAccessRegistryMatchesRules` still green (no rule change expected).
- Public page HTML for an application contains the application layout marker;
  JSON resolve contains `purpose`.
- Existing watermark tests stay green.

**Flutter (`app/test/`)**
- `toPixelRect` rounds outward and clamps.
- `renderRedacted` on a synthetic white image: every box centre is black,
  pixels outside untouched; `verifyRedacted` rejects a PNG with a missing box.
- `ApplicationsStore` builds the expected create spec (purpose, watermark,
  expiry) — pure, no network.
- `no_setstate_test`, `rounded_ink_test` pass (no `setState`, ink radii).

**Manual**
- Portrait phone photo → redaction → upload → landlord page: upright, boxes
  black, stamp tiled over it.
- Landlord flow in a private window on another device.

---

## 8. Open questions (decide before M3)

1. **Which URL goes to the landlord?** It must be a web URL on a host the
   landlord can reach (`https://<public-domain>/s/<slug>`). A self-hosted
   instance on `localhost` or a LAN IP is useless here — this feature needs the
   hosted server or a public self-hosted domain. Build the URL from the
   server's advertised domain (`/api/server`), not the app's base URL.
2. Should `link_opened` apply to every share (opt-in per link) instead of only
   applications?
3. PDF redaction: out of scope. Later: rasterise pages (`pdfrx`), redact as
   images, re-assemble — accept that the text layer is lost.
4. Account model: flat hunters won't self-host; this depends on the hosted
   `revoked.link` and the device-key login discussion.

---

## 9. Milestones

| # | Scope | Size |
|---|---|---|
| M1 | Redaction editor + export + tests, hooked into `VaultFileRow` | 4–5 days |
| M2 | Server: `purpose` migration, application ⇒ watermark hook, `link_opened` notification + migration, tests | 2 days |
| M3 | App: `Link.purpose`, `ApplicationsStore`, apply sheet, Applications tab, shared slug generator | 4 days |
| M4 | Landlord page application layout | 1–2 days |
| M5 | Template extension, ID presets measured, "Replace with redacted copy", docs (`docs/guide/sharing.md`, API reference) | 2 days |

Build in order: M1 is independent and the most valuable on its own; M2 must
land before M3; M4 can go in parallel with M3.
