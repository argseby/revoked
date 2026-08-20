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
