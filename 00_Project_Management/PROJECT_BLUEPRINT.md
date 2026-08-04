# MEMORY.md
## Enterprise AWS Data Engineering Platform

## 1. Purpose of this file

This file gives Claude the full working context for the project so it can continue across chats without rereading the entire repository or inventing missing details.

Claude should read this file before making architectural, coding, infrastructure, or documentation changes.

This file should be updated whenever:

- A phase or step is completed.
- A major architectural decision is made.
- A tool or AWS service is added or removed.
- A blocker appears.
- A production incident is simulated or discovered.
- The next task changes.
- A significant lesson is learned.

---

# 2. Project Vision

Build a production-grade AWS Data Engineering platform that demonstrates the knowledge expected from a modern Data Engineer and progressively develops the skills expected from a Senior Data Engineer.

The project must not be a collection of disconnected AWS demos.

It must operate as one coherent enterprise platform with:

- Multiple ingestion patterns
- Reliable storage
- Data transformation
- Governance
- Security
- Monitoring
- CI/CD
- Disaster recovery
- Cost optimisation
- Interview preparation
- Documentation
- Architecture decisions
- Production runbooks

The project domain is an Enterprise Product Intelligence Platform.

It will ingest and manage data from:

- Manufacturer websites
- Public or private APIs
- PDFs
- EPDs
- TDS files
- Certificates
- Excel and CSV files
- JSON files
- Relational databases
- Streaming events
- Product and supplier systems

The platform should support:

- Analytics
- Search
- APIs
- Dashboards
- Data quality
- Manual review
- Operational monitoring
- AI-assisted product intelligence in later phases

---

# 3. Main Career Goal

The project is being built to strengthen practical AWS Data Engineering skills and improve readiness for Data Engineer and Senior Data Engineer interviews.

The project should demonstrate:

- Cloud architecture
- Infrastructure as Code
- Networking
- IAM
- Security
- Batch ingestion
- Streaming ingestion
- CDC
- Data lakehouse design
- Spark
- dbt
- Warehousing
- APIs
- Observability
- Cost awareness
- Reliability
- Disaster recovery
- Trade-off analysis
- Production incident handling

Every major technical choice must be explainable in an interview.

---

# 4. Local System Constraint

The local laptop has 8 GB RAM.

The laptop should act mainly as a thin client and control centre.

Heavy development work should not run locally unless it is lightweight.

The laptop should be used for:

- Browser
- VS Code interface
- AWS Console
- ChatGPT
- Claude
- Draw.io or Excalidraw
- GitHub
- Secure remote access
- Light command-line work if necessary

The laptop should not be relied on for:

- Spark
- Kafka
- Docker-heavy workloads
- Multiple databases
- Large browser automation jobs
- Elasticsearch or OpenSearch local clusters
- Airflow-heavy local environments
- Large local data processing
- Memory-intensive integration testing

---

# 5. EC2 Development Workstation Strategy

An EC2 instance will be used as the main cloud development workstation.

Important clarification:

The entire AWS platform will not be installed inside EC2.

EC2 is used for development, testing, building, administration, and selected heavy workloads.

Managed AWS services remain separate AWS services.

## EC2 will be used for

- Git
- GitHub repository access
- Python development
- Terraform
- Docker
- Docker Compose
- dbt
- Java
- Spark development with small or moderate samples
- AWS CLI
- PostgreSQL client
- Browser automation development
- Container image builds
- Unit and integration testing
- Documentation
- Temporary scripts
- Deployment commands
- Debugging
- Administration

## Managed AWS services remain separate

Examples:

- S3
- Lambda
- SQS
- SNS
- EventBridge
- Step Functions
- ECS Fargate
- Glue
- EMR Serverless
- RDS
- Aurora
- DynamoDB
- Kinesis
- Redshift
- OpenSearch
- QuickSight
- Lake Formation

## Important operational rule

The EC2 development workstation should be stoppable when not in use.

AWS pipelines and managed services must continue to work independently after EC2 is stopped.

## EC2 access model

