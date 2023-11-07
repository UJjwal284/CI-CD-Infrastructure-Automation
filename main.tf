provider "aws" {
  region     = var.AWS_REGION
  access_key = var.AWS_ACCESS_KEY
  secret_key = var.AWS_SECRET_KEY
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = {
    Name = "vpc"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id
  tags   = {
    Name = "route_table"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "us-east-2a"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = {
    Name = "subnet"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags   = {
    Name = "internet_gateway"
  }
}

resource "aws_route" "route" {
  route_table_id         = aws_route_table.route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table_association" "route_table_association" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_security_group" "security_group" {
  description = "Security Group"
  name        = "security-group"
  vpc_id      = aws_vpc.vpc.id
  dynamic "ingress" {
    for_each = [80, 8080, 22, 443, 5000, 9000]
    iterator = port
    content {
      from_port   = port.value
      protocol    = "tcp"
      to_port     = port.value
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "security_group"
  }
}

resource "aws_security_group" "security_group_all_ports" {
  description = "Security group allowing all ports"
  name        = "security_group_all_ports"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "security_group_all_ports"
  }
}

resource "aws_instance" "aws_instance_jenkins" {
  ami                    = "ami-0e83be366243f524a"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet.id
  key_name               = "test-key"
  vpc_security_group_ids = [aws_security_group.security_group.id]
  user_data              = <<-EOF
                    #!/bin/bash
                    sudo apt-get update -y
                    sudo apt-get install fontconfig openjdk-17-jre -y
                    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian/jenkins.io-2023.key
                    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
                    sudo apt-get update -y
                    sudo apt-get install jenkins -y
                    sudo systemctl enable jenkins
                    sudo systemctl start jenkins
                    EOF
  tags                   = {
    Name = "jenkins"
  }
}

resource "aws_instance" "aws_instance_registry" {
  ami                    = "ami-0e83be366243f524a"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet.id
  key_name               = "test-key"
  vpc_security_group_ids = [aws_security_group.security_group.id]
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("test-key.pem")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install docker.io -y",
      "sudo docker run -d -p 5000:5000 --restart=always --name registry registry",
    ]
  }
  tags = {
    Name = "registry"
  }
}

resource "aws_instance" "aws_instance_sonarqube" {
  ami                    = "ami-0e83be366243f524a"
  instance_type          = "t3a.xlarge"
  subnet_id              = aws_subnet.subnet.id
  key_name               = "test-key"
  vpc_security_group_ids = [aws_security_group.security_group.id]
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("test-key.pem")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install --fix-missing",
      "sudo apt-get install default-jre docker.io  -y",
      "sudo docker run -d --name sonarqube -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true -p 9000:9000 sonarqube",
    ]
  }
  tags = {
    Name = "sonarqube"
  }
}

resource "aws_instance" "aws_instance_kubernetes" {
  ami                    = "ami-0e83be366243f524a"
  instance_type          = "t3a.small"
  subnet_id              = aws_subnet.subnet.id
  key_name               = "test-key"
  vpc_security_group_ids = [aws_security_group.security_group_all_ports.id]
  user_data              = <<-EOF
                    #!/bin/bash
                    sudo apt-get update -y
                    sudo snap install microk8s --classic
                    sudo microk8s status --wait-ready
                    sudo microk8s enable dashboard dns ingress
                    sudo snap alias microk8s.kubectl kubectl
                    EOF
  tags                   = {
    Name = "kubernetes"
  }
}