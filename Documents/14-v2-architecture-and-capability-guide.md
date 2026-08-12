# CVT BackupBridge v2: Architecture and Capability Guide

## 1. Problem solved

BackupBridge addresses the shared-fate risk of keeping SQL Server backups only in the source site. It creates a controlled path for native backup files to reach S3 and a documented path for a separate recovery SQL Server to retrieve, inspect, sequence, restore, and validate them.

The project is deliberately narrow. It does not provision AWS, manage SQL Agent jobs, restore databases automatically, fail over applications, or certify a business continuity program.

## 2. Architecture

### Implemented data flow

```text
Source SQL Server
  -> native SQL backups
  -> short-lived local staging hierarchy
  -> PowerShell orchestration
  -> AWS CLI v2 sync
  -> S3 bucket/prefix

Recovery Reader identity
  -> AWS CLI v2 sync to recovery staging
  -> SQL-native media verification
  -> metadata-derived candidate restore chain
  -> DBA-reviewed restore on separate SQL Server
  -> CHECKDB and application/data acceptance
```

### Component responsibility

| Component | Responsibility | Does not do |
|---|---|---|
| SQL backup scripts | FULL/DIFF/LOG, COMPRESSION, CHECKSUM, naming/hierarchy | Cloud transfer or retention |
| `S3_Uploader.ps1` | Validate config/CLI/source, invoke upload sync, log output/exit | Queue files, retry objects, delete, or prove SQL integrity |
| AWS CLI v2 | Compare sync candidates, concurrency, multipart, request retries, transfer exit | Choose SQL chain or validate database consistency |
| S3 | Durable object storage and configured bucket controls | Become an air gap merely because it is offsite |
| `S3_Downloader.ps1` | Validate config/CLI/destination, invoke checksum-mode download sync, log exit | Restore archived objects or perform SQL restore |
| `validation_script.ps1` | Optional `.bak`/`.trn` relative-path and exact-size comparison | Cryptographic content proof or source-independent DR proof |
| `verify-backup.sql` | HEADERONLY/FILELISTONLY/VERIFYONLY inspection | Actual database restore or CHECKDB |
| `Get-BackupChain.ps1` | Metadata-based candidate order and obvious gap warnings | Automatic restore or guaranteed chain validity |
| DBA/runbook | Version selection, review, restore, RECOVERY, CHECKDB, smoke test | Eliminate the need for evidence and judgment |

## 3. Security model

### Implemented examples

- Separate least-privilege Backup Writer and Recovery Reader policy examples.
- Prefix-scoped S3 permissions.
- No normal `DeleteObject` permission in v2 roles.
- No credentials embedded in scripts or `settings.json`.
- AWS CLI HTTPS behavior and explicit Region.

The legacy `Scripts/cvt-s3-policy.json` combines read/write/delete and is retained only as a historical lab artifact. It is not the v2 production model.

### Temporary credentials

Production workloads should prefer temporary credentials from an IAM role or federation mechanism. An IAM user with a long-lived access key may be acceptable only as a tightly controlled learner POC where role delivery is unavailable; it is not the preferred production recommendation. Never store access keys in Git, scripts, settings, logs, screenshots, or task definitions.

For a non-AWS Windows host, select and test an organizational credential-delivery pattern such as federation/role assumption or an approved external workload identity solution. This repository does not implement credential vending.

### Encryption

The scripts do not create encryption controls. Default S3 encryption applies according to bucket configuration. TLS protects normal AWS CLI connections in transit. SSE-S3 is the simpler lab baseline. Customer-managed SSE-KMS can provide key-policy separation and auditability, but it adds KMS permissions, cost, throttling considerations, and a recovery dependency on the key and its policy.

Encryption does not provide immutability, prove backup correctness, or replace TLS/checksums. Do not disable TLS validation.

### Versioning and Object Lock

