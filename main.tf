

# Define variables
variable "name" {
  description = "The name of the VPC"
  type        = string
  default     = "my-vpc"  # Replace with your desired VPC name
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"  # Replace with your desired CIDR block
}

variable "azs" {
  description = "A list of availability zones"
  type        = list(string)
  default     = ["us-west-1a", "us-west-1c"]  # Replace with your desired availability zones
}

variable "tags" {
  description = "A map of tags to apply to the VPC"
  type        = map(string)
  default     = {
    Name        = "my-vpc"
    Environment = "production"
  }  # Replace with your desired tags
}

# Define the provider for the first AWS account
provider "aws" {
  region = "us-west-1"
}

# Create the VPC in the first AWS account
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k + 10)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = var.tags
}

# Create the peering connection
resource "aws_vpc_peering_connection" "peering" {
  provider = aws
  depends_on = [module.vpc]

  peer_vpc_id    = "vpc-xxxxxxxxxxxxxxxxx"  # Replace with actual peer VPC ID
  vpc_id         = module.vpc.vpc_id
  auto_accept    = false
  peer_region    = "us-west-1"
  peer_owner_id  = "123456789012"  # Replace with actual peer account ID
}

# Create the peering connection accepter
resource "aws_vpc_peering_connection_accepter" "accepter" {
  provider                  = aws.account2
  vpc_peering_connection_id = aws_vpc_peering_connection.peering.id
  auto_accept               = true
}

# Define the provider for the second AWS account
provider "aws" {
  alias  = "account2"
  region = "us-west-1"
  assume_role {
    role_arn = "arn:aws:iam::987654321012:role/second-account-role"  # Replace with actual account ID and role name
  }
}

# Reference the existing VPC in the second AWS account
data "aws_vpcs" "vpcs_account2" {
  provider = aws.account2
}

# Create subnets in the VPC of the second AWS account
resource "aws_subnet" "public_subnet_1_account2" {
  provider                  = aws.account2
  vpc_id     = data.aws_vpcs.vpcs_account2.ids[0]
  cidr_block = "172.31.32.0/24"

  tags = {
    Name        = "public-subnet-1-account2"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnet_2_account2" {
  provider                  = aws.account2
  vpc_id     = data.aws_vpcs.vpcs_account2.ids[0]
  cidr_block = "172.31.48.0/24"

  tags = {
    Name        = "public-subnet-2-account2"
    Environment = "production"
  }
}

# Create a route table in the second VPC (account2)
resource "aws_route_table" "route_table_account2" {
  provider = aws.account2
  vpc_id   = data.aws_vpcs.vpcs_account2.ids[0]

  route {
    cidr_block                = var.vpc_cidr 
    vpc_peering_connection_id = aws_vpc_peering_connection_accepter.accepter.id
  }

  tags = {
    Name = "peering-route-table-account2"
  }
}

# Associate the route table with the public subnets in the second VPC (account2)
resource "aws_route_table_association" "association_account2_1" {
  provider = aws.account2
  subnet_id      = aws_subnet.public_subnet_1_account2.id
  route_table_id = aws_route_table.route_table_account2.id
}

resource "aws_route_table_association" "association_account2_2" {
  provider = aws.account2
  subnet_id      = aws_subnet.public_subnet_2_account2.id
  route_table_id = aws_route_table.route_table_account2.id
}