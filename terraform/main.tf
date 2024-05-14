# Create S3 bucket
resource "aws_s3_bucket" "blog" {
  bucket = var.BLOG_BUCKET
}

resource "aws_s3_bucket_website_configuration" "blog" {
  bucket = aws_s3_bucket.blog.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.blog.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_access" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.blog.arn,
      "${aws_s3_bucket.blog.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "public_access" {
  bucket = aws_s3_bucket.blog.id
  policy = data.aws_iam_policy_document.public_access.json

  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

# Create CloudFront distribution
resource "aws_cloudfront_distribution" "blog" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.blog.website_endpoint
    origin_id   = aws_s3_bucket_website_configuration.blog.website_endpoint

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

  aliases = ["blog.cv.benjamesdodwell.com"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket_website_configuration.blog.website_endpoint

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
    acm_certificate_arn      = aws_acm_certificate.blog.arn
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
resource "aws_acm_certificate" "blog" {
  provider          = aws.virginia
  domain_name       = "blog.cv.benjamesdodwell.com"
  validation_method = "DNS"
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

