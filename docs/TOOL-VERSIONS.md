# Tool version policy

The EKS OpenTofu root currently declares OpenTofu `>= 1.11.5, < 1.12.0`.
The workstation used during the platform-contract change had OpenTofu 1.12.5
installed. That binary is outside the declared supported range.

The constraint is not widened in this phase. Provider and module compatibility
with OpenTofu 1.12 has not been established through a clean initialization,
plan, provision, and destroy cycle, and widening it would turn an observed local
version into an unsupported repository promise.

For supported EKS work, install and select an OpenTofu 1.11.x release satisfying
the root constraint. OpenTofu 1.12 support may be added after compatibility is
tested deliberately. Validation performed with 1.12.5 is useful static evidence
but does not certify that version as supported.
