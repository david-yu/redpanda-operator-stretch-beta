# Look up resources from the main `aws/terraform/` stack via tags. The main
# stack tags VPCs/TGWs/SGs with `Project=<project_name>` and Name patterns
# matching the cluster name, so we can find them without remote_state.
#
# These data sources will fail at apply time if the main stack hasn't been
# applied yet (or if its tags were customized away from the defaults).
# Override `existing_clusters` in variables.tf if you renamed clusters.

# --- Existing VPCs ---
data "aws_vpc" "east" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["east"].name}-vpc"]
  }
}

data "aws_vpc" "west" {
  provider = aws.west
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["west"].name}-vpc"]
  }
}

data "aws_vpc" "eu" {
  provider = aws.eu
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["eu"].name}-vpc"]
  }
}

# --- Existing Transit Gateways (used as peer_transit_gateway_id targets) ---
data "aws_ec2_transit_gateway" "east" {
  provider = aws.east
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["east"].name}-tgw"]
  }
}

data "aws_ec2_transit_gateway" "west" {
  provider = aws.west
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["west"].name}-tgw"]
  }
}

data "aws_ec2_transit_gateway" "eu" {
  provider = aws.eu
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["eu"].name}-tgw"]
  }
}

# --- Existing VPC route tables — for adding routes to failover_vpc_cidr ---
data "aws_route_tables" "east" {
  provider = aws.east
  vpc_id   = data.aws_vpc.east.id
}

data "aws_route_tables" "west" {
  provider = aws.west
  vpc_id   = data.aws_vpc.west.id
}

data "aws_route_tables" "eu" {
  provider = aws.eu
  vpc_id   = data.aws_vpc.eu.id
}

# --- Existing EKS node security groups — for adding failover-CIDR ingress ---
# The terraform-aws-modules/eks/aws module names the node SG `<cluster>-node-<rand>`
# and tags it `Name = "<cluster>-node"`. Filter by VPC + Name tag for an exact match.
data "aws_security_groups" "east_node_sg" {
  provider = aws.east
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.east.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["east"].name}-node"]
  }
}

data "aws_security_groups" "west_node_sg" {
  provider = aws.west
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.west.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["west"].name}-node"]
  }
}

data "aws_security_groups" "eu_node_sg" {
  provider = aws.eu
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eu.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.existing_clusters["eu"].name}-node"]
  }
}

data "aws_availability_zones" "failover" {
  provider = aws.failover
  state    = "available"
}
