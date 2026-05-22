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
    to_port     = 65535
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

resource "aws_instance" "inference_vm" {
  ami           = "ami-0c02fb55956c7d316" # Debian 12 (update as needed)
  instance_type = var.machine_type
  subnet_id     = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.internal.id]

  key_name = aws_key_pair.ssh_key.key_name

  user_data = <<-EOS
    #!/bin/bash
    sudo apt-get update && sudo apt-get install -y curl jq git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    git clone https://github.com/your-org/quickstart.git /opt/quickstart
    cd /opt/quickstart/may-2026/devops/quickstart
    cd workers/inference-worker && pip3 install -r requirements.txt && cd ../..
    cd workers/caller-worker && npm install && npm run build && cd ../..
    iii start --config config.yaml &
  EOS
}


# Caller worker VM (private, no public IP)
resource "aws_instance" "caller_vm" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = var.machine_type
  subnet_id     = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.internal.id]
  key_name = aws_key_pair.ssh_key.key_name
  user_data = <<-EOS
    #!/bin/bash
    sudo apt-get update && sudo apt-get install -y curl jq git
    curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
    git clone https://github.com/your-org/quickstart.git /opt/quickstart
    cd /opt/quickstart
    cd workers/caller-worker && npm install && npm run build && cd ../..
    iii start --config config.yaml &
  EOS
}

# API gateway VM (public, runs only HTTP worker)
resource "aws_security_group" "api_sg" {
  name   = "quickstart-api"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "api_vm" {
  ami           = "ami-0c02fb55956c7d316"
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
