# AKS Milestone 18: Physical cluster-foundation extraction design

Milestone 18 designs—but does not perform—the first physical foundation extraction. The accepted baseline is `5a143624a11145f8e21cfe4128084cd8fc7ac424` (`refactor: reuse deterministic selection for istio revisions`). M16 established the in-repository boundary; M17 proved one neutral implementation with two unrelated consumers.

## Scope and rationale

The first physical move contains only `Resolve-DeterministicSelection`, its neutral tests, and its public contract. It does not extract evidence, diagnosis rules, profiles, health, lifecycle, providers, OpenTofu, or Kubernetes behavior. Repository topology and dependency wiring are deliberately kept separate from further capability extraction.

The target direction remains:

```text
platform-breakfix  --->  cluster-foundation  <---  future-platform
```

A future platform must never consume foundation through `platform-breakfix`.

## Proposed repository topology

```text
cluster-foundation/
  README.md
  VERSION
  src/
    DeterministicSelection.ps1
  tests/
    DeterministicSelection.tests.ps1
  docs/
    DETERMINISTIC-SELECTION.md
```

`README.md` states scope, supported PowerShell runtime, test command, release policy, and non-goals. `VERSION` initially contains `0.1.0`. The source file is ordinary PowerShell, not a generalized module ecosystem. The test file is the current neutral suite adapted only for its repository root. The contract document defines the public surface and bounded failures. A license may be added when repository ownership determines the appropriate license; package manifests, generated archives, and a release pipeline are not required initially.

## Transport options

| Option | Pinning | Local/CI ergonomics | Offline behavior | Update and rollback | Copy/divergence and reuse |
| --- | --- | --- | --- | --- | --- |
| Git submodule | Gitlink pins an exact commit; lock metadata can bind URL/tag/SHA | Standard `--recurse-submodules`; CI support is common but must initialize explicitly | Works after the pinned object is fetched; normal clones need one dependency fetch | Update gitlink in one reviewable commit; rollback by reverting it | Canonical source stays external; directly reusable by another repository |
| Git subtree | Import commit can be recorded, but source is materialized in the consumer | Simple clone and fully offline; updates require subtree commands | Excellent | Updates and rollback are larger source diffs | High copy-and-diverge risk; canonical ownership is less visually enforceable |
| Vendored copy | Pin must be documented separately and can drift silently | Easy clone/CI | Excellent | Manual replacement and comparison | Highest copy-and-diverge risk; rejected as canonical transport |
| PowerShell module/package | Package version gives strong identity | Good after feed/bootstrap exists | Requires cache or internal feed availability | Version bump/revert is clear | Good reuse, but feed, signing, packaging, and publishing are premature for one function |
| GitHub release archive | Tag plus archive checksum can be immutable in a lock file | Requires bootstrap download/extract logic | Only after caching | Replace lock/checksum; revert lock | Avoids gitlink but creates release-artifact and bootstrap machinery prematurely |
| Pinned repository checkout | Bootstrap script can fetch an exact SHA outside the tree | Flexible in CI; local path conventions and cleanup are harder | Requires a populated cache/checkout | Change SHA in bootstrap lock | Canonical source preserved, but dependency state is less visible in ordinary Git status |
| Floating branch/latest | Mutable | Initially easy | Unreliable | Non-deterministic | Rejected: silent drift and untrusted mutable execution |

## Recommended transport

Use a Git submodule at `external/cluster-foundation`. The platform repository records:

- `.gitmodules` with one allowlisted HTTPS repository URL;
- the gitlink commit SHA;
- `external/cluster-foundation.lock.json` containing exact repository URL, semantic tag, commit SHA, and contract major version.

The gitlink is the executable pin. The lock file is redundant audit metadata and must fail validation if it disagrees with the initialized submodule, `VERSION`, or expected remote URL. No consumer may load from `main`, `latest`, a mutable URL, an adjacent developer checkout, or a runtime download.

