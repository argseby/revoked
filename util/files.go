package util

import (
	"os"
	"strconv"
	"strings"
)

// Operator policy for uploaded files, in megabytes. Unset or -1 means
// unlimited; 0 disables file uploads entirely. The schema's own file field
// stays permissive because migrations snapshot it per deploy — these are read
// at request time and enforced by the record hook, so a change needs only a
// restart, not a migration.
const (
	FileMaxSizeEnv    = "FILE_MAX_SIZE"
	FileMaxStorageEnv = "FILE_MAX_STORAGE"
)

// CleanFilename normalizes a user-supplied file name to something safe to hand
// back in a download. Path separators are the point: a name is a label, never a
// location, and one that traverses would let a rename reach outside the record.
func CleanFilename(name string) (string, bool) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", false
	}
	if strings.ContainsAny(name, `/\`) {
		return "", false
	}
	for _, r := range name {
		if r < 0x20 || r == 0x7f {
			return "", false
		}
	}
	// A leading dot hides the file on unix desktops and confuses sync tools.
	name = strings.TrimLeft(name, ".")
	if name == "" {
		return "", false
	}
	if len(name) > 255 {
		name = name[:255]
	}
	return name, true
}

// FileLimitBytes reads a megabyte limit from the environment; -1 means
// unlimited.
func FileLimitBytes(name string) int64 {
	v := strings.TrimSpace(os.Getenv(name))
	if v == "" {
		return -1
	}
	mb, err := strconv.ParseInt(v, 10, 64)
	if err != nil || mb < 0 {
		return -1
	}
	return mb << 20
}
