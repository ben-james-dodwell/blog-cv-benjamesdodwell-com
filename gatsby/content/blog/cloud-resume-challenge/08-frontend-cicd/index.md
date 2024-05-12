---
title: "IaC and CI/CD for Frontend Infrastructure"
date: "2024-05-08T16:00:00.000Z" 
description: "Using GitHub Actions workflows to deploy the frontend infrastructure with Terraform."
---

Creating the Terraform configuration files and GitHub Actions deployment workflow for the frontend infrastructure is very similar to that of the backend.

I would need to define an S3 bucket configured for static website hosting, with policies to allow public access.

```hcl
# Create S3 bucket
resource "aws_s3_bucket" "cv" {
  bucket = "bucket-name-here"
}

resource "aws_s3_bucket_website_configuration" "cv" {
  bucket = aws_s3_bucket.cv.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.cv.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_access" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.cv.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "public_access" {
  bucket = aws_s3_bucket.cv.id
  policy = data.aws_iam_policy_document.public_access.json

  depends_on = [aws_s3_bucket_public_access_block.public_access]
}
```
I needed to define the `depends_on` relationship between the `aws_s3_bucket_policy` and `aws_s3_bucket_public_access_block` resources, to avoid an error where the policy was being created before the public access had been configured.

The HTML file for my CV would need to be uploaded as an object to the S3 bucket, specifying a MIME file type of "text/html" so that the browser would render as intended rather than attempt to download the file. This could potentially grow over time to include other files such as CSS, JS, or icons and images. The `source_hash` attribute is used to store an MD5 hash of the file contents, allowing Terraform to easily detect changes in state that would require an update to infrastructure.

```hcl
# Upload file to S3 bucket
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.cv.id
  key          = "index.html"
  source       = "../index.html"
  source_hash  = filemd5("../index.html")
  content_type = "text/html"
}
```

In front of the S3 bucket I would define a CloudFront distribution, with a certificate from ACM for HTTPS, and DNS records.

```hcl
# Create CloudFront distribution
resource "aws_cloudfront_distribution" "cv" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.cv.website_endpoint
    origin_id   = aws_s3_bucket_website_configuration.cv.website_endpoint

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols = [
        "SSLv3",
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
  }

  enabled         = true
  is_ipv6_enabled = true

  aliases = ["cv.benjamesdodwell.com"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket_website_configuration.cv.website_endpoint

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cv.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

# CloudFront requires certificate in us-east-1 region
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# Request certificate from ACM to be used with CloudFront
resource "aws_acm_certificate" "cv" {
  provider          = aws.virginia
  domain_name       = "cv.benjamesdodwell.com"
  validation_method = "DNS"
}

data "aws_route53_zone" "cv_benjamesdodwell_com" {
  name         = "cv.benjamesdodwell.com."
  private_zone = false
}

# Create DNS records for validation of ACM request
resource "aws_route53_record" "cv_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cv.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.cv_benjamesdodwell_com.zone_id
}

# Validate ACM request from DNS record
resource "aws_acm_certificate_validation" "cv_validated" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.cv.arn
  validation_record_fqdns = [for record in aws_route53_record.cv_validation : record.fqdn]
}

# Create DNS record
resource "aws_route53_record" "cv_benjamesdodwell_com" {
  name    = "cv.benjamesdodwell.com"
  type    = "A"
  zone_id = data.aws_route53_zone.cv_benjamesdodwell_com.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.cv.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
  }
}
```

With the GitHub Actions workflow, I have only focused on deployment for the time being. It is possible to write [Terraform Tests](https://developer.hashicorp.com/terraform/language/tests) but this is something that I'll handle as an enhancement at a later date.

The majority of the frontend deployment workflow is the same as with the backend.

```yaml
name: 'Deploy'

on:
  workflow_dispatch:
  push:
    branches: [ "master" ]

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    name: 'Deploy'
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        shell: bash

    steps:
    - name: Configure aws credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::############:role/GitHubActionsTerraformRole
        aws-region: eu-west-2

    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.8.2

    - name: Terraform Init
      working-directory: ./terraform
      run: terraform init -input=false

    - name: Terraform Plan
      id: tfplan
      working-directory: ./terraform
      run: terraform plan -out=tfplan -input=false
```

I made changes to the last few steps, as a result of a challenge that I encountered. Currently, there seems to be no native Terraform method of invalidating the CloudFront distribution cache. I would like to do this following each change to infrastructure, which will most frequently be updates to the CV itself, so that the latest version is served as soon as possible.

AWS CLI can handle the task with the [cloudfront create-invalidation](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/cloudfront/create-invalidation.html) command, and this can be run as a GitHub Actions step. The next issue is that this command requires the CloudFront distribution ID, and since I can't hard-code this, I needed a way to extract the value from Terraform. This can be accomplished with [Terraform Output Values](https://developer.hashicorp.com/terraform/language/values/outputs) such as the following:

```hcl
output "cf_id" {
  description = "ID of CloudFront Distribution"
  value       = aws_cloudfront_distribution.cv.id
}
```

Then, using `terraform output` and GitHub Actions [steps context](https://docs.github.com/en/actions/learn-github-actions/contexts#steps-context), I'm able to access the value and provide it to the `aws cloudfront create-invalidation` command. Finally, I wanted to also use the steps to check the output of `terraform plan` so that I would only execute the apply and invalidate steps when there had actually been a successful change to infrastructure.

```yaml
    - name: Terraform Apply
      if: ${{ !contains(steps.tfplan.outputs.stdout, 'Your infrastructure matches the configuration.') }}
      working-directory: ./terraform
      run: terraform apply -auto-approve -input=false tfplan

    - name: Terraform Output
      if: ${{ !contains(steps.tfplan.outputs.stdout, 'Your infrastructure matches the configuration.') }}
      id: tfoutput
      working-directory: ./terraform
      run: terraform output -raw cf_id

    - name: Create CloudFront Cache Invalidation
      if: ${{ !contains(steps.tfplan.outputs.stdout, 'Your infrastructure matches the configuration.') }}
      run: aws cloudfront create-invalidation --distribution-id ${{ steps.tfoutput.outputs.stdout }} --paths '/*'
```

This should now provide me with a complete backend and frontend infrastructure, defined as code, with automated build, testing, and deployment pipelines. 

There will surely be some fixes and improvements that I make over time to this project but the final and most important part of this Cloud Resume Challenge is for me to start writing my CV with HTML and CSS and get it published on the internet.