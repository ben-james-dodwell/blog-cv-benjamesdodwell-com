---
title: "Cloud Resume Challenge: Infrastructure as Code - Backend"
date: "2024-04-25T13:40:00.000Z" 
description: "Using Terraform to configure the DynamoDB table, Lambda function, and API Gateway as code."
---

So far, everything that I've created in AWS has been through the web console. This is a great way to learn which services are available, and how those services can be configured.

I can improve upon this foundation by utilising Infrastructure as Code (IaC) techniques which provide many benefits, such as:
- **Version Control** to help track changes, and revert to previous versions if required.
- **Reusability** which allows me to efficiently recreate and adapt the infrastructure for other projects.
- **Automation** to quickly and consistently deploy changes.

AWS supports IaC with some native tooling such as [CloudFormation](https://aws.amazon.com/cloudformation/) and [SAM](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-specification.html). However, I would like to use the third-party HashiCorp [Terraform](https://developer.hashicorp.com/terraform/install), as I have some familiarity with it and the vSphere provider, and feel that it will offer more flexibility going forwards.

Reading the documentation for the [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) shows that there are several ways for Terraform to authenticate to AWS. While I am working locally and manually with Terraform, I will use the [Shared Configuration and Credentials Files](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#shared-configuration-and-credentials-files) method as configured by [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). This will likely change when I move towards an automated continuous integration and continuous deployment (CI/CD) pipeline.

I wanted to create an account specifically to be used by Terraform so that I could follow the principle of least privilege. There are tools that can help with this endeavour, namely [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-getting-started.html) and [IAM Access Advisor](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_access-advisor.html?icmpid=docs_iam_console), but I found an approach where I gradually add permissions as required while developing my code was easiest.

With Terraform and AWS CLI installed and configured, I was ready to start writing code. There are [tutorials](https://developer.hashicorp.com/terraform/tutorials) available on the HashiCorp website, including those tailored towards certain providers such as AWS. I also discovered a useful collection of curated [.gitignore](https://github.com/github/gitignore/blob/main/Terraform.gitignore) files which I opted to use for Terraform. I'm aware that sensitive information may be stored in certain files and shouldn't be committed to public source code repositories, so having a sensible starting point for exclusions is worthwhile.

At a high level, I knew that I'd need a DynamoDB table, a Lambda function, and an API Gateway.

The DynamoDB table was quite straightforward to define in Terraform:
```hcl
# Create DynamoDB table Visits
resource "aws_dynamodb_table" "visits" {
  name         = "Visits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Id"

  attribute {
    name = "Id"
    type = "S"
  }
}
```

The Lambda function started to become more slightly more complex, as it would need to assume an IAM role for execution with policies that grant it the required permissions, such as access to the previously created DynamoDB table.
```hcl
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "visits_policy" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]

    resources = [
      "${aws_dynamodb_table.visits.arn}"
    ]
  }
}

# Create IAM role for Lambda
resource "aws_iam_role" "LambdaAssumeRole" {
  name               = "LambdaAssumeRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  inline_policy {
    name   = "policy-visits"
    policy = data.aws_iam_policy_document.visits_policy.json
  }
}
```

It also seemed to be necessary to create the Lambda function from an archive of the Python file, rather than directly.
```hcl
data "archive_file" "lambda_incrementvisits_payload" {
  type        = "zip"
  source_file = "${path.module}/lambda/IncrementVisits/IncrementVisits.py"
  output_path = "${path.module}/lambda/IncrementVisits/IncrementVisits_payload.zip"
}

# Create Lambda function from Python archive
resource "aws_lambda_function" "IncrementVisits" {
  filename      = "${path.module}/lambda/IncrementVisits/IncrementVisits_payload.zip"
  function_name = "IncrementVisits"
  role          = aws_iam_role.LambdaAssumeRole.arn
  handler       = "IncrementVisits.lambda_handler"

  source_code_hash = data.archive_file.lambda_incrementvisits_payload.output_base64sha256

  runtime = "python3.12"
}
```

The API Gateway didn't seem too difficult at first, requiring 3 resources for the gateway itself, then an integration with the Lambda function, and a HTTP route. However, at this stage I encountered a challenge in that the gateway is created with randomised subdomain for the Invoke URL and I needed to be able to target it in my website code. The easiest solution to this problem seemed to be the use of a custom domain, so that I could instead target something that I control, such as api.cv.benjamesdodwell.com.

So, I would first need to request a certificate for this domain from ACM:
```hcl
# Request certificate from ACM to be used as Custom Domain with API Gateway
resource "aws_acm_certificate" "api_request" {
  domain_name       = "api.cv.benjamesdodwell.com"
  validation_method = "DNS"
}
```

Then, I would validate the certificate using DNS records:
```hcl
data "aws_route53_zone" "cv_benjamesdodwell_com" {
  name         = "cv.benjamesdodwell.com."
  private_zone = false
}

# Create DNS records for validation of ACM request
resource "aws_route53_record" "api_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_request.domain_validation_options : dvo.domain_name => {
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

# Validate ACM request from DNS records
resource "aws_acm_certificate_validation" "api_validated" {
  certificate_arn         = aws_acm_certificate.api_request.arn
  validation_record_fqdns = [for record in aws_route53_record.api_validation : record.fqdn]
}
```

Once the certificate was validated and issued, I could create it as a custom domain to be used by the API Gateway with an associated DNS alias record:
```hcl
# Create Custom Domain for API Gateway (HTTP)
resource "aws_apigatewayv2_domain_name" "api_cv_benjamesdodwell_com" {
  domain_name = "api.cv.benjamesdodwell.com"
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api_validated.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

# Create DNS (A) record for API Gateway (HTTP) Custom Domain
resource "aws_route53_record" "api_cv_benjamesdodwell_com_alias" {
  name    = aws_apigatewayv2_domain_name.api_cv_benjamesdodwell_com.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.cv_benjamesdodwell_com.id

  alias {
    evaluate_target_health = true
    name                   = aws_apigatewayv2_domain_name.api_cv_benjamesdodwell_com.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api_cv_benjamesdodwell_com.domain_name_configuration[0].hosted_zone_id
  }
}
```

Finally, all the pieces can come together to create the API Gateway with CORS configuration, integration and permission to execute the Lambda function, defining an HTTP route, and mapping to the custom domain.
```hcl
# Create API Gateway (HTTP) with CORS
resource "aws_apigatewayv2_api" "lambda_incrementvisits" {
  name                         = "Lambda-IncrementVisits"
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = true

  cors_configuration {
    allow_origins = ["https://cv.benjamesdodwell.com"]
    allow_methods = ["GET"]
  }
}

# Create Lambda permissions for API Gateway
resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.IncrementVisits.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda_incrementvisits.execution_arn}/*/*"
}

# Create API Gateway (HTTP) Stage
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.lambda_incrementvisits.id
  name        = "prod"
  auto_deploy = true
}

# Create API Gateway (HTTP) mapping to Custom Domain
resource "aws_apigatewayv2_api_mapping" "lambda_incrementvisits_api_cv_benjamesdodwell_com_prod" {
  api_id      = aws_apigatewayv2_api.lambda_incrementvisits.id
  domain_name = aws_apigatewayv2_domain_name.api_cv_benjamesdodwell_com.id
  stage       = aws_apigatewayv2_stage.prod.id
}

# Create API Gateway (HTTP) integration with Lambda function
resource "aws_apigatewayv2_integration" "api_IncrementVisits" {
  api_id = aws_apigatewayv2_api.lambda_incrementvisits.id

  integration_uri    = aws_lambda_function.IncrementVisits.arn
  integration_type   = "AWS_PROXY"
  integration_method = "GET"
}

# Create API Gateway route
resource "aws_apigatewayv2_route" "api-route" {
  api_id = aws_apigatewayv2_api.lambda_incrementvisits.id

  route_key = "GET /IncrementVisits"
  target    = "integrations/${aws_apigatewayv2_integration.api_IncrementVisits.id}"
}
```

With all of that complete, I was able to recreate my original backend infrastructure, even including an improvement of custom domain for the API Gateway.