A submodule has an explicit initialization step, but at this maturity it is the smallest option combining immutable source identity, one canonical owner, repeatable local/CI checkout, clean rollback, and reuse without package infrastructure.

## Versioning and releases

Start with semantic version tags plus commit-SHA pinning:

- signed annotated tag `v0.1.0` identifies the first public contract;
- `VERSION` contains `0.1.0`;
- consumers pin the exact tagged commit SHA, never the tag name alone;
- the platform lock records both tag and SHA;
- Git history and the signed tag establish provenance.

Patch releases preserve the public contract and fix implementation defects. Minor releases may add backward-compatible capabilities without enlarging this primitive's input shape. Major releases may change its contract and require an explicit consumer migration. Package versioning and automated release infrastructure remain deferred.

## Public consumer contract

The initial stable surface is exactly:

```powershell
Resolve-DeterministicSelection -Candidates <object[]>
```

Each candidate has exactly:

- `Name`: non-empty unique string used only for deterministic ordering and validation;
- `Matches`: Boolean already evaluated by the domain-owning consumer;
- `Value`: non-null opaque caller value.

The function validates every candidate and rejects missing/unknown fields, invalid types, null values, and duplicate names. Zero matches and multiple matches fail closed with bounded errors. Exactly one match returns that candidate's original `Value`. Candidate order does not alter the semantic result. There is no fallback, scoring, closest match, domain predicate execution, filesystem discovery, external command execution, or mutation.

Compatibility is defined by contract major version and neutral contract tests, not by PowerShell implementation internals or error-message parsing. Consumers may translate bounded failures but must not depend on internal candidate ordering or exception stack details.

## Ownership after extraction

`cluster-foundation` owns:

- the deterministic-selection implementation;
- neutral unit and public-contract tests;
- `VERSION`, release tags, changelog/release notes when releases occur;
- reusable contract and security documentation.

`platform-breakfix` owns:

- scenario observations and diagnosis predicates;
- diagnosis identifiers and summaries;
- scenario catalog, injection, repair, and acceptance semantics;
- Azure managed-Istio catalog acquisition and object shape;
- index-based candidate creation and the revision matching predicate;
- Kubernetes compatibility evaluation and provider error translation;
- all consumer compatibility and break/fix regression tests.

No domain rule moves into foundation.

## Test ownership

The foundation repository runs neutral unit and contract tests for candidate shape, zero/one/multiple matches, ordering, duplicates, malformed input, bounded failure, dependency neutrality, and absence of commands or mutation.

`platform-breakfix` runs both consumers against the pinned checkout. It retains diagnosis outcome/identity/summary regressions, Istio revision zero/one/multiple and compatibility regressions, architecture dependency checks, and the complete static suite. A pin is acceptable only if all platform tests pass. Platform tests verify the submodule HEAD, allowed remote, lock SHA/tag, `VERSION`, public function presence, and absence of a second local implementation.

## Explicit update workflow

1. Change `cluster-foundation` in its repository.
2. Run all neutral and public-contract tests.
3. Review provenance and create a signed annotated semantic version tag.
4. Record the immutable release commit SHA.
5. In a platform branch, update the submodule gitlink and lock URL/tag/SHA/contract version together.
6. Initialize the exact submodule revision and verify lock, remote, tag, and `VERSION` agreement.
7. Run foundation tests from the pinned checkout and the complete `platform-breakfix` static suite.
8. Commit only the pin/lock update and any necessary explicit consumer compatibility change.
9. Never auto-follow or periodically merge `main`.

## Local development workflow

Normal development uses:

```text
git clone --recurse-submodules <platform-breakfix-url>
git submodule update --init --recursive
```

Offline work is repeatable after the pinned submodule object and existing tool dependencies are present. Tests fail closed with setup guidance if the submodule is absent; they never download it at runtime.

