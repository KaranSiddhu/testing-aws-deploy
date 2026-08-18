# 1.36 for three reasons: it is on standard support (so $0.10/hour, not $0.60),
# it is what magoneai-awnic-deploy runs, and it matches the local kind cluster
# (v1.36.1) so local and cloud behave identically.
kubernetes_version = "1.36"

# t3.small: 2 vCPU, 2 GiB, ~$0.0208/hour on-demand in us-east-1.
# Two of them is ~$1.00/day.
#
# If pods end up Pending with "Insufficient memory", this is the knob. Bump to
# t3.medium (4 GiB, ~$0.0416/hour) rather than adding nodes: the EKS system
# daemonsets run on EVERY node, so a third small node adds less usable capacity
# than you would expect.
node_instance_type = "t3.small"
node_count         = 2
