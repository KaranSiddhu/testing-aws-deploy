# EKS managed node group: the EC2 instances your pods actually run on.
#
# "Managed" means AWS handles the autoscaling group, the AMI, and draining nodes
# during an upgrade. The alternative is self-managed nodes, where all of that is
# yours.
#
# FIXED SIZE, no autoscaler. Two nodes, always. Karpenter or Cluster Autoscaler
# would add a controller, IAM permissions and a scaling policy to reason about,
# and none of that teaches you anything you need yet. AWNIC also runs a fixed
# group, for a different reason: Karpenter has no VPC endpoint for the EC2 Price
# List API and falls back to a static price list it can never refresh.

data "aws_iam_policy_document" "assume_node" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.assume_node.json
}

# The three policies every EKS node needs. Miss any one and nodes either fail to
# join the cluster or join and cannot do useful work.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    # Lets the kubelet register the node with the cluster.
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",

    # Lets the VPC CNI plugin attach elastic network interfaces and hand pods
    # real VPC IP addresses. Without it every pod sits in ContainerCreating with
    # "failed to assign an IP address to container".
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",

    # Lets the node pull images from ECR. Not needed for Docker Hub, but Phase 7
    # mirrors images into ECR and it is far easier to grant now than to debug an
    # ImagePullBackOff later.
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.instance_type]

  # AL2023 is the current Amazon Linux for EKS. AL2 is end of life.
  # x86_64, because the images CI builds are multi-arch but t3 instances are
  # Intel. (An arm64 node type like t4g would also work and is cheaper - a good
  # experiment later, and one that only works BECAUSE the images are multi-arch.)
  ami_type = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  # Replace one node at a time during an upgrade rather than all at once.
  update_config {
    max_unavailable = 1
  }

  # No remote_access block, so no SSH key and no port 22 exposed. If you need a
  # shell on a node, use SSM Session Manager - it needs no open port and every
  # session is logged.

  depends_on = [aws_iam_role_policy_attachment.node]

  tags = { Name = "${var.name}-ng" }

  lifecycle {
    # desired_size drifts if anything ever scales the group. Ignoring it stops
    # Terraform proposing to undo that on the next apply.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
