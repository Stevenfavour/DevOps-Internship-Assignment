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

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "quickstart-vpc" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.zone
  map_public_ip_on_launch = false
  tags = { Name = "quickstart-private" }
}

resource "aws_security_group" "internal" {
  name   = "quickstart-internal"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

resource "aws_instance" "inference_vm" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.machine_type
  subnet_id     = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.internal.id]

  key_name = aws_key_pair.ssh_key.key_name

  user_data = <<-EOS
    #!/bin/bash
    sudo apt-get update && sudo apt-get install -y curl jq git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    git clone --depth 1 --filter=blob:none --sparse https://github.com/Alchemyst-ai/hiring.git && \
    cd hiring && \
    git sparse-checkout set may-2026/devops && \
    cd may-2026/devops/quickstart && \
    # Build the inference worker (Python)
    cd workers/inference-worker && pip3 install -r requirements.txt && cd ../.. && \
    iii start --config config.yaml &
  EOS
}


# Caller worker VM (private, no public IP)
resource "aws_instance" "caller_vm" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.machine_type
  subnet_id     = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.internal.id]
  key_name = aws_key_pair.ssh_key.key_name
  user_data = <<-EOS
    #!/bin/bash
    sudo apt-get update && sudo apt-get install -y curl jq git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    git clone --depth 1 --filter=blob:none --sparse https://github.com/Alchemyst-ai/hiring.git && \
    cd hiring && \
    git sparse-checkout set may-2026/devops && \
    cd may-2026/devops/quickstart && \
    # Build the caller worker (TypeScript)
    cd workers/caller-worker && npm install && npm run build && cd ../.. && \
    iii start --config config.yaml &
  EOS
}

# API gateway VM (public, runs only HTTP worker)
resource "aws_security_group" "api_sg" {
  name   = "quickstart-api"
  description = "Allow HTTP, HTTPS and SSH"
  vpc_id = aws_vpc.vpc.id

 ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # chomp() removes the hidden newline character from the website response
  cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "api_vm" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.machine_type
  subnet_id     = aws_subnet.private.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.internal.id, aws_security_group.api_sg.id]
  key_name = aws_key_pair.ssh_key.key_name
  user_data = <<-EOS
    #!/bin/bash
    sudo apt-get update && sudo apt-get install -y curl jq git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    git clone https://github.com/your-org/quickstart.git /opt/quickstart
    cd /opt/quickstart
    # Only start HTTP worker (iii-http) – the config.yaml already defines it
    iii start --config config.yaml &
  EOS
}



resource "aws_key_pair" "ssh_key" {
  key_name   = "quickstart-key"
  public_key = file("${path.module}/.ssh/id_rsa.pub")
}
