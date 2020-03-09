provider "aws" {
  region = "us-west-2"
}


# Create Redis Cluster 
resource "aws_elasticache_cluster" "results" {
  cluster_id           = "results-cache"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379
  apply_immediately    = true
  security_group_ids   = ["${aws_security_group.allow_redis.id}"]
  subnet_group_name    = "${aws_elasticache_subnet_group.redis.name}"

}
#  Add cluster to VPC Subnet
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-lambda-subnet"
  subnet_ids = ["${aws_subnet.private.id}"]
  
}
# Create VPC
resource "aws_vpc" "redis" {

  cidr_block = "10.66.0.0/16"
    tags = {
    Name = "Elasticache VPC"
  }
}
#Update default subnet to include internet gateway route





resource "aws_route" "default" {
  route_table_id            = "${aws_vpc.redis.default_route_table_id}"
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.gw.id}"
}



# Add internet access to the VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.redis.id}"

  tags = {
    Name = "Lambda Internet Gateway"
  }
}
resource "aws_subnet" "private" {
  vpc_id     = "${aws_vpc.redis.id}"
  cidr_block = "10.66.1.0/24"
  
 map_public_ip_on_launch = false
 

  tags = {
    Name = "Private-Lambda"
  }
}

resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.redis.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.gw.id}"
  }
  tags = {
    Name = "Private-Lambda"
  }
}

# Associate NAT route with lambda subnet
resource "aws_route_table_association" "private" {
  subnet_id      = "${aws_subnet.private.id}"
  route_table_id = "${aws_route_table.private.id}"
}


resource "aws_subnet" "public" {
  vpc_id     = "${aws_vpc.redis.id}"
  cidr_block = "10.66.2.0/24"
  
 map_public_ip_on_launch = false
 

  tags = {
    Name = "Public-Internet"
  }
}


# Create route to internet
resource "aws_route_table" "internet" {
  vpc_id = "${aws_vpc.redis.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }
  tags = {
    Name = "Public-Internet"
  }
}
# Associate internet route with lambda subnet
resource "aws_route_table_association" "public" {
  subnet_id      = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.internet.id}"
}



# Define firewall rules for VPC
resource "aws_security_group" "allow_redis" {
  name        = "allow_redis"
  description = "Allow redis inbound traffic"
  vpc_id      = "${aws_vpc.redis.id}"

  ingress {
    # TLS (change to whatever ports you need)
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["10.66.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create NAT gateway for default subnet
resource "aws_nat_gateway" "gw" {
  subnet_id ="${aws_subnet.public.id}"
  allocation_id = "${aws_eip.LambdaPublic.id}"
  tags = {
    Name = "Redis NAT Gateway"
  }
}
# Create public IP for use with lambda
resource "aws_eip" "LambdaPublic" {
  vpc = true
  
}

resource "aws_lambda_function" "lambda_function" {
  filename      = "lambda.zip"
  function_name = "checkAbuseIPDB"
  role          = "${aws_iam_role.iam_for_lambda.arn}"
  handler       = "Reputation-Service"

  runtime     = "go1.x"
  timeout     = "10"
  memory_size = 128
  publish     = true

  vpc_config {
    subnet_ids         = ["${aws_subnet.private.id}"]
    security_group_ids = ["${aws_security_group.allow_redis.id}"]
  }

  environment {
    variables = {
      "IPADDRESS"     = "1.1.1.1"
      "REDIS_CLUSTER" = "${aws_elasticache_cluster.results.cache_nodes.0.address}"
      "REDIS_DB" = "0"
    }
  }
}


resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "vpc_access" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeSubnets",
            "ec2:DescribeVpcs",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.vpc_access.arn}"
}

