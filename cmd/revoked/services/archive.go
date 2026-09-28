package services

import (
	"archive/zip"
	"io"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"
)

// LinkFileRecords returns the file records a link grants, each once and in
// grant order.
func LinkFileRecords(app core.App, link *core.Record) []*core.Record {
	ids := link.GetStringSlice(util.Fields.Link.Records)
	seen := map[string]bool{}
	var out []*core.Record
	for _, id := range ids {
		if seen[id] {
			continue
		}
		seen[id] = true
		rec, err := app.FindRecordById(util.Coll.Records, id)
		if err != nil || rec == nil || rec.GetString(util.Fields.Record.Type) != util.TypeFile ||
			rec.GetString(util.Fields.Record.File) == "" {
			continue
		}
		out = append(out, rec)
	}
	return out
}

// LinkGrantsRecord reports whether the link grants recordId. A section only
// groups records on the page; the resolve serves those in the link's own
// records, and nothing reachable by download may reach further than it.
func LinkGrantsRecord(link *core.Record, recordId string) bool {
	return slices.Contains(link.GetStringSlice(util.Fields.Link.Records), recordId)
}

// SafeFileName strips what a file name must not carry into a download header
// or a zip entry: path separators, control characters and quotes.
func SafeFileName(name string) string {
	name = strings.Map(func(r rune) rune {
		switch {
		case r == '/' || r == '\\':
			return '_'
		case r == '"' || unicode.IsControl(r):
			return -1
		}
		return r
	}, name)
	name = strings.TrimSpace(name)
	if strings.Trim(name, ".") == "" {
		return "file"
	}
	return name
}

// FileDownloadName is the name the owner gave a file record, falling back to
// the name it is stored under.
func FileDownloadName(rec *core.Record) string {
	if name := rec.GetString(util.Fields.Record.Filename); name != "" {
		return name
	}
	return rec.GetString(util.Fields.Record.File)
}

// WriteLinkArchive zips files into w, each stamped with line, or as stored when
// line is empty. A file that cannot be stamped is left out, never included
// unmarked. It returns how many files went in; with none, nothing reaches w,
// so the caller can still answer with an error.
func WriteLinkArchive(app core.App, files []*core.Record, line string, w io.Writer) (int, error) {
	fsys, err := app.NewFilesystem()
	if err != nil {
		return 0, err
	}
	defer fsys.Close()

	zw := zip.NewWriter(w)
	taken := map[string]bool{}
	written := 0
	for _, rec := range files {
		key := rec.BaseFilesPath() + "/" + rec.GetString(util.Fields.Record.File)
		name := FileDownloadName(rec)
		header := func(name string) *zip.FileHeader {
			return &zip.FileHeader{
				Name:     uniqueEntryName(taken, SafeFileName(name)),
				Method:   zip.Deflate,
				Modified: rec.GetDateTime(util.Fields.Record.Updated).Time(),
			}
		}

		if line != "" {
			data, ok := readStampable(fsys, key)
			if !ok {
				continue
			}
			stamped, err := WatermarkFile(data, line)
			if err != nil {
				continue
			}
			entry, err := zw.CreateHeader(header(strings.TrimSuffix(name, filepath.Ext(name)) + stamped.Ext))
			if err != nil {
				return written, err
			}
			if _, err := entry.Write(stamped.Bytes); err != nil {
				return written, err
			}
		} else {
			r, err := fsys.GetReader(key)
			if err != nil {
				continue
			}
			entry, err := zw.CreateHeader(header(name))
			if err == nil {
				_, err = io.Copy(entry, r)
			}
			r.Close()
			if err != nil {
				return written, err
			}
		}
		written++
	}
	if written == 0 {
		return 0, nil
	}
	return written, zw.Close()
}

func readStampable(fsys *filesystem.System, key string) ([]byte, bool) {
	r, err := fsys.GetReader(key)
	if err != nil {
		return nil, false
	}
	defer r.Close()
	data, err := io.ReadAll(io.LimitReader(r, MaxWatermarkInputBytes+1))
	if err != nil || len(data) > MaxWatermarkInputBytes {
		return nil, false
	}
	return data, true
}

// uniqueEntryName numbers a repeated name the way a file manager does. Names
// compare case-insensitively, since most extractors write to a filesystem that
// does.
func uniqueEntryName(taken map[string]bool, name string) string {
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)
	candidate := name
	for n := 2; taken[strings.ToLower(candidate)]; n++ {
		candidate = base + " (" + strconv.Itoa(n) + ")" + ext
	}
	taken[strings.ToLower(candidate)] = true
	return candidate
}
