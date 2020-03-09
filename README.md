# Terracode-Redis
Terracode for deploying an Elasticache (Redis) cluster in a VPC, accessible by a Lambda that can reach the internet 

The terracode in this repo automatically deploys a solution for the use case "How do I deploy a Lambda Function with access to a Private VPC and the internet"

In my case I wanted a worker function running in Lambda to have the ability to check the cache before sending a request to a public API


```
git clone https://github.com/louisbarrett/Terracode-Redis/
cd ./Terracode-Redis
terraform plan
```



Reference: https://aws.amazon.com/premiumsupport/knowledge-center/internet-access-lambda-function/