Versioning retains object versions and helps recovery from replacement or simple deletion. It is not immutable when a principal can delete versions. Object Lock protects specified versions using WORM retention/legal hold and requires Versioning. It does not block creation of a new version or delete marker, so recovery must identify the correct version.

Object Lock can strengthen ransomware resilience, but only if retention, permissions, lifecycle, and recovery procedures are independently controlled and tested. Governance mode can be bypassed by specially authorized principals; Compliance mode has stronger restrictions and should be used only after legal and operational approval.

### Air-gap terminology

S3 offsite storage is online storage. It is not a physical air gap. A protected bucket can contribute to a logical isolation strategy when the source cannot delete protected versions and when administrators, credentials, policies, KMS, and recovery paths are separated. Describe the result as offsite storage with layered immutability and access isolation, not as automatically air-gapped.

### Compliance

BackupBridge provides design examples and potential evidence sources. It does not make an organization compliant with any regulation or framework. Compliance depends on approved requirements, retention, identity governance, monitoring, legal interpretation, operating evidence, and independent assessment.

## 4. Backup workflow

1. Select FULL recovery model when transaction-log recovery is required.
2. Create conventional FULL backups.
3. Create compatible DIFFERENTIAL backups where useful.
4. Create transaction-log backups at a schedule derived from RPO.
5. Use COMPRESSION to reduce storage and transfer bytes.
6. Use CHECKSUM to add SQL backup/page-checksum validation evidence.
7. Write unique timestamped files below `Server/Database/FULL|DIFF|LOG`.
8. Retain local staging long enough to tolerate transfer/recovery issues; do not equate local and cloud retention.

CHECKSUM detects certain I/O corruption and validates stored checksums when SQL reads the media. It cannot guarantee application correctness or full recoverability.

## 5. S3 synchronization workflow

The uploader executes one command equivalent to:

```text
aws s3 sync <BackupRootPath> s3://<bucket>/<optional-prefix>/
  --exclude * --include *.bak --include *.trn --region <Region> --no-progress
```

It preserves relative hierarchy, captures AWS CLI output, and returns the CLI exit code. It does not use `--delete`, `DeleteObject`, `Start-Process`, a PowerShell queue, custom retry logic, or `aws s3 ls` fallback success.

AWS CLI v2 transfer commands are internally multithreaded and manage multipart transfer/retries. The scripts do not set concurrency. Tune AWS CLI configuration only after measured tests and document host/network impact.

An exit code of 0 proves command success, not cryptographic equality or SQL recoverability. Cloud confirmation should record exact keys, sizes, versions, encryption, storage class, and compatible checksum/manifest evidence.

## 6. Recovery workflow

1. Prepare a separate recovery host and independent Recovery Reader credentials.
2. Restore archived S3 objects first when their storage class requires it.
3. Download the configured prefix with `aws s3 sync --checksum-mode ENABLED`.
4. Reconcile the expected object versions and local files.
5. Run SQL backup verification.
6. Generate and review the candidate chain report.
7. Restore FULL with NORECOVERY and explicit MOVE paths.
8. Restore an optional compatible DIFF with NORECOVERY.
9. Restore every required LOG in order, optionally using a reviewed STOPAT.
10. Run RECOVERY, CHECKDB, and application/data validation.

Checksum mode validates compatible stored S3 checksums. It does not guarantee every legacy object has checksum metadata and does not replace SQL verification.

## 7. Validation layers

| Layer | Establishes | Does not establish |
|---|---|---|
| CLI exit code/log | Transfer command result | Correct SQL media or chain |
| S3 inventory/version | Expected object identity | File content by key alone |
| Stored S3 checksum/manifest | Transfer/content evidence within algorithm/workflow | SQL logical consistency |
| Path and size comparison | Completeness/shape evidence | Cryptographic equality |
| HEADERONLY/FILELISTONLY | SQL metadata and file layout | Successful recovery |
| VERIFYONLY | Readability/completeness and stored SQL checksums when present | Full restore, CHECKDB, usability |
| Chain report | Plausible metadata-derived sequence and obvious gaps | Guaranteed successful restore |
| Isolated restore | SQL can apply selected chain | Database/application correctness alone |
| DBCC CHECKDB | Allocation/logical consistency | Business correctness |
| Smoke tests | Agreed data/application usability | Every application function |

## 8. LAB / POC versus PRODUCTION-HARDENED

### LAB / POC implementation

- Manually created Azure/AWS resources.
- SQL Server Developer Edition example.
- Manual execution or simple scheduling.
- Example IAM policies and optional learner credentials.
- S3 security, retention, and Object Lock documented but not provisioned.
- Repeatable manual DR validation.
- Placeholder RPO/RTO results until a test is measured.
- Screenshots show one environment and may predate v2 script internals.

### PRODUCTION-HARDENED recommendations

- Infrastructure as Code with reviewed changes.
- Private bucket, account-level and bucket-level Block Public Access, HTTPS-only policy, Versioning, lifecycle, monitoring, and approved Object Lock.
- Separate accounts/administration where required by the threat model.
- Temporary role credentials, MFA for human recovery access, protected break-glass process, and independent KMS administration.
- Central logs, alerts, CloudTrail analysis, transfer metrics, backup-chain monitoring, and capacity forecasts.
- Immutable unique object keys plus authoritative manifests/version IDs.
- Scheduled isolated restores and evidence retention.
- Tested cross-account/Region and KMS recovery where business requirements demand it.
- Business-approved RPO/RTO and compliance control mapping.

Recommendations are not implemented capabilities until deployed and tested.

## 9. Limitations

- No AWS/Azure provisioning or configuration enforcement.
- No automated SQL restore, infrastructure failover, DNS change, or application orchestration.
- Current downloader syncs current object versions; version-specific selection is a manual/recommended enhancement.
- No upload manifest or independent full-object digest generated by the uploader.
- No automatic pre-upload SQL VERIFYONLY gate.
- No monitoring/notification service.
- No demonstrated cross-account/Region recovery.
- No guarantee that archived backups meet RTO.
- No universal benchmark, RPO, RTO, durability outcome, ransomware guarantee, or compliance certification.
- The optional path/size validator requires both directories and therefore is not the source-independence proof.

## 10. RPO and RTO

Transaction-log frequency influences potential data loss, but actual offsite RPO also includes backup failures, scheduling delay, upload lag, chain continuity, object availability, and the latest transaction validated after restore.

End-to-end RTO includes incident declaration, recovery infrastructure/access preparation, archive retrieval, download, transfer validation, SQL verification, chain review, restores, RECOVERY, CHECKDB, and smoke validation. The repository supplies a measurement framework and blank results template; it does not publish benchmark results.

## 11. Lessons learned

- Delegate transfer mechanics to AWS CLI v2 and keep PowerShell understandable.
- Preserve and interpret native exit codes under Windows PowerShell 5.1.
- Treat checksums, SQL verification, restore, CHECKDB, and application tests as distinct layers.
- Separate writer and reader capability, and normally deny deletion to both.
- Let S3 Lifecycle manage cloud expiration; never use uploader `--delete` for retention.
- Prove recovery after removing access to the source.
- Measure DR instead of describing it as fast or guaranteed.

## 12. Future enhancements

1. Infrastructure as Code and automated policy validation.
2. Temporary credential integration for non-AWS Windows workloads.
3. Version-aware recovery inventory and protected manifests.
4. Central metrics, alerts, and failed-chain detection.
5. Orchestrated but approval-gated recovery-host preparation.
6. Cross-account/Region recovery and KMS continuity exercises.
7. Recurring restore tests with RPO/RTO trend reports.

## 13. Operational validation

Use the end-to-end runbook. A valid test must make the source SQL endpoint and source backup share unavailable before retrieval, use a separate recovery identity/server, restore the metadata-derived chain, run CHECKDB and smoke tests, and retain evidence. That is repeatable DR; unattended automated DR is outside the current implementation.

