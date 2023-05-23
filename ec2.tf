data "aws_ami" "latest_amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

# terrascan-ignore AC_AWS_0319
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["82.16.66.135/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  monitoring = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 10
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "example-instance"
  }
}
