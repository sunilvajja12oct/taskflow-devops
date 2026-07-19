resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.environment}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-${var.environment}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# NAT instance via fck-nat: a maintained, purpose-built NAT AMI (Amazon
# Linux 2023 based). Cheaper than a hand-rolled iptables NAT script to
# operate long-term, and far cheaper than a managed NAT Gateway.
# Billable resource - see cost note below.
module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "1.3.0"

  name      = "${var.project}-${var.environment}-nat"
  vpc_id    = aws_vpc.main.id
  subnet_id = aws_subnet.public[0].id

  instance_type = "t3.micro"

  update_route_tables = true
  route_tables_ids = {
    "${var.project}-${var.environment}-private-rt" = aws_route_table.private.id
  }
}

# Baseline security group for private-subnet instances (Phase 2 attaches
# this to EC2/k3s nodes). No inbound rules at all - access is via SSM
# Session Manager, never an open port.
resource "aws_security_group" "private_instances" {
  name_prefix = "${var.project}-${var.environment}-private-"
  description = "Baseline SG for private-subnet instances - no inbound, SSM-only access"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-private-instances-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
