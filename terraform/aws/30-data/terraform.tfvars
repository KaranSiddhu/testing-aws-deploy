# db.t4g.micro: 2 vCPU (burstable), 1 GiB, Graviton. ~$0.016/hour.
#
# Graviton (t4g) is cheaper than Intel (t3) for the same specs, and RDS runs the
# same PostgreSQL either way, so there is no compatibility question - unlike the
# node group, where the instance architecture has to match the container images.
#
# AWNIC runs db.m6g.large Multi-AZ. This is roughly 1/20th the cost.
db_instance_class = "db.t4g.micro"
