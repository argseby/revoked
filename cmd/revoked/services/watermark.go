package services

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	_ "image/gif"
	"image/jpeg"
	"image/png"
	"math"
	"strings"
	"time"
	"unicode/utf8"

	"revoked/util"

	"github.com/pdfcpu/pdfcpu/pkg/api"
	"github.com/pdfcpu/pdfcpu/pkg/pdfcpu/model"
	"github.com/pdfcpu/pdfcpu/pkg/pdfcpu/types"
	"github.com/pocketbase/pocketbase/core"
	_ "golang.org/x/image/bmp"
	xdraw "golang.org/x/image/draw"
	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/f64"
	"golang.org/x/image/math/fixed"
	_ "golang.org/x/image/webp"
)

// ErrNotWatermarkable reports a file that cannot be stamped. A watermarked
// share refuses to serve it rather than fall back to the unmarked original.
var ErrNotWatermarkable = errors.New("file cannot be watermarked")

const (
	// A small file can declare enormous dimensions; decoding allocates for the
	// declared size, so the header is checked before anything is decoded.
	maxWatermarkSourcePixels = 60_000_000
	// A stamped copy is for reading, not printing, and a smaller copy of an ID
	// is also a less useful one to misuse.
	maxWatermarkEdge = 2400
	// MaxWatermarkInputBytes bounds what is read into memory to be stamped;
	// uploads themselves may be unlimited.
	MaxWatermarkInputBytes = 64 << 20
)

var watermarkFont = mustParseFont(goregular.TTF)

func mustParseFont(ttf []byte) *opentype.Font {
	f, err := opentype.Parse(ttf)
	if err != nil {
		panic(err)
	}
	return f
}

func init() {
	// pdfcpu otherwise creates a config directory in the user's home on first use.
	api.DisableConfigDir()
}

// Stamped is a watermarked copy of a stored file.
type Stamped struct {
	Bytes []byte
	Mime  string
	// Ext is the extension the copy should be saved under; it differs from the
	// original's when an image had to be re-encoded in another format.
	Ext string
}

// WatermarkLine is the text a share stamps onto its files: what it is for, the
// day it was read, and a short tag naming the share, so any copy that surfaces
// later points back at the link it was read through.
func WatermarkLine(link *core.Record, now time.Time) string {
	text := strings.TrimSpace(link.GetString(util.Fields.Link.WatermarkText))
	if text == "" {
		text = strings.TrimSpace(link.GetString(util.Fields.Link.Label))
	}
	if text == "" {
		text = "Shared via revoked"
	}
	return fmt.Sprintf("%s · %s · #%s", text, now.Format("2006-01-02"), WatermarkTag(link.Id))
}

// PreviewWatermarkLine is the stamp an owner previews before sharing. Its tag
// is the literal "preview", so a preview copy can never pass for one that was
// read through a real share.
func PreviewWatermarkLine(text string, now time.Time) string {
	return fmt.Sprintf("%s · %s · #preview", text, now.Format("2006-01-02"))
}

// maxWatermarkTextRunes matches the links.watermarkText field.
const maxWatermarkTextRunes = 120

// ValidWatermarkText trims text and reports whether it is a stamp text a link
// would accept: one line of 1 to 120 characters.
func ValidWatermarkText(text string) (string, bool) {
	text = strings.TrimSpace(text)
	n := utf8.RuneCountInString(text)
	if n == 0 || n > maxWatermarkTextRunes || strings.ContainsAny(text, "\r\n\t") {
		return "", false
	}
	return text, true
}

// WatermarkTag is the short share reference printed in every stamp. The owner
// sees the same tag on the share, which is how a leaked copy is traced.
func WatermarkTag(linkId string) string {
	if len(linkId) > 6 {
		linkId = linkId[:6]
	}
	return strings.ToLower(linkId)
}

// WatermarkFile stamps line across a PDF or raster image. The type is decided
// from the bytes, never from a stored MIME type.
func WatermarkFile(data []byte, line string) (Stamped, error) {
	head := data
	if len(head) > 1024 {
		head = head[:1024]
	}
	if bytes.Contains(head, []byte("%PDF-")) {
		out, err := watermarkPDF(data, line)
		if err != nil {
			return Stamped{}, err
		}
		return Stamped{Bytes: out, Mime: "application/pdf", Ext: ".pdf"}, nil
	}
	return watermarkImage(data, line)
}

