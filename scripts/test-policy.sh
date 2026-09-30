#!/usr/bin/env bash
# Offline check of policy/binary-provenance.rego against the fixtures. No Kosli API calls.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

failed=0
check() { # <fixture> <expected allow> [params-override-jq]
	local fixture="$1" want="$2" params
	params=$(jq -c "${3:-.}" policy/params.json)
	got=$(kosli evaluate input --input-file "policy/fixtures/$fixture.json" \
		--policy policy/binary-provenance.rego --params "$params" \
		--no-assert --output json | jq -r '.allow')
	if [ "$got" = "$want" ]; then echo "ok    $fixture${3:+ ($3)} -> allow=$got"
	else echo "FAIL  $fixture${3:+ ($3)} -> allow=$got, want $want"; failed=1; fi
}

check pass        true
check fail        false
check no-artifact false
check pass        false '.require_slsa=true'
check pass-slsa   true  '.require_slsa=true'
exit $failed
