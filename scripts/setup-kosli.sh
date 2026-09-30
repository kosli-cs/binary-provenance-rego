#!/usr/bin/env bash
# One-off (idempotent) setup of the Kosli side of the spike.
# Needs KOSLI_API_TOKEN, or a ~/.kosli.yml with api-token.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

export KOSLI_ORG="${KOSLI_ORG:-dangrondahl}"
FLOW=binary-provenance-rego
ENV=binary-provenance-rego-kind
POLICY=binary-provenance-rego
CONTROL=RCTL-030

# The control must already exist: a policy that references an unknown control is rejected.
kosli get control "$CONTROL" >/dev/null

kosli create flow "$FLOW" \
	--description "Binary provenance (RCTL-030) decided by Rego, for a hello-world image" \
	--template-file kosli/flow-template.yml

kosli create environment "$ENV" --type K8S \
	--description "Ephemeral Kind cluster created by the binary-provenance-rego release workflow"

kosli create policy "$POLICY" kosli/policy-after.yml \
	--description "Binary provenance as a named control (RCTL-030), decided by Rego" \
	--comment "binary-provenance-rego setup"

kosli attach-policy "$POLICY" --environment "$ENV"

# Only needed for the optional SLSA stretch (see README).
kosli create attestation-type provenance-facts \
	--description "SLSA build provenance facts distilled from GitHub's signed attestation"

kosli get control "$CONTROL"
