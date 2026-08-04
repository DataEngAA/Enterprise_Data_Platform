# Technical Stack

| Area | Technology | Purpose |
|---|---|---|
| IaC | Terraform | Reproducible AWS infrastructure |
| Development | EC2 | Cloud workstation for an 8 GB local machine |
| Language | Python | Ingestion, APIs, utilities, tests |
| Containers | Docker and ECR | Workload packaging |
| API ingestion | Lambda | Short event-driven extraction |
| Browser ingestion | ECS Fargate / EC2 | Browser and specialised workers |
| Messaging | SQS / EventBridge | Buffering and routing |
| Orchestration | Step Functions | AWS service workflows |
| CDC | AWS DMS | Full load and change capture |
| Streaming | Kinesis | AWS-native event streaming |
| Lake | S3 / Iceberg | Durable governed lakehouse |
| Catalog | Glue Catalog | Shared metadata |
| Governance | Lake Formation | Fine-grained access |
| Processing | Glue / EMR Serverless / dbt | Transformations |
| Serving | Athena / Redshift / OpenSearch / APIs | Consumption |
| Observability | CloudWatch / Grafana | Monitoring |
