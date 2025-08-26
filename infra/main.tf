terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

# ---------------- VARIABLES ----------------
variable "aws_region"  { type = string, default = "eu-west-1" }
variable "aws_profile" { type = string, default = "cloudlaunch" }

# Add a short suffix if names are taken globally, e.g. "-ama"
variable "bucket_suffix" { type = string, default = "" }

# Derived bucket names
locals {
  site_bucket     = "cloudlaunch-site-bucket-GM${var.bucket_suffix}"
  private_bucket  = "cloudlaunch-private-bucket-GM${var.bucket_suffix}"
  visible_bucket  = "cloudlaunch-visible-only--GM${var.bucket_suffix}"
  iam_user_name   = "cloudlaunch-user"
}

# ---------------- PROVIDER -----------------
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# --------------- S3: WEBSITE ----------------
resource "aws_s3_bucket" "site" {
  bucket        = local.site_bucket
  force_destroy = false
  tags = { Name = local.site_bucket }
}

resource "aws_s3_bucket_public_access_block" "site_pab" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site_web" {
  bucket = aws_s3_bucket.site.id
  index_document { suffix = "index.html" }
  error_document { key    = "404.html" }
}

# Public read for website objects
data "aws_iam_policy_document" "site_public_read" {
  statement {
    sid     = "PublicReadGetObject"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    principals { type = "AWS"; identifiers = ["*"] }
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
}
resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_public_read.json
}

# ------------- S3: PRIVATE + VISIBLE --------
resource "aws_s3_bucket" "private" {
  bucket        = local.private_bucket
  force_destroy = false
  tags = { Name = local.private_bucket }
}
resource "aws_s3_bucket_public_access_block" "private_pab" {
  bucket                  = aws_s3_bucket.private.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "visible" {
  bucket        = local.visible_bucket
  force_destroy = false
  tags = { Name = local.visible_bucket }
}
resource "aws_s3_bucket_public_access_block" "visible_pab" {
  bucket                  = aws_s3_bucket.visible.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- IAM: GRADER USER ----------
resource "aws_iam_user" "cloud_user" {
  name = local.iam_user_name
}

data "aws_iam_policy_document" "cloud_user_doc" {
  # List all buckets + see the 3 specific buckets
  statement {
    sid     = "ListBucketsAndEachBucket"
    effect  = "Allow"
    actions = ["s3:ListAllMyBuckets", "s3:ListBucket"]
    resources = [
      "*",
      aws_s3_bucket.site.arn,
      aws_s3_bucket.private.arn,
      aws_s3_bucket.visible.arn
    ]
  }

  # Read from site bucket (even though public)
  statement {
    sid     = "ReadSiteObjects"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  # Read/Write (no delete) on private bucket
  statement {
    sid     = "RWNoDeletePrivate"
    effect  = "Allow"
    actions = ["s3:GetObject","s3:PutObject"]
    resources = ["${aws_s3_bucket.private.arn}/*"]
  }

  # Explicitly deny deletes anywhere
  statement {
    sid     = "DenyDeletes"
    effect  = "Deny"
    actions = ["s3:DeleteObject","s3:DeleteObjectVersion"]
    resources = [
      "${aws_s3_bucket.site.arn}/*",
      "${aws_s3_bucket.private.arn}/*",
      "${aws_s3_bucket.visible.arn}/*"
    ]
  }

  # Deny object access in visible-only bucket
  statement {
    sid     = "DenyVisibleBucketObjectAccess"
    effect  = "Deny"
    actions = ["s3:GetObject","s3:PutObject"]
    resources = ["${aws_s3_bucket.visible.arn}/*"]
  }
}

resource "aws_iam_user_policy" "cloud_user_policy" {
  name   = "cloudlaunch-user-policy"
  user   = aws_iam_user.cloud_user.name
  policy = data.aws_iam_policy_document.cloud_user_doc.json
}

# ---------------- VPC LAYOUT ----------------
resource "aws_vpc" "cloud_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "cloudlaunch-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cloud_vpc.id
  tags   = { Name = "cloudlaunch-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.cloud_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  tags = { Name = "cloudlaunch-public-subnet" }
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.cloud_vpc.id
  cidr_block = "10.0.2.0/24"
  tags = { Name = "cloudlaunch-app-subnet" }
}

resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.cloud_vpc.id
  cidr_block = "10.0.3.0/28"
  tags = { Name = "cloudlaunch-db-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cloud_vpc.id
  tags   = { Name = "cloudlaunch-public-rt" }
}
resource "aws_route" "public_inet" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.cloud_vpc.id
  tags   = { Name = "cloudlaunch-app-rt" }
}
resource "aws_route_table_association" "app_assoc" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table" "db_rt" {
  vpc_id = aws_vpc.cloud_vpc.id
  tags   = { Name = "cloudlaunch-db-rt" }
}
resource "aws_route_table_association" "db_assoc" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.db_rt.id
}

