# AKS Milestone 16: Generic deterministic selection foundation

Milestone 16 is the first concrete implementation of the repository boundary designed in M11. The accepted baseline is `f658d96a9a4a862948196d1f29790867a982b9f1` (`feat: expose deterministic lab health operation`). It introduces no cloud, Kubernetes, lifecycle, contract, or operator-surface behavior.

## Problem and previous coupling

`scripts/ScenarioDiagnosis.ps1` previously owned two distinct concerns: breakfix-specific observation rules and the generic requirement that exactly one candidate match. That made a reusable deterministic mechanism share an owner with scenario-specific semantics.

## Extracted primitive

`foundation/DeterministicSelection.ps1` now owns `Resolve-DeterministicSelection`. It accepts a bounded candidate set with exactly `Name`, boolean `Matches`, and non-null `Value`; validates shape and unique names; normalizes evaluation through ordinal name ordering; returns the sole matched value; and fails closed for zero or multiple matches. It has no fallback, closest-match behavior, scoring, filesystem discovery, external command execution, or mutation.

The candidate shape deliberately contains an already evaluated boolean. Domain predicates remain with the caller, preventing executable breakfix rules or an over-generalized rules engine from entering foundation.

## Ownership split and dependency direction

```text
scripts/ScenarioDiagnosis.ps1
        |
        v
foundation/DeterministicSelection.ps1
```

Breakfix continues to own readiness and selector observation predicates, identifiers, summaries, scenario identity independence, evidence integration, expected failures, injection, repair, and recovery semantics. Foundation knows only generic candidates and exactly-one selection. It does not import or inspect any breakfix, scenario, provider, profile, lifecycle, evidence, health, dashboard, Azure, AWS, or Kubernetes implementation.

## Canonical owner

The former `Assert-SingleScenarioDiagnosisMatch` implementation was removed. `Resolve-DeterministicSelection` is the repository's only active exactly-one-match implementation, and ScenarioDiagnosis delegates to it. Architecture tests reject a duplicate guard in ScenarioDiagnosis and reject upstream or domain-specific knowledge in executable foundation source.

## Behavioral compatibility

The accepted diagnoses remain byte-compatible:

- `readiness_probe_failure`: `Destination workload is running but not Ready because the injected readiness probe fails while the Service selector still matches.`
- `service_selector_mismatch`: `Destination workload is running and Ready, but the Service selector does not match the destination workload label.`

Evidence Contract remains v1. Scenario identity still does not participate. Healthy, hybrid, inconsistent, malformed, zero-match, and multiple-match inputs continue to fail closed.

Breakfix Operations Contracts v1 and v2, Lab Health Contract v1, scenario manifest schema v1, M13 health semantics, M14 dashboard behavior, and M15 `get_lab_health` behavior remain unchanged.

## Validation evidence

Neutral foundation tests cover empty candidates, zero matches, one match, multiple matches, order independence, duplicate names, malformed shapes and types, null input/value, dependency absence, external-command absence, and mutation absence. Existing M10 diagnosis regressions continue to prove exact diagnosis outcomes and fail-closed patterns. The full accepted repository suite covers OpenTofu 1.11.13 formatting and AKS/EKS validation, PowerShell parsing, all provider regressions, all seven Kustomize renders, architecture boundaries, whitespace, and generated-artifact exclusion.

## Deferred work

M16 does not create a repository or package, extract evidence or Lab Health, add a consumer, expose a CLI/API operation, or begin future-platform composition. Physical extraction into `cluster-foundation` and any second consumer are intentionally deferred to a later milestone.
