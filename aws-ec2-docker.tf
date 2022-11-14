terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region     = "eu-west-2"
  shared_credentials_file = "/home/shlomi/.aws/credentials"
  profile                 =  "labos"
}



variable "ssh_allow_ip" {
    description = "used with security group to all ingress ssh ip"
}

resource "aws_vpc" "dev-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}


resource "aws_subnet" "flask-restapi-app" {
  vpc_id     = aws_vpc.dev-vpc.id
  cidr_block = "10.0.1.0/24"
  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.dev-vpc.id
  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_route_table" "dev-routing-table" {
  vpc_id = aws_vpc.dev-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_route_table_association" "dev-rta" {
  subnet_id      = aws_subnet.flask-restapi-app.id
  route_table_id = aws_route_table.dev-routing-table.id
}


resource "aws_security_group" "allow_web_ssh" {
  name        = "allow_web_ssh"
  description = "Allow web & ssh traffic"
  vpc_id      = aws_vpc.dev-vpc.id

  ingress {
    description = "web"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allow_ip]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_network_interface" "nic" {
  subnet_id       = aws_subnet.flask-restapi-app.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web_ssh.id]

  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_eip" "eip" {
  vpc                       = true
  network_interface         = aws_network_interface.nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.gw,
    aws_instance.dev-server
  ]

  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2-key-pair" {
  key_name   = "deployer"
  public_key = tls_private_key.pk.public_key_openssh

  provisioner "local-exec" {
    command = "echo '${tls_private_key.pk.private_key_pem}' > ./deployer.pem"
  }

  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }
}

resource "aws_instance" "dev-server" {
  ami           = "ami-0f540e9f488cfa27d"
  instance_type = "t2.micro"
  key_name      = "deployer"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.nic.id
  }


  tags = {
    "env"     = "assignment"
    "creator" = "shlomi-tubul"
  }


  user_data = <<-EOF
  #!/bin/bash
  sudo apt-get update
  sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y 
  sudo groupadd docker
  sudo usermod -aG docker ubuntu
  mkdir ~/app
  curl -LSs https://api.github.com/repos/shlomitubul/flask-gunicorn-nginx/tarball -o master.tar.gz
  tar -xvzf master.tar.gz --strip-components=1 -C ~/app
  cd ~/app && docker compose build && docker compose up -d
  EOF
}



