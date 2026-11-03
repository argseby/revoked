package util

import (
	"runtime/debug"
	"sync"
)

// releaseVersion is set with `-ldflags -X` by the release image build. It wins
// over the toolchain's stamp: .dockerignore leaves files out of the build
// context, so git sees them deleted and stamps the release `+dirty`.
var releaseVersion string

// Version is the release this binary was built from: `v0.22.0` on a tagged
// commit, a pseudo-version past it otherwise, `+dirty` with uncommitted
// changes. The Go toolchain stamps it from the git checkout at build time, so
// nothing has to be kept in step by hand. `go run` stamps nothing and reports
// `dev`.
var Version = sync.OnceValue(func() string {
	if releaseVersion != "" {
		return releaseVersion
	}
	info, ok := debug.ReadBuildInfo()
	if ok {
		if v := info.Main.Version; v != "" && v != "(devel)" {
			return v
		}
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
