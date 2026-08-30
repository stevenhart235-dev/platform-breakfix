# AKS Milestone 9: structured scenario evidence

## Objective

Milestone 9 adds a versioned, machine-readable diagnostic evidence contract to the two canonical AKS scenarios. It preserves their accepted failure mechanisms and the existing six-hook scenario lifecycle. The contract separates observed facts from the scenario-owned diagnosis so tools can distinguish different Kubernetes root causes that present the same external symptoms.

This is deterministic platform output, not AI integration. No model, agent, MCP server, telemetry stack, cloud storage, or autonomous repair behavior is introduced. Future consumers such as reports, CLI tools, diagnostic logic, observability correlation, or AI reasoning are deliberately deferred.

## Contract and ownership

`scripts/ScenarioEvidence.ps1` owns evidence contract version `1`. It constructs a common envelope, validates the exact required shape and types, serializes UTF-8 JSON, and reads or writes artifacts. It recognizes exactly two stable diagnostic identifiers in this milestone:

- `readiness_probe_failure`
- `service_selector_mismatch`

The helper has no Kubernetes root-cause rules. Each scenario's existing `Inspect` hook gathers Kubernetes facts, confirms its accepted broken state, chooses its own identifier and summary, and passes explicit observations to the generic helper. Evidence is therefore structured independently of diagnosis: observations say what was retrieved, while diagnosis records the scenario-specific interpretation.

The scenario manifest schema remains version 1. The hooks remain `Inject`, `Validate-Broken`, `Inspect`, `Repair`, `Validate-Recovered`, and `Cleanup`; no seventh hook is needed. Generic scenario resolution and lifecycle files are unchanged.

## JSON shape

Every document contains these exact top-level members:

```text
SchemaVersion
Scenario
Provider
Profile
TimestampUtc
Status
Observations
  Workload
    DestinationPodExists, Phase, ContainerRunning, Ready,
    ReadinessProbePath, DestinationLabels.app
  Service
    Exists, Selector.app, SelectorMatchesDestinationLabel,
    ReadyEndpointCount
  Connectivity
    DnsSuccess, HttpSuccess, HttpStatus
Diagnosis
  Identifier, Summary
```

`Status` is `expected_failure_confirmed`. `HttpStatus` is an integer from 100 through 599 when a response status is available and is explicitly `null` when the bounded request fails before receiving one. Required retrieval failures are never translated into `false` or `null`: the existing kubectl helpers throw, malformed JSON throws, and missing Pod, Service, selector, readiness, or EndpointSlice state prevents artifact creation.

## Scenario evidence

A readiness-probe failure document records a Running container with `Ready=false`, probe path `/platform-breakfix-readiness-failure`, matching Service selector and destination label `app=scenario-destination`, zero Ready endpoints, successful DNS, failed HTTP, and diagnosis `readiness_probe_failure`.

A service-selector mismatch document records a Running container with `Ready=true`, healthy probe path `/`, Service selector `app=scenario-destination-missing`, destination label `app=scenario-destination`, `SelectorMatchesDestinationLabel=false`, zero Ready endpoints, successful DNS, failed HTTP, and diagnosis `service_selector_mismatch`.

Both cases therefore have DNS success, HTTP failure, and zero Ready endpoints. They remain deterministically distinguishable because the readiness scenario has `Ready=false` with selector alignment, while the selector scenario has `Ready=true` without selector alignment.

Representative broken-state fragments make the distinction explicit:

```json
{
  "Scenario": "readiness-probe-failure",
  "Observations": {
    "Workload": { "Ready": false, "ReadinessProbePath": "/platform-breakfix-readiness-failure" },
    "Service": { "SelectorMatchesDestinationLabel": true, "ReadyEndpointCount": 0 },
    "Connectivity": { "DnsSuccess": true, "HttpSuccess": false }
  },
  "Diagnosis": { "Identifier": "readiness_probe_failure" }
}
```

```json
{
  "Scenario": "service-selector-mismatch",
  "Observations": {
    "Workload": { "Ready": true, "ReadinessProbePath": "/" },
    "Service": { "SelectorMatchesDestinationLabel": false, "ReadyEndpointCount": 0 },
    "Connectivity": { "DnsSuccess": true, "HttpSuccess": false }
  },
  "Diagnosis": { "Identifier": "service_selector_mismatch" }
}
```

These fragments are explanatory excerpts; actual artifacts contain the complete version-1 shape listed above.

Existing human-readable `Inspect` output remains and now also reports the artifact path. Injection and repair are unchanged: readiness changes only the probe path and uses its scenario-local `Recreate` strategy; selector mismatch changes only the Service selector.

## Artifact lifecycle and security

The current scenario document is written as UTF-8 JSON without a byte-order mark to:

```text
.runtime/scenario-evidence/<scenario>.json
```

The scenario-specific filename is deterministic and is overwritten predictably by a later inspection of the same scenario. `.runtime/` is gitignored, is outside scenario source directories, and has no effect on Kubernetes or Azure cleanup. Evidence stays local and bounded: the strict contract rejects unknown fields and contains no kubeconfig, token, credential, Azure authentication material, raw kubectl dump, event history, or broad environment metadata.

## Validation and scope

Static validation covers both valid scenario documents, serialization round trips, artifact write/read, UTF-8 encoding, missing identity and observation fields, missing diagnosis, wrong boolean and count types, unsupported versions, unknown diagnoses, malformed JSON, sensitive-field exclusion, and the same-symptom/different-root-cause comparison. Existing scenario, EndpointSlice, profile, guardrail, PowerShell, OpenTofu, Kustomize, and EKS regressions remain required.

Milestone 9 changes no OpenTofu infrastructure, AKS profile, Cilium, Istio, EKS, scenario manifest schema, generic scenario lifecycle, injection, or repair behavior. Azure operations are not part of this implementation phase.

A live Azure run could demonstrate that the accepted Inspect hooks write real cluster observations, but it would not add evidence about the schema, serialization, taxonomy, or scenario distinction beyond the deterministic static coverage. Recommendation: review and accept the static implementation first; authorize a live run only if an end-to-end artifact capture is independently required.
