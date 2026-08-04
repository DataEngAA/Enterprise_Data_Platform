# AI and Development Rules

- Do not invent ARNs, IDs, secrets, or deployment results.
- Do not add AWS services without a documented requirement.
- Do not disable security, encryption, tests, or logging to make code pass.
- Keep ingestion idempotent and preserve failed payloads.
- Retry only retryable errors.
- Update tests, documentation, ADRs, and Memory.md with meaningful changes.
- Prefer boto3, pydantic, httpx, tenacity, pytest, and typed Python.
