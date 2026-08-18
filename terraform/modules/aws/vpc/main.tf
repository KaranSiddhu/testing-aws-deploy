# VPC with public subnets only.
#
# NO PRIVATE SUBNETS AND NO NAT GATEWAY, deliberately. A NAT Gateway costs
# $0.045/hour ($32.85/month) just to exist, whether or not traffic flows, and it
# is the single most common surprise on an AWS bill.
#
# The trade-off: nodes get public IPs and reach the internet directly, so their
# only protection is security groups rather than security groups AND an
# unroutable subnet. That is thinner defence in depth, and for a practice
# cluster it is the right call.
#
# Converting this to private subnets + NAT is a good standalone exercise later,
# where the networking is the lesson rather than a complication on top of a
# first EKS cluster.
#
# For contrast: magoneai-awnic-deploy has no internet gateway AND no NAT. Its
# nodes reach AWS services through ~14 VPC interface endpoints and nothing else,
# which is why every image is mirrored into ECR. That costs far MORE than a NAT
# Gateway - it exists because the client required an air gap.

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block

  # Both required by EKS. Without DNS hostnames the kubelet cannot resolve the
  # cluster endpoint, and nodes fail to join with a timeout that says nothing
  # about DNS.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# One subnet per availability zone.
#
# Two AZs minimum: the EKS control plane requires subnets in at least two, and
# RDS requires two even for a single-AZ instance (it wants somewhere to fail
# over to if you ever enable Multi-AZ).
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  # Nodes need a public IP to reach the internet without a NAT Gateway.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${each.key}"

    # Tells the AWS Load Balancer Controller (Phase 7) that it may create
    # internet-facing load balancers in this subnet. Without this tag the
    # controller ignores the subnet and an Ingress never gets an address, with
    # the reason buried in the controller's logs.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  # Everything not destined for inside the VPC goes to the internet gateway.
  # This single route is what makes a subnet "public". There is no flag.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

# A route table does nothing until it is associated with a subnet. Miss one
# subnet and instances in that AZ alone have no internet - which reads as a
# flaky availability zone rather than a missing association.
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
