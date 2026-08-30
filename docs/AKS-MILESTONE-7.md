# AKS Milestone 7: readiness probe failure scenario

## Objective

Milestone 7 proves that the Milestone 6 scenario abstraction supports a materially different Kubernetes failure mechanism without changing the scenario schema or generic lifecycle semantics. The tested combination is `aks/minimal/readiness-probe-failure`; Cilium and Istio are explicitly rejected.

## Causal chain and abstraction reuse

Milestone 6 changes a Service selector while both workloads remain healthy: selector mismatch leads to no Ready Service endpoint and HTTP failure. Milestone 7 leaves the selector correct and changes only the destination HTTP readiness path from `/` to `/platform-breakfix-readiness-failure`. Kubelet then marks the current destination Pod NotReady even though its container remains Running, EndpointSlice loses its Ready backend, and Service HTTP becomes unavailable while DNS continues to resolve.

The existing schema version 1 manifest and its six hooks are reused unchanged: Inject, ValidateBroken, Inspect, Repair, ValidateRecovered, and Cleanup. The existing Kubernetes composition mechanism, saved-plan scenario binding, generic orchestration, and finally-style cleanup are also unchanged. All readiness-specific behavior is owned by `scenarios/readiness-probe-failure`.

## Workload and compatibility

The scenario owns the established `platform-breakfix-scenario` namespace, a curl source Deployment, an nginx destination Deployment, and a ClusterIP Service. Those generic resource names are the existing lifecycle convention; ownership remains scenario-local because only one selected scenario exists at a time. The Service selector remains `app=scenario-destination` throughout. The healthy probe uses HTTP `/` on the named `http` port with a two-second period. Compatibility is deliberately limited to provider `aks` and profile `minimal`.

## Validation and diagnosis

Healthy and recovered validation require a Ready source, a current non-deleting destination Pod in phase Running with its container running, Pod Ready=True, probe path `/`, the correct selector, one explicitly Ready EndpointSlice backend, DNS success, and bounded HTTP 200. Broken validation requires the source to remain Ready, a fresh current destination Pod with the invalid probe path, phase Running, its container running, Pod Ready=False, the unchanged selector, zero Ready endpoints, DNS success, and bounded HTTP failure before emitting `EXPECTED SCENARIO FAILURE CONFIRMED`.

Pod selection uses fresh list snapshots and does not retain a Pod name across Deployment reconciliation. Structured Pod phase, container state, Ready condition, and configured readiness path are primary evidence. Bounded `Unhealthy` event messages are supplementary diagnostic evidence. EndpointSlice counting retains Milestone 6 semantics: only explicit `conditions.ready=true` counts, legitimate absent/null endpoint fields count as zero, while retrieval, JSON, and malformed top-level failures remain visible.

Inspect reports the destination Pod name and phase, container Running state, Pod Ready condition, configured and expected readiness paths, Service selector, destination labels, Ready endpoint count, DNS, HTTP, and up to three readiness events. This distinguishes a readiness failure from a selector mismatch.

## Repair, recovery, and cleanup

Repair restores only the readiness path to `/`. Normal Deployment rollout is accepted as Kubernetes reconciliation; validation never depends on the old Pod identity. Recovery must re-prove Running and Ready=True, the restored path, unchanged selector, one Ready endpoint, DNS, and HTTP 200. Finally-style cleanup deletes only the scenario namespace. The shared baseline is then validated by the existing lifecycle.

## Azure footprint, PAYG, and TTL

The scenario supplies Kubernetes resources only and changes no OpenTofu input or Azure ownership tag. The minimal plan must remain six Azure resources plus one `time_static`, one `Standard_D2as_v7` node, Azure CNI Overlay with the Azure data plane, and mesh disabled. The existing minimal PAYG estimate, exact four-hour TTL, duplicate-provision protection, and cleanup guardrails remain unchanged.

## Acceptance

The static suite passed with checksum-verified OpenTofu 1.11.13. The plan remained six Azure resources plus `time_static`, with seven additions, no changes or deletions, one `Standard_D2as_v7` node, Azure CNI Overlay and Azure data plane, mesh disabled, the unchanged four-hour TTL, and the unchanged minimal PAYG estimate.

The single authorized live lifecycle provisioned successfully and passed common Kubernetes, AKS provider, and Azure Disk validation. Healthy scenario proof passed: the current destination was Running and Ready=True with probe `/`, the selector remained `app=scenario-destination`, Ready endpoint count was one, DNS succeeded, and HTTP returned 200. Injection changed only the readiness path to `/platform-breakfix-readiness-failure`.

Broken validation did not complete. Control flow reached the zero-endpoint wait only after observing a current destination Pod that was Running, Ready=False, and configured with the injected path, and after confirming the Service selector remained correct. The Ready EndpointSlice count nevertheless remained one for the full bounded wait. The Deployment's default rolling-update strategy retained the old healthy Pod as a Ready Service backend because the replacement Pod could never become Ready. Consequently the run could not prove zero Ready endpoints, bounded Service HTTP failure, the exact expected-failure classification, inspect, repair, recovery, post-scenario baseline, or duplicate-provision protection. No retry was performed and validation was not weakened.

Scenario cleanup deleted its namespace. Azure destroy removed all seven managed objects, verify-clean passed, OpenTofu state was empty, both resource groups were absent, no tagged AKS resources remained, and final status was `NO LAB`. Timings were: doctor 00:00:14, plan 00:00:15, provision 00:04:48, connect 00:00:02, bootstrap 00:00:07, validate 00:01:46, scenario 00:02:54, destroy 00:07:47, verify-clean 00:00:04, total 00:18:01.

The scenario schema and generic lifecycle semantics were sufficient and remained unchanged, but the scenario workload's default `RollingUpdate` strategy did not produce the required service-level failure. Kubernetes intentionally retained the old Ready Pod while the replacement remained NotReady, so the old Pod stayed in the Service EndpointSlice and the Ready count remained one. This is scenario workload semantics, not a framework failure.

The targeted correction sets only the readiness scenario destination Deployment to `strategy.type: Recreate`. This scenario tests the Service effect of a failed readiness probe, not rolling-update availability guarantees. Recreate deterministically removes the old Ready Pod before creating the replacement, allowing the replacement container to remain Running with Pod Ready=False while the correctly selected Service has zero Ready backends. The source workload, namespace, Service selector, probe paths, hook contract, schema, and generic lifecycle remain unchanged.

The final authorized lifecycle after that correction passed end to end. Healthy proof showed the destination Running and Ready=True with probe `/`, one Ready endpoint, DNS success, and HTTP 200. Injection changed only the probe path. Broken proof showed the replacement Pod Running and Ready=False with `/platform-breakfix-readiness-failure`, the correct selector and labels, zero Ready endpoints, DNS success, bounded HTTP exit code 7, a 404 readiness event, and `EXPECTED SCENARIO FAILURE CONFIRMED`. Inspect diagnosed readiness failure; path-only repair restored Ready=True, one endpoint, DNS, and HTTP 200. Scenario cleanup, complete post-scenario baseline validation, duplicate-provision protection, the exact four-hour TTL, destroy, and verify-clean passed. Final state was `NO LAB` with empty OpenTofu state, absent resource groups, and zero tagged resources. Timings were: doctor 00:00:21, plan 00:00:22, provision 00:05:29, connect 00:00:04, bootstrap 00:00:13, validate 00:02:21, scenario 00:02:41, inspect 00:00:07, destroy 00:07:49, verify-clean 00:00:06, total 00:19:37. Milestone 7 is accepted.
