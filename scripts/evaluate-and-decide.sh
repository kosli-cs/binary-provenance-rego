#!/usr/bin/env bash
# The Policy Decision Point (PDP) for RCTL-030.
#
#   evaluate-and-decide.sh <trail> <fingerprint>
#
# `kosli evaluate trail --no-assert` prints the verdict and exits 0 even on a deny, so a
# deny still reaches `kosli attest decision` instead of killing the step. The policy and the
# evaluation report are attached to the decision, so an auditor can re-run the judgment
# rather than take the pipeline's word for it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TRAIL="$1"
FINGERPRINT="$2"
FLOW="${KOSLI_FLOW:-binary-provenance-rego}"
CONTROL=RCTL-030
POLICY=policy/binary-provenance.rego
PARAMS="${PARAMS_FILE:-policy/params.json}"
OUT="${OUT_DIR:-out}"
mkdir -p "$OUT"

kosli evaluate trail "$TRAIL" --flow "$FLOW" \
	--policy "$POLICY" --params "@$PARAMS" \
	--no-assert --output json >"$OUT/eval-report.json"

allow=$(jq -r '.allow' "$OUT/eval-report.json")
jq --arg c "$CONTROL" --arg p "$POLICY" --slurpfile params "$PARAMS" \
	'{control: $c, policy: $p, params: $params[0], allow: .allow, violations: (.violations // [])}' \
	"$OUT/eval-report.json" >"$OUT/decision-data.json"

if [ "$allow" = "true" ]; then
	desc="binary-provenance.rego allowed: artifact is traceable to its commit and pipeline."
else
	desc="binary-provenance.rego denied: $(jq -r '(.violations // []) | join("; ")' "$OUT/eval-report.json")"
fi
echo "rego: allow=$allow"
jq -r '.violations // [] | .[] | "  - " + .' "$OUT/eval-report.json"

kosli attest decision \
	--flow "$FLOW" --trail "$TRAIL" \
	--name binary-provenance-decision \
	--control "$CONTROL" \
	--compliant="$allow" \
	--fingerprint "$FINGERPRINT" \
	--description "$desc" \
	--attachments "$POLICY,$OUT/eval-report.json" \
	--user-data "$OUT/decision-data.json"
