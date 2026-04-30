# Three VPCs — one per region — using the canonical VPC module.
# Each VPC has 3 public + 3 private subnets across AZs and NAT gateways
# (one per AZ) so EKS managed node groups in private subnets can pull images.

data "aws_availability_zones" "east" {
  provider = aws.east
  state    = "available"
}

data "aws_availability_zones" "west" {
  provider = aws.west
  state    = "available"
}

data "aws_availability_zones" "eu" {
  provider = aws.eu
  state    = "available"
}

module "vpc_east" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"
  providers = { aws = aws.east }

  name = "${local.cluster_name_east}-vpc"
  cidr = local.vpc_cidr_east

  azs             = slice(data.aws_availability_zones.east.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(local.vpc_cidr_east, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(local.vpc_cidr_east, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = false
  one_nat_gateway_per_az = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "vpc_west" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"
  providers = { aws = aws.west }

  name = "${local.cluster_name_west}-vpc"
  cidr = local.vpc_cidr_west

  azs             = slice(data.aws_availability_zones.west.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(local.vpc_cidr_west, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(local.vpc_cidr_west, 4, i + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "vpc_eu" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"
  providers = { aws = aws.eu }

  name = "${local.cluster_name_eu}-vpc"
  cidr = local.vpc_cidr_eu

  azs             = slice(data.aws_availability_zones.eu.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(local.vpc_cidr_eu, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(local.vpc_cidr_eu, 4, i + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
