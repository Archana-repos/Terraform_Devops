terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}


# 1. Create VPC

resource "aws_vpc" "PROD-VPC" {
  cidr_block       = "9.0.0.0/16"
  #instance_tenancy = "default"

  tags = {
    Name = "PROD-VPC"
  }
}

# 2. Create Internet Gateway

resource "aws_internet_gateway" "PROD-IGW" {
  vpc_id = aws_vpc.PROD-VPC.id

  tags = {
    Name = "PROD-IGW"
  }
}

# 4. Create a Route table

resource "aws_route_table" "PROD-RT" {
  vpc_id = aws_vpc.PROD-VPC.id

  route {
    cidr_block = "9.0.1.0/24"
    gateway_id = aws_internet_gateway.PROD-IGW.id
  }
  
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.PROD-IGW.id
  }

  tags = {
    Name = "PROD-RT"
  }
}

# 3. Create a subnet

resource "aws_subnet" "PROD-Subnet" {
  vpc_id     = aws_vpc.PROD-VPC.id
  cidr_block = "9.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "PROD-Subnet"
  }
}
# 5. Associate subnet with route table

resource "aws_route_table_association" "PROD-RT-SN" {
  subnet_id      = aws_subnet.PROD-Subnet.id
  route_table_id = aws_route_table.PROD-RT.id
}
# 6. Create Security group to allow port 22, 80,443

resource "aws_security_group" "allow_web_tls" {
  name        = "allow_web_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.PROD-VPC.id

  tags = {
    Name = "allow_web_tls"
  }

  ingress {
    description = "HTTPS"
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 7. Create Network interface in subnet that was created in step 3

resource "aws_network_interface" "web-server" {
  subnet_id       = aws_subnet.PROD-Subnet.id
  private_ips     = ["9.0.1.50"]
  security_groups = [aws_security_group.allow_web_tls.id]

}

#8. Attach Elastic Internet Protocol to Network interface created in step 7

resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web-server.id
  associate_with_private_ip = "10.0.2.50"
  #depends_on = [ aws_internet_gateway.PROD-IGW ]
}

# Create a ubuntu server and install/enable apache

resource "aws_instance" "web-server-instance" {
    ami = "ami-04b4f1a9cf54c11d0"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "terraform_key"

    network_interface {
      network_interface_id = aws_network_interface.web-server.id
      device_index         = 0
    }

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your web server > /var/www/html/index.html'
                EOF
    tags = {
        Name = "web-server-instance"
    }


  
}