func watermarkImage(data []byte, line string) (Stamped, error) {
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || cfg.Width <= 0 || cfg.Height <= 0 ||
		cfg.Width*cfg.Height > maxWatermarkSourcePixels {
		return Stamped{}, ErrNotWatermarkable
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return Stamped{}, ErrNotWatermarkable
	}

	// Re-encoding drops the EXIF block, so a phone photo's orientation has to
	// be applied to the pixels or the copy shows up sideways.
	var canvas *image.RGBA
	if format == "jpeg" {
		canvas = orient(img, jpegOrientation(data))
	} else {
		canvas = toRGBA(img)
	}
	canvas = fitWithin(canvas, maxWatermarkEdge)
	stampImage(canvas, line)

	var out bytes.Buffer
	if format == "jpeg" {
		if err := jpeg.Encode(&out, canvas, &jpeg.Options{Quality: 88}); err != nil {
			return Stamped{}, err
		}
		return Stamped{Bytes: out.Bytes(), Mime: "image/jpeg", Ext: ".jpg"}, nil
	}
	if err := png.Encode(&out, canvas); err != nil {
		return Stamped{}, err
	}
	return Stamped{Bytes: out.Bytes(), Mime: "image/png", Ext: ".png"}, nil
}

func toRGBA(img image.Image) *image.RGBA {
	b := img.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	draw.Draw(dst, dst.Bounds(), img, b.Min, draw.Src)
	return dst
}

func fitWithin(img *image.RGBA, edge int) *image.RGBA {
	w, h := img.Bounds().Dx(), img.Bounds().Dy()
	if w <= edge && h <= edge {
		return img
	}
	scale := float64(edge) / float64(max(w, h))
	dst := image.NewRGBA(image.Rect(0, 0, max(1, int(float64(w)*scale)), max(1, int(float64(h)*scale))))
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), img, img.Bounds(), xdraw.Src, nil)
	return dst
}

// stampImage tiles line diagonally over the whole image. A single corner stamp
// crops away in seconds; one across the entire document cannot be removed
// without ruining it.
func stampImage(dst *image.RGBA, line string) {
	w, h := dst.Bounds().Dx(), dst.Bounds().Dy()
	size := math.Max(11, math.Min(64, float64(min(w, h))/26))

	// The text layer is laid out at half resolution and scaled up while it is
	// rotated, which keeps its memory a quarter of a full-size layer.
	const k = 2.0
	face, err := opentype.NewFace(watermarkFont, &opentype.FaceOptions{Size: size / k, DPI: 72})
	if err != nil {
		return
	}
	defer face.Close()

	phrase := line + "      "
	advance := font.MeasureString(face, phrase).Ceil()
	if advance <= 0 {
		return
	}
	side := int(math.Hypot(float64(w), float64(h))/k) + 2
	layer := image.NewAlpha(image.Rect(0, 0, side, side))
	gap := int(size / k * 3.4)
	for row, y := 0, gap; y < side+gap; row, y = row+1, y+gap {
		shift := (row % 2) * advance / 2
		for x := -shift; x < side; x += advance {
			d := font.Drawer{Dst: layer, Src: image.Opaque, Face: face, Dot: fixed.P(x, y)}
			d.DrawString(phrase)
		}
	}

	theta := -math.Pi / 6
	c, s := math.Cos(theta)*k, math.Sin(theta)*k
	centre := float64(side) / 2
	cx, cy := float64(w)/2, float64(h)/2
	toDst := f64.Aff3{
		c, -s, cx - c*centre + s*centre,
		s, c, cy - s*centre - c*centre,
	}
	mask := image.NewAlpha(dst.Bounds())
	xdraw.ApproxBiLinear.Transform(mask, toDst, layer, layer.Bounds(), xdraw.Src, nil)

	// A light halo under dark ink keeps the line legible on dark photos and
	// light scans alike.
	r := dst.Bounds()
	draw.DrawMask(dst, r, image.NewUniform(color.NRGBA{255, 255, 255, 80}), image.Point{}, mask, image.Pt(1, 1), draw.Over)
	draw.DrawMask(dst, r, image.NewUniform(color.NRGBA{30, 30, 30, 100}), image.Point{}, mask, image.Point{}, draw.Over)
}

// jpegOrientation reads the EXIF Orientation tag, or 1 when there is none.
func jpegOrientation(data []byte) int {
	if len(data) < 4 || data[0] != 0xFF || data[1] != 0xD8 {
		return 1
	}
	i := 2
	for i+4 <= len(data) {
		if data[i] != 0xFF {
			return 1
		}
		marker := data[i+1]
		if marker == 0xDA || marker == 0xD9 {
			return 1
		}
		size := int(binary.BigEndian.Uint16(data[i+2 : i+4]))
		if size < 2 || i+2+size > len(data) {
			return 1
		}
		segment := data[i+4 : i+2+size]
		if marker == 0xE1 && len(segment) > 6 && string(segment[:6]) == "Exif\x00\x00" {
			return exifOrientation(segment[6:])
		}
		i += 2 + size
	}
	return 1
}

