# Gatsby Blog

A blog to capture thoughts on technology projects.

## Requirements

- [Node.js](https://nodejs.org/en/)
- [Git](https://git-scm.com/download/win)
- [Gatsby CLI](https://www.gatsbyjs.com/docs/tutorial/getting-started/part-0/#gatsby-cli)

## Usage

Install packages:
```sh
npm install
```

Run a local development server:
```sh
npm run develop
```

Run the deploy script to build and push to GitHub pages:
```sh
npm run deploy
```

# Blog Infrastructure as Code (IaC)

Provision and configure infrastructure used by https://blog.cv.benjamesdodwell.com

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

## Usage

Configure an AWS IAM account with appropriate permissions and an access key to be used by Terraform:

https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration

Configure AWS CLI with the access key:
```sh
aws cli configure
```

Run the Terraform module:
```sh
terraform init -backend-config="backend.tfvars"
terraform apply -var-file="production.tfvars" -var-file="backend.tfvars"
```