# ECR: AWS's private container registry.
#
# Not used until Phase 7, created here because it belongs with the other data
# resources and costs nothing while empty (storage is $0.10/GB/month).
#
# WHY MIRROR AT ALL when the images are already on Docker Hub:
#   - Docker Hub rate-limits anonymous pulls to 100 per 6 hours. A cluster
#     restarting can burn that in minutes, and every pod then fails with
#     `toomanyrequests`.
#   - ECR pulls stay inside AWS: faster, and no egress charge.
#   - AWNIC has no choice at all - its VPC has no route to Docker Hub.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name = each.value

  # IMMUTABLE tags: once dummy-hello-be:dev-7adf167 is pushed, that tag can
  # never point at different content. Pushing the same tag again is rejected.
  #
  # This is what makes a tag as trustworthy as a digest, and it is why AWNIC can
  # safely tag-pin its two vendored charts instead of digest-pinning them.
  #
  # It also means your CI cannot silently overwrite a released image, which is a
  # surprisingly common way to break a rollback.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Scan for known CVEs on every push. Free at basic level.
    scan_on_push = true
  }

  # Practice only: lets `terraform destroy` remove a repository that still has
  # images in it. In production this is false, so a destroy cannot quietly take
  # your images with it.
  force_delete = true

  tags = { Name = each.value }
}

# Without a lifecycle policy every image ever pushed is kept forever and billed
# forever. Untagged images in particular pile up: each new push of a tag leaves
# the previous digest untagged but still stored.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
