# VPC route table entries:
#   - failover VPC's route tables learn the three existing CIDRs (via failover TGW)
#   - each existing VPC's route tables learn the failover CIDR (via that region's TGW)

locals {
  failover_route_table_ids = concat(
    module.vpc_failover.private_route_table_ids,
    module.vpc_failover.public_route_table_ids,
  )
}

# --- failover VPC route tables → existing CIDRs ---

resource "aws_route" "failover_to_east" {
  provider               = aws.failover
  count                  = length(local.failover_route_table_ids)
  route_table_id         = local.failover_route_table_ids[count.index]
  destination_cidr_block = var.existing_clusters["east"].vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.failover.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.failover]
}

resource "aws_route" "failover_to_west" {
  provider               = aws.failover
  count                  = length(local.failover_route_table_ids)
  route_table_id         = local.failover_route_table_ids[count.index]
  destination_cidr_block = var.existing_clusters["west"].vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.failover.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.failover]
}

resource "aws_route" "failover_to_eu" {
  provider               = aws.failover
  count                  = length(local.failover_route_table_ids)
  route_table_id         = local.failover_route_table_ids[count.index]
  destination_cidr_block = var.existing_clusters["eu"].vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.failover.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.failover]
}

# --- existing VPC route tables → failover CIDR ---
# `aws_route_tables` data source returns ids as a list; iterate via for_each
# on the list converted to a set so each id keys a stable resource address.

resource "aws_route" "east_to_failover" {
  provider               = aws.east
  for_each               = toset(data.aws_route_tables.east.ids)
  route_table_id         = each.value
  destination_cidr_block = var.failover_vpc_cidr
  transit_gateway_id     = data.aws_ec2_transit_gateway.east.id
}

resource "aws_route" "west_to_failover" {
  provider               = aws.west
  for_each               = toset(data.aws_route_tables.west.ids)
  route_table_id         = each.value
  destination_cidr_block = var.failover_vpc_cidr
  transit_gateway_id     = data.aws_ec2_transit_gateway.west.id
}

resource "aws_route" "eu_to_failover" {
  provider               = aws.eu
  for_each               = toset(data.aws_route_tables.eu.ids)
  route_table_id         = each.value
  destination_cidr_block = var.failover_vpc_cidr
  transit_gateway_id     = data.aws_ec2_transit_gateway.eu.id
}
