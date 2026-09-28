package routes

import (
	"mime"
	"testing"
)

func TestAttachmentDispositionCarriesUTF8Names(t *testing.T) {
	got := attachmentDisposition(`Lindenallee 12, 50968 Köln "Süd".zip`)
	want := `attachment; filename="Lindenallee 12, 50968 Koeln Sued.zip"; ` +
		`filename*=UTF-8''Lindenallee%2012%2C%2050968%20K%C3%B6ln%20S%C3%BCd.zip`
	if got != want {
		t.Fatalf("got  %s\nwant %s", got, want)
	}
	_, params, err := mime.ParseMediaType(got)
	if err != nil {
		t.Fatal(err)
	}
	// Go's parser prefers filename* exactly as browsers do.
	if params["filename"] != "Lindenallee 12, 50968 Köln Süd.zip" {
		t.Fatalf("decoded filename = %q", params["filename"])
	}
}

func TestAttachmentDispositionCannotBreakTheHeader(t *testing.T) {
	got := attachmentDisposition("a\r\nSet-Cookie: x=1\\\"; b.pdf")
	if _, _, err := mime.ParseMediaType(got); err != nil {
		t.Fatalf("unparseable header %q: %v", got, err)
	}
	for _, c := range got {
		if c == '\r' || c == '\n' {
			t.Fatalf("header contains a line break: %q", got)
		}
	}
}
