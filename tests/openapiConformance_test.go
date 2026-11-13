package tests

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"revoked/tests/testutils"
)

// Every response the suite receives is checked against docs/api/openapi.yaml
// as it is served (testutils/conformance.go). The verdict comes after the last
// test, so the whole suite is the conformance test: a field, status or shape
// the spec does not describe fails the run. Where the two disagree, the spec
// is what gets fixed, unless the server is the one that is wrong.
func TestMain(m *testing.M) {
	code := m.Run()
	violations, checked := testutils.ConformanceViolations()
	if len(violations) > 0 {
		fmt.Fprintf(os.Stderr, "\n%d responses checked; these depart from docs/api/openapi.yaml:\n  %s\n",
			checked, strings.Join(violations, "\n  "))
		if code == 0 && os.Getenv("REVOKED_SKIP_CONFORMANCE") == "" {
			code = 1
		}
	}
	os.Exit(code)
}

func TestOpenAPISpecLoads(t *testing.T) {
	if _, err := testutils.LoadSpec(testutils.SpecPath); err != nil {
		t.Fatal(err)
	}
}
