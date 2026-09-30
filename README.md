# binary-provenance-rego: binary provenance as a Rego-decided control

A learning spike. It takes a customer's built-in Kosli environment policy

```yaml
_schema: https://kosli.com/schemas/policy/environment/v1
artifacts:
  provenance:
    required: true
```

and turns it into a **named control**, `RCTL-030 Artifact binary provenance`. The control is decided by a
Rego policy, recorded as a decision, required by the flow template and enforced by the environment policy.

Kosli org: `dangrondahl` · flow: `binary-provenance-rego` · environment: `binary-provenance-rego-kind` · policy: `binary-provenance-rego`

## Before and after

| | Before | After |
|---|---|---|
| What is checked | "Kosli knows this fingerprint" (built in) | [`policy/binary-provenance.rego`](policy/binary-provenance.rego): fingerprint known, built from a commit in this repo, trail started by this repo's Actions |
| Who decides | Kosli, implicitly | A Policy Decision Point in the pipeline: `kosli evaluate trail --no-assert` |
| What is recorded | Nothing | A `decision` attestation against `RCTL-030`, with the Rego and eval report attached |
| Trail requirement | – | [`kosli/flow-template.yml`](kosli/flow-template.yml): `binary-provenance-decision` of `type: decision`, under the `hello-world` artifact |
| Environment requirement | [`kosli/policy-before.yml`](kosli/policy-before.yml) | [`kosli/policy-after.yml`](kosli/policy-after.yml): `for_control: RCTL-030` |
| Audit view | – | Controls → RCTL-030: **Decisions** (every judgment) and **Coverage** (`binary-provenance-rego-kind` covered) |

The environment policy stops talking about *tooling* ("has provenance") and starts talking about a
*requirement* ("RCTL-030 was satisfied"). The decision carries the evidence of how that judgment was reached.

## How it flows

```
Build (push to main)                                  Release (after Build, or manual)
───────────────────────────────────────────────       ─────────────────────────────────────────
kosli begin trail <sha>                               resolve image -> digest
docker build + push ghcr.io/kosli-cs/binary-provenance-rego       PEP  kosli assert artifact --environment binary-provenance-rego-kind
kosli attest artifact  (name: hello-world)            kind create cluster (ephemeral)
PDP  kosli evaluate trail --policy *.rego --no-assert kubectl apply (image@digest)
     kosli attest decision --control RCTL-030         kosli snapshot k8s binary-provenance-rego-kind
          --compliant=<allow> --attachments rego,report
```

* **PDP** (decide + record): [`scripts/evaluate-and-decide.sh`](scripts/evaluate-and-decide.sh)
* **PEP** (enforce): `kosli assert artifact --environment` in [`release.yml`](.github/workflows/release.yml)

## Try it

```bash
./scripts/test-policy.sh        # Rego against fixtures, offline (kosli evaluate input)
./scripts/setup-kosli.sh        # once: flow, environment, policy, attach
```

Deploy a new version by changing the greeting in [`app/main.go`](app/main.go) and pushing to `main`. Build creates a new
trail and decision, and Release deploys the new digest and snapshots it.

### See the policy bite

* **No decision:** run Release by hand with `image: nginx:alpine`. The PEP fails. Run it again with `skip_assert: true`
  and the snapshot shows `binary-provenance-rego-kind` as **non-compliant** (no provenance, no RCTL-030 decision).
* **Rego denies:** change `expected_repo_url` in [`policy/params.json`](policy/params.json) and push. The decision is recorded
  with `--compliant=false` and the violations. The trail goes non-compliant and Release's assert fails.

### Inspect what the policy sees

```bash
kosli evaluate trail <sha> --flow binary-provenance-rego --org dangrondahl \
  --policy policy/binary-provenance.rego --params @policy/params.json --show-input -o json | jq .input
```

## Learning notes

* **Where the decision slot goes.** The first attempt put `binary-provenance-decision` in `trail.attestations`.
  A decision recorded with `--fingerprint` lands on the *artifact*, though. It showed up there as `unexpected`,
  the trail-level slot stayed `MISSING` and the trail was `INCOMPLETE`. So the slot is declared under
  `trail.artifacts[hello-world].attestations`. The fingerprint is what lets `for_control` and `kosli assert` tie the
  decision to the artifact that is running.
* **`--no-assert`.** `kosli evaluate` fails the step on a deny by default. The PDP wants the verdict, not a failed
  step, so a deny is still *recorded* as `--compliant=false`.
* **Build URL is not in the Rego input.** The "known builder" check uses the trail's `origin_url`, which
  `kosli begin trail` sets to the Actions run URL.

## Stretch: SLSA build provenance

Set the repo variable `SLSA_STRETCH=true`. Build then:

1. signs SLSA provenance for the image with `actions/attest-build-provenance`,
2. verifies it with `gh attestation verify` and distils `subject_digest`, `source_git_commit` and `builder_id`
   into a `provenance-facts` custom attestation on the artifact,
3. evaluates with `require_slsa: true`. The Rego then also requires the *signed* digest and commit to match the
   artifact. This is a trimmed-down version of cyber-dojo's
   [SDLC-CTRL-0002 policy](https://github.com/cyber-dojo/reusable-actions-workflows/blob/1eb30d6113565e828c4c137413f283b75a53094b/SDLC-CTRL-0002/slsa-provenance.rego).

## Setup notes

* Repo secret `KOSLI_API_TOKEN`: a Kosli service-account token for the `dangrondahl` org.
* Kind pulls from GHCR with an `imagePullSecret` made from the workflow's `GITHUB_TOKEN` (`packages: read`), so the package can stay private.
* Refs: [Working with controls](https://docs.kosli.com/tutorials/working_with_controls) ·
  [evaluate trail](https://docs.kosli.com/client_reference/kosli_evaluate_trail) ·
  [attest decision](https://docs.kosli.com/client_reference/kosli_attest_decision)
