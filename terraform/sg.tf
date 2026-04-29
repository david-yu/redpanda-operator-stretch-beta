# Cross-cluster SG ingress on the EKS node security groups.
# For each cluster, allow var.cross_cluster_ports from the two REMOTE CIDRs,
# plus port 9443 from the LOCAL CIDR (covers AWS NLB SNAT for the operator
# raft Service whose pods are in the same VPC as the NLB ENIs).

locals {
  # Map of "cluster:port:peer" -> rule definition. for_each loves flat maps.
  east_rules = merge(
    # Peer CIDRs
    {
      for combo in setproduct(var.cross_cluster_ports, [local.vpc_cidr_west, local.vpc_cidr_eu]) :
      "${combo[0]}-${combo[1]}" => { port = combo[0], cidr = combo[1] }
    },
    # Local CIDR for 9443 (NLB SNAT)
    { "9443-local" = { port = 9443, cidr = local.vpc_cidr_east } },
  )
  west_rules = merge(
    {
      for combo in setproduct(var.cross_cluster_ports, [local.vpc_cidr_east, local.vpc_cidr_eu]) :
      "${combo[0]}-${combo[1]}" => { port = combo[0], cidr = combo[1] }
    },
    { "9443-local" = { port = 9443, cidr = local.vpc_cidr_west } },
  )
  eu_rules = merge(
    {
      for combo in setproduct(var.cross_cluster_ports, [local.vpc_cidr_east, local.vpc_cidr_west]) :
      "${combo[0]}-${combo[1]}" => { port = combo[0], cidr = combo[1] }
    },
    { "9443-local" = { port = 9443, cidr = local.vpc_cidr_eu } },
  )
}

resource "aws_vpc_security_group_ingress_rule" "east" {
  provider          = aws.east
  for_each          = local.east_rules
  security_group_id = module.eks_east.node_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value.port}/tcp from ${each.value.cidr}"
}

resource "aws_vpc_security_group_ingress_rule" "west" {
  provider          = aws.west
  for_each          = local.west_rules
  security_group_id = module.eks_west.node_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value.port}/tcp from ${each.value.cidr}"
}

resource "aws_vpc_security_group_ingress_rule" "eu" {
  provider          = aws.eu
  for_each          = local.eu_rules
  security_group_id = module.eks_eu.node_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value.port}/tcp from ${each.value.cidr}"
}
