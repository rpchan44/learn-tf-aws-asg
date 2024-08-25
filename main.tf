provider "aws" {
  region = "ap-southeast-1"

  default_tags {
    tags = {
      hashicorp-learn = "Frontend"
    }
  }
}

# VPC
resource "aws_vpc" "devel" {
  cidr_block = "10.0.0.0/23" # 512 IPs 
  tags = {
    Name = "devel-vpc"
  }
}

# Creating 1st public subnet 
resource "aws_subnet" "dev_subnet_1" {
  vpc_id                  = aws_vpc.devel.id
  cidr_block              = "10.0.0.0/27" #32 IPs
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true
}
# Creating 2nd public subnet 
resource "aws_subnet" "dev_subnet_1a" {
  vpc_id                  = aws_vpc.devel.id
  cidr_block              = "10.0.0.32/27" #32 IPs
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = true
}
# Creating 1st private subnet 
resource "aws_subnet" "dev_subnet_2" {
  vpc_id                  = aws_vpc.devel.id
  cidr_block              = "10.0.1.0/27" #32 IPs
  map_public_ip_on_launch = false
  availability_zone       = "ap-southeast-1b"
}

# Internet Gateway
resource "aws_internet_gateway" "dev_gw" {
  vpc_id = aws_vpc.devel.id
}

# route table for public subnet - connecting to Internet gateway
resource "aws_route_table" "dev_rt_public" {
  vpc_id = aws_vpc.devel.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_gw.id
  }
}

# associate the route table with public subnet 1
resource "aws_route_table_association" "dev_rta1" {
  subnet_id      = aws_subnet.dev_subnet_1.id
  route_table_id = aws_route_table.dev_rt_public.id
}
# associate the route table with public subnet 2
resource "aws_route_table_association" "dev_rta2" {
  subnet_id      = aws_subnet.dev_subnet_1a.id
  route_table_id = aws_route_table.dev_rt_public.id
}

# Elastic IP for NAT gateway
resource "aws_eip" "dev_eip" {
  depends_on = [aws_internet_gateway.dev_gw]
  domain     = "vpc"
  tags = {
    Name = "ec2 ip for NAT"
  }
}

# NAT gateway for private subnets 
# (for the private subnet to access internet - eg. ec2 instances downloading softwares from internet)
resource "aws_nat_gateway" "dev_nat_for_private_subnet" {
  allocation_id = aws_eip.dev_eip.id
  subnet_id     = aws_subnet.dev_subnet_1.id # nat should be in public subnet

  tags = {
    Name = "NAT for private subnet"
  }

  depends_on = [aws_internet_gateway.dev_gw]
}

# route table - connecting to NAT
resource "aws_route_table" "dev_rt_private" {
  vpc_id = aws_vpc.devel.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dev_nat_for_private_subnet.id
  }
}

# associate the route table with private subnet
resource "aws_route_table_association" "dev_rta3" {
  subnet_id      = aws_subnet.dev_subnet_2.id
  route_table_id = aws_route_table.dev_rt_private.id
}

resource "aws_lb" "dev_lb" {
  name                             = "apps01-devel-lb-asg"
  internal                         = false
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.dev_sg_for_elb.id]
  subnets                          = [aws_subnet.dev_subnet_1.id, aws_subnet.dev_subnet_1a.id]
  depends_on                       = [aws_internet_gateway.dev_gw]
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true
  idle_timeout                     = 60
  drop_invalid_header_fields       = true
  enable_http2                     = true
}

resource "aws_lb_target_group" "dev_alb_tg" {
  name     = "dev-tf-lb-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.devel.id
}

resource "aws_lb_listener" "dev_front_end" {
  load_balancer_arn = aws_lb.dev_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dev_alb_tg.arn
  }
}

# ASG with Launch template
resource "aws_launch_template" "dev_ec2_launch_templ" {
  name_prefix   = "dev_ec2_launch_templ"
  image_id      = "ami-0a6b545f62129c495" # To note: AMI is specific for each region
  instance_type = "t2.micro"
  user_data     = filebase64("user_data.sh")

  network_interfaces {
    associate_public_ip_address = false
    subnet_id                   = aws_subnet.dev_subnet_2.id
    security_groups             = [aws_security_group.dev_sg_for_ec2.id]
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "devel-instance" # Name for the EC2 instances
    }
  }
}

resource "aws_security_group" "dev_sg_for_elb" {
  name   = "devel-sg_for_elb"
  vpc_id = aws_vpc.devel.id

  ingress {
    description      = "Allow http request from anywhere"
    protocol         = "tcp"
    from_port        = 80
    to_port          = 80
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow https request from anywhere"
    protocol         = "tcp"
    from_port        = 443
    to_port          = 443
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "dev_sg_for_ec2" {
  name   = "devel-sg_for_ec2"
  vpc_id = aws_vpc.devel.id

  ingress {
    description     = "Allow http request from Load Balancer"
    protocol        = "tcp"
    from_port       = 80 # range of
    to_port         = 80 # port numbers
    security_groups = [aws_security_group.dev_sg_for_elb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_autoscaling_group" "dev_asg" {
  # no of instances
  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  # Connect to the target group
  target_group_arns = [aws_lb_target_group.dev_alb_tg.arn]

  vpc_zone_identifier = [ # Creating EC2 instances in private subnet
    aws_subnet.dev_subnet_2.id
  ]

  launch_template {
    id      = aws_launch_template.dev_ec2_launch_templ.id
    version = "$Latest"
  }
}

resource "aws_route53_zone" "private" {
  name = "mentee-ron.local"
  vpc {
    vpc_id = aws_vpc.devel.id
  }
  depends_on = [aws_lb.dev_lb]
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.private.id
  name    = "lb01.mentee-ron.local"
  type    = "A"
  alias {
    name                   = aws_lb.dev_lb.dns_name
    zone_id                = aws_lb.dev_lb.zone_id
    evaluate_target_health = true
  }
}
