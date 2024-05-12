---
title: "CI/CD for Backend Infrastructure"
date: "2024-05-08T08:30:00.000Z" 
description: "Using GitHub Actions workflows to test the Python Lambda function, then deploy the backend infrastructure with Terraform."
---

Using [GitHub Actions](https://docs.github.com/en/actions), I would create YAML files in the `.github\workflows` path of the project to define my pipelines. My structure was basic, with one file to run the Python tests for integration, and another to create the infrastructure with Terraform for deployment.

The test workflow would primarily trigger whenever there was a push to the master branch of the repository, with an alternative manual trigger for testing the pipeline itself.

```yaml
name: 'Test'

on:
  workflow_dispatch:
  push:
    branches: [ "master" ]
```

The jobs would set up a Python environment, using the same version as the Lambda function, install the dependencies, and then run the tests.

```yaml
jobs:
  python:
    name: 'Test'
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        shell: bash

    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          architecture: 'x64'

      - name: Install dependencies
        run: python -m pip install --upgrade pip boto3 simplejson botocore moto

      - name: Test with unittest
        working-directory: ./lambda/IncrementVisits
        run: python -m unittest ./test_IncrementVisits.py
        env:
          AWS_ACCESS_KEY_ID: dummy-access-key
          AWS_SECRET_ACCESS_KEY: dummy-access-key-secret
          AWS_DEFAULT_REGION: eu-west-2
```

 I discovered that [Boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html) was throwing an error: `botocore.exceptions.NoCredentialsError: Unable to locate credentials`
 This wasn't an error that I encountered when testing locally, because I had already configured a `.aws/credentials` file. However, I didn't expect to need credentials in the GitHub runner environment since I was using [Moto](https://docs.getmoto.org/en/latest/docs/getting_started.html) to mock my AWS interactions during testing. It appears that Boto3 expects to find credentials, even if they ultimately aren't used, so setting some dummy keys as environment variables was the solution.

The deployment job should trigger only on successful completion of the test workflow. This is managed at two points with GitHub Actions. First, the deploy workflow triggers when the test workflow completes. However, it is important to note that this will trigger regardless of the results of the test. 

 ```yaml
 name: 'Terraform'

on:
  workflow_dispatch:
  workflow_run:
    workflows: [Test]
    types: [completed]
```

The workflow needs permissions to handle the OIDC [JSON Web Token (JWT)](https://auth0.com/docs/secure/tokens/json-web-tokens) so that the `aws-actions/configure-aws-credentials` action can request an access token from AWS. This action will also assume the IAM Role that was created with permissions to manage all of the necessary infrastructure.

Here, we also check the conclusion of our previous test workflow, before running the Terraform job steps.

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    name: 'Terraform'
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        shell: bash

    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
    - name: Configure aws credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::########:role/GitHubActionsTerraformRole
        aws-region: eu-west-2
```

Finally, we start our deployment steps adhering to some of the [Running Terraform in automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform) best practice. The main change when compared to running locally, is the use of a file output from `terraform plan` as input for `terraform apply` since there will be no manual validation of the plan. This can offer improved consistency which may not be relevant for my small scale project but can ensure that the plan is applied as expected, regardless of any change that could have occurred between running the commands.

```yaml
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
      working-directory: ./terraform
      run: terraform plan -out=tfplan -input=false

    - name: Terraform Apply
      working-directory: ./terraform
      run: terraform apply -auto-approve -input=false tfplan
 ```

 Testing these pipelines was successful, with my backend AWS infrastructure being deployed automatically following a code commit to the repository, only on the condition that the Python tests pass.