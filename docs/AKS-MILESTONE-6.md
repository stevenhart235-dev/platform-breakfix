# AKS Milestone 6: Scenario Framework

Milestone 6 separates environment profiles from controlled break/fix conditions. A profile describes what environment exists; a scenario describes a condition introduced after that environment has passed baseline validation. The first and only implemented combination is `aks/minimal + bad-service-selector`.

## Architecture and contract

Portable scenarios live under `scenarios/<name>`. Each `scenario.psd1` uses schema version 1 and declares its name, description, supported providers, supported profiles, Kubernetes composition, and repository-owned PowerShell hooks for `Inject`, `ValidateBroken`, `Inspect`, `Repair`, `ValidateRecovered`, and `Cleanup`.

The resolver is deterministic and fail-closed. It rejects unknown names, fields, hooks, schemas, providers, profiles, missing files, invalid names, and paths outside the selected scenario directory. Manifests contain file references rather than arbitrary command strings. Omitting `-Scenario` resolves to `none` and preserves the prior lifecycle.

Compatibility is explicit. `bad-service-selector` supports only provider `aks` and profile `minimal`; Cilium and Istio are rejected before doctor, plan, or provision. This is a tested-support decision rather than a claim that the Kubernetes mechanism could not run elsewhere.

## Lifecycle

The canonical invocation is:

```powershell
.\scripts\Invoke-Lab.ps1 -Provider aks -Profile minimal -Scenario bad-service-selector -Operation full -TofuPath <supported-1.11.x-tofu>
```

Ordering is doctor, plan, provision, connect, bootstrap, common/provider/storage validation, scenario setup and healthy proof, inject, prove broken, inspect, repair, prove recovered, scenario cleanup, provider inspect, destroy, and verify-clean. Scenario cleanup is in a `finally` path and deletes only `platform-breakfix-scenario`. Destroy repeats that bounded cleanup when the scenario is selected, so infrastructure cleanup remains available after a failed scenario phase.

The existing `scenario` lifecycle operation is retained as the single standalone break/fix operation. It runs the complete healthy-to-recovered sequence and cleanup; separate inject/repair command surfaces are intentionally deferred.

## bad-service-selector semantics

The scenario owns a source deployment, destination deployment, and ClusterIP Service in `platform-breakfix-scenario`. The healthy selector is `app=scenario-destination`. Healthy and recovered validation require both deployments Ready, the Service present with a Ready EndpointSlice backend, working Service DNS, and a bounded HTTP 200.

Injection changes only the Service selector to `app=scenario-destination-missing`. Broken validation passes only when both workloads remain Ready, the Service and DNS remain functional, Ready endpoints equal zero, and the bounded HTTP request fails. A curl failure alone is insufficient. This expected application failure is reported as a successful broken-condition validation, distinct from infrastructure or baseline failure.

Inspection reports the Service, current selector, destination label, Ready endpoint count, pod readiness, DNS exit/result, and bounded HTTP exit/result. Repair idempotently restores only the known-good selector. Recovery proves the endpoint and HTTP 200 return before cleanup.

## Plan, Azure identity, and PAYG

Saved-plan metadata binds both profile and scenario (`none` is distinct from a named scenario) while retaining the plan SHA-256 check. A scenario does not alter OpenTofu inputs or Azure resources. It is deliberately not an Azure ownership tag: the live Azure environment remains `aks/minimal`, while scenario selection belongs to the workload lifecycle layer.

The minimal profile remains one `Standard_D2as_v7` node, the existing four-hour advisory TTL, and the existing minimal PAYG estimate. Duplicate-provision protection is unchanged. Scenario selection adds no Azure resource type.

## Future candidates

Possible future scenarios include `network-policy-deny`, `mesh-authz-deny`, `dns-failure`, `readiness-probe-failure`, and `pvc-pending`. None is implemented by this milestone. Each should gain an explicit tested compatibility declaration rather than inheriting compatibility implicitly.

## Acceptance timing

Two authorized live acceptance runs on 2026-08-29 provisioned AKS successfully but stopped before scenario setup at the existing kube-system baseline gate. The targeted rerun captured a healthy AKS-managed `metrics-server` rollout: the deployment was desired/updated/available/ready `2/2/2/2`, both current pods were Running and Ready with zero restarts, and the old ReplicaSet scaled to zero. `kubectl wait pods --all` nevertheless failed because an old pod disappeared between list and watch.

The common validator now polls fresh kube-system pod snapshots for up to the same 180 seconds and still requires every current non-completed pod to be Running with all containers Ready. No timeout was increased and no component is ignored. The targeted rerun timings were: doctor 00:00:16, plan 00:00:14, provision 00:04:58, connect 00:00:02, bootstrap 00:00:08, baseline validate 00:00:02, destroy 00:07:39, verify-clean 00:00:04, total 00:13:27. Cleanup again verified `NO LAB`, absent resource groups, empty state, and zero tagged resources. At that point, scenario behavior still required a separately authorized lifecycle using the corrected baseline rule.
The subsequent final live acceptance reached the scenario, proved both workloads Ready, selector `app=scenario-destination`, one Ready endpoint, DNS success, HTTP 200, and successfully injected only `app=scenario-destination-missing`. Kubernetes then correctly emptied the Service EndpointSlice, but the validator assumed every iterated endpoint exposed `conditions.ready`; the valid absent endpoint/conditions representation failed under PowerShell strict mode before broken-state classification.

The narrow correction separates retrieval/parsing from counting. `kubectl` failures and invalid JSON still fail visibly. The pure counter treats absent/null endpoints, conditions, or ready values as not Ready, counts only explicit `ready=true`, and rejects malformed list structure. Focused regressions cover single, multiple, mixed, false, empty, null, and absent optional properties plus visible parse/structure failures.

The final authorized lifecycle passed end to end. It proved the corrected common Kubernetes baseline, AKS and Azure Disk validation, the healthy scenario, selector-only injection, zero Ready endpoints while workloads and DNS remained healthy, bounded HTTP failure with curl exit code `7`, `EXPECTED SCENARIO FAILURE CONFIRMED`, inspect diagnosis, exact selector repair, HTTP 200 recovery, scenario cleanup, and post-scenario baseline validation. Duplicate-provision protection, the four-hour TTL, destroy, and verify-clean also passed; final state was `NO LAB` with empty OpenTofu state, absent resource groups, and zero tagged Azure resources. Final timings were: doctor 00:00:15, plan 00:00:13, provision 00:05:11, connect 00:00:02, bootstrap 00:00:08, validate 00:01:19, scenario 00:02:19, inspect 00:00:06, destroy 00:06:46, verify-clean 00:00:04, total 00:16:27.
