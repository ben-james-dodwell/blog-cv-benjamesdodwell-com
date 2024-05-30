# Create Key Management Service Customer Managed Key for encryption of blog resources
resource "aws_kms_key" "blog" {
  description             = "blog"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
  {
    "Version": "2012-10-17",
    "Id": "default",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${var.aws_account}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${var.aws_account}:user/terraform"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${var.aws_account}:role/GitHubActionsTerraformRole" 
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "logs.${var.region}.amazonaws.com" 
        },
        "Action": [
            "kms:Encrypt*",
            "kms:Decrypt*",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:Describe*"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "delivery.logs.amazonaws.com"
        },
        "Action": "kms:GenerateDataKey*",
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "cloudfront.amazonaws.com"
        },
        "Action": "kms:Decrypt*",
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "AWS:SourceArn": "${aws_cloudfront_distribution.blog.arn}"
          }
        }
      }
    ]
  }
POLICY
}

# Create S3 bucket
resource "aws_s3_bucket" "blog" {
  #checkov:skip=CKV_AWS_144:Cross-region replication not required for frontend bucket.
  #checkov:skip=CKV_AWS_18:Access logging not required for frontend bucket.
  #checkov:skip=CKV2_AWS_62:Event notifications not required for frontend bucket.
  #checkov:skip=CKV2_AWS_61:Lifecycle configuration not required for frontend bucket.

  bucket = var.BLOG_BUCKET

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "blog_public_access_block" {
  bucket = aws_s3_bucket.blog.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "blog_versioning" {
  bucket = aws_s3_bucket.blog.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "blog_encryption" {
  bucket = aws_s3_bucket.blog.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.blog.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

data "aws_iam_policy_document" "cloudfront_blog_access" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.blog.arn}/*"
    ]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "AWS:SourceArn"
      values   = ["${aws_cloudfront_distribution.blog.arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_blog_access" {
  bucket = aws_s3_bucket.blog.id
  policy = data.aws_iam_policy_document.cloudfront_blog_access.json
}

data "aws_s3_bucket" "logging" {
  bucket = var.LOGGING_BUCKET
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "blog" {
  #checkov:skip=CKV_AWS_310:Origin failover not required for frontend CloudFront distribution.
  #checkov:skip=CKV_AWS_68:WAF not required for frontend CloudFront distribution.
  #checkov:skip=CKV2_AWS_47:WAF (AMR for Log4j) not required for frontend CloudFront distribution.
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  aliases             = ["blog.cv.benjamesdodwell.com"]

  origin {
    domain_name              = aws_s3_bucket.blog.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.blog.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.blog.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = aws_s3_bucket.blog.bucket_regional_domain_name
    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = 0
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.blog_security_headers.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.blog.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  logging_config {
    include_cookies = false
    bucket          = data.aws_s3_bucket.logging.bucket_regional_domain_name
    prefix          = "blog"
  }
}

resource "aws_cloudfront_origin_access_control" "blog" {
  name                              = "blog"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "blog_security_headers" {
  name = "blog-security-headers-policy"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
  }
}

# CloudFront requires certificate in us-east-1 region
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# Request certificate from ACM to be used with CloudFront
resource "aws_acm_certificate" "blog" {
  provider          = aws.virginia
  domain_name       = "blog.cv.benjamesdodwell.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "cv_benjamesdodwell_com" {
  name         = "cv.benjamesdodwell.com."
  private_zone = false
}

# Create DNS records for validation of ACM request
resource "aws_route53_record" "blog_validation" {
  for_each = {
    for dvo in aws_acm_certificate.blog.domain_validation_options : dvo.domain_name => {
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
resource "aws_acm_certificate_validation" "blog_validated" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.blog.arn
  validation_record_fqdns = [for record in aws_route53_record.blog_validation : record.fqdn]
}

# Create DNS record
resource "aws_route53_record" "blog_cv_benjamesdodwell_com" {
  name    = "blog.cv.benjamesdodwell.com"
  type    = "A"
  zone_id = data.aws_route53_zone.cv_benjamesdodwell_com.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.blog.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
  }
}

