# Failover region's TGW + VPC attachment + three peering attachments to the
# existing TGWs. Each peering needs a (requester, accepter) pair: requester
# in the failover region, accepter in the existing region (via aws.<region>
# provider alias). Routes are added on both sides so traffic can flow
# bidirectionally between failover and each existing region.

resource "aws_ec2_transit_gateway" "failover" {
  provider                        = aws.failover
  description                     = "rp-stretch-failover"
  amazon_side_asn                 = var.failover_tgw_asn
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "${var.failover_cluster_name}-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "failover" {
  provider           = aws.failover
  transit_gateway_id = aws_ec2_transit_gateway.failover.id
  vpc_id             = module.vpc_failover.vpc_id
  subnet_ids         = module.vpc_failover.private_subnets

  tags = { Name = "${var.failover_cluster_name}-tgw-attach" }
}

# --- Peering attachments: failover (requester) ↔ each existing TGW (accepter) ---

resource "aws_ec2_transit_gateway_peering_attachment" "failover_east" {
  provider                = aws.failover
  transit_gateway_id      = aws_ec2_transit_gateway.failover.id
  peer_transit_gateway_id = data.aws_ec2_transit_gateway.east.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = var.existing_clusters["east"].region

  tags = { Name = "rp-failover-to-${var.existing_clusters["east"].name}" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "failover_east" {
  provider                      = aws.east
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.failover_east.id

  tags = { Name = "rp-failover-to-${var.existing_clusters["east"].name}" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "failover_west" {
  provider                = aws.failover
  transit_gateway_id      = aws_ec2_transit_gateway.failover.id
  peer_transit_gateway_id = data.aws_ec2_transit_gateway.west.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = var.existing_clusters["west"].region

  tags = { Name = "rp-failover-to-${var.existing_clusters["west"].name}" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "failover_west" {
  provider                      = aws.west
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.failover_west.id

  tags = { Name = "rp-failover-to-${var.existing_clusters["west"].name}" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "failover_eu" {
  provider                = aws.failover
  transit_gateway_id      = aws_ec2_transit_gateway.failover.id
  peer_transit_gateway_id = data.aws_ec2_transit_gateway.eu.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = var.existing_clusters["eu"].region

  tags = { Name = "rp-failover-to-${var.existing_clusters["eu"].name}" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "failover_eu" {
  provider                      = aws.eu
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.failover_eu.id

  tags = { Name = "rp-failover-to-${var.existing_clusters["eu"].name}" }
}

# --- TGW routes: failover side learns the three existing CIDRs ---

resource "aws_ec2_transit_gateway_route" "failover_to_east" {
  provider                       = aws.failover
  destination_cidr_block         = var.existing_clusters["east"].vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_east.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.failover.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "failover_to_west" {
  provider                       = aws.failover
  destination_cidr_block         = var.existing_clusters["west"].vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.failover.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "failover_to_eu" {
  provider                       = aws.failover
  destination_cidr_block         = var.existing_clusters["eu"].vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.failover.association_default_route_table_id
}

# --- TGW routes: each existing TGW learns the failover CIDR ---

resource "aws_ec2_transit_gateway_route" "east_to_failover" {
  provider                       = aws.east
  destination_cidr_block         = var.failover_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_east.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway.east.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "west_to_failover" {
  provider                       = aws.west
  destination_cidr_block         = var.failover_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_west.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "eu_to_failover" {
  provider                       = aws.eu
  destination_cidr_block         = var.failover_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.failover_eu.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway.eu.association_default_route_table_id
}
