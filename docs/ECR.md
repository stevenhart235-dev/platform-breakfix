# Optional Amazon ECR repositories

Amazon ECR is optional AWS infrastructure that external workload repositories
can use to store container images. It belongs here because this repository
owns the ephemeral AWS environment. Application source, image builds, pushes,
Kubernetes configuration, and workload deployment remain external.

No repositories are created by default. Configure zero, one, or many using a
map keyed by stable logical identifiers:

```hcl
ecr_repositories = {
  first = {
    name = "example/first"
  }
  second = {
    name                   = "example/second"
    preserve_on_destroy    = true
    max_untagged_image_age = 14
    max_tagged_images      = 50
  }
}
```

| Attribute | Type | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `name` | string | yes | none | AWS ECR repository name |
| `preserve_on_destroy` | bool | no | `false` | Protect the repository and lifecycle policy from OpenTofu destruction |
| `max_untagged_image_age` | number | no | `7` | Expire untagged images older than this many days |
| `max_tagged_images` | number | no | `20` | Retain this many most-recent tagged images |

Repository names must be unique and follow the ECR naming rules validated by
the root module. Retention settings must be positive whole numbers.

## Repository and lifecycle defaults

All repositories use immutable image tags, scan images on push, and use
AWS-managed AES-256 encryption. These defaults prevent a tag from silently
changing, provide basic vulnerability scanning, and encrypt images without
introducing customer-managed key infrastructure. Because tags cannot be
overwritten, external builders must publish unique, versioned tags such as a
release version or commit identifier instead of repeatedly pushing `latest`.

Each repository receives two non-overlapping lifecycle rules:

1. Priority 1 expires untagged images more than 7 days after they were pushed.
2. Priority 2 matches all tagged images and expires older images when more
   than 20 tagged images exist.

Both retention numbers can be overridden per repository. The first rule
matches only untagged images and the second only tagged images, so an image
cannot match both rules.

## Deletion and preservation

Repositories use forced deletion by default, allowing a normal ephemeral
`tofu destroy` to delete them even when they contain images. A repository with
`preserve_on_destroy = true` disables forced deletion and applies OpenTofu
`prevent_destroy` to both the repository and lifecycle policy. A destroy or
configuration removal therefore fails until preservation is deliberately
disabled.

Changing `preserve_on_destroy` moves the item between protected and
destroyable resource sets. OpenTofu cannot make `prevent_destroy` conditional,
so changing the setting without moving state may produce a destroy/create
plan; a transition away from preservation is blocked by `prevent_destroy`.
Change the setting in configuration, move both resource instances in state to
their new addresses, and review the resulting plan. State operations should
be backed up and performed by an experienced operator.

To change `example` from destroyable to preserved:

```powershell
tofu state mv 'aws_ecr_repository.destroyable["example"]' 'aws_ecr_repository.preserved["example"]'
tofu state mv 'aws_ecr_lifecycle_policy.destroyable["example"]' 'aws_ecr_lifecycle_policy.preserved["example"]'
tofu plan
```

To change `example` from preserved to destroyable:

```powershell
tofu state mv 'aws_ecr_repository.preserved["example"]' 'aws_ecr_repository.destroyable["example"]'
tofu state mv 'aws_ecr_lifecycle_policy.preserved["example"]' 'aws_ecr_lifecycle_policy.destroyable["example"]'
tofu plan
```

These addresses exactly match the separate resource collections. Forced
deletion and destruction prevention are never enabled on the same repository.

## External workflow

```text
Create ephemeral AWS infrastructure and EKS cluster
↓
Optionally create ECR repositories
↓
Read repository URIs from OpenTofu outputs
↓
External repository builds application images
↓
External repository authenticates to ECR and pushes images
↓
External repository deploys workloads to Kubernetes
↓
Destroy the ephemeral environment and, unless explicitly preserved, its ECR repositories
```

An external system can retrieve all repository details after apply:

```powershell
tofu output -json ecr_repositories
```

The structured output is keyed exactly like the input and provides `name`,
`arn`, `uri`, and `registry_id` for each repository. It is `{}` when ECR is
not configured.

## Disposable Seneschal lab repositories

The example configuration for this disposable lab provisions these release
artifact repositories:

- `seneschal/core`
- `seneschal/migrations`
- `seneschal/demo-deployment-worker`

`platform-breakfix` provisions only the reusable ECR infrastructure.
`seneschal-core` builds and publishes the core and migration images, including
`seneschal/migrations:<release-tag>`. The repository that owns
`seneschal/demo-deployment-worker` builds and publishes that worker image.
`seneschal-demo-lab` references and consumes the published images during
deployment.

Image building, pushing, tagging, and deployment are not responsibilities of
`platform-breakfix`.

The EKS module attaches the standard Amazon ECR read-only managed policy to
managed node roles, so no additional IAM policy is created. Image builders and
deployment systems must obtain their own authentication and least-privilege
push access outside this repository. This configuration creates no build
logic, deployment identity, push permission, Kubernetes manifest, pull secret,
Helm or Kustomize configuration, or workload.