Preferred:

- IAM-based access
- Systems Manager Session Manager
- Private subnet
- No unnecessary public ports
- No permanent AWS keys
- IAM instance profile
- Encrypted EBS
- GitHub as code source of truth
- S3 for durable artefacts
- Remote Terraform state

## EC2 development tools

Install:

- Git
- Python 3.12
- pip
- uv or Poetry
- Terraform
- AWS CLI
- Docker
- Docker Compose
- dbt
- Java
- PostgreSQL client
- jq
- curl
- make
- tmux
- Ruff
- Pytest
- Node.js if required later
- VS Code Remote support

---

# 6. Documentation-First Process

The project should use a documentation-first workflow.

Before implementation begins, the following files should exist.

## Core project documents

### PRD.md

Defines:

- What is being built
- Why it is being built
- Target users
- Functional requirements
- Non-functional requirements
- Success metrics
- Constraints
- Scope
- Future roadmap

### Architecture.md

Defines:

- High-level architecture
- Data flow
- AWS architecture
- Network architecture
- Component architecture
- Deployment architecture
- File and folder structure
- Service responsibilities
- Technical stack

### Rules.md

Defines boundaries for Claude and all development work.

Examples:

- Which libraries are preferred
- Which libraries should be avoided
- Error handling rules
- Logging requirements
- Testing requirements
- IAM rules
- Terraform rules
- Security rules
- Naming standards
- What Claude must not change silently
- What Claude must not invent

### Phases.md

Defines the full roadmap.

Each phase contains:

- Objective
- Scope
- Steps
- Deliverables
- Testing
- ADRs
- Runbooks
- Completion criteria
- Interview guide

### Design.md or UX_UI.md

Defines:

- Dashboard style
- Colours
- Typography
- Tables
- Filters
- Pipeline monitoring views
- Product search
- Data quality views
- Manual review flows

### Memory.md

This file.

It tracks:

- Current phase
- Current step
- Completed work
- Current task
- Known blockers
- Pending decisions
- Recent changes
- Next task
- Lessons learned

---

# 7. Additional Required Documentation

The project should also contain:

- TechStack.md
- Standards.md
- Security.md
- Monitoring.md
- Cost.md
- Testing.md
- Runbooks.md
- Lessons_Learned.md
- ADRs
- Roadmap.md
- Networking.md
- IAM_and_Access.md
- Disaster_Recovery.md
- CI_CD.md
- Data_Governance.md

---

# 8. Interview Guide

A dedicated folder must exist:

```text
17_Interview_Guide/
```

Every phase gets its own interview notes.

Example:

```text
17_Interview_Guide/
├── README.md
├── Phase_0.md
├── Phase_1.md
├── Phase_2.md
├── ...
└── Final_System_Design.md
```

Each phase guide should contain:

- Concepts covered
- Easy questions
- Medium questions
- Hard questions
- Senior-level questions
- AWS service questions
- System design questions
- Trade-offs
- Production incidents
- Debugging scenarios
- Scaling questions
- Security questions
- Cost questions
- Lessons learned
- Evidence from the implementation

Examples for Phase 1:

- Why choose Fargate?
- Why not Lambda?
- Why use SQS?
- What happens if a consumer fails?
- How does replay work?
- How is idempotency implemented?
- How would the system scale?
- What happens when a source changes schema?
- How would a backlog be handled?
- How would duplicate CDC events be handled?

Target:

By the end of the project, build approximately 300 to 500 interview questions with answers based on the actual implementation.

---

# 9. Phase Completion Rule

A phase is complete only when all of the following are complete:

- All planned implementation steps are finished
- Terraform is complete
- Code is committed
- Functional tests pass
- Integration tests pass
- End-to-end tests pass where applicable
- Failure scenarios are tested
- Monitoring exists
- Alerts exist
- IAM is reviewed
- Security controls are documented
- Cost impact is documented
- Runbooks are written
- ADRs are completed
- Interview guide is updated
- Memory.md is updated
- Lessons learned are recorded
- Environment can be recreated
- The phase can be demonstrated

