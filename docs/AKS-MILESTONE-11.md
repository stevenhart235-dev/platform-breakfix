# AKS Milestone 11: repository boundary and foundation extraction design

## Objective and accepted baseline

Milestone 11 locks the repository boundary before any CLI, HTTP API, or MCP implementation. The accepted baseline is Milestone 10 commit `ebc41c2db50ad72930add674c5b6ce5a00b6db93` (`feat: add deterministic scenario diagnosis`). This milestone changes documentation only: it moves no code, creates no repository, and changes no runtime behavior.

The inventory used repository paths, function boundaries, OpenTofu roots/outputs, profile and scenario manifests, Kustomize compositions, validation scripts, lifecycle standards, accepted ADRs, and regression tests. Each component below is assigned exactly one current classification:

- `BREAKFIX_SPECIFIC`
- `FOUNDATION_CANDIDATE`
- `PROVIDER_IMPLEMENTATION`
- `SHARED_CONTRACT_CANDIDATE`
- `HISTORICAL_OR_TEST_ONLY`

The canonical architectural fence is [REPOSITORY-BOUNDARY.md](REPOSITORY-BOUNDARY.md).

## Current architecture and boundary decision

The repository currently combines a mature AKS lab orchestrator, a less-unified EKS implementation, a portable synthetic Kubernetes baseline, provider/profile compositions, deterministic scenario execution, and structured evidence/diagnosis. The outcome contract is already provider-aware, but implementation maturity is asymmetric.

The decision is:

```text
platform-breakfix --> cluster-foundation <-- future-platform
```

`platform-breakfix` remains the owner of lab intent, scenarios, expected failures, repair, and acceptance. Foundation eventually owns reusable cluster/provider primitives and shared contracts. A future platform consumes foundation directly and owns application-platform reconciliation. It never consumes breakfix implementation.

No stop condition prevents this design. The current coupling does prevent a one-step move: it requires staged extraction and explicit provider adapters. AKS and EKS differ substantially, but they are compatible at the existing outcome contract; they must not be forced into identical OpenTofu internals.

## Component inventory

“Dependency” describes the desired direction after extraction. “Owner” is the recommended eventual canonical owner.