func exifOrientation(tiff []byte) int {
	if len(tiff) < 8 {
		return 1
	}
	var order binary.ByteOrder
	switch string(tiff[:2]) {
	case "II":
		order = binary.LittleEndian
	case "MM":
		order = binary.BigEndian
	default:
		return 1
	}
	ifd := int(order.Uint32(tiff[4:8]))
	if ifd < 8 || ifd+2 > len(tiff) {
		return 1
	}
	count := int(order.Uint16(tiff[ifd : ifd+2]))
	for n := 0; n < count; n++ {
		entry := ifd + 2 + n*12
		if entry+12 > len(tiff) {
			return 1
		}
		if order.Uint16(tiff[entry:entry+2]) == 0x0112 {
			v := int(order.Uint16(tiff[entry+8 : entry+10]))
			if v >= 1 && v <= 8 {
				return v
			}
			return 1
		}
	}
	return 1
}

// orient returns img turned upright for an EXIF orientation value.
func orient(img image.Image, orientation int) *image.RGBA {
	src := toRGBA(img)
	if orientation <= 1 || orientation > 8 {
		return src
	}
	w, h := src.Bounds().Dx(), src.Bounds().Dy()
	dw, dh := w, h
	if orientation >= 5 {
		dw, dh = h, w
	}
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	for y := 0; y < dh; y++ {
		for x := 0; x < dw; x++ {
			var sx, sy int
			switch orientation {
			case 2:
				sx, sy = w-1-x, y
			case 3:
				sx, sy = w-1-x, h-1-y
			case 4:
				sx, sy = x, h-1-y
			case 5:
				sx, sy = y, x
			case 6:
				sx, sy = y, h-1-x
			case 7:
				sx, sy = w-1-y, h-1-x
			case 8:
				sx, sy = w-1-y, x
			}
			dst.SetRGBA(x, y, src.RGBAAt(sx, sy))
		}
	}
	return dst
}

func watermarkPDF(data []byte, line string) ([]byte, error) {
	conf := model.NewDefaultConfiguration()
	conf.ValidationMode = model.ValidationRelaxed
	// The upload cap bounds the file, not what it decompresses to.
	conf.Limits.MaxStreamBytes = 64 << 20
	conf.Limits.MaxDecodeBytes = 64 << 20
	conf.Limits.MaxImageBytes = 64 << 20
	conf.Limits.MaxImagePixels = maxWatermarkSourcePixels
	conf.Limits.MaxObjectCount = 200_000
	conf.Limits.MaxXRefEntries = 200_000

	dims, err := api.PageDims(bytes.NewReader(data), conf)
	if err != nil || len(dims) == 0 || len(dims) > maxWatermarkPages {
		return nil, ErrNotWatermarkable
	}

	stamps := make(map[int][]*model.Watermark, len(dims))
	for i, d := range dims {
		for _, at := range pdfStampGrid(d.Width, d.Height, line) {
			// On top of the content: a scanned page is one opaque image, and a
			// stamp underneath it would never be seen.
			wm, err := api.TextWatermark(line, fmt.Sprintf(
				"fontname:Helvetica, points:%g, scalefactor:1 abs, rotation:%g, opacity:0.3, fillcolor:#1e1e1e, rendermode:0, position:c, offset:%.1f %.1f",
				pdfStampPoints, pdfStampDegrees, at[0], at[1]), true, false, types.POINTS)
			if err != nil {
				return nil, err
			}
			stamps[i+1] = append(stamps[i+1], wm)
		}
	}

	var out bytes.Buffer
	if err := api.AddWatermarksSliceMap(bytes.NewReader(data), &out, stamps, conf); err != nil {
		return nil, ErrNotWatermarkable
	}
	return out.Bytes(), nil
}

const (
	pdfStampPoints  = 12.0
	pdfStampDegrees = 30.0
	// Each page carries a few dozen stamps, so the page count bounds the work.
	maxWatermarkPages = 300
)

// pdfStampGrid returns offsets from the page centre for a lattice of stamps
// laid along the stamp's own angle, so the lines run diagonally across the
// whole page the way the image stamp does, corners included.
func pdfStampGrid(width, height float64, line string) [][2]float64 {
	length := float64(utf8.RuneCountInString(line)) * pdfStampPoints * 0.52
	stepX := length + pdfStampPoints*4
	stepY := pdfStampPoints * 7
	theta := pdfStampDegrees * math.Pi / 180
	c, s := math.Cos(theta), math.Sin(theta)
	reach := math.Hypot(width, height)/2 + stepX
	limitX, limitY := width/2+length/2, height/2+length/2

	var grid [][2]float64
	for row, v := 0, -reach; v <= reach; row, v = row+1, v+stepY {
		shift := float64(row%2) * stepX / 2
		for u := -reach - shift; u <= reach; u += stepX {
			x, y := u*c-v*s, u*s+v*c
			if math.Abs(x) <= limitX && math.Abs(y) <= limitY {
				grid = append(grid, [2]float64{x, y})
			}
		}
	}
	return grid
}
