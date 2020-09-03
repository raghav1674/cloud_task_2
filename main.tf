provider "aws"{

  profile="raghav-terraform"
  region="ap-south-1"

}


// creating sg
resource "aws_security_group" "allow_http_ssh_nfs" {
  name        = "allow_http-_ssh_nfs"
  description = "Allow TLS inbound traffic"
  

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }
   ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }
   ingress {
    description = "allow nfs"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_ssh_nfs"
  }
}

// launching ec2 
resource "aws_instance" "webserver" {
  depends_on= [aws_security_group.allow_http_ssh_nfs]
  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name      = "my_vpc_1"
  security_groups = [aws_security_group.allow_http_ssh_nfs.name]
  
  tags = {
    Name = "web-os"
  }
}


// installing softwares

resource "null_resource" "softwares"  {
  depends_on = [aws_instance.webserver]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:\\Users\\Raghav Gupta\\Downloads\\my_vpc_1.pem")
    host     = aws_instance.webserver.public_ip
  }
provisioner "remote-exec" {
    inline = [
    "sudo yum -y install git",
    "sudo git clone https://github.com/aws/efs-utils",
    "sudo yum -y install make",
    
     "sudo mv efs-utils/* /home/ec2-user/",
     "sudo yum -y install rpm-build",
     "sudo make rpm",
     "sudo yum -y install build/amazon-efs-utils*rpm",
      "sudo yum install httpd -y",
      "sudo yum install php -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      
     
    ]
  }
}
// creating  efs

resource "aws_efs_file_system" "efs" {
    depends_on= [aws_security_group.allow_http_ssh_nfs]

  creation_token = "web-efs"

  tags = {
    Name = "web-efs"
  }
}
resource "aws_efs_file_system_policy" "policy" {


  depends_on=[aws_efs_file_system.efs]

  file_system_id = aws_efs_file_system.efs.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "ExamplePolicy01",
    "Statement": [
        {
            "Sid": "ExampleSatement01",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Resource": "${aws_efs_file_system.efs.arn}",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_efs_mount_target" "efsmount" {

  depends_on= [aws_efs_file_system.efs]

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_instance.webserver.subnet_id
  security_groups = [aws_security_group.allow_http_ssh_nfs.id]
}

output "file_system"{


  value= aws_efs_file_system.efs
}


resource "null_resource" "mount-download"  {

  depends_on = [aws_instance.webserver,aws_efs_mount_target.efsmount,null_resource.softwares]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:\\Users\\Raghav Gupta\\Downloads\\my_vpc_1.pem")
    host     = aws_instance.webserver.public_ip
  }
provisioner "remote-exec" {
    inline = [
    
        "sudo mount -t efs ${aws_efs_file_system.efs.id}:/ /var/www/html/",
        "sudo echo  ${aws_efs_file_system.efs.dns_name}:/  /var/www/html/    nfs4      defaults        0  0 >> /etc/fstab",
        "sudo systemctl daemon-reload",
         "sudo rm -f /var/www/html/*",
         "sudo git clone https://github.com/raghav1674/cloud_task2.git /var/www/html/",
         "sudo systemctl restart httpd"
      
     
    ]
  }
}


// creating bucket

resource "aws_s3_bucket" "static-data" {
  bucket = "raghav81"
  acl    = "private"

  tags = {
    Name        = "raghav81"
    Environment = "Dev"
  }
}

// public access block

resource "aws_s3_bucket_public_access_block" "s3-public-block" {
  bucket = aws_s3_bucket.static-data.id

  block_public_acls   = true
  // block_public_policy = true
}
// uploading keyfile

resource "aws_s3_bucket_object" "image" {
  bucket = aws_s3_bucket.static-data.bucket
  key    = "aws_img.png"
  source = "D:\\c_data\\future\\GCP\\cloud_task_2\\aws_img.png"
  content_type="img/png"

}

// creating cloudfront OAI

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
depends_on=[aws_s3_bucket_object.image]
comment = "comments"
}

// updating_the_policy

data "aws_iam_policy_document" "s3_policy" {
statement {
actions   = ["s3:GetObject"]
resources = ["${aws_s3_bucket.static-data.arn}/*"]
principals {
type        = "AWS"
identifiers = [  aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn ]
}
}
}

//adding_the_policy

resource "aws_s3_bucket_policy" "policy" {
depends_on=[aws_s3_bucket_object.image]
bucket = aws_s3_bucket.static-data.id
policy = data.aws_iam_policy_document.s3_policy.json
}

//cloudfront_distribution

locals {
s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
depends_on=[aws_s3_bucket_object.image]
origin {
domain_name = aws_s3_bucket.static-data.bucket_regional_domain_name
origin_id   = local.s3_origin_id
s3_origin_config {
origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
}
}


enabled             = true
is_ipv6_enabled     = true
comment             = "Some comment"
default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}

viewer_protocol_policy = "redirect-to-https"
min_ttl                = 0
default_ttl            = 200
max_ttl                = 36000
}

price_class = "PriceClass_All"
restrictions {
geo_restriction {
restriction_type = "none"
}
}
tags = {
Environment = "dev"
}
viewer_certificate {
cloudfront_default_certificate = true
}
}


output "cloud_domain"{
value=aws_cloudfront_distribution.s3_distribution.domain_name
}

// now update the code .

resource "null_resource" "update_code"{
  depends_on=[aws_cloudfront_distribution.s3_distribution]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:\\Users\\Raghav Gupta\\Downloads\\my_vpc_1.pem")
    host     = aws_instance.webserver.public_ip
  }
provisioner "remote-exec" {
    inline = [
       
      "sudo chmod 777 /var/www/html/*",
      "sudo  echo  \"<img src = https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image.key} >\"  >> /var/www/html/index.html"
     
    ]
  }
}

