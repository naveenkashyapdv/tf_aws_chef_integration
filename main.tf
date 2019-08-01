provider "aws" {
    region = "${var.region}"
}

data "aws_availability_zones" "available" {}


## VPC
resource "aws_vpc" "main" {
  cidr_block           = "${var.vpc_cidr}"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
 
  tags {
    Name        = "${var.name}-${var.environment}"
    Environment = "${var.environment}"
  }
}
 
## Internet GW
resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name        = "${var.name}-${var.environment}"
    Environment = "${var.environment}"
  }
}
 
## Subnet
resource "aws_subnet" "external" {
  count                   = 2
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "${cidrsubnet(var.vpc_cidr, 8, count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  map_public_ip_on_launch = true
 
  tags {
    Name = "${var.name}-${var.environment}-${format("external-%02d", count.index+1)}"
  }
}
 
## Route Table
resource "aws_route_table" "external" {
  count = 1
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.name}-${var.environment}-${format("external-%02d", count.index+1)}"
  }
}
 
resource "aws_route" "external" {
  route_table_id         = "${aws_route_table.external.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.main.id}"
}

resource "aws_route_table_association" "external" {
  count          = 2
  subnet_id      = "${element(aws_subnet.external.*.id, count.index)}"
  route_table_id = "${aws_route_table.external.id}"
}

## Security Group
resource "aws_security_group" "external_ssh" {
  name        = "${format("%s-%s-external-ssh", var.name, var.environment)}"
  description = "Allows SSH connections"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "${format("%s external ssh", var.name)}"
    Environment = "${var.environment}"
  }
}

resource "aws_security_group" "demo_server" {
  name        = "${format("%s-%s-demo_server", var.name, var.environment)}"
  description = "Allows HTTP connections to Web Server"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "${format("%s demo_server", var.name)}"
    Environment = "${var.environment}"
  }
}

## IAM role
data "aws_iam_policy_document" "assume_role_ec2" {
    statement {
        effect     = "Allow"
        actions    = ["sts:AssumeRole"]
        principals = {
            type        = "Service"
            identifiers = ["ec2.amazonaws.com"]
        }
    }
}

data "aws_iam_policy_document" "demo_server" {
    statement {
        effect = "Allow"
        actions = [
            "autoscaling:Describe*",
            "cloudwatch:*",
            "logs:*",
            "sns:*",
        ]

        resources = [
            "*",
        ]
    }
}

resource "aws_iam_role" "demo_server" {
    name                          = "${var.name}-demo_server-role-${var.environment}"
    assume_role_policy            = "${data.aws_iam_policy_document.assume_role_ec2.json}"
}

resource "aws_iam_role_policy" "demo_server" {
    name                          = "${var.name}-demo_server-policy-${var.environment}"
    role                          = "${aws_iam_role.demo_server.id}"
    policy                        = "${data.aws_iam_policy_document.demo_server.json}"
}

resource "aws_iam_instance_profile" "demo_server" {
    name                          = "${var.name}-demo_server-instance-profile-${var.environment}"
    roles                         = ["${aws_iam_role.demo_server.name}"]
}

## EC2 Instance
resource "aws_instance" "demo_server" {
    count                         = 1
    ami                           = "${var.ami_id}"
    instance_type                 = "t2.micro"
    key_name = "${var.ssh_key_name}"
    vpc_security_group_ids = [
        "${aws_security_group.external_ssh.id}",
        "${aws_security_group.demo_server.id}",
    ]
    subnet_id                     = "${element(aws_subnet.external.*.id, count.index)}"
    associate_public_ip_address   = true
    root_block_device = {
        volume_type               = "gp2"
        volume_size               = "30"
    }
    iam_instance_profile          = "${aws_iam_instance_profile.demo_server.name}"
    monitoring                    = false
    disable_api_termination       = false
    tags {
        Name                      = "${var.name}-${format("demo_server-%02d", count.index+1)}"
        Environment               = "${var.environment}"
    }
    provisioner "chef"  {
        connection {
            host                  = "${self.public_ip}"
            type                  = "ssh"
            user                  = "ec2-user"
            private_key           = "${file(var.ssh_key_file)}"
        }
        environment               = "_default"
        run_list                  = "${var.chef_runlist}"
        node_name                 = "${var.name}-${format("demo_server-%02d", count.index+1)}"
        server_url                = "${var.chef_server_url}"
        recreate_client           = true
        user_name                 = "${var.chef_server_user_name}"
        user_key                  = "${file(var.chef_server_user_key)}"
        fetch_chef_certificates   = true
        version                   = "${var.chef_version}"
    }
}

