# AKS Milestone 2: Repeatability and PAYG Guardrails

Milestone 2 preserves the live-tested Milestone 1 AKS architecture while
making PAYG ownership, expected lifetime, and operator cost exposure visible.
It does not add an Azure service or any platform capability.

## PAYG ownership metadata

The AKS Resource Group, VNet, control-plane identity, and cluster receive these
OpenTofu-managed tags:

| Tag | Meaning |
| --- | --- |
| `Project=platform-breakfix` | Repository ownership and verify-clean selector |
| `PlatformBreakfix=true` | Explicit lab ownership marker |
| `Provider=aks` | Provider identity |
| `Purpose=ephemeral-lab` | Disposable PAYG lab purpose |
| `Lifecycle=ephemeral` | Lifecycle classification |
| `ManagedBy=OpenTofu` | Authoritative infrastructure workflow |
| `CreatedAt=<UTC RFC 3339>` | Stable creation timestamp |
| `ExpiresAt=<UTC RFC 3339>` | Time by which the operator should have destroyed the lab |

`time_static.lab` records `CreatedAt` once in the isolated AKS OpenTofu state.
`ExpiresAt` is derived with `timeadd` and the configurable `lab_ttl_hours`
variable. The default is four hours; `-LabTtlHours` on `Invoke-Lab.ps1`
supplies the plan value. This avoids a new timestamp on every plan.

TTL is advisory metadata. Azure does not automatically delete the lab at
`ExpiresAt`. It means, "This lab should have been destroyed by this time."
Explicit `destroy` followed by `verify-clean` remains mandatory.

## Cost visibility

Immediately before applying the saved plan, lifecycle tooling prints an
`AKS PAYG LAB` warning. The estimate assumes one `Standard_D2as_v7` node at
approximately USD 0.10 per hour, or approximately USD 0.40 for the default
four-hour TTL. The assumption is deliberately stored as one easy-to-update
constant in `Lab-Aks.ps1`.

This is not a quote or billing-authoritative estimate. AKS Free tier has no
cluster-management charge, but managed disks, Standard Load Balancer/public IP
usage, network egress, taxes, and other usage-based charges may apply.

## Lab-state detection and duplicate protection

`doctor` and `inspect` query the dedicated Resource Group without changing it
and report one of:

- `NO LAB`: the Resource Group is absent.
- `ACTIVE`: ownership and timestamps are valid and `ExpiresAt` is in the future.
- `STALE`: `ExpiresAt` has passed, with a visible overdue duration and explicit
  destroy reminder.
- `EXISTING UNCLASSIFIED` or `EXISTING INVALID`: a Resource Group exists but
  ownership/timestamp metadata cannot safely classify it.

Before apply, `provision` repeats this query. Any state other than `NO LAB`
blocks the normal provision path and identifies the existing Resource Group.
It never deletes or modifies an existing lab. This is a single configured-lab
guard, not a concurrent multi-user orchestration system.

The deterministic test below proves ACTIVE and STALE parsing without changing
live tags or waiting for expiration:

```powershell
.\validation\providers\aks-guardrails.tests.ps1
```

## Cleanup boundary

Destroy still removes API-dependent Kubernetes resources before OpenTofu
destroy. `verify-clean` requires:

- `rg-platform-breakfix-aks` absent
- `rg-platform-breakfix-aks-nodes` absent
- no Azure resources selected by `Project=platform-breakfix` with
  `Provider=aks`
- read-only status detection returns `NO LAB`

No automatic TTL deletion exists in Milestone 2.

## Repeatability benchmark

Milestone 1 is the comparison benchmark, not an SLA:

```text
doctor        00:00:14
plan          00:00:13
provision     00:05:23
connect       00:00:02
bootstrap     00:00:14
validate      00:02:06
destroy       00:07:32
verify-clean  00:00:03
Total         00:15:52
```

The single authorized PAYG repeatability run on 2026-08-27 completed with exit
code zero:

| Phase | Milestone 1 | Milestone 2 | Delta |
| --- | ---: | ---: | ---: |
| doctor | 00:00:14 | 00:00:15 | +00:00:01 |
| plan | 00:00:13 | 00:00:10 | -00:00:03 |
| provision | 00:05:23 | 00:05:14 | -00:00:09 |
| connect | 00:00:02 | 00:00:02 | 00:00:00 |
| bootstrap | 00:00:14 | 00:00:14 | 00:00:00 |
| validate | 00:02:06 | 00:02:22 | +00:00:16 |
| destroy | 00:07:32 | 00:16:31 | +00:08:59 |
| verify-clean | 00:00:03 | 00:00:06 | +00:00:03 |
| **Total** | **00:15:52** | **00:24:57** | **+00:09:05** |

The infrastructure and Kubernetes behavior repeated successfully. The total
increase came almost entirely from Azure/OpenTofu teardown duration; provision
was nine seconds faster. These measurements are observations, not an SLA.

During the live run, `CreatedAt=2026-08-27T13:36:23Z` and
`ExpiresAt=2026-08-27T17:36:23Z` proved an exact four-hour TTL. Inspection
reported ACTIVE, validated ownership tags, and proved the shared normal
provision gate rejected the existing lab. Common Kubernetes and backing Azure
Disk deletion validation passed. After destroy, both Resource Groups were
absent, tagged leftovers were zero, and status returned NO LAB.

## Out of scope

Milestone 2 does not implement automatic expiration, Azure Cost Management,
remote state, CI/CD, profiles, Cilium, Istio, ingress, registry integration, or
observability. Future profiles must preserve the ownership and cleanup
contract, but profile design remains separate work.
