package policy

import rego.v1

# RCTL-030 Artifact binary provenance
# "Every artifact reaching an environment is traceable to the commit and the pipeline
#  that built it."
#
# The built-in environment policy `artifacts.provenance.required: true` only asks
# "does Kosli know this fingerprint?". This policy makes that judgment explicit and
# a little stricter, using nothing but the trail data `kosli evaluate trail` provides:
#
#   known identity  -> the template artifact was reported with a sha256 fingerprint
#   known source    -> it was built from a commit in the expected repository
#   known builder   -> the trail was begun by the expected CI pipeline
#   (optional) SLSA -> GitHub's signed build provenance names the same digest + commit
#
# Inspect the input with:
#   kosli evaluate trail <trail> --flow binary-provenance-rego --policy <this file> --show-input -o json
#
# PARAMS (--params @policy/params.json), available as data.params:
#   artifact_name           template name of the artifact (eg "hello-world")
#   expected_repo_url       commit URL must start with this (eg "https://github.com/kosli-cs/binary-provenance-rego/")
#   expected_origin_prefix  trail origin_url must start with this (the repo's Actions runs)
#   require_slsa            when true, also require a matching provenance-facts attestation
#
# allow is built from positive conditions only. A missing param or input field makes a
# condition undefined, which keeps allow false: it fails toward non-compliance.

artifact_name := data.params.artifact_name

require_slsa if data.params.require_slsa == true

# ---------------------------------------------------------------------------
# Where the facts live in the trail input
# ---------------------------------------------------------------------------
artifact_status := input.trail.compliance_status.artifacts_statuses[artifact_name]

fingerprint := artifact_status.artifact_fingerprint

# The latest artifact_creation_reported event for this template artifact carries the
# commit it was built from.
creation_events := [e |
	some e in input.trail.events
	e.type == "artifact_creation_reported"
	e.template_reference_name == artifact_name
]

creation := creation_events[count(creation_events) - 1]

# Optional SLSA facts, distilled from GitHub's build provenance (see README, stretch).
slsa := artifact_status.attestations_statuses["provenance-facts"].attestation_data

# ---------------------------------------------------------------------------
# Decision
# ---------------------------------------------------------------------------
default allow := false

allow if {
	identity_known
	source_known
	builder_known
	slsa_ok
}

identity_known if regex.match(`^[a-f0-9]{64}$`, fingerprint)

source_known if {
	non_empty(creation.git_commit)
	startswith(creation.git_commit_info.url, data.params.expected_repo_url)
}

builder_known if startswith(input.trail.origin_url, data.params.expected_origin_prefix)

slsa_ok if not require_slsa

slsa_ok if {
	require_slsa
	same(slsa.subject_digest, fingerprint)
	same(slsa.source_git_commit, creation.git_commit)
}

non_empty(s) if {
	is_string(s)
	s != ""
}

same(a, b) if {
	non_empty(a)
	non_empty(b)
	lower(a) == lower(b)
}

# ---------------------------------------------------------------------------
# Violations (diagnostics only; they do not drive allow)
# ---------------------------------------------------------------------------
violations contains sprintf("no artifact '%v' with a sha256 fingerprint on this trail", [artifact_name]) if {
	not identity_known
}

violations contains sprintf("artifact '%v' has no commit from %v (got %v)", [
	artifact_name,
	data.params.expected_repo_url,
	object.get(object.get(creation, "git_commit_info", {}), "url", "<missing>"),
]) if {
	identity_known
	not source_known
}

violations contains sprintf("trail was not started by the expected pipeline %v (origin_url %v)", [
	data.params.expected_origin_prefix,
	object.get(input.trail, "origin_url", "<missing>"),
]) if {
	not builder_known
}

violations contains "SLSA provenance-facts missing, or its digest or commit does not match the artifact" if {
	identity_known
	not slsa_ok
}
