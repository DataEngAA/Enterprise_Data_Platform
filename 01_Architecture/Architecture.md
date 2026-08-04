# Architecture

```text
Sources: APIs | Websites | Files | Databases | Streams
                  ↓
Ingestion: Lambda | SQS | EventBridge | Step Functions | Fargate | EC2 | DMS | Kinesis
                  ↓
Storage: Landing | Quarantine | Bronze | Silver | Gold | Iceberg | Glue Catalog
                  ↓
Processing: Glue | EMR Serverless | Spark | dbt
                  ↓
Serving: Athena | Redshift | Aurora | DynamoDB | OpenSearch | FastAPI | QuickSight
```

## EC2 boundary
EC2 is used as a cloud workstation and for selected workloads such as custom browser workers. It does not replace managed AWS services.

## Principles
- Immutable raw data.
- Idempotent and replayable ingestion.
- Queues between failure domains.
- Explicit schemas and data contracts.
- Managed services when justified.
- No duplicate services without separate responsibilities.
