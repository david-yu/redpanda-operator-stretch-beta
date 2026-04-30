# Security-group ingress rules:
#   - failover node SG accepts traffic from each existing VPC CIDR (and own CIDR for NLB SNAT)
#   - each existing node SG accepts traffic from the failover VPC CIDR
#
# We pull the existing node SG IDs via data sources (filtered by VPC + Name
# tag — the terraform-aws-modules/eks/aws module names node SGs
# `<cluster>-node-<rand>` and tags them `Name = "<cluster>-node"`).

locals {
  failover_sg_rules = merge(
    {
      for combo in setproduct(var.cross_cluster_ports, local.existing_vpc_cidrs) :
      "${combo[0]}-${combo[1]}" => { port = combo[0], cidr = combo[1] }
    },
    { "9443-local" = { port = 9443, cidr = var.failover_vpc_cidr } },
  )
}

# --- failover node SG ingress ---
resource "aws_vpc_security_group_ingress_rule" "failover" {
  provider          = aws.failover
  for_each          = local.failover_sg_rules
  security_group_id = module.eks_failover.node_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value.port}/tcp from ${each.value.cidr}"
}

# --- existing node SGs ingress for failover CIDR ---
resource "aws_vpc_security_group_ingress_rule" "east_from_failover" {
  provider          = aws.east
  for_each          = toset([for p in var.cross_cluster_ports : tostring(p)])
  security_group_id = data.aws_security_groups.east_node_sg.ids[0]
  cidr_ipv4         = var.failover_vpc_cidr
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value}/tcp from failover ${var.failover_vpc_cidr}"
}

resource "aws_vpc_security_group_ingress_rule" "west_from_failover" {
  provider          = aws.west
  for_each          = toset([for p in var.cross_cluster_ports : tostring(p)])
  security_group_id = data.aws_security_groups.west_node_sg.ids[0]
  cidr_ipv4         = var.failover_vpc_cidr
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value}/tcp from failover ${var.failover_vpc_cidr}"
}

resource "aws_vpc_security_group_ingress_rule" "eu_from_failover" {
  provider          = aws.eu
  for_each          = toset([for p in var.cross_cluster_ports : tostring(p)])
  security_group_id = data.aws_security_groups.eu_node_sg.ids[0]
  cidr_ipv4         = var.failover_vpc_cidr
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  description       = "stretch-cluster ${each.value}/tcp from failover ${var.failover_vpc_cidr}"
}