Do not mark a phase complete only because the happy-path code works.

---

# 10. Pre-Phase — Engineering Environment Setup

Before Phase 0 begins, complete a Pre-Phase.

## Objective

Prepare the working environment, documentation, repository, AWS access, and EC2 development workstation.

## Pre-Phase Steps

### Step 1 — Finalise project planning

Create and review:

- PRD.md
- Architecture.md
- Rules.md
- Phases.md
- Memory.md
- Roadmap.md
- TechStack.md
- Standards.md
- Interview Guide structure

### Step 2 — Prepare the AWS account

Decide:

- AWS region
- Budget
- Billing alerts
- Naming convention
- Tagging convention
- IAM access strategy
- Development environment strategy
- Free Tier versus pay-as-you-go expectations

### Step 3 — Create the GitHub repository

Create:

- Repository
- README
- Branch strategy
- Folder structure
- .gitignore
- Pull request process
- Issue templates if useful

### Step 4 — Create the EC2 development workstation

Create a development-only EC2 instance.

Requirements:

- Secure access
- Encrypted EBS
- IAM instance profile
- Session Manager
- Automatic shutdown or disciplined stop process
- No unnecessary public exposure
- Reproducible setup

### Step 5 — Install development tools

Install:

- Git
- Python
- Terraform
- Docker
- Docker Compose
- AWS CLI
- dbt
- Java
- PostgreSQL client
- jq
- curl
- make
- tmux
- Ruff
- Pytest

### Step 6 — Configure VS Code remote development

The user should be able to:

- Open the EC2 project folder from the laptop
- Edit files in VS Code
- Run commands on EC2
- Use the EC2 terminal
- Run Python
- Run Terraform
- Build Docker images
- Run tests

### Step 7 — Test the development workstation

Verify:

- Git clone works
- Git push works
- Python runs
- Terraform runs
- Docker runs
- AWS CLI identifies the correct role
- Session Manager works
- VS Code remote works
- The instance can be stopped and started safely

## Pre-Phase Completion Criteria

- Documentation structure exists
- GitHub repository exists
- AWS account access is secure
- EC2 workstation is operational
- Tools are installed
- VS Code remote works
- Git works
- AWS CLI works
- Docker works
- Terraform works
- Budget controls exist
- The workstation can be recreated

---

# 11. Phase 0 — AWS Platform Foundation

## Objective

Create the secure, repeatable AWS foundation required by every later phase.

## Phase 0 Steps

### Step 1 — Finalise requirements

Define:

- Business requirements
- Functional requirements
- Non-functional requirements
- Expected volume
- Latency
- SLA
- RPO
- RTO
- Retention
- Security requirements
- Cost expectations

### Step 2 — Bootstrap Terraform

Create:

- Terraform repository structure
- Remote state
- State locking
- Environment separation
- Module structure
- Provider configuration

### Step 3 — Build environment structure

Initial environments:

- dev
- test
- stage
- prod

For the portfolio, dev may be implemented first while the multi-environment design is documented.

### Step 4 — Build networking

Create:

- VPC
- Public subnets
- Private application subnets
- Private data subnets
- Route tables
- Internet Gateway
- NAT Gateway only where justified
- VPC endpoints
- Security groups
- VPC Flow Logs

### Step 5 — Build IAM foundation

Create:

- Deployment role
- Runtime roles
- Read-only role
- EC2 instance profile
- Least-privilege policies
- Secret access policies
- Environment-specific permissions

### Step 6 — Configure logging and auditing

Create:

- CloudTrail
- CloudWatch log groups
- Retention policies
- Basic alarms
- VPC Flow Logs
- Deployment logs

### Step 7 — Configure encryption and secrets

Create:

- KMS foundations
- Secrets Manager usage
- Parameter Store where appropriate
- S3 encryption defaults
- EBS encryption

### Step 8 — Configure cost controls

Create:

- AWS Budgets
- Alerts
- Required tags
- Automatic EC2 shutdown
- Log retention
- Resource cleanup strategy

### Step 9 — Create initial CI/CD foundation

Create:

- GitHub Actions validation
- Terraform fmt
- Terraform validate
- Security scan
- Plan generation
- Manual approval design for later production deployment

### Step 10 — Test recovery and recreation

Test:

- Recreate infrastructure
- Recover EC2 workstation
- Access through Session Manager
- Restore required configuration
- Confirm remote Terraform state

### Step 11 — Complete documentation

Complete:

- ADRs
- Runbooks
- Security notes
- Cost notes
- Monitoring notes
- Phase 0 interview guide
- Lessons learned
- Memory update

## Phase 0 Completion Criteria

- Terraform can reproduce the foundation
- Secure access works
- IAM follows least privilege
- Networking is documented and deployed
- Logging exists
- Budget alerts work
- Encryption is enabled
- EC2 workstation can be recreated
- CI checks work
- Phase 0 runbooks exist
- Phase 0 interview notes exist

---

# 12. Phase 1 — Multi-Source Data Ingestion

## Objective

Build production-oriented ingestion pipelines for multiple source types using shared standards for reliability, observability, replay, validation, and metadata.

## Source Patterns

### Source 1 — REST API ingestion

Proposed flow:

```text
EventBridge Scheduler
    ↓
Step Functions
    ↓
Lambda API Extractor
    ↓
SQS
    ↓
Validation
    ↓
S3 Landing
```

Key concepts:

- Authentication
- Pagination
- Rate limits
- Incremental extraction
- Checkpoints
- Retry
- Timeout
- Validation
- Idempotency

### Source 2 — File ingestion

Supported files:

- PDF
- Excel
- CSV
- JSON

Proposed flow:

```text
Upload or Transfer
    ↓
S3
    ↓
EventBridge
    ↓
Step Functions
    ↓
Validation
    ├── Valid → Landing
    └── Invalid → Quarantine
```

Key concepts:

- File validation
- MIME checking
- Extension checking
- Checksum
- Duplicate detection
- Corrupt file detection
- Password-protected file handling
- Unsupported schema handling
- Quarantine

Document extraction itself belongs mainly to later processing phases.

### Source 3 — Website ingestion

Primary option:

```text
EventBridge Scheduler
    ↓
Step Functions
    ↓
ECS Fargate
    ↓
S3 Landing
```

Alternative:

```text
Step Functions
    ↓
EC2 Worker from Custom AMI
    ↓
Run Browser Scraper
    ↓
Upload Data
    ↓
Terminate Worker
```

Primary recommendation:

Use Fargate for isolated, containerised, scheduled browser jobs.

Use EC2 when:

- Custom AMI is needed
- Persistent browser environment is needed
- Long-running jobs are needed
- Special dependencies are required
- EC2 is more economical for predictable workloads

### Source 4 — Database CDC

Proposed flow:

```text
RDS PostgreSQL
    ↓
AWS DMS
    ↓
Full Load + CDC
    ↓
S3 Landing
```

Advanced extension:

```text
RDS PostgreSQL
    ↓
AWS DMS
    ↓
Kinesis
    ↓
S3
```

Key concepts:

- Full load
- Inserts
- Updates
- Deletes
- CDC
- Primary keys
- Replication lag
- Checkpoints
- Network access
- Database recovery

### Source 5 — Streaming ingestion

Primary recommendation:

Use Kinesis first.

Proposed flow:

```text
Producer
    ↓
Kinesis Data Streams
    ↓
Consumer
    ↓
S3 Landing
```

Key concepts:

- Shards
- Partitions
- Ordering
- Duplicate delivery
- Retention
- Replay
- Backpressure
- Checkpointing
- Throughput
- Consumer lag

Do not add MSK unless Kafka compatibility or ecosystem requirements justify it.

---

# 13. Phase 1 Shared Ingestion Standards

Every ingestion pipeline must support:

- Retry
- Dead Letter Queue
- Replay
- Idempotency
- Metadata
- Validation
- Quarantine
- Structured logging
- Monitoring
- Alerting
- Checkpoints
- Correlation IDs
- Pipeline run IDs
- Duplicate protection
- Failure preservation
- Audit history

## Standard ingestion metadata

Suggested fields:

```json
{
  "event_id": "uuid",
  "source_system": "source-name",
  "source_type": "api|file|website|database|stream",
  "ingestion_timestamp": "UTC timestamp",
  "source_timestamp": "UTC timestamp",
  "schema_version": "1.0",
  "correlation_id": "uuid",
  "pipeline_run_id": "uuid",
  "checksum": "sha256",
  "payload_location": "s3://bucket/key"
}
```

---

# 14. Phase 1 Steps

### Step 1 — Define source requirements

For every source define:

- Source owner
- Authentication
- Format
- Volume
- Frequency
- Latency
- SLA
- Retention
- Incremental method
- Checkpoint method
- Replay method
- Schema owner
- Failure behaviour

Deliverable:

Source Requirement Matrix.

### Step 2 — Define common ingestion framework

Define:

- Metadata envelope
- Error model
- Retry policy
- DLQ policy
- Correlation IDs
- Pipeline run IDs
- Naming conventions
- Idempotency rules
- Quarantine rules

Deliverable:

Ingestion Contract.

### Step 3 — Build Landing and Quarantine zones

Create:

- S3 Landing
- S3 Quarantine
- S3 Audit
- Versioning
- Encryption
- Lifecycle rules
- Bucket policies

### Step 4 — Build pipeline metadata tracking

Use DynamoDB for:

- Run status
- Start time
- End time
- Source
- Checkpoint
- Record count
- Error count
- Retry count
- Output location
- Schema version

### Step 5 — Implement REST API ingestion

Deliverable:

Scheduled, incremental, retryable API pipeline.

### Step 6 — Implement file ingestion

Deliverable:

Valid files land correctly and invalid files are quarantined.

### Step 7 — Implement website ingestion

Deliverable:

Scheduled browser scraper using Fargate, with EC2 comparison documented.

### Step 8 — Implement database CDC

Deliverable:

Full load and CDC into S3.

### Step 9 — Implement streaming ingestion

Deliverable:

Events reach S3 with checkpoints and replay.

### Step 10 — Add orchestration

Use:

- EventBridge
- Step Functions

Deliverable:

Unified workflow control and failure handling.

### Step 11 — Add observability

Create:

- CloudWatch dashboard
- DLQ alarms
- Queue-depth alarms
- Lambda error alarms
- Fargate failure alarms
- DMS lag alarms
- Kinesis lag alarms
- Freshness metrics
- Run status metrics

### Step 12 — Test failure scenarios

Test:

- API timeout
- API rate limiting
- Invalid JSON
- Duplicate file
- Corrupt PDF
- Unsupported schema
- Browser crash
- Database outage
- DMS lag
- Duplicate CDC event
- Consumer crash
- Queue backlog
- Permission failure
- Missing secret
- Replay after failure

### Step 13 — Complete architecture decisions

Create ADRs for:

- Terraform versus CloudFormation/CDK
- Lambda versus Fargate
- Fargate versus EC2
- SQS versus direct invocation
- Kinesis versus MSK
- EventBridge versus scheduled Lambda
- Step Functions versus Airflow
- DMS versus custom CDC

### Step 14 — Complete documentation

Update:

- Runbooks
- Testing evidence
- Security notes
- Cost notes
- Monitoring notes
- Interview guide
- Lessons learned
- Memory.md

---

# 15. Remaining Planned Phases

## Phase 2 — Data Lake and Lakehouse

Will cover:

- Landing
- Quarantine
- Bronze
- Silver
- Gold
- S3
- Parquet
- Apache Iceberg
- Glue Catalog
- Lake Formation
- Athena
- Partitioning
- Compaction
- Schema evolution
- Storage optimisation

## Phase 3 — Processing and Transformation

Will cover:

- Glue
- EMR Serverless
- Spark
- PySpark
- dbt
- SQL
- Data quality
- Deduplication
- CDC merge
- Slowly Changing Dimensions
- Business transformations
- Technical transformations

## Phase 4 — Warehousing and Databases

Will cover:

- Redshift
- Aurora/RDS
- DynamoDB
- OpenSearch
- Workload selection
- Serving models
- Transactional versus analytical storage
- Performance tuning

## Phase 5 — Data Serving and Analytics

Will cover:

- FastAPI
- API Gateway
- Athena
- Redshift
- OpenSearch
- QuickSight
- Search
- Dashboards
- Product-facing APIs
- Data access patterns

## Phase 6 — Security and Governance

Will cover:

- Lake Formation
- IAM
- KMS
- Secrets
- Data classification
- Macie
- GuardDuty
- Security Hub
- Config
- Auditing
- Ownership
- Lineage
- Fine-grained access

## Phase 7 — Observability and Operations

Will cover:

- CloudWatch
- Grafana
- Prometheus
- OpenTelemetry
- SLOs
- SLAs
- Error budgets
- Data freshness
- Incident response
- Runbooks
- On-call practices

## Phase 8 — CI/CD and Infrastructure as Code

Will cover:

- Terraform modules
- GitHub Actions
- Validation
- Security scanning
- Automated testing
- Deployment stages
- Manual approvals
- Rollback
- Environment promotion

## Phase 9 — Reliability and Disaster Recovery

Will cover:

- RPO
- RTO
- Backups
- Cross-region replication
- Replay
- Failover
- Recovery testing
- Chaos testing
- Restore testing
- Disaster recovery runbooks

## Phase 10 — Cost and Performance Engineering

Will cover:

- Budgets
- Cost allocation
- Cost per source
- Cost per pipeline
- Cost per million records
- Athena scan optimisation
- Glue DPU optimisation
- EC2 right-sizing
- S3 lifecycle
- Spot
- Reserved capacity
- Performance testing
- Load testing
- Capacity planning

---

# 16. Working Rules for Claude

Claude must follow these rules.

## Architecture rules

- Do not add AWS services only to increase the number of technologies.
- Every service must have a defined responsibility.
- Avoid duplicate services doing the same job.
- Document trade-offs.
- Record major decisions in ADRs.
- Prefer managed AWS services when justified.
- Use EC2 only when its flexibility, persistence, dependencies, or economics justify it.

## Infrastructure rules

- Terraform is the primary Infrastructure as Code tool.
- No untracked manual production changes.
- Do not commit Terraform state.
- Use remote state.
- Use environment separation.
- Apply required tags.
- Encrypt supported resources.
- Use least privilege.
- Do not create public databases.

## Security rules

- Never place credentials in code.
- Never place credentials in user data.
- Never store permanent AWS keys on EC2.
- Use IAM roles and temporary credentials.
- Use Secrets Manager or Parameter Store.
- Block public S3 access.
- Use TLS.
- Use KMS where appropriate.
- Log privileged activity.

## Python rules

- Use Python 3.12 unless an AWS service requires another version.
- Use type hints.
- Use structured logging.
- Validate inputs.
- Do not silently swallow exceptions.
- Add retries only for retryable errors.
- Use pytest.
- Use Ruff.
- Use Pydantic where contracts are useful.

## Data rules

- Use UTC timestamps.
- Preserve source payloads.
- Use checksums.
- Track schema versions.
- Make ingestion idempotent.
- Use Parquet for analytics.
- Use Iceberg for governed lakehouse tables.
- Keep invalid data in Quarantine.
- Keep audit records.

## Documentation rules

- Update Memory.md after meaningful work.
- Update ADRs after architectural decisions.
- Update Runbooks after operational changes.
- Update Lessons Learned after every phase.
- Update Interview Guide after every phase.
- Do not mark work complete without evidence.

## AI behaviour rules

Claude should not:

- Invent ARNs
- Invent account IDs
- Invent secrets
- Invent completed work
- Claim a deployment succeeded without evidence
- Replace the architecture silently
- Remove tests to make code pass
- Disable security controls to simplify development
- Add libraries without justification
- Assume missing business requirements when they materially affect architecture

Claude should:

- Use the current phase and current step
- Keep changes scoped
- Explain trade-offs
- Produce production-oriented code
- Update documentation
- Preserve context
- Mention blockers clearly
- Use placeholders where values are unknown
- Ask only when a missing decision materially changes the implementation

---

# 17. What to Share with Claude Before Starting

Before asking Claude to write code, share or place these files in the project root or documentation folder:

1. `MEMORY.md`
2. `PRD.md`
3. `Architecture.md`
4. `Rules.md`
5. `Phases.md`
6. `TechStack.md`
7. `Standards.md`
8. `Roadmap.md`
9. Current phase document
10. Relevant ADRs
11. Relevant runbooks
12. Current folder structure
13. Current Terraform structure
14. Current code files related to the task
15. The exact task to complete
16. Acceptance criteria
17. Known constraints
18. Expected output files
19. Current errors or logs
20. What Claude must not change

## Best prompt format for Claude

Use this structure:

```text
Read these files first:

- MEMORY.md
- PRD.md
- Architecture.md
- Rules.md
- Phases.md
- Current phase document
- Relevant ADRs

Current phase:
[Phase name]

Current step:
[Step name]

Current task:
[Exact task]

Constraints:
[List constraints]

Acceptance criteria:
[List measurable completion conditions]

Files you may modify:
[List files or folders]

Files you must not modify:
[List files or folders]

Before coding:
1. Summarise your understanding.
2. Identify missing information.
3. State the implementation plan.
4. Mention any architectural conflict.
5. Do not begin unrelated work.

After coding:
1. List files changed.
2. Explain the implementation.
3. Show tests run.
4. Show unresolved issues.
5. Update MEMORY.md.
6. Update ADRs or runbooks if required.
```

---

# 18. Recommended First Claude Task

The first Claude task should not be:

“Build the entire platform.”

The first Claude task should be:

```text
Read MEMORY.md, PRD.md, Architecture.md, Rules.md, Phases.md, and the Pre-Phase plan.

Create the initial repository folder structure and documentation files only.

Do not deploy AWS resources.

Do not add services.

Do not create credentials.

Do not invent missing AWS values.

Create placeholders for:
- Terraform
- Source code
- Tests
- CI/CD
- ADRs
- Runbooks
- Interview guide

Update MEMORY.md after completion.
```

After that, the next task should be:

```text
Create the Pre-Phase EC2 development workstation setup plan.

Include:
- IAM role
- Session Manager
- VPC placement
- EBS
- Security groups
- Bootstrap script
- Installed tools
- Cost controls
- Backup and recovery
- Acceptance tests

Do not deploy until the design and Terraform plan are reviewed.
```

---

# 19. Current Project Status

## Completed

- Overall platform vision defined
- Phase-based approach defined
- Pre-Phase added
- Phase 0 defined
- Phase 1 defined
- EC2 development workstation strategy defined
- Documentation-first process defined
- Interview guide strategy defined
- Phase completion rules defined
- Main AWS service responsibilities defined

## Current phase

Pre-Phase — Engineering Environment Setup

## Current step

Prepare the repository, Claude context files, AWS account decisions, and EC2 development workstation plan.

## Next action

Share this file and the supporting documents with Claude.

Then ask Claude to create or validate the repository structure before any AWS deployment begins.

---

# 20. Final Working Principle

Build the platform gradually.

Do not attempt to build all services at once.

The correct sequence is:

```text
Project Planning
    ↓
AWS Account Preparation
    ↓
GitHub Repository
    ↓
EC2 Development Workstation
    ↓
Development Tool Installation
    ↓
Terraform Bootstrap
    ↓
Phase 0 AWS Foundation
    ↓
Phase 1 Multi-Source Ingestion
    ↓
Phase 2 Lakehouse
    ↓
Phase 3 Processing
    ↓
Later Phases
```

Each step must be tested, documented, and explainable before moving forward.
