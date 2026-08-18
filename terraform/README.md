# Terraform

Provisions the AWS infrastructure the Kubernetes layer runs on: VPC, EKS, RDS
and ECR. Structure mirrors `magoneai-awnic-deploy/terraform`, which is the AWS
one of the three real deployment repos.

**Unlike AWNIC's, this tree IS applied by us.** AWNIC's exists as a
specification and a drift baseline because the client's own vendor owns their
AWS layer. Here there is no vendor: we build it.

## Layout

```
modules/aws/           reusable, one concern each
  vpc                  10.0.0.0/16, 2 public subnets, IGW. No NAT, no private subnets
  eks                  control plane + OIDC provider for IRSA
  node-group           managed node group, fixed size, AL2023
  rds                  PostgreSQL 16, single-AZ, private
  ecr                  repositories, immutable tags, scan on push

aws/                   layers, applied in numeric order
  00-prereq            state bucket. LOCAL backend, it creates the remote one
  10-network           vpc
  20-cluster           eks + node group + add-ons
  30-data              rds + ecr
```

Shared configuration (`common.auto.tfvars`, `common-variables.tf`,
`common-providers.tf`, `common-versions.tf`) lives once at `aws/` and is
**symlinked** into each layer. Edit the file at `aws/`, not the symlink.

## Apply order

```bash
cd aws/00-prereq  && terraform init && terraform apply   # local backend
cd ../10-network  && terraform init && terraform apply
cd ../20-cluster  && terraform init && terraform apply   # ~12 minutes
cd ../30-data     && terraform init && terraform apply   # ~8 minutes
```

Layers read each other through `terraform_remote_state`, which is read-only.
That is what makes the split worth the extra steps: a bad plan in `10-network`
physically cannot destroy the database, and `terraform plan` in one layer
refreshes only that layer's resources rather than all of them.

## Cost

| Layer | Resource | Per hour | Per day |
|---|---|---|---|
| 00-prereq | S3 bucket | ~$0 | ~$0 |
| 10-network | VPC, subnets, IGW, routes | $0 | $0 |
| 20-cluster | EKS control plane | $0.100 | $2.40 |
| 20-cluster | 2 x t3.small | $0.042 | $1.00 |
| 30-data | RDS db.t4g.micro + 20 GiB | $0.019 | $0.46 |
| 30-data | ECR (empty) | $0 | $0 |
| **Total** | | **~$0.161** | **~$3.86** |

A six-hour session is about **$0.97**.

**No NAT Gateway**, deliberately: it would add $0.045/hour ($32.85/month) just
to exist. Nodes sit in public subnets with public IPs and are protected by
security groups rather than by being unroutable. That is thinner defence in
depth and the right trade for a practice cluster. Converting to private subnets
plus NAT is a good standalone exercise later.

**Kubernetes 1.36**, and the version matters financially: a version that has
fallen off EKS standard support costs **$0.60/hour** instead of $0.10. Check
before bumping:

```bash
aws eks describe-cluster-versions --region us-east-1 \
  --query 'clusterVersions[?versionStatus==`STANDARD_SUPPORT`].clusterVersion'
```

## Destroy

```bash
terraform/destroy.sh
```

Reverse order, `30-data` first. Destroying `10-network` first fails, because the
VPC still contains a cluster and a database.

`00-prereq` is left alone on purpose: it holds the state of everything else and
costs a fraction of a cent per month.

## State

Remote, in `s3://dummy-hello-tfstate-<account-id>`, one key per layer.
Versioned and encrypted, because **state files contain every managed value in
plaintext, including the RDS password**.

Locking is native S3 (`use_lockfile = true`, Terraform 1.11+). The DynamoDB
table older guides describe is obsolete.

There is no local state file except in `00-prereq`, and that one is gitignored.

## Conventions

- **Never commit** `.tfstate`, `.terraform/`, or anything under `generated/`
- **Read every plan** before applying. `terraform plan` is free and read-only
- **`terraform fmt -recursive`** before committing
- Bucket names include the account id because S3 names are globally unique
- Backend blocks cannot use variables, so the bucket name is written out in
  full in each layer. Changing accounts means editing all three
