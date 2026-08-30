# AKS Milestone 10: deterministic diagnosis from structured evidence

## Objective and baseline

Milestone 10 builds on accepted Milestone 9 commit `28f82f0758c9f4d1ef7a6a5e6f52ac67a54e0c34`. Milestone 9 defined Evidence Contract version 1 and allowed scenario `Inspect` hooks to attach their own diagnosis. Milestone 10 changes diagnosis ownership without changing the two accepted failure mechanisms or the serialized contract:

```text
observed cluster state -> structured observations -> deterministic diagnosis -> Evidence Contract v1 JSON
```

Observations are retrieved facts. Evidence is the bounded identity, observation, and diagnosis envelope. Diagnosis is the deterministic interpretation of a complete supported observation pattern.

## Ownership and boundaries

Scenario `Inspect` hooks continue to retrieve Kubernetes state and print operator-friendly Pod, readiness path, label, selector, endpoint, DNS, and HTTP evidence. They construct observations, but contain no diagnosis identifiers or summaries.

`scripts/ScenarioEvidence.ps1` owns observation and document shape validation, Evidence Contract version 1 construction, JSON serialization, and local artifact read/write. It does not select root causes.

`scripts/ScenarioDiagnosis.ps1` owns observation-to-diagnosis mapping. It does not execute `kubectl`, access Azure or kubeconfig, inspect scenario identity, mutate Kubernetes, invoke hooks, or repair workloads. It is a two-rule function, not a DSL, plugin system, heuristic engine, or autonomous remediation mechanism. No AI, probability, confidence score, fuzzy matching, or generated reasoning is involved.

## Complete deterministic rules

The readiness rule requires the complete combination:

- workload exists, phase `Running`, container running, `Ready=false`
- readiness path `/platform-breakfix-readiness-failure`
- destination label `app=scenario-destination`
- Service exists with selector `app=scenario-destination`
- selector matches the destination label
- Ready endpoint count `0`
- DNS succeeds and HTTP fails

It returns the stable identifier `readiness_probe_failure` and a fixed summary.

The selector rule requires the complete combination:

- workload exists, phase `Running`, container running, `Ready=true`
- readiness path `/`
- destination label `app=scenario-destination`
- Service exists with selector `app=scenario-destination-missing`
- selector does not match the destination label
- Ready endpoint count `0`
- DNS succeeds and HTTP fails

It returns `service_selector_mismatch` and a fixed summary. Neither rule selects on scenario name. Passing identical observations under different valid `Scenario` metadata produces the same result.

## Fail-closed and ambiguity behavior

The engine validates the complete observation shape and types before rule evaluation, gathers all matching rules, and enforces `matches.Count == 1`. Zero matches throw; multiple matches throw. It never returns `unknown`, `maybe`, a closest match, or a generic successful diagnosis.

Healthy state, unsupported hybrids, inconsistent selector facts, nonzero endpoints, DNS failure, HTTP success, a non-Running Pod, a stopped container, missing Pod or Service, missing observations, and invalid types all fail closed. An isolated test calls the exactly-one guard with two results to prove ambiguity protection independently of the current mutually exclusive rules.

## Evidence Contract and artifact compatibility

The external JSON shape remains Evidence Contract version `1`: identity, workload, service, connectivity, and diagnosis are unchanged. Construction is now explicitly staged:

1. Build and validate observations.
2. Resolve diagnosis from observations.
3. Attach diagnosis to identity metadata.
4. Validate the complete v1 document.
5. Serialize and write it.

Both derived diagnoses pass v1 validation and UTF-8 JSON write/read round trips. Unknown fields, sensitive fields, malformed JSON, unsupported schema versions, missing fields, invalid types, and unbounded diagnosis identifiers remain rejected.

Artifacts remain local at `.runtime/scenario-evidence/<scenario>.json`. The ignored location, deterministic overwrite behavior, bounded content, lack of secrets and machine paths, and independence from Azure cleanup are unchanged.

## Human-readable and scenario compatibility

Both `Inspect` hooks continue to show the facts needed for diagnosis and now display the identifier and fixed summary returned by the shared engine. Operators do not need to open JSON. Readiness injection still changes only the readiness path and repair restores only that path. Selector injection still changes only the Service selector and repair restores only that selector.

The scenario manifest schema remains version 1 with the existing six hooks. Generic resolver and lifecycle behavior, OpenTofu infrastructure, AKS profiles, Cilium, Istio, and canonical EKS behavior are unchanged. No seventh hook or new scenario is introduced.

## Static acceptance

Static acceptance covers exact diagnoses, deterministic summaries, scenario identity independence, every required fail-closed mutation, explicit ambiguity protection, both v1 artifact round trips, M9 contract regressions, both scenario integrations, all existing provider/scenario regressions, all required Kustomize renders, architecture comparisons, OpenTofu 1.11.13 validation, PowerShell parsing, and diff hygiene.

A live Azure lifecycle could show the already accepted `Inspect` retrieval path feeding the new engine, but it would not materially strengthen evidence for pure deterministic rule behavior, identity independence, zero/multiple-match handling, or v1 serialization. Static acceptance is sufficient unless an end-to-end artifact demonstration is separately required.
