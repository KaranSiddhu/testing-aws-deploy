# 00-prereq

Creates the S3 bucket that holds every other layer's Terraform state.

**This layer uses a LOCAL backend.** Its `terraform.tfstate` is a file in this
directory, gitignored. It has to be: it creates the bucket that remote state
lives in, and it cannot store its own state somewhere that does not exist yet.

```bash
terraform init
terraform plan      # read it
terraform apply
```

Four resources, a few seconds, effectively free.

## After applying

```bash
terraform output state_bucket
```

That name is already hardcoded in each downstream layer's `backend.tf`. If your
account id differs from the one they were written against, update all three -
the bucket name includes the account id, because S3 bucket names are globally
unique across all of AWS.

## Do not destroy this

`destroy.sh` deliberately leaves this layer alone. The bucket costs a fraction
of a cent per month and holds the state of everything else. Destroying it
between sessions would mean Terraform forgetting what it built - the resources
would still exist, still bill, and nothing would know how to remove them.

If you genuinely want it gone, destroy every other layer first, then:

```bash
terraform destroy
```

`force_destroy = true` allows it even with state files inside. That is a
practice-only setting; in production it is `false`.
