package services

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"testing"
)

func solidPNG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.White)
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestWatermarkImageStampsEveryPartOfTheImage(t *testing.T) {
	out, err := WatermarkFile(solidPNG(t, 800, 600), "Nur für Wohnungsbewerbung Musterstr. 5 · 2026-09-28 · #abc123")
	if err != nil {
		t.Fatalf("stamp failed: %v", err)
	}
	if out.Mime != "image/png" {
		t.Fatalf("mime = %s, want image/png", out.Mime)
	}
	img, err := png.Decode(bytes.NewReader(out.Bytes))
	if err != nil {
		t.Fatalf("stamped copy does not decode: %v", err)
	}
	if b := img.Bounds(); b.Dx() != 800 || b.Dy() != 600 {
		t.Fatalf("size changed to %v", b)
	}

	// Cropping must not be able to remove it: every quadrant carries ink.
	quadrants := []image.Rectangle{
		image.Rect(0, 0, 400, 300), image.Rect(400, 0, 800, 300),
		image.Rect(0, 300, 400, 600), image.Rect(400, 300, 800, 600),
	}
	for _, q := range quadrants {
		marked := false
		for y := q.Min.Y; y < q.Max.Y && !marked; y++ {
			for x := q.Min.X; x < q.Max.X; x++ {
				if r, _, _, _ := img.At(x, y).RGBA(); r < 0xF000 {
					marked = true
					break
				}
			}
		}
		if !marked {
			t.Fatalf("quadrant %v carries no watermark", q)
		}
	}
}

func TestWatermarkKeepsJPEGAsJPEGAndShrinksLargeImages(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 3000, 1500))
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	out, err := WatermarkFile(buf.Bytes(), "line")
	if err != nil {
		t.Fatalf("stamp failed: %v", err)
	}
	if out.Mime != "image/jpeg" || out.Ext != ".jpg" {
		t.Fatalf("got %s %s, want image/jpeg .jpg", out.Mime, out.Ext)
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(out.Bytes))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Width != maxWatermarkEdge || cfg.Height != maxWatermarkEdge/2 {
		t.Fatalf("got %dx%d, want %dx%d", cfg.Width, cfg.Height, maxWatermarkEdge, maxWatermarkEdge/2)
	}
}

// A few hundred bytes can declare billions of pixels; the header alone must be
// enough to refuse it, before anything is allocated for the pixels.
func TestWatermarkRefusesDecompressionBombs(t *testing.T) {
	var buf bytes.Buffer
	buf.WriteString("\x89PNG\r\n\x1a\n")
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:4], 100_000)
	binary.BigEndian.PutUint32(ihdr[4:8], 100_000)
	ihdr[8], ihdr[9] = 8, 2
	writeChunk := func(kind string, data []byte) {
		binary.Write(&buf, binary.BigEndian, uint32(len(data)))
		buf.WriteString(kind)
		buf.Write(data)
		crc := crc32.NewIEEE()
		crc.Write([]byte(kind))
		crc.Write(data)
		binary.Write(&buf, binary.BigEndian, crc.Sum32())
	}
	writeChunk("IHDR", ihdr)
	writeChunk("IEND", nil)

	if _, err := WatermarkFile(buf.Bytes(), "line"); !errors.Is(err, ErrNotWatermarkable) {
		t.Fatalf("err = %v, want ErrNotWatermarkable", err)
	}
}

func TestWatermarkRefusesWhatItCannotStamp(t *testing.T) {
	for name, data := range map[string][]byte{
		"text":       []byte("just some text"),
		"zip":        []byte("PK\x03\x04rest-of-an-archive"),
		"broken pdf": []byte("%PDF-1.4 not really a pdf"),
		"svg":        []byte(`<svg xmlns="http://www.w3.org/2000/svg"></svg>`),
		"truncated":  solidPNG(t, 50, 50)[:40],
	} {
		if _, err := WatermarkFile(data, "line"); err == nil {
			t.Errorf("%s: stamped, want a refusal", name)
		}
	}
}

func TestJpegOrientationIsReadFromExif(t *testing.T) {
	for _, order := range []binary.ByteOrder{binary.LittleEndian, binary.BigEndian} {
		tiff := make([]byte, 26)
		if order == binary.LittleEndian {
			copy(tiff, "II")
		} else {
			copy(tiff, "MM")
		}
		order.PutUint16(tiff[2:4], 42)
		order.PutUint32(tiff[4:8], 8)
		order.PutUint16(tiff[8:10], 1)
		order.PutUint16(tiff[10:12], 0x0112)
		order.PutUint16(tiff[12:14], 3)
		order.PutUint32(tiff[14:18], 1)
		order.PutUint16(tiff[18:20], 6)

		app1 := append([]byte("Exif\x00\x00"), tiff...)
		jpg := []byte{0xFF, 0xD8, 0xFF, 0xE1}
		jpg = binary.BigEndian.AppendUint16(jpg, uint16(len(app1)+2))
		jpg = append(jpg, app1...)
		jpg = append(jpg, 0xFF, 0xD9)

		if got := jpegOrientation(jpg); got != 6 {
			t.Fatalf("orientation = %d, want 6", got)
		}
	}
	if got := jpegOrientation([]byte{0xFF, 0xD8, 0xFF}); got != 1 {
		t.Fatalf("truncated JPEG: orientation = %d, want 1", got)
	}
}

// Orientation 6 is the usual portrait phone photo: stored sideways, to be
// turned 90° clockwise. A 2×1 image with a red left pixel becomes 1×2 with
// red on top.
func TestOrientTurnsPhonePhotosUpright(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 2, 1))
	red := color.RGBA{255, 0, 0, 255}
	blue := color.RGBA{0, 0, 255, 255}
	src.SetRGBA(0, 0, red)
	src.SetRGBA(1, 0, blue)

	got := orient(src, 6)
	if b := got.Bounds(); b.Dx() != 1 || b.Dy() != 2 {
		t.Fatalf("size = %v, want 1x2", b)
	}
	if got.RGBAAt(0, 0) != red || got.RGBAAt(0, 1) != blue {
		t.Fatalf("pixels = %v %v, want red over blue", got.RGBAAt(0, 0), got.RGBAAt(0, 1))
	}

	got = orient(src, 8)
	if got.RGBAAt(0, 0) != blue || got.RGBAAt(0, 1) != red {
		t.Fatalf("orientation 8: pixels = %v %v, want blue over red", got.RGBAAt(0, 0), got.RGBAAt(0, 1))
	}
}

func TestWatermarkTagIsShortAndStable(t *testing.T) {
	if got := WatermarkTag("AbCdEf123456789"); got != "abcdef" {
		t.Fatalf("tag = %q, want abcdef", got)
	}
}
