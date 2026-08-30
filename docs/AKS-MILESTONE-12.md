# AKS Milestone 12: read-only breakfix operation contract and CLI adapter

## Objective and boundary baseline

Milestone 12 creates the first stable consumer-facing interface to `platform-breakfix`: a transport-neutral Breakfix Operations v1 layer and a thin PowerShell CLI. It starts from accepted Milestone 11 commit `22add7d1862fdc2e3c544972438e1f871a14c66a` and preserves:

```text
platform-breakfix -> cluster-foundation <- future-platform
```

This is an ephemeral break/fix lab interface, not an application-platform interface. The operation layer is canonical; the CLI is only an adapter. HTTP and MCP are future adapters over the same semantics.

Read-only comes first because catalog inspection, bounded local evidence reading, offline diagnosis, and observational status have no cleanup or mutation-authorization burden. Creation, scenario execution, validation that creates transient storage, repair, cleanup, destroy, and credential reconfiguration remain outside v1.

## Breakfix Operations Contract v1

Operation Contract version `1` is independent of scenario manifest schema v1 and Evidence Contract v1. Results use an exact bounded envelope:

```json
{
  "ContractVersion": 1,
  "Operation": "list_profiles",
  "Success": true,
  "Data": {},
  "Error": null
}
```

Failures set `Success` to false, `Data` to null, and return only `Code` and `Message` in `Error`. Success requires non-null `Data` and null `Error`. Contract validation rejects unknown envelope and error fields. Public failures do not include stack traces, credentials, kubeconfig contents, or internal paths.

The bounded error codes are:

| Code | Meaning |
|---|---|
| `INVALID_ARGUMENT` | The operation, argument name, identity, or required value is invalid. |
| `NOT_FOUND` | A valid bounded evidence identity has no local artifact. |
| `INVALID_EVIDENCE` | JSON is malformed, violates Evidence Contract v1, or disagrees with its bounded artifact identity. |
| `DIAGNOSIS_FAILED` | Valid observations produce zero or multiple supported diagnoses. |
| `PROVIDER_UNSUPPORTED` | The provider has no safe v1 adapter for the requested capability. |
| `LAB_STATE_UNAVAILABLE` | The provider-native read could not determine lab state. |
| `INTERNAL_ERROR` | An unexpected internal failure occurred; details are not exposed publicly. |

Exactly five canonical operations are public:

| Operation | Inputs | Data | Read behavior |
|---|---|---|---|
| `list_profiles` | Optional `Provider` | Lexically ordered `Profiles` with `Name` and `Provider` | Resolves the existing AKS profile manifests; EKS truth is an empty profile catalog. |
| `list_scenarios` | None | Lexically ordered `Scenarios` with name, description, providers, and profiles | Imports and validates existing scenario manifests through the accepted resolver. |
| `read_evidence` | Canonical `Scenario` | Valid Evidence Contract v1 document | Reads only `.runtime/scenario-evidence/<scenario>.json`. |
| `diagnose_evidence` | Canonical `Scenario` | `Identifier` and `Summary` | Reads validated evidence and delegates observation-only diagnosis to `ScenarioDiagnosis.ps1`. |
| `get_lab_status` | `Provider` | Provider, state, profile, timestamps, connection state | Adapts an existing provider-native observational status primitive. |

There is no generic execute, command, script, hook, raw-operation, or mutation route.

## Catalog behavior

`list_profiles` enumerates the existing AKS `profile.psd1` source and validates each item with `Resolve-AksProfile`. It does not carry a second list of `minimal`, `cilium`, or `istio`. The current deterministic result is `cilium`, `istio`, then `minimal`. EKS has no equivalent profile catalog, so an EKS filter returns an empty catalog rather than fabricated parity.

`list_scenarios` enumerates existing `scenario.psd1` manifests, validates their supported provider/profile combinations with `Resolve-LabScenario`, and returns deterministic lexical ordering. The active catalog is `readiness-probe-failure` and `service-selector-mismatch`. `bad-service-selector` remains absent.

## Evidence and diagnosis

Evidence identifiers must match `^[a-z][a-z0-9-]*$` and an active scenario manifest. Separators, traversal, absolute paths, nested paths, and arbitrary file paths fail with `INVALID_ARGUMENT`. A valid identifier resolves only beneath `.runtime/scenario-evidence`.

`read_evidence` distinguishes missing artifacts (`NOT_FOUND`) from malformed, schema-invalid, or identity-inconsistent artifacts (`INVALID_EVIDENCE`). It delegates JSON parsing and Evidence Contract v1 validation to `Read-ScenarioEvidence`; it is not a generic file reader.

