# ---------- Red: VPC 10.0.0.0/22 + 6 subredes /25 (2 publicas, 2 App, 2 Data) ----------
# Mismo diseno que EV1. Cambian dos cosas para EKS:
#   - etiquetas kubernetes.io/role/* para que Auto Mode encuentre donde crear el ALB
#   - la capa Data tiene su propia route table, sin ruta a Internet (RDS no la necesita)
# Queda libre 10.0.3.0/24 para crecer.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${local.name}-subnet-public-${local.az_suffix[count.index]}"
    Layer                    = "web"
    "kubernetes.io/role/elb" = "1" # ALB internet-facing del Ingress
  }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name                              = "${local.name}-subnet-app-${local.az_suffix[count.index]}"
    Layer                             = "app"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name  = "${local.name}-subnet-data-${local.az_suffix[count.index]}"
    Layer = "data"
  }
}

# Un solo NAT Gateway (en public-1a) por costo, como en EV1: da salida a los
# nodos de ambas AZ (ECR, CloudWatch, STS). El trafico de usuarios no pasa por
# aqui: entra por el IGW al ALB y llega a los pods por la ruta local de la VPC.
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${local.name}-eip-natgw" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.name}-natgw" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.name}-rt-app" }
}

# Solo la ruta local implicita: la capa Data no sale ni entra desde Internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-data" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}
