# Blog Infrastructure as Code (IaC)

Provision and configure infrastructure used by https://blog.cv.benjamesdodwell.com

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

## Usage

Configure an AWS IAM account with appropriate permissions and an access key to be used by Terraform:

https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration

Configure AWS CLI with the access key:
```
aws cli configure
```

Run the Terraform module:
```
terraform apply
```