| Current component/path | Current responsibility | Classification | Dependency | Extraction suitability and blocker | Eventual owner |
| --- | --- | --- | --- | --- | --- |
| `standards/lab-contract.md`, `standards/acceptance-v0.md` | Provider-neutral lab outcomes and acceptance | `SHARED_CONTRACT_CANDIDATE` | Breakfix and provider adapters depend on contract | High; normalize versioning without turning outcomes into universal infrastructure | Foundation contract, with breakfix acceptance extension |
| `providers/azure/aks/infrastructure/*.tf` | Azure network, identity, role assignment, AKS, TTL outputs | `PROVIDER_IMPLEMENTATION` | Breakfix calls AKS adapter | High after state/package boundary is designed; local state and repo-relative outputs block a direct move | Foundation `providers/aks` |
| `infrastructure/eks/*.tf` | AWS VPC, EKS, nodes, EBS identity, ECR | `PROVIDER_IMPLEMENTATION` | Breakfix/manual workflow calls EKS implementation | Medium; ECR preservation is a known lifecycle mismatch and EKS lacks AKS-style orchestration | Foundation `providers/eks`; ECR separated by ownership first |
| `providers/azure/aks/scripts/Lab-Aks.ps1` doctor/connect/bootstrap/inspect | AKS preflight and provider operations | `PROVIDER_IMPLEMENTATION` | Breakfix orchestrator calls provider adapter | Medium; one large file mixes provider calls with reusable guardrails and lab presentation | Foundation AKS adapter after seams are split |
| `scripts/Connect-Cluster.ps1`, `connect-cluster.sh` | EKS authentication and kubeconfig connection | `PROVIDER_IMPLEMENTATION` | Breakfix/manual workflow calls provider adapter | Medium; hard-coded cluster/region and split Windows/WSL behavior | Foundation EKS adapter |
| `Invoke-AksPlan`, `Invoke-AksProvision`, `Invoke-AksDestroy` | AKS plan/apply/destroy sequencing | `PROVIDER_IMPLEMENTATION` | Breakfix lifecycle invokes AKS implementation | High after metadata/guardrail contract extraction; preserve independent state | Foundation AKS implementation |
| EKS manual OpenTofu create/destroy | EKS lifecycle without normalized orchestrator | `PROVIDER_IMPLEMENTATION` | Breakfix operator invokes provider root | Low-to-medium until deterministic status, destroy, and verify-clean adapters exist | Foundation EKS implementation |
| `Invoke-AksVerifyClean` | Azure RG/tag/state absence checks | `PROVIDER_IMPLEMENTATION` | Common cleanup outcome calls provider-specific inventory | High; retain Azure-native implementation behind stable outcome | Foundation AKS adapter |
| EKS cleanup verification (currently absent) | Required v0 outcome without implementation parity | `PROVIDER_IMPLEMENTATION` | Future breakfix interface needs provider adapter | Blocked until ownership markers and retained ECR exceptions are machine-readable | Foundation EKS adapter |
| `Profile-Aks.ps1` manifest/path/schema mechanics | Fail-closed profile parsing and saved/live binding | `FOUNDATION_CANDIDATE` | Breakfix profile catalog consumes parser | Medium; names and allowed inputs are AKS-specific and must become provider adapter data, not generic conditionals | Foundation profile mechanism |
| `profiles/*/profile.psd1` (`minimal`, `cilium`, `istio`) | Exact tested AKS lab configurations | `BREAKFIX_SPECIFIC` | Catalog consumes profile mechanism and provider capability | Keep initially; these are lab taxonomy, not future-platform contracts | Platform-breakfix unless individually promoted with another consumer |
| Managed Cilium/Istio AKS inputs in OpenTofu | Provider-native addon enablement | `PROVIDER_IMPLEMENTATION` | Profiles request AKS capabilities | High; keep Azure-native semantics visible | Foundation AKS addon implementation |
| Cilium/Istio profile Kustomize and allow/deny fixtures | Synthetic lab policy/workloads | `BREAKFIX_SPECIFIC` | Profile acceptance uses provider addon | Low as reusable addon; fixtures prove lab behavior | Platform-breakfix |
| `Validate-Cilium.ps1`, `Validate-Istio.ps1` | Profile-specific managed-addon acceptance | `BREAKFIX_SPECIFIC` | Breakfix validation consumes live addon | Medium only for factual probes; current assertions are profile acceptance | Platform-breakfix, consuming reusable probes later |
| `providers/*/*/kubernetes/kustomization.yaml` and storage additions | Provider bootstrap composition | `PROVIDER_IMPLEMENTATION` | Breakfix bootstrap composes shared baseline and provider additions | High; preserve provider-owned composition | Foundation provider packages, with breakfix overlay |
| `kubernetes/shared` and synthetic nginx/podinfo/whoami/curl baseline | Portable lab workload baseline | `BREAKFIX_SPECIFIC` | Breakfix validation/scenarios consume it | Keep; applications are synthetic acceptance fixtures, not platform workloads | Platform-breakfix |
| Temporal state, PAYG warning, ownership tags, duplicate protection in `Lab-Aks.ps1` | Cost/lifetime safety | `FOUNDATION_CANDIDATE` | Breakfix orchestration consumes guardrails via provider facts | High conceptually; currently bound to AKS tags/defaults and console output | Foundation guardrail primitives; presentation remains breakfix |
| Plan metadata, profile/scenario binding, SHA binding | Prevent stale or mismatched provision/destroy | `FOUNDATION_CANDIDATE` | Provider plan/apply adapters consume binding contract | High; define provider-neutral metadata envelope while keeping provider plan generation native | Foundation lifecycle guardrail |
| ACTIVE/STALE/NO LAB classification | Normalize lab temporal/existence state | `FOUNDATION_CANDIDATE` | Status operation consumes provider inventory | High; separate pure state machine from Azure discovery | Foundation pure primitive |
| `validation/common/Validate-Kubernetes.ps1` | API, nodes, system pods, workloads, DNS/HTTP, storage smoke | `FOUNDATION_CANDIDATE` | Breakfix acceptance invokes reusable facts | Medium-high; synthetic deployment names and transient storage fixture must be parameters/contracts | Foundation validation primitives; fixture policy remains breakfix |
| `validation/manifests/storage-smoke.yaml` | Disposable dynamic-volume proof | `FOUNDATION_CANDIDATE` | Common validation creates/deletes bounded resources | High as a reusable validation fixture if ownership labels and cleanup contract remain explicit | Foundation validation package |
| `validation/providers/aks.ps1`, `eks.ps1` | Cloud-native status, storage class, backing-volume deletion | `PROVIDER_IMPLEMENTATION` | Common validation delegates provider facts | High; keep implementations provider-specific | Foundation provider validation adapters |
| Profile validation scripts | Cilium/Istio lab acceptance | `BREAKFIX_SPECIFIC` | Breakfix profile catalog invokes them | Keep; can consume foundation factual probes | Platform-breakfix |
| `scripts/Validate-Lab.ps1` | Select common/provider/profile validation | `FOUNDATION_CANDIDATE` | Breakfix operation invokes validation coordinator | Medium; defaults and profile acceptance are breakfix/provider coupled | Foundation coordinator plus breakfix acceptance wrapper |
| `scripts/Scenario.ps1` manifest resolver/compatibility/path checks | Fail-closed six-hook scenario resolution and plan binding | `FOUNDATION_CANDIDATE` | Breakfix scenario catalog consumes resolver | High; AKS-named saved-plan helper must be generalized separately | Foundation scenario contract/resolver |
| Scenario manifest shape (`scenario.psd1` schema v1) | Six-hook compatibility contract | `SHARED_CONTRACT_CANDIDATE` | Resolver and catalog depend on it | High; retain strict schema and no arbitrary plugin execution | Foundation contract; scenario manifests remain breakfix |
| `Invoke-ResolvedScenario` in `Invoke-Lab.ps1` | Apply topology, execute six hooks, always cleanup | `FOUNDATION_CANDIDATE` | Breakfix lifecycle calls generic executor | Medium; fixed namespace/deployment names and AKS-only entry point are extraction blockers | Foundation executor after inputs are explicit |
| `scripts/Invoke-Lab.ps1` top-level full lifecycle | Timed AKS breakfix lifecycle and cleanup priority | `BREAKFIX_SPECIFIC` | Breakfix consumes provider and scenario primitives | Keep; it expresses lab policy and accepted operation order | Platform-breakfix |
| Scenario-local EndpointSlice counters/waits | Ready-backend facts duplicated in two scenarios | `FOUNDATION_CANDIDATE` | Scenario observation gathering consumes helper | High; deduplicate pure retrieval/counting without moving scenario semantics | Foundation Kubernetes observation helper |
| `scenarios/readiness-probe-failure/**` | Inject, prove, inspect, repair readiness fault | `BREAKFIX_SPECIFIC` | Catalog consumes executor/evidence/diagnosis | Not for extraction; it is the breakfix catalog | Platform-breakfix |
| `scenarios/service-selector-mismatch/**` | Inject, prove, inspect, repair selector fault | `BREAKFIX_SPECIFIC` | Catalog consumes executor/evidence/diagnosis | Not for extraction | Platform-breakfix |
| `scripts/ScenarioEvidence.ps1`, Evidence Contract v1 | Observation/document validation, JSON, artifact I/O | `SHARED_CONTRACT_CANDIDATE` | Breakfix and future consumers use stable contract | Very high; filesystem location should be caller policy, schema/serialization canonical | Foundation shared contract |
| `.runtime/scenario-evidence/` lifecycle | Ignored local bounded artifact policy | `SHARED_CONTRACT_CANDIDATE` | Breakfix evidence operation applies storage policy | Medium; generic writer plus consumer-selected local root | Contract in foundation, path policy in breakfix |
| `scripts/ScenarioDiagnosis.ps1` current composite | Exactly-one guard plus two breakfix-specific complete rules | `BREAKFIX_SPECIFIC` | Inspect consumes evidence and current catalog rules | Split required: generic exactly-one executor is reusable; current label/path rules are catalog-bound | Rules in platform-breakfix; executor may move to foundation |
| Scenario `Inspect.ps1` hooks | Kubectl retrieval and operator-facing context | `BREAKFIX_SPECIFIC` | Hooks consume evidence and diagnosis primitives | Keep; tightly bound to scenario topology and expected observations | Platform-breakfix |
| `validation/providers/*.tests.ps1` | Deterministic regression/architecture characterization | `HISTORICAL_OR_TEST_ONLY` | Protect current/extracted behavior | Tests stay with behavior owner; extraction needs contract tests in both owner and consumer | Split tests only when code ownership changes |
| `docs/AKS-MILESTONE-*.md`, acceptance reports | Historical design/live evidence | `HISTORICAL_OR_TEST_ONLY` | Future work references accepted facts | Do not rewrite or extract | Platform-breakfix history |
| Root compatibility Kustomization and legacy EKS docs | Transition compatibility | `HISTORICAL_OR_TEST_ONLY` | EKS workflow still references compatibility entry point | Remove only under separately accepted migration | Platform-breakfix until retired |