`diagnose_evidence` does not trust the diagnosis stored in the artifact as a fresh decision. It passes the validated observations to the accepted `Resolve-ScenarioDiagnosis` engine and returns its identifier and summary. Rules remain exactly `readiness_probe_failure` and `service_selector_mismatch`. Healthy and hybrid evidence fail closed. Scenario identity does not select the diagnosis. No kubectl, Azure, AWS, hook, collection, repair, or mutation occurs.

## Provider-neutral lab status

The v1 data shape is:

| Field | Values |
|---|---|
| `Provider` | Provider identity |
| `State` | `NO_LAB`, `ACTIVE`, `STALE`, or `UNKNOWN` |
| `Profile` | Detected profile or null |
| `CreatedAt` | UTC ISO 8601 timestamp or null |
| `ExpiresAt` | UTC ISO 8601 timestamp or null |
| `ConnectionState` | `CONNECTED`, `DISCONNECTED`, or `UNKNOWN` |

AKS delegates to the existing read-only `Get-AksLabStatus` primitive. Native `NO LAB` maps to `NO_LAB`; valid temporal states remain `ACTIVE` or `STALE`; unclassified or invalid native states map to `UNKNOWN`. Missing fields stay null. M12 does not run `az aks get-credentials` or inspect/mutate kubeconfig, so `ConnectionState` is honestly `UNKNOWN`.

EKS has no equivalent safe provider-native status primitive. `get_lab_status` therefore returns `PROVIDER_UNSUPPORTED` for EKS. M12 does not add EKS lifecycle code or manufacture timestamps, profiles, or parity. Provider-read failures map to `LAB_STATE_UNAVAILABLE` without exposing raw provider output.

## CLI adapter

The adapter is `breakfix.ps1` at the repository root:

| CLI | Canonical operation |
|---|---|
| `./breakfix.ps1 profiles list [-Provider aks]` | `list_profiles` |
| `./breakfix.ps1 scenarios list` | `list_scenarios` |
| `./breakfix.ps1 evidence read <scenario>` | `read_evidence` |
| `./breakfix.ps1 evidence diagnose <scenario>` | `diagnose_evidence` |
| `./breakfix.ps1 lab status -Provider <provider>` | `get_lab_status` |

Add `-Json` for machine output. JSON mode emits only the operation result envelope on stdout. Human mode prints concise catalog rows, evidence identity/status, diagnosis, or status fields. Successful operations exit zero, operation failures exit one, and invalid CLI syntax exits two.

The CLI owns argument mapping, result rendering, and exit codes. It does not enumerate directories, parse evidence, contain diagnosis rules or catalog identities, inspect state, or invoke cloud/Kubernetes lifecycle logic. Future HTTP and MCP adapters must call `Invoke-BreakfixOperation`; they do not receive separate business logic.

## Read-only and repository-boundary guarantees

The public allowlist is statically asserted to contain only the five named operations. The operation layer has no route for provisioning, scenario execution, injection, repair, cleanup, destroy, validation, profile switching, arbitrary commands, scripts, or hooks.

M12 adds no application blueprint, application contract, developer self-service, platform reconciliation, multi-cloud placement, application lifecycle, promotion, GitOps application management, data-plane provisioning, routing, identity lifecycle, or platform capability composition.

Unchanged architecture includes OpenTofu, AKS/EKS infrastructure and lifecycle, profile manifests, scenario schema v1, the six hooks, scenario resolver/executor behavior, scenario injection/repair, Evidence Contract v1, diagnosis rules, Cilium, Istio, and canonical EKS behavior.

## Static validation

Static acceptance covers:

- checksum-verified OpenTofu 1.11.13, formatting, and AKS/EKS validation;
- all PowerShell parse checks;
- profile, PAYG, scenario, EndpointSlice, readiness, selector, evidence, and diagnosis regressions;
- operation-contract and CLI adapter tests;
- all six existing Kustomize renders;
- framework/lifecycle, infrastructure/profile/provider, evidence/schema/hook, and injection/repair comparisons;
- forbidden-concept and public-operation allowlist checks;
- `git diff --check`.

Lab-status tests use injected deterministic fixtures for `NO_LAB`, `ACTIVE`, `STALE`, `UNKNOWN`, missing optional fields, provider unsupported, and provider unavailable behavior. No Azure or AWS operation is part of M12 acceptance.

## Non-goals and next step

M12 does not implement HTTP, MCP, cluster creation, scenario execution, validation workflows, collection of fresh evidence, repair, cleanup, destruction, credential updates, or EKS lifecycle parity. A live cloud lifecycle would add little evidence: catalog, evidence, diagnosis, envelope, routing, and error behavior are deterministic offline, while provider status already delegates to an accepted observational primitive and is covered by fixtures.

The recommended next milestone is a review of the v1 read boundary and adapter ergonomics before choosing one narrowly authorized extension. Any future mutation requires explicit authorization, idempotency, saved-plan/profile/scenario binding, and cleanup semantics; it must not be inferred from M12.
