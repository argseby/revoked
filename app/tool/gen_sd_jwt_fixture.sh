#!/usr/bin/env bash
# Regenerates the two fixtures that tie the app's SD-JWT code to the server's:
#
#   test/fixtures/sd_jwt.json            a credential the server code issued
#   test/fixtures/app_presentation.json  that credential, presented by the app's code
#
# The Dart tests check the first, the Go tests verify the second. The holder's
# private key exists only for the length of this script.
set -euo pipefail
cd "$(dirname "$0")/../.."
key="$(mktemp)"
trap 'rm -f "$key"' EXIT
go run ./app/tool/gen_sd_jwt_fixture.go "$key" > app/test/fixtures/sd_jwt.json
echo "wrote app/test/fixtures/sd_jwt.json"
(cd app && dart run tool/gen_presentation_fixture.dart "$key")
