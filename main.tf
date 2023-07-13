# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_key_pair" "key-pair" {
  key_name                       = var.key_pair_name
  public_key                     = tls_private_key.rsa.public_key_openssh
}

resource "tls_private_key" "rsa" {
  algorithm                      = "RSA"
  rsa_bits                       = 4096
}

resource "local_file" "tf-key" {
  content                        = tls_private_key.rsa.private_key_pem
  filename                       = var.key_pair_name
}

# SSM Role

resource "aws_iam_instance_profile" "iam_instance_profile" {
  name       = "${var.EC2InstanceProfile}-profile"
  role       = aws_iam_role.iam_role_tool_server.name
}

resource "aws_iam_role" "iam_role_tool_server" {
  name       = var.EC2InstanceProfile

 assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2ssmcwlogsaccess_iam_policy" {
  name       = "ec2ssmcwlogsaccess_iam_policy"
  policy     = "${file("ec2ssmcwlogsaccess.json")}"
  role       = aws_iam_role.iam_role_tool_server.id
}

resource "aws_iam_role_policy" "ec2ssmaccess_iam_policy" {
  name       = "ec2ssmaccess_iam_policy"
  policy     = "${file("ec2ssmaccess.json")}"
  role       = aws_iam_role.iam_role_tool_server.id
}

resource "aws_iam_role_policy_attachment" "amazonssmmanagedinstancecore-attach" {
  role = aws_iam_role.iam_role_tool_server.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "amazonssmmanagedcwagent-attach" {
  role = aws_iam_role.iam_role_tool_server.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "amazonselasticfilesystemutils-attach" {
  role = aws_iam_role.iam_role_tool_server.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemsUtils"
}

resource "aws_db_subnet_group" "RDSSubnetGroup" {
  name        = "subnetgroup"
  description = "Private subnets for RDS"
  subnet_ids  = [
    var.PrivateSubnetA,
    var.PrivateSubnetB
  ]
}

resource "aws_s3_bucket" "script_bucket" {
  bucket = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning_bucket" {
  bucket = aws_s3_bucket.script_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object" "script_object" {
  bucket = aws_s3_bucket.script_bucket.id
  key    = "script.sh"
  content = <<EOF
#!/bin/bash -xe
# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

sudo apt-get install awscli -y

export VER="10.0.5"
export ENDPOINT="${aws_db_instance.RDSInstance.endpoint}"
export USER="user"
export PWD="$(aws ssm get-parameter --name /path/to/password --with-decryption --query "Parameter.Value" --output text --region ${var.region})"

sudo apt-get -y update
sudo apt-get -y install apache2 mariadb-client wget libapache2-mod-perl2 libapache-dbi-perl libapache-db-perl php7.4 libapache2-mod-php7.4 php7.4-common php7.4-sqlite3 php7.4-mysql php7.4-gmp php-cas php-pear php7.4-curl php7.4-mbstring php7.4-gd php7.4-cli php7.4-xml php7.4-zip php7.4-soap php7.4-json php-pclzip composer php7.4-intl php7.4-apcu php7.4-memcache php7.4-ldap php7.4-tidy php7.4-xmlrpc php7.4-pspell php7.4-json php7.4-xml php7.4-gd php7.4-bz2
sudo systemctl enable apache2
sudo mysql -h $ENDPOINT -P 3306 -u $USER -p$PWD -e "CREATE $USER 'glpi'@'localhost' IDENTIFIED BY 'password';"
sudo mysql -h $ENDPOINT -P 3306 -u $USER -p$PWD -e "GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';"
sudo mysql -h $ENDPOINT -P 3306 -u $USER -p$PWD -e "flush privileges;"
sudo mysql -h $ENDPOINT -P 3306 -u $USER -p$PWD -e "exit"

sudo bash -c 'cat >> /etc/php/7.4/apache2/php.ini' << EOL
memory_limit = 512M
post_max_size = 100M
upload_max_filesize = 100M
max_execution_time = 360
date.timezone = Europe/Paris
EOL

sudo wget https://github.com/glpi-project/glpi/releases/download/$VER/glpi-$VER.tgz
sudo tar xvf glpi-$VER.tgz
sudo mv glpi /var/www/html/
sudo chown -R www-data:www-data /var/www/html/glpi

sudo bash -c 'cat >> /etc/apache2/apache2.conf' << EOL
<Directory /var/www/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
</Directory>
EOL

sudo systemctl restart apache2
EOF
}


locals {
  userdata = templatefile("userdata.sh", {
    ssm_cloudwatch_config = aws_ssm_parameter.log_glpi.name
  })
}

resource "aws_instance" "EC2Instance" {

  depends_on = [
    aws_db_instance.RDSInstance,
    aws_kms_key.encryption_key
  ]
  
  instance_type          = var.EC2InstanceType
  iam_instance_profile   = aws_iam_instance_profile.iam_instance_profile.id
  subnet_id              = var.PrivateSubnetA
  ami                    = var.AMI
  key_name               = var.key_pair_name
  user_data              = local.userdata

  security_groups = [
    aws_security_group.EC2InstanceSecurityGroup.id,
  ]

  tags = {
    Name = "GLPI-EC2"
  }
}

resource "aws_ssm_parameter" "log_glpi" {
  description = "GLPI log"
  name        = "/cloudwatch/glpi"
  type        = "SecureString"
  value       = "redacted"
}

resource "aws_kms_key" "encryption_key" {
  description = "Encryption key for GLPI password"
}

resource "aws_kms_alias" "encryption_key_alias" {
  name          = "alias/glpi-encryption-key"
  target_key_id = aws_kms_key.encryption_key.key_id
}

resource "aws_ssm_parameter" "password_parameter" {
  name        = "/path/to/password"
  description = "Encrypted GLPI password"
  type        = "SecureString"
  value       = var.encrypted_password
  key_id      = aws_kms_key.encryption_key.key_id
}

resource "aws_lb" "LoadBalancer" {
  depends_on = [
    aws_instance.EC2Instance
  ]

  name                = "my-load-balancer"
  internal            = false
  load_balancer_type  = "application"
  security_groups     = [
    aws_security_group.LoadBalancerSecurityGroup.id
  ]
  subnets             = [
    var.PublicSubnetA,
    var.PublicSubnetB
  ]
}

resource "aws_lb_target_group" "TargetGroup" {
  depends_on = [
    aws_instance.EC2Instance
  ]

  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.VPC
  target_type = "instance"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    path                = "/"
    matcher             = "200-299"
    timeout             = 5
  }
}

resource "aws_lb_listener" "Listener" {
  depends_on = [
    aws_instance.EC2Instance
  ]

  load_balancer_arn = aws_lb.LoadBalancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.TargetGroup.arn
  }
}


resource "aws_lb_target_group_attachment" "EC2InstanceAttachment" {
  depends_on = [
    aws_instance.EC2Instance
  ]

  target_group_arn = aws_lb_target_group.TargetGroup.arn
  target_id        = aws_instance.EC2Instance.id
  port             = 80
}


resource "aws_db_instance" "RDSInstance" {
  engine                    = "MariaDB"
  db_name                   = "glpi"
  identifier                = "glpi-db"
  vpc_security_group_ids    = [
    aws_security_group.EC2InstanceSecurityGroup.id
  ]

  instance_class            = "db.m5.large"
  allocated_storage         = 20
  username                  = "user"
  password                  = var.encrypted_password
  storage_type              = "gp2"
  multi_az                  = var.multi_az
  db_subnet_group_name      = aws_db_subnet_group.RDSSubnetGroup.id
  skip_final_snapshot  = true
}

resource "aws_security_group" "EC2InstanceSecurityGroup" {
  description = "Allow inbound traffic from ALB"
  vpc_id      = var.VPC

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    description      = "All"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "InstanceSecurityGroupIngress" {
  depends_on = [aws_security_group.EC2InstanceSecurityGroup]
  type              = "ingress"

  security_group_id        = aws_security_group.EC2InstanceSecurityGroup.id
  source_security_group_id = aws_security_group.EC2InstanceSecurityGroup.id
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 3306
}

resource "aws_security_group" "LoadBalancerSecurityGroup" {
  description = "Allow inbound traffic from the internet"
  vpc_id      = var.VPC

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "All"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "bucket_policy" {
  name        = var.policy_name
  description = "Policy giving full access to the S3 bucket"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::${var.bucket_name}/*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "bucket_policy_attachment" {
  role       = var.EC2InstanceProfile
  policy_arn = aws_iam_policy.bucket_policy.arn
}