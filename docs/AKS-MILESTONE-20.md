# AKS Milestone 20: Consume cluster-foundation v0.1.0

Milestone 20 atomically migrates `platform-breakfix` from its in-repository deterministic-selection implementation to the signed standalone release created in M19. The accepted platform baseline is `c884fead5a6c6f313a934d4a7b8a5f5e336b13af`.

## Pinned dependency

```text
external/cluster-foundation
  URL:     https://github.com/stevenhart235-dev/cluster-foundation.git
  gitlink: 06509854104d8b0289790a6ec3b3bd9053761522
  tag:     v0.1.0 (signed annotated)
  VERSION: 0.1.0
  source:  src/DeterministicSelection.ps1
  SHA-256: F03C4401552FB6F9F9BE65DB813127B8ECF020A1089A8889064F95C4A0B4D866
```

`.gitmodules` contains the approved HTTPS URL and no branch. `external/cluster-foundation.lock.json` is a bounded schema recording dependency name, URL, semantic version, tag, commit SHA, source path, source SHA-256, and public contract major version. The gitlink is the executable pin; the lock is independently validated audit metadata.

Source integrity hashes the raw source blob at the pinned Git commit. This makes the published SHA deterministic across platforms where Git may normalize checkout line endings. The working source file must separately exist and parse.

## Atomic canonical ownership transfer

Both consumers now load the same portable repository-relative path:

```text
external/cluster-foundation/src/DeterministicSelection.ps1
```

The consumers are:

- `scripts/ScenarioDiagnosis.ps1`
- `providers/azure/aks/scripts/Lab-Aks.ps1`

The former `foundation/DeterministicSelection.ps1` and platform-owned neutral suite are removed in the same migration. No compatibility wrapper or fallback remains. After M20, `cluster-foundation` is the sole canonical implementation owner.

## Ownership and compatibility

`cluster-foundation` owns the generic source, neutral public-contract tests, VERSION, and signed release. `platform-breakfix` owns the lock and integrity checks, consumer path wiring, diagnosis predicates/identifiers/summaries, Azure revision candidate adaptation and matching, Kubernetes compatibility, provider errors, and all consumer regressions.

Diagnosis identifiers and summaries remain byte-compatible. Managed-Istio zero/one/multiple selection, original-object return, post-selection `KubernetesOfficial` compatibility, and bounded provider failure remain unchanged. Operations Contracts v1/v2, Lab Health Contract v1, Evidence Contract v1, scenario schema v1, profiles, lifecycle, OpenTofu, dashboard, and CLI are unchanged.

## Integrity and architecture enforcement

`validation/foundation/cluster-foundation-dependency.tests.ps1` fails closed unless:

- the submodule exists and is a gitlink;
- `.gitmodules`, actual origin, and lock use the approved URL;
- gitlink, detached submodule HEAD, lock SHA, and signed tag target equal the release commit;
- no mutable branch is configured or checked out;
- lock version/tag/contract and submodule VERSION agree;
- the locked source exists, its raw Git blob SHA-256 agrees, and it parses;
- the signed tag verifies when an allowed-signers configuration is available;
- both consumers load the external source;
- no local implementation remains;
- one reachable implementation and one generic exactly-one guard remain;
- foundation executable content has no dependency on platform consumers.

The upstream standalone suite runs from the submodule during platform validation but remains physically owned upstream. Platform diagnosis and Istio tests prove contract compatibility.

## Developer bootstrap

Fresh clone:

```powershell
git clone --recurse-submodules https://github.com/stevenhart235-dev/platform-breakfix.git
```

Existing clone:

```powershell
git submodule update --init --recursive
```

The platform never downloads dependency source during runtime. If the submodule is missing, integrity validation fails with the initialization command; it never falls back to a local implementation. Tests and consumers resolve paths from repository/script locations, not the current directory or a developer-specific absolute path.

## CI and trust

A future CI checkout must initialize submodules, preserve the recorded gitlink, configure the approved SSH allowed-signers policy when signature verification is required, run dependency integrity and upstream tests, then run the complete platform suite. It must reject URL, lock, gitlink, VERSION, tag, signature, source hash, or detached-HEAD mismatches.

Trust is anchored in the approved public repository, immutable gitlink SHA, bounded lock, signed annotated tag, expected source hash, and platform consumer regressions. No mutable `main`/`latest` dependency, runtime network fetch, or credential is used.

## Rollback

Rollback the initial migration by reverting the complete M20 platform commit, restoring the previous local implementation and wiring together. For a future dependency update, restore the prior gitlink and lock atomically and rerun the full suite. Never manually copy foundation source back into the platform or update only one side of the pin.

## Validation

Acceptance requires dependency integrity and tag verification, upstream standalone tests, all platform PowerShell parsing and provider regressions, checksum-verified OpenTofu 1.11.13 formatting and AKS/EKS validation, all seven Kustomize renders, architecture/schema/hook checks, whitespace, artifact exclusion, and a safe submodule deinitialize/reinitialize simulation restoring the exact gitlink.
