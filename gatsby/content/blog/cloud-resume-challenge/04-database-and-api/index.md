---
title: "Database and API"
date: "2024-03-08T08:02:00.000Z" 
description: "Configuring a DynamoDB table, Lambda function, and API Gateway."
---

The next stage of the challenge is to add a visitor counter to the website, which is a little arbitrary since there are obviously much better solutions such as [Google Analytics](https://marketingplatform.google.com/intl/en_uk/about/analytics/). However, this artificially gives us a reason to create some back-end infrastructure and introduce a few more AWS services to the mix. I feel that this stage comes with a level of flexibility and opportunity to be creative, but I will start simple and meet the basic requirements then potentially make improvements in the future.

The first step is to provision a database and the challenge recommends [Amazon DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Introduction.html) with on-demand billing which is a fully managed NoSQL database service. I briefly covered document database types and used MongoDB during a university course, but needless to say I am far more familiar with relational databases. The main difference to be aware of, seems to be that tables are schemaless other than the primary key; this means that you do not need to use the same attributes for every row or item, in fact you can add or omit attributes at-will for each item. 

I created a table named Visits with a primary key named Id that accepts a String data type. I intend to later create an item with an additional attribute named VisitTotal (COUNT and TOTAL are protected keywords!) that accepts a Number data type.

Next up we need a way to interact with the database so that we can increment the VisitTotal value. For this, we are going to use [AWS Lambda](https://aws.amazon.com/lambda/) which is a serverless compute service so we don't need to manage any virtual machines and we're only paying for the compute time used when our code executes. There are several different runtime options with Lambda including .NET, Java, Node.js, Python, and Ruby. 

Lambda took me a little trial and error to get familiar with the service itself, to reacquaint myself with Python, and to reference the [Boto3 documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html). AWS provide a decent number of blueprints that help with examples, and once again the integrations with other AWS services make life much easier. 

The initial Python code for my Lambda function is:
```python
import boto3
import simplejson as json

table = boto3.resource('dynamodb').Table('Visits')

def lambda_handler(event, context):   
    response = table.update_item(
        Key={
            'Id': 'cv'
        },
        UpdateExpression='ADD VisitTotal :inc',
        ExpressionAttributeValues={
            ':inc': 1
        }
    )

    response = table.get_item(
        Key={
            'Id': 'cv'
        }
    )
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(response['Item'])
    }
```

This can be improved upon by adding error handling and tests, but it meets the basic requirements for now. I encountered some issues later where the native Lambda tests were successful, but via the API Gateway I was receiving a HTTP 500 status code and "Internal server error" message. This turned out to be that the 'body' response needs to be a String data type, which is why I introduced the json.dumps() function to convert the objects to String. However, the function in the standard json library seems to [lack support](https://bugs.python.org/issue16535) for the Decimal data type but is fixed by using [simplejson](https://pypi.org/project/simplejson/).

While I won't cover in great detail, permissions over the Lambda functions and other resources are all managed by policies and roles. Creating a Lambda function gives the option of automatically creating a role with the basic permissions required including for CloudWatch logs. I did need to add the following to the role, to allow it to access my DynamoDB table.

```json
{
    "Effect": "Allow",
    "Action": [
        "dynamodb:UpdateItem",
        "dynamodb:GetItem"
    ],
    "Resource": "arn:aws:dynamodb:eu-west-2:############:table/Visits"
}
```

Now we need a way for a website to trigger the Lambda function and the challenge suggests using an [API Gateway](https://aws.amazon.com/api-gateway/). While I will follow this approach, I did notice that it is possible to create a function URL on the Lambda function itself. Both accomplish the same basic functionality, but it seems that an API Gateway supports more features particularly around API types, authentication types, security, and logging.

The integrations in the AWS console shine through again, as you can either create an API Gateway and add an integration to the Lambda function, or you can add a trigger the the Lambda function and choose to create a new API Gateway.

![Lambda function diagram view](lambda-diagram.png)

Since my function is very simple with a singular purpose, I opted for an HTTP API type rather than REST API. I've also selected open security as there won't be any type of authentication required to view my CV website and embedding an API key into JavaScript does little other than add obscurity since it is readable client-side. One final setting that I have configured for the API gateway is for Cross-origin resource sharing (CORS) which will allow the API to be called from a different domain.

![CORS headers in browser](cors-headers.png)

Finally, a little addition to my placeholder index.html file to call the API:
```html
<script type="text/javascript">
async function incrementVisits() {
    const response = await fetch("https://abcdef.execute-api.eu-west-2.amazonaws.com/default/incrementVisits");
    const output = await response.json();
    console.log(output);
}

incrementVisits();    
</script>
```

It's worth pointing out that since we're using CloudFront, whenever we make a change to the S3 static website, we may continue to be served the cached version for a while. If we want to force the process, we can [invalidate the cache](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Invalidation.html).

Now we have a working visit counter:

![API endpoint response in browser](api-endpoint-response.png)