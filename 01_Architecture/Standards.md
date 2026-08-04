# Engineering Standards

## Python
Python 3.12, type hints, structured JSON logs, Ruff, Pytest, Pydantic, no hardcoded secrets.

## Terraform
Modules, remote state, locking, required tags, validation and security scans, no manual production changes.

## Data
UTC timestamps, schema versions, SHA-256 checksums, idempotency keys, immutable source payloads, Parquet and Iceberg for analytical tables.

## S3 layout
```text
landing/source/year=YYYY/month=MM/day=DD/
quarantine/reason/source/
bronze/domain/table/
silver/domain/table/
gold/domain/data_product/
audit/ingestion_runs/
```
