#!/usr/bin/env bash
# Regenerates test/fixtures/rsa_signature.json using the real server root key
# code, so the Dart verifier is tested against what the server actually emits.
set -euo pipefail
cd "$(dirname "$0")/../.."
go run ./app/tool/gen_rsa_fixture.go > app/test/fixtures/rsa_signature.json
echo "wrote app/test/fixtures/rsa_signature.json"
