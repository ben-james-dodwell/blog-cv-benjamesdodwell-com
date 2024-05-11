output "cf_id" {
  description = "ID of CloudFront Distribution"
  value       = aws_cloudfront_distribution.blog.id
}
