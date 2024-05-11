---
title: "Cloud Resume Challenge: Preparing for Continuous Integration and Continuous Deployment"
date: "2024-05-03T16:30:00.000Z" 
description: "Writing Python tests, storing Terraform state remotely, and preparing authentication and authorization for GitHub Actions."
---

The infrastructure is now defined as code, using Terraform, but deployment is still manual. I would like to automate this process with a continuous integration and continuous deployment (CI/CD) pipeline.

**Continuous Integration (CI)** is a software development practice where code changes are frequently merged into a repository, triggering automated builds and tests. This can provide benefits such as earlier detection of integration errors, leading to faster feedback loops for developers. **Continuous Deployment (CD)** then follows as the steps which deploy successfully integrated builds into production environments.

Considering the importance of testing for successful integration, I felt that I'd need to revisit my Lambda function and at least write some basic unit tests. I'm using Boto3 for interacting with AWS, but knew that I'd need a way to mock this functionality so that my tests don't actually impact anything in production, and [Moto](https://docs.getmoto.org/en/latest/index.html) allows for exactly that.

The following test class imports my IncrementVisits module, then uses the `@mock_aws` decorator to wrap each function. Since we aren't actually connecting to our existing AWS infrastructure, we need to create a mocked DynamoDB table to be used by the test. The `test_lambda_handler_success()` function asserts that we receive the  HTTP 200 success code and that the returned body matches what we would expect. The `test_lambda_handler_error()` function asserts that we receive an HTTP 500 error code in a scenario such as where the DynamoDB table does not exist.

```python
from moto import mock_aws
import boto3
import unittest
from IncrementVisits import lambda_handler


class Test_IncrementVisits(unittest.TestCase):

    @mock_aws
    def test_lambda_handler_success(self):
        boto3.client('dynamodb').create_table(
            AttributeDefinitions=[
                {
                    'AttributeName': 'Id',
                    'AttributeType': 'S'
                },
            ],
            TableName='Visits',
            KeySchema=[
                {
                    'AttributeName': 'Id',
                    'KeyType': 'HASH'
                },
            ],
            BillingMode='PAY_PER_REQUEST'
        )

        event = {}
        context = {}

        # Invoke lambda_handler
        response = lambda_handler(event, context)

        # Check response 1
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(response['body'], '{"Id": "cv", "VisitTotal": 1}')

        # Invoke lambda_handler
        response = lambda_handler(event, context)

        # Check response 2
        self.assertEqual(response['statusCode'], 200)
        self.assertEqual(response['body'], '{"Id": "cv", "VisitTotal": 2}')

    @mock_aws
    def test_lambda_handler_error(self):
        event = {}
        context = {}

        # Invoke lambda_handler without DynamoDB Table
        response = lambda_handler(event, context)
        print(response)

        self.assertEqual(response['statusCode'], 500)
        self.assertIn('error', response['body'])

```

Since my goal is to move away from manually running the tests and deployment, I need to also consider how to handle some of the local state. The [Terraform .tfstate](https://developer.hashicorp.com/terraform/language/state) and [.aws/credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) files are not part of source control because they contain sensitive data but would need to be available in some form for automation to function.

Terraform can support a backend for remote state storage which helps to avoid inconsistency and conflicts when compared with local state storage. In my case, I would use an [S3 backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3) with the state file stored in a bucket and a DynamoDB table used to provide state locking and consistency checking.

I can use Terraform, as before, to configure the S3 backend. Of course, this is a cyclic dependency, where we can't actually use the backend before it is defined so this infrastructure will likely remain a manual deployment step on initial setup.

```hcl
resource "aws_s3_bucket" "terraform_bucket" {
  bucket = "abcdef-terraform-state"
}
```

Terraform recommends using bucket versioning:
> Warning! It is highly recommended that you enable Bucket Versioning on the S3 bucket to allow for state recovery in the case of accidental deletions and human error.
I'm also going to use object lock and encryption for added protection and security, since our state files could contain sensitive data.

```hcl
resource "aws_s3_bucket_versioning" "terraform_versioning" {
  bucket = aws_s3_bucket.terraform_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "terraform_object_lock" {
  bucket = aws_s3_bucket.terraform_bucket.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 5
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.terraform_versioning
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_encryption" {
  bucket = aws_s3_bucket.terraform_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

Note that it was necessary to define a [depends_on](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on) relationship between the object lock and the versioning configuration. The order that resources are declared in a configuration file does not dictate the order that Terraform executes them. It typically does a good job of inferring relationships automatically, but in this case I was receiving an error that object lock can only be used when versioning is enabled. By adding the dependency manually, it ensured that versioning was enabled before object lock.

Lastly, we create the DynamoDB table to track the locking and consistency.

```hcl
resource "aws_dynamodb_table" "terraform_table" {
  name           = "abcdef-terraform-locking"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}
```

The local `.aws/credentials` file is generated by the AWS CLI, which is reasonable for local development but not ideal for automation. It seems that one of the recommended methods to authenticate to AWS with GitHub Actions is to use an [OpenID Connect](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) identity provider and assume an IAM Role for authorization.

Once again, we can use Terraform to configure our infrastructure. In this case, we can now use the S3 backend, but we can't yet use GitHub Actions to automate the deployment due to the cyclic dependency. Adding the following to my `terraform.tf` file, will configure the backend, and running `terraform init` should show that this is successful.

```hcl
  backend "s3" {
    bucket         = "abcdef-terraform-state"
    key            = "github-oidc/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "abcdef-terraform-locking"
  }
```

**Note that it is possible to store multiple states in the same S3 bucket and DynamoDB table, but be careful to configure the key for each project or you risk overwriting your state.**

Configuring the identity provider is quite simple. The thumbprint is that of the signing certificate, "DigiCert Global G2 TLS RSA SHA256 2020 CA1", so there is potential that this will change over time.

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = ["1b511abead59c6ce207077c0bf0e0043b1382612"]
}
```

The IAM policy for trusted entities is also relatively simple. Other than the AWS account number in the principal, the GitHub account name or repository that is being permitted to assume the role is the only part of the configuration that might be changed for each project.

```hcl
data "aws_iam_policy_document" "assume_role_github" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:githubaccountname/githubreponame:*"]
    }
  }
}
```

Finally, we're configuring the permissions that this assumed role has within AWS. This should always aim to follow the principal of least privilege as a security best practice. The below includes some basic access to our Terraform backend, but additional permissions would be required and is likely to change for each project or throughout a project as it grows.

```hcl
resource "aws_iam_role_policy" "terraform_policy" {
  name = "TerraformPolicy"
  role = aws_iam_role.github_actions_terraform_role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "TerraformBackendS3",
        "Effect" : "Allow",
        "Action" : [
          "s3:*"
        ],
        "Resource" : "arn:aws:s3:::abcdef-terraform-state/*/terraform.tfstate"
      },
      {
        "Sid" : "TerraformBackendDynamoDB",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:*"
        ],
        "Resource" : "arn:aws:dynamodb:eu-west-2:123456789012:table/abcdef-terraform-locking"
      }
    ]
  })
}

resource "aws_iam_role" "github_actions_terraform_role" {
  name = "GitHubActionsTerraformRole"

  assume_role_policy = data.aws_iam_policy_document.assume_role_github.json
}
```

With these steps complete, the environment should now be prepared for GitHub Actions and a CI/CD pipeline.