## Ownership recommendations

### Evidence and diagnosis

Evidence Contract v1, observation/document validation, serialization, and bounded read/write behavior are the strongest first shared-contract extraction. Artifact path selection remains consumer policy.

The current diagnosis file should not move intact. `Assert-SingleScenarioDiagnosisMatch` is a generic deterministic execution primitive. The two rules encode the breakfix catalog's exact labels and injected readiness path and therefore remain breakfix-owned. A rule moves to foundation only when it becomes a deliberately supported reusable diagnostic contract used by another consumer—not merely because it is deterministic.

### Profiles and addons

Extract fail-closed profile parsing, schema/version checks, path containment, and binding mechanics. Preserve provider-specific capability inputs behind provider adapters. Keep `minimal`, `cilium`, and `istio` as breakfix profiles initially. Managed AKS addon enablement is provider implementation; synthetic policies, probes, and acceptance workloads stay breakfix.

### Scenario engine

Extract the manifest contract and resolver first. Extract execution only after namespace, topology rollout targets, timeouts, and setup/cleanup inputs are explicit. Do not expose arbitrary hook/plugin execution. The catalog and all injection/repair/expected-failure semantics stay in breakfix.

## Extraction blockers and risks

1. AKS lifecycle and reusable guardrails share one large script and common state/default variables.
2. EKS lacks normalized status, orchestration, TTL, duplicate protection, and verify-clean parity.
3. ECR resources share the EKS root despite different preservation semantics.
4. Provider outputs and Kustomize paths are repository-relative.
5. The AKS profile resolver hard-codes AKS infrastructure input names.
6. Scenario execution assumes `platform-breakfix-scenario` topology and two fixed Deployment names.
7. EndpointSlice and kubectl helpers are duplicated across scenarios.
8. Common validation mixes reusable cluster facts with named synthetic workloads and a mutating storage smoke test.
9. Diagnosis execution and breakfix-specific rules share one file.
10. Local OpenTofu state makes physical movement require a deliberate state/path migration plan.

These are staged-extraction constraints, not reasons to create a universal provider. The highest risks are accidental state loss, weakening plan/profile/scenario binding, copy-and-diverge during transition, misclassifying lab profiles as platform contracts, and presenting validation as read-only when it creates transient resources.

## Recommended extraction order

1. **Characterize and freeze contracts.** Keep current regression suites, boundary document, provider outcome contract, and strict schema versions as acceptance gates.
2. **Extract leaf shared contracts.** Evidence v1 validation/serialization, profile and scenario parsing helpers, pure EndpointSlice/counting helpers, common error/result types, and the generic exactly-one diagnosis executor. Keep breakfix rules and local artifact policy in this repo.
3. **Define provider adapter contracts and close EKS gaps.** Normalize status, plan metadata, connection, destroy, and verify-clean outcomes without changing provider-native implementations. Separate ECR preservation ownership before moving the EKS root.
4. **Extract lifecycle guardrail primitives.** Temporal state, TTL/ownership metadata, duplicate prevention, plan/SHA binding, and cleanup-result contracts; provider discovery stays in adapters.
5. **Move AKS and EKS provider packages independently.** Preserve independent OpenTofu roots/state and provider-specific networking, identity, storage, and teardown. Use explicit state migration procedures; never copy then leave two owners.
6. **Extract profile/addon mechanisms.** Move parsing and provider capability mechanisms; keep breakfix catalog overlays and synthetic validations here.
7. **Extract reusable validation primitives.** Parameterize workload facts and storage smoke ownership; retain breakfix acceptance composition.
8. **Extract generic scenario execution.** Remove fixed topology assumptions through bounded inputs, retain six hooks and finally cleanup, and keep scenario definitions here.
9. **Make platform-breakfix consume foundation.** Delete replaced local implementations only when regression parity passes and one canonical owner remains.
10. **Allow future-platform consumption.** It consumes foundation contracts directly and never imports or reaches through breakfix.

## Transport-neutral breakfix operation contract

Every operation belongs to the `platform-breakfix` capability contract; its implementation may delegate to foundation/provider primitives.

