package util

import (
	"runtime/debug"
	"sync"
)

// releaseVersion is set with `-ldflags -X` by a build whose source arrived
// without .git, such as a Portainer stack, where the toolchain has nothing to
// stamp from. A real git checkout wins over it.
var releaseVersion string

// Version is the release this binary was built from: `v0.22.0` on a tagged
// commit, a pseudo-version past it otherwise, `+dirty` with uncommitted
// changes. The Go toolchain stamps it from the git checkout at build time, so
// nothing has to be kept in step by hand. `go run` stamps nothing and reports
// `dev`.
var Version = sync.OnceValue(func() string {
	info, ok := debug.ReadBuildInfo()
	if ok {
		if v := info.Main.Version; v != "" && v != "(devel)" {
			return v
		}
	}
	if releaseVersion != "" {
		return releaseVersion
	}
	if !ok {
		return "dev"
	}
	for _, s := range info.Settings {
		if s.Key == "vcs.revision" && len(s.Value) >= 12 {
			return "dev-" + s.Value[:12]
		}
	}
	return "dev"
})
