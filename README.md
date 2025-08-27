# CloudLaunch — Semester Assessment

## Overview
Hi, I am Gyunom maigida. This repo documents my deployment of **CloudLaunch** using AWS core services.  
Tasks covered:
- **Task 1:** Static website on S3 with strict IAM-scoped access.
- **Task 2:** VPC network layout (no compute/NAT).

---

## Task 1 — Static Website + IAM

### Buckets
- `cloudlaunch-site-bucket-gm` — static website hosting (public read).
- `cloudlaunch-private-bucket-gm` — private storage (IAM user can Get/Put, no Delete).
- `cloudlaunch-visible-only-bucket-gm` — visible in bucket list only (no object access).

### Website Link
- **S3 Website Endpoint:** `http://cloudlaunch-site-bucket-gm.s3-website-eu-west-1.amazonaws.com`  
- **(Bonus) CloudFront URL:** `https://dppqw5nuul7rz.cloudfront.net` 

### IAM User and Policy
- User: `cloudlaunch-user` (password is provided)
- Attached policy (`cloudlaunch-access-policy`) excerpt:

**IAM Policy (`cloudlaunch-access-policy`)**
~~~json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "AllowS3ConsoleBucketList", "Effect": "Allow", "Action": ["s3:ListAllMyBuckets"], "Resource": "*" },
    {
      "Sid": "AllowListThreeBuckets",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::cloudlaunch-site-bucket-gm",
        "arn:aws:s3:::cloudlaunch-private-bucket-gm",
        "arn:aws:s3:::cloudlaunch-visible-only-bucket-gm"
      ]
    },
    {
      "Sid": "AllowReadSiteObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::cloudlaunch-site-bucket-gm/*"
    },
    {
      "Sid": "AllowReadWritePrivateObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::cloudlaunch-private-bucket-gm/*"
    },
    {
      "Sid": "DenyAccessVisibleOnlyObjects",
      "Effect": "Deny",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::cloudlaunch-visible-only-bucket-gm/*"
    },
    {
      "Sid": "DenyDeleteEverywhere",
      "Effect": "Deny",
      "Action": ["s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::cloudlaunch-site-bucket-gm/*",
        "arn:aws:s3:::cloudlaunch-private-bucket-gm/*",
        "arn:aws:s3:::cloudlaunch-visible-only-bucket-gm/*"
      ]
    },
    {
      "Sid": "AllowVPCReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcEndpoints",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ConsoleSupportDescribes",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeRegions",
        "ec2:DescribeNetworkAcls",
        "ec2:DescribeDhcpOptions"
      ],
      "Resource": "*"
    }
  ]
}
~~~

**S3 Bucket Policy (CloudFront OAC) for the site bucket**
~~~json
{
  "Version": "2008-10-17",
  "Id": "PolicyForCloudFrontPrivateContent",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cloudlaunch-site-bucket-gm/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::193083278892:distribution/E37SK0A4RJUQ1M"
        }
      }
    }
  ]
}
~~~

**What the user can do:**
- List all three buckets.
- Get from site + private buckets.
- Put only to private bucket.
- No deletes anywhere.
- No object access to visible-only bucket.
- Read-only (Describe) over VPC resources.

---

## Task 2 — VPC Design

- **VPC:** `cloudlaunch-vpc` — `10.0.0.0/16`

### Subnets
- `Public-Subnet` — `10.0.1.0/24`
- `Application-Subnet` — `10.0.2.0/24` (private)
- `Databse-Subnet` — `10.0.3.0/28` (private)

### Internet Gateway
- `cloudlaunch-igw` (attached to VPC)

### Route Tables
- `cloudlaunch-public-rt` → `0.0.0.0/0` via IGW → associated to public subnet.
- `cloudlaunch-app-rt` → no internet route → associated to app subnet.
- `cloudlaunch-db-rt` → no internet route → associated to db subnet.

### Security Groups
- `cloudlaunch-app-sg`: inbound **HTTP 80** from `10.0.0.0/16`.
- `cloudlaunch-db-sg`: inbound **MySQL 3306** from **cloudlaunch-app-sg**.

---

## Console Sign-in (for graders)

- **Account alias/ID:** `193083278892`
- **User:** `cloudlaunch-user`
- **Console sign-in URL:** `https://eu-west-1.console.aws.amazon.com`
- **Temp password:** `Cloudlaunch1?` → **Password reset is required at first login.**

> This user is tightly scoped and cannot delete objects or access private contents beyond what’s defined above.
