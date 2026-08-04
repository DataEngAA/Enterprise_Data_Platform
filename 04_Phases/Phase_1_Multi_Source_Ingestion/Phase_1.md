# Phase 1 — Multi-Source Data Ingestion

## Patterns
- API: EventBridge → Step Functions → Lambda → SQS → validation → S3.
- Files: S3/Transfer Family → EventBridge → Step Functions → Landing or Quarantine.
- Websites: EventBridge → Step Functions → Fargate; EC2 where justified.
- CDC: RDS PostgreSQL → DMS → S3.
- Streaming: producer → Kinesis → consumer → S3.

## Shared requirements
Run IDs, correlation IDs, checkpoints, retries, DLQs, idempotency, duplicate detection, quarantine, structured logs, metrics, and replay.

## Steps
1. Source matrix.
2. Ingestion contract.
3. Landing/Quarantine/Audit.
4. DynamoDB run metadata.
5. API ingestion.
6. File ingestion.
7. Website ingestion.
8. Database CDC.
9. Streaming ingestion.
10. Unified orchestration.
11. Monitoring.
12. Failure testing.
13. ADRs, runbooks, cost notes, interview guide.
