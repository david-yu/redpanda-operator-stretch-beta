module "vpc_failover" {
  source    = "terraform-aws-modules/vpc/aws"
  version   = "~> 5.13"
  providers = { aws = aws.failover }

  name = "${var.failover_cluster_name}-vpc"
  cidr = var.failover_vpc_cidr

  azs             = slice(data.aws_availability_zones.failover.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(var.failover_vpc_cidr, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.failover_vpc_cidr, 4, i + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
