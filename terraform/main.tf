data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_security_group" "cubic" {
  name   = "cubic"
  vpc_id = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = [80, 443]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = var.ssh_public_key == "" ? [] : [22]
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_allowed_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "cubic" {
  count      = var.ssh_public_key == "" ? 0 : 1
  key_name   = "cubic"
  public_key = var.ssh_public_key
}

resource "aws_instance" "cubic" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.ssh_public_key == "" ? null : aws_key_pair.cubic[0].key_name
  vpc_security_group_ids = [aws_security_group.cubic.id]

  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    env_b64    = filebase64(var.env_file)
    domain     = var.domain
    infra_repo = var.infra_repo
    infra_ref  = var.infra_ref
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  # The database lives on this disk: never replace the instance just because
  # a newer AMI was published or the bootstrap script changed.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name = "cubic"
  }
}

resource "aws_eip" "cubic" {
  instance = aws_instance.cubic.id
  domain   = "vpc"
}