To develop foundation intentionally, clone or enter the submodule, create a foundation branch, change and test it there, then temporarily point the parent worktree's submodule at that exact commit and run the platform suite. The parent pin is committed only after the foundation change is reviewed and released. Developers do not copy files or redirect consumers to arbitrary adjacent paths.

## CI design

A future minimal CI job should:

1. Check out `platform-breakfix` at the tested commit without credentials persisted unnecessarily.
2. Read `.gitmodules` and the lock before initialization; reject an unapproved URL.
3. Initialize the submodule at the recorded gitlink commit, not a branch.
4. Verify submodule HEAD equals both gitlink and lock SHA, its remote URL is allowlisted, its signed tag resolves to that SHA, and `VERSION` matches the lock.
5. Run foundation neutral/contract tests from the pinned checkout.
6. Run platform consumer tests and the full static suite.
7. Fail closed if the dependency is unavailable, uninitialized, mismatched, unsigned, or incompatible.

CI does not download or execute mutable release assets and does not update the pin automatically.

## Security and provenance

Trust is anchored in an approved repository URL, least-privilege read access, the immutable gitlink SHA, matching lock metadata, and a signed annotated release tag. Release creation should require review and protected tags. Consumers must review foundation diffs between old and new pins. CI must not accept URL rewrites, mutable branches, unsigned replacement tags, or a lock that disagrees with the gitlink.

The dependency is obtained during explicit checkout/bootstrap, never during operator CLI execution. No Azure, AWS, Kubernetes, registry, or application credentials are needed. If signing infrastructure is temporarily unavailable, extraction stops rather than silently weakening the intended provenance policy; an explicitly reviewed interim policy would require a separate design decision.

## Migration sequence

1. Create the standalone `cluster-foundation` repository with the minimal layout, governance, and approved URL.
2. Import the exact M17 primitive and neutral tests with provenance linking the source commit; make no functional changes.
3. Run neutral tests, set `VERSION` to `0.1.0`, review, and create signed tag `v0.1.0`.
4. In one platform migration branch, add the pinned submodule and lock, rewire both consumers to the submodule source, and remove `foundation/DeterministicSelection.ps1` plus its local neutral test. Do not merge an intermediate state containing two active canonical implementations.
5. Add dependency-integrity checks and adapt only paths in consumer/architecture tests.
6. Run foundation tests from the pin and the entire platform static suite.
7. Merge only when one external canonical implementation remains and both consumers are proven compatible.
8. Observe the first release/pin through normal development before considering another extraction candidate.

History-preserving tooling may be used to prepare the new repository, but repository creation and history transfer are M19 implementation decisions. M18 creates neither.

## Rollback

The normal rollback is a platform commit reverting the submodule gitlink and lock to the last accepted release, followed by the full static suite. If the initial extraction itself is defective, revert the atomic platform migration commit to restore the prior in-repository implementation and wiring. Never hot-copy a previous source file over the submodule or retag an existing release. Published version tags are immutable.

## Risks and stop conditions

- Submodule initialization is an explicit developer/CI step and can be omitted; fail-closed integrity tests mitigate this.
- Private-repository access could complicate CI and onboarding; access must be solved before migration without embedding credentials.
- Repository or tag ownership without protection weakens provenance.
- A lock and gitlink can disagree; validation must reject the mismatch.
- Consumer path rewiring can accidentally leave a second implementation; source and dependency scans must reject it.
- Cross-platform path and PowerShell-version behavior must be proven before release.

Stop physical extraction if it requires multiple capabilities, any public contract change, provider/lifecycle behavior changes, package infrastructure, floating dependencies, runtime downloading, retained vendored canonical code, weakened tag trust, or a merged state with duplicate active implementations.

## Deferred capabilities

Evidence contracts, diagnosis rules, Lab Health, operations/CLI, scenario execution, profiles/addons, providers, lifecycle, OpenTofu, dashboard behavior, and future-platform composition remain deferred. Each requires separate evidence and scope. No additional capability should accompany the first physical move.