| Operation | Mode | Purpose and required inputs | Returned result | Important errors | Existing primitive(s) |
| --- | --- | --- | --- | --- | --- |
| `create_lab` | Mutating | Provider, profile, scenario binding, approved plan/config, TTL | Lab identity, provider status, timestamps, bindings | Existing/stale lab, plan/SHA/profile/scenario mismatch, preflight/provision failure | `Invoke-Lab plan/provision`, AKS plan/provision; EKS gap |
| `get_lab_status` | Read-only | Provider and ownership scope | `NO LAB`/`ACTIVE`/`STALE`, identity, age/expiry | Auth/discovery failure, ambiguous ownership | AKS `Get/Show-AksLabStatus`; EKS gap |
| `inspect_lab` | Read-only | Provider, live lab identity/profile | Bounded provider/Kubernetes observations | Wrong context, unreachable provider/API, incomplete facts | `Invoke-AksInspect`; EKS/manual inspection gap |
| `list_profiles` | Read-only | Provider | Valid profile identities and compatibility | Invalid manifest, unsupported schema/provider | `Resolve-AksProfile`, profile directory |
| `list_scenarios` | Read-only | Provider/profile | Compatible scenario identities/descriptions | Invalid manifest or compatibility | `Resolve-LabScenario`, scenario directory |
| `run_scenario` | Mutating | Live validated lab, exact scenario/profile binding | Healthy, injected, broken, diagnosis, repaired, cleaned results | Unsupported binding, hook failure, cleanup failure | `Invoke-ResolvedScenario`, six hooks |
| `collect_evidence` | Read-only cloud/Kubernetes; local write | Connected lab/scenario and artifact policy | Valid Evidence Contract v1 artifact | Retrieval/schema/write failure, wrong context | scenario `Inspect`, `ScenarioEvidence` |
| `diagnose` | Read-only | Valid structured observations/evidence | Exactly one stable diagnosis and summary | Missing/type/inconsistency, zero or multiple matches | `Resolve-ScenarioDiagnosis` |
| `validate_lab` | Bounded transient mutation | Connected lab, expected provider/profile/capacity | Machine-readable conformance and cleanup result | Any common/provider/profile failure; transient cleanup failure | `Validate-Lab`, common/provider/profile validators |
| `destroy_lab` | Mutating | Exact provider/profile/scenario/state binding | Destroy result and cleanup evidence | State/binding mismatch, API cleanup or provider destroy failure | AKS destroy; EKS manual gap |
| `verify_clean` | Read-only | Provider ownership markers and allowed exceptions | Leftover inventory and clean status | Discovery failure, owned leftovers, ambiguous exceptions | AKS verify-clean; EKS gap |

`validate_lab` is not safely representable as a pure GET today because storage validation creates and removes a namespace, PVC, Pod, PV, and backing volume. `collect_evidence` is read-only against the lab but overwrites an ignored local artifact.

## One contract, three transports

| Capability | CLI | HTTP API | MCP tool |
| --- | --- | --- | --- |
| `create_lab` | `breakfix lab create` | `POST /labs` | `create_lab` |
| `get_lab_status` | `breakfix lab status` | `GET /labs/current` | `get_lab_status` |
| `inspect_lab` | `breakfix lab inspect` | `GET /labs/current/inspection` | `inspect_lab` |
| `list_profiles` | `breakfix profiles list` | `GET /profiles` | `list_profiles` |
| `list_scenarios` | `breakfix scenarios list` | `GET /scenarios` | `list_scenarios` |
| `run_scenario` | `breakfix scenario run` | `POST /labs/current/scenario-runs` | `run_scenario` |
| `collect_evidence` | `breakfix evidence collect` | `POST /labs/current/evidence-collections` | `collect_evidence` |
| `diagnose` | `breakfix diagnose` | `POST /diagnoses` | `diagnose` |
| `validate_lab` | `breakfix lab validate` | `POST /labs/current/validations` | `validate_lab` |
| `destroy_lab` | `breakfix lab destroy` | `DELETE /labs/current` | `destroy_lab` |
| `verify_clean` | `breakfix lab verify-clean` | `GET /labs/current/cleanup-verification` | `verify_clean` |

CLI, HTTP, and MCP are transports over the same capability contract, not three contracts. HTTP `POST` is used where an operation creates an execution/artifact or transient validation resources even if it does not change durable lab intent.

## Read-only-first recommendation for M12

M12 should implement a transport-neutral result/error envelope and a read-only-first operator surface for `list_profiles`, `list_scenarios`, reading existing evidence, offline `diagnose`, and provider-neutral status contracts. A CLI may be the first adapter because it matches current local operator workflows, but API and MCP should remain deferred until the same service boundary is proven.

Do not initially expose `create_lab`, `run_scenario`, `validate_lab`, or `destroy_lab`. Defer live `inspect_lab` and evidence collection until context-binding and provider adapter semantics are explicit. Mutation requires authorization, idempotency, saved-plan binding, concurrent-operation protection, cleanup priority, and auditable results.

## Explicit non-goals

M11 does not move code, create foundation, implement a transport, change schemas, alter providers/profiles/scenarios, or introduce any application-platform concepts listed in the repository boundary. It does not run Azure.

## Static validation

Validation must prove the working tree differs from accepted M10 only by `docs/REPOSITORY-BOUNDARY.md` and `docs/AKS-MILESTONE-11.md`, `git diff --check` passes, and no PowerShell, OpenTofu, scenario, profile, manifest, lifecycle, or schema file changed. No commit or push is authorized in M11 implementation.
