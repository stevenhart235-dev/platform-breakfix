# AKS Milestone 8: scenario catalog canonicalization

## Objective and decision

Milestone 8 canonicalizes the selector-mismatch scenario catalog and retains stronger deterministic validation. Repository review proved that the proposed `service-selector-mismatch` and Milestone 6's live-accepted `bad-service-selector` exercise the same causal mechanism; M8 does not introduce a new Kubernetes failure class.

The canonical identity is `service-selector-mismatch` because it names the Kubernetes mechanism precisely. The duplicate `bad-service-selector` directory is removed. No alias, redirect, compatibility mapping, alternate manifest, or resolver special case is retained.

## Historical relationship to Milestone 6

Milestone 6 accurately records that its live acceptance used `bad-service-selector`. That run proved a healthy destination, selector-only mutation to `app=scenario-destination-missing`, zero Ready endpoints, working DNS, bounded HTTP failure, selector-mismatch diagnosis, exact selector repair, and recovery. Milestone 8 preserves that historical evidence while changing the active catalog identity to `service-selector-mismatch`.

The newer implementation adds stronger current-Pod validation and richer inspection evidence: fresh snapshots ignore deleting Pod identities; the destination phase must be Running; its container must be running; Ready must remain True; label `app=scenario-destination` must remain unchanged; and inspect must exclude readiness failure. These improvements strengthen evidence but do not change the fault mechanism.

## Canonical behavior

Healthy validation requires a current non-deleting destination Pod in phase Running, its destination container running, Ready=True, label `app=scenario-destination`, a matching Service selector, one explicitly Ready EndpointSlice backend, DNS success, and HTTP 200.

Injection patches only the Service selector to `app=scenario-destination-missing`. Pod labels, probes, images, commands, replicas, and infrastructure remain unchanged. Broken validation requires the destination to remain Running and Ready=True with its original label, the selector to mismatch, zero Ready endpoints, DNS success, bounded HTTP failure, and the exact `EXPECTED SCENARIO FAILURE CONFIRMED` classification.

Inspect reports the current Pod, phase, container state, Ready condition, selector, Pod label, endpoint count, DNS, and HTTP. It diagnoses Service selector mismatch and explicitly excludes readiness failure. Repair restores only `app=scenario-destination`; recovery re-proves selector/label alignment, one Ready endpoint, DNS, and HTTP 200. Cleanup remains scenario-owned and finally-style.

## Fail-closed identity and saved plans

Scenario schema version 1 and the existing six hooks remain unchanged. Generic resolution continues to require the requested directory and manifest name to match exactly. Consequently `bad-service-selector` is now unknown and fails closed.

Saved-plan scenario metadata remains an exact string comparison and plan SHA validation is unchanged. A plan bound to `service-selector-mismatch` can provision only with that identity. Plans bound to `none` or `readiness-probe-failure` cannot provision as the selector scenario. Stale metadata containing `bad-service-selector` does not map to the canonical name and must be discarded and replanned. This intentional incompatibility avoids ambiguous dual identities.

## Why no Azure lifecycle is required

Milestone 6 already live-proved the complete Kubernetes causal chain. M8 validates catalog identity, strict plan binding, removal of the duplicate, and stronger deterministic assertions. Another Azure lifecycle would repeat behavior evidence rather than prove a new failure class, so this milestone is static-only.

## Static acceptance

Acceptance requires the duplicate directory to be absent; the old name to fail as unknown; no alias; exact saved-plan mismatch behavior; service-selector, readiness, and EndpointSlice regressions; all provider/scenario Kustomize renders; checksum-verified OpenTofu 1.11.13 formatting and validation; unchanged generic framework, lifecycle, infrastructure, profiles, and schema; intentional classification of every remaining historical old-name reference; and `git diff --check`.