---
title: "Static Application Security Testing"
date: "2024-05-28T09:00:00.000Z" 
description: "Implementing Static Application Security Testing (SAST) into Continuous Integration (CI) pipelines with GitHub Actions."
---

During the Cloud Resume Challenge, I identified that my Terraform Infrastructure as Code (IaC) should include tests as part of my Continuous Integration (CI) pipelines. There are many types of software testing, each serving different purposes and providing various benefits. One area of particular interest to my current role is Static Code Analysis (SCA), also known as Static Application Security Testing (SAST).

I performed some research into SAST tooling that supports infrastructure languages such as Terraform and identified three interesting projects:
- [Checkov by Prisma Cloud (Palo Alto)](https://github.com/bridgecrewio/checkov)
- [TFsec by Aqua Security](https://github.com/aquasecurity/tfsec)
- [Terrascan by Tenable](https://github.com/tenable/terrascan)

All three options meet my requirements, including support for Terraform and integration with GitHub Actions. They are open-source projects backed by companies in the security industry. I decided to use Checkov for the time being, partly due to the reputation of Palo Alto, but also for its ability to write custom policies in Python.

Checkov can be installed using Python pip or pip3:
```sh
pip3 install checkov
```

A directory can then be scanned recursively:
```sh
checkov -d ./
```

This can also be integrated into a CI pipeline using the [Checkov GitHub Action](https://github.com/bridgecrewio/checkov-action).

An example of the output from Checkov for my Terraform Backend project:

```sh
Check: CKV_AWS_119: "Ensure DynamoDB Tables are encrypted using a KMS Customer Managed CMK"
    FAILED for resource: aws_dynamodb_table.terraform_table
    File: \terraform\main.tf:90-103
    Guide: https://docs.prismacloud.io/en/enterprise-edition/policy-reference/aws-policies/aws-general-policies/bc-aws-52

Check: CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
    FAILED for resource: aws_s3_bucket.terraform_bucket
    File: \main.tf:54-56
    Guide: https://docs.prismacloud.io/en/enterprise-edition/policy-reference/aws-policies/aws-general-policies/ensure-that-s3-bucket-has-cross-region-replication-enabled 
```

In software development, a change to one part of code often impacts another. For example, enabling encryption on DynamoDB with a Key Management Service (KMS) Customer Manager Key (CMK) requires creating a new resource. That new resource may then fail additional checks, necessitating further work. This highlights the importance of Regression Testing and Continuous Integration.

Additionally, some checks might fail but can be safely ignored depending on the context. Enabling [Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html#replication-scenario) can provide redundancy, help with compliance requirements, or reduce latency. However, for my use case, these benefits are negligible, and minimising costs is a higher priority.

Checkov allows [skipping of individual checks](https://www.checkov.io/2.Basics/Suppressing%20and%20Skipping%20Policies.html) by adding comments to the Terraform code. For instance:
```hcl
#checkov:skip=CKV_AWS_144:Cross-region replication not required for Terraform state bucket.
```

This method provides documentation specifying why a particular policy is being skipped, demonstrating that the risks have been carefully considered rather than skipped merely to pass a test.

Some of the changes and enhancements that I've made to my infrastructure, based on feedback from Checkov, are as follows:

- Encrypted S3 buckets and DynamoDB tables with AWS Key Management Service and Customer Managed Keys.
- Enabled DynamoDB point-in-time recovery.
- Configured S3 Public Access Block.
- Enforced code-signing in Lambda and signed Python code with AWS Signer.
- Enabled access logging to an S3 bucket for CloudFront distribution.

Incorporating Checkov into my Continuous Integration (CI) pipeline will help to ensure that the security of my AWS infrastructure is maintained.