resource "aws_security_group" "app_sg" {
  name        = "cloudlaunch-app-sg"
  description = "Allow HTTP within VPC only"
  vpc_id      = aws_vpc.cloud_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.cloud_vpc.cidr_block] # 10.0.0.0/16
  }
  egress  {
    from_port=0 to_port=0 protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
  }
  tags = { Name = "cloudlaunch-app-sg" }
}

resource "aws_security_group" "db_sg" {
  name        = "cloudlaunch-db-sg"
  description = "Allow MySQL from app subnet only"
  vpc_id      = aws_vpc.cloud_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.app.cidr_block] # 10.0.2.0/24
  }
  egress  {
    from_port=0 to_port=0 protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
  }
  tags = { Name = "cloudlaunch-db-sg" }
}

# ---- Add VPC read-only to the grader user's policy
data "aws_iam_policy_document" "cloud_user_doc_with_vpc" {
  source_json = data.aws_iam_policy_document.cloud_user_doc.json
  statement {
    sid     = "VpcReadOnly"
    effect  = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeSecurityGroups"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_user_policy" "cloud_user_policy_final" {
  name   = "cloudlaunch-user-policy-final"
  user   = aws_iam_user.cloud_user.name
  policy = data.aws_iam_policy_document.cloud_user_doc_with_vpc.json
}

# ---------------- CLOUDFRONT (HTTPS) --------
resource "aws_cloudfront_distribution" "site_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudLaunch site CDN"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket_website_configuration.site_web.website_endpoint
    origin_id   = "s3-website-cloudlaunch-site"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"   # CF -> S3 website over HTTP
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-website-cloudlaunch-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET","HEAD"]
    cached_methods         = ["GET","HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "error/404.html"
    error_caching_min_ttl = 300
  }
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "error/404.html"
    error_caching_min_ttl = 300
  }

  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }

  tags = { Name = "cloudlaunch-cloudfront" }
}

# ---------------- OUTPUTS -------------------
output "site_bucket_name"         { value = aws_s3_bucket.site.bucket }
output "site_website_url"         { value = aws_s3_bucket_website_configuration.site_web.website_endpoint }
output "private_bucket_name"      { value = aws_s3_bucket.private.bucket }
output "visible_bucket_name"      { value = aws_s3_bucket.visible.bucket }
output "iam_username"             { value = aws_iam_user.cloud_user.name }
output "vpc_id"                   { value = aws_vpc.cloud_vpc.id }
output "public_subnet_id"         { value = aws_subnet.public.id }
output "app_subnet_id"            { value = aws_subnet.app.id }
output "db_subnet_id"             { value = aws_subnet.db.id }
output "app_sg_id"                { value = aws_security_group.app_sg.id }
output "db_sg_id"                 { value = aws_security_group.db_sg.id }
output "cloudfront_domain_name"   { value = aws_cloudfront_distribution.site_cdn.domain_name }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.site_cdn.id }
