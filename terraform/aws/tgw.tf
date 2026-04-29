# One TGW per region, full-mesh inter-region peering, static routes, VPC routes.
# AWS doesn't auto-cascade peering associations to TGW route tables — explicit
# resources for both the route table association and the route are required.

resource "aws_ec2_transit_gateway" "east" {
  provider                        = aws.east
  description                     = "rp-stretch-east"
  amazon_side_asn                 = 64900
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "${local.cluster_name_east}-tgw" }
}

resource "aws_ec2_transit_gateway" "west" {
  provider                        = aws.west
  description                     = "rp-stretch-west"
  amazon_side_asn                 = 64901
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "${local.cluster_name_west}-tgw" }
}

resource "aws_ec2_transit_gateway" "eu" {
  provider                        = aws.eu
  description                     = "rp-stretch-eu"
  amazon_side_asn                 = 64902
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "${local.cluster_name_eu}-tgw" }
}

# VPC attachments — each VPC attaches to its local TGW via the private subnets.
resource "aws_ec2_transit_gateway_vpc_attachment" "east" {
  provider           = aws.east
  transit_gateway_id = aws_ec2_transit_gateway.east.id
  vpc_id             = module.vpc_east.vpc_id
  subnet_ids         = module.vpc_east.private_subnets

  tags = { Name = "${local.cluster_name_east}-tgw-attach" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west" {
  provider           = aws.west
  transit_gateway_id = aws_ec2_transit_gateway.west.id
  vpc_id             = module.vpc_west.vpc_id
  subnet_ids         = module.vpc_west.private_subnets

  tags = { Name = "${local.cluster_name_west}-tgw-attach" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "eu" {
  provider           = aws.eu
  transit_gateway_id = aws_ec2_transit_gateway.eu.id
  vpc_id             = module.vpc_eu.vpc_id
  subnet_ids         = module.vpc_eu.private_subnets

  tags = { Name = "${local.cluster_name_eu}-tgw-attach" }
}

# Inter-region peering — full mesh: east<->west, east<->eu, west<->eu.
# Each peering needs an accepter on the receiver side.

resource "aws_ec2_transit_gateway_peering_attachment" "east_west" {
  provider                = aws.east
  transit_gateway_id      = aws_ec2_transit_gateway.east.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.west.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = local.region_west

  tags = { Name = "rp-east-to-rp-west" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_west" {
  provider                      = aws.west
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.east_west.id

  tags = { Name = "rp-east-to-rp-west" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "east_eu" {
  provider                = aws.east
  transit_gateway_id      = aws_ec2_transit_gateway.east.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.eu.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = local.region_eu

  tags = { Name = "rp-east-to-rp-eu" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "east_eu" {
  provider                      = aws.eu
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.east_eu.id

  tags = { Name = "rp-east-to-rp-eu" }
}

resource "aws_ec2_transit_gateway_peering_attachment" "west_eu" {
  provider                = aws.west
  transit_gateway_id      = aws_ec2_transit_gateway.west.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.eu.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = local.region_eu

  tags = { Name = "rp-west-to-rp-eu" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "west_eu" {
  provider                      = aws.eu
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.west_eu.id

  tags = { Name = "rp-west-to-rp-eu" }
}

# TGW route table — associate each peering attachment with the default RT
# (peerings aren't auto-associated even when default_route_table_association
# is enabled — that flag only applies to VPC attachments).

resource "aws_ec2_transit_gateway_route_table_association" "east_west" {
  provider                       = aws.east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "east_eu" {
  provider                       = aws.east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "west_east" {
  provider                       = aws.west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "west_eu" {
  provider                       = aws.west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.west_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "eu_east" {
  provider                       = aws.eu
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.eu.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_association" "eu_west" {
  provider                       = aws.eu
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.west_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.eu.association_default_route_table_id
}

# Static routes in each TGW route table for the two remote CIDRs.

resource "aws_ec2_transit_gateway_route" "east_to_west" {
  provider                       = aws.east
  destination_cidr_block         = local.vpc_cidr_west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "east_to_eu" {
  provider                       = aws.east
  destination_cidr_block         = local.vpc_cidr_eu
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.east.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "west_to_east" {
  provider                       = aws.west
  destination_cidr_block         = local.vpc_cidr_east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_west.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "west_to_eu" {
  provider                       = aws.west
  destination_cidr_block         = local.vpc_cidr_eu
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.west_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.west.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "eu_to_east" {
  provider                       = aws.eu
  destination_cidr_block         = local.vpc_cidr_east
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.east_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.eu.association_default_route_table_id
}

resource "aws_ec2_transit_gateway_route" "eu_to_west" {
  provider                       = aws.eu
  destination_cidr_block         = local.vpc_cidr_west
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.west_eu.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.eu.association_default_route_table_id
}

# VPC route table entries — each VPC's private and public route tables get
# entries pointing at the LOCAL TGW for the two REMOTE CIDRs. Pod traffic to
# remote-cluster CIDRs hits the local TGW, which then forwards through the
# inter-region peering.

locals {
  east_route_table_ids = concat(module.vpc_east.private_route_table_ids, module.vpc_east.public_route_table_ids)
  west_route_table_ids = concat(module.vpc_west.private_route_table_ids, module.vpc_west.public_route_table_ids)
  eu_route_table_ids   = concat(module.vpc_eu.private_route_table_ids, module.vpc_eu.public_route_table_ids)
}

# NOTE: count (not for_each) on aws_route. The route table IDs come from the
# VPC module's outputs, which Terraform treats as computed at apply time.
# for_each over those values fails with "Invalid for_each argument" because
# Terraform can't determine the set keys at plan time. count works because
# the LENGTH of the route_table_ids list is statically determinable from the
# VPC module's input subnet count.

resource "aws_route" "east_to_west" {
  provider               = aws.east
  count                  = length(local.east_route_table_ids)
  route_table_id         = local.east_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_west
  transit_gateway_id     = aws_ec2_transit_gateway.east.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.east]
}

resource "aws_route" "east_to_eu" {
  provider               = aws.east
  count                  = length(local.east_route_table_ids)
  route_table_id         = local.east_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_eu
  transit_gateway_id     = aws_ec2_transit_gateway.east.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.east]
}

resource "aws_route" "west_to_east" {
  provider               = aws.west
  count                  = length(local.west_route_table_ids)
  route_table_id         = local.west_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_east
  transit_gateway_id     = aws_ec2_transit_gateway.west.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.west]
}

resource "aws_route" "west_to_eu" {
  provider               = aws.west
  count                  = length(local.west_route_table_ids)
  route_table_id         = local.west_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_eu
  transit_gateway_id     = aws_ec2_transit_gateway.west.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.west]
}

resource "aws_route" "eu_to_east" {
  provider               = aws.eu
  count                  = length(local.eu_route_table_ids)
  route_table_id         = local.eu_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_east
  transit_gateway_id     = aws_ec2_transit_gateway.eu.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.eu]
}

resource "aws_route" "eu_to_west" {
  provider               = aws.eu
  count                  = length(local.eu_route_table_ids)
  route_table_id         = local.eu_route_table_ids[count.index]
  destination_cidr_block = local.vpc_cidr_west
  transit_gateway_id     = aws_ec2_transit_gateway.eu.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.eu]
}
