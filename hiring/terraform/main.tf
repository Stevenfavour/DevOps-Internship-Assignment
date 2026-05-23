terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -------------------------------------------------
# VPC
# -------------------------------------------------
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "quickstart-vpc" }
}

# -------------------------------------------------
# Subnets
# -------------------------------------------------
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.zone
  map_public_ip_on_launch = false
  tags = { Name = "quickstart-private" }
}

# Public subnet — required for the NAT Gateway and API VM
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.zone
  map_public_ip_on_launch = true
  tags = { Name = "quickstart-public" }
}


# Internet Gateway (required for public subnet → internet)

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "quickstart-igw" }
}


# NAT Gateway (allows private VMs to reach internet


resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id # NAT must live in the PUBLIC subnet
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "quickstart-nat" }
}


# Route Tables


# Public route table: public subnet → IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "quickstart-public-rt" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Private route table: private subnet → NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "quickstart-private-rt" }
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}


# Security Groups


# Internal SG: allow all traffic between VMs in the private subnet
resource "aws_security_group" "internal" {
  name   = "quickstart-internal"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "All traffic from private subnet (RPC)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "quickstart-internal-sg" }
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# API SG: port 3111 public, SSH from your IP only
resource "aws_security_group" "api_sg" {
  name        = "quickstart-api"
  description = "API gateway: port 3111 public, SSH from deployer IP"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "iii-http inference API"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from deployer only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  # This cidr block allows ssh traffic from only your local machine to reach the API VM. AWS reads the your current IP address and stores it each time the script is invoked.

  ingress {
    description = "III engine WebSocket from private subnet"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "quickstart-api-sg" }
}


# AMI + Key Pair

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "quickstart-key"
  public_key = file("${path.module}/.ssh/id_rsa.pub")
}


# EC2 Instances


# Inference worker (private subnet, no public IP)
resource "aws_instance" "inference_vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.machine_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.internal.id]
  key_name                    = aws_key_pair.ssh_key.key_name
  user_data = templatefile("${path.module}/scripts/inference_vm_userdata.sh", {
    api_private_ip = aws_instance.api_vm.private_ip
  })
  root_block_device {
    volume_size = 20  # increase from default 8GB to 20GB
    volume_type = "gp3"
  }
  
    

  tags = { Name = "inference-vm" }
}

# Caller worker (private subnet, no public IP)
resource "aws_instance" "caller_vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.machine_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.internal.id]
  key_name                    = aws_key_pair.ssh_key.key_name
  user_data = templatefile("${path.module}/scripts/caller_vm_userdata.sh", {
    api_private_ip = aws_instance.api_vm.private_ip
  })
  

  tags = { Name = "caller-vm" }
}

# API gateway VM (PUBLIC subnet, public IP, runs iii-http)
resource "aws_instance" "api_vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.machine_type
  subnet_id                   = aws_subnet.public.id # ← public subnet
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.api_sg.id]
  key_name                    = aws_key_pair.ssh_key.key_name
  user_data = templatefile("${path.module}/scripts/api_vm_userdata.sh", {})
  

  tags = { Name = "api-vm" }
}
