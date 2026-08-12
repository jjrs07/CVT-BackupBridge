# CVT BackupBridge

CVT BackupBridge v2 is a lab-tested, script-based pattern for moving native SQL Server FULL, DIFFERENTIAL, and transaction-log backups from local staging storage to Amazon S3 and retrieving them on a separate recovery SQL Server.

It solves one specific problem: a SQL Server backup that exists only beside its source environment can be lost with that environment. BackupBridge adds an offsite copy, a least-privilege transfer path, metadata-based chain planning, SQL-native verification, a manual DR runbook, and measurable RPO/RTO evidence.

It is not a backup appliance, an offline air gap, an automated SQL restore platform, or a compliance-certified product.

## Implemented architecture

```text
SQL Server
  -> native FULL / DIFF / LOG backups with COMPRESSION and CHECKSUM
  -> local staging: Server / Database / FULL|DIFF|LOG
  -> S3_Uploader.ps1
  -> AWS CLI v2: aws s3 sync (only .bak and .trn; no --delete)
  -> private S3 bucket/prefix

Separate recovery SQL Server
  <- S3_Downloader.ps1
  <- AWS CLI v2: aws s3 sync --checksum-mode ENABLED
  -> RESTORE HEADERONLY / VERIFYONLY
  -> Get-BackupChain.ps1 report
  -> reviewed FULL / optional DIFF / LOG restore
  -> RECOVERY -> DBCC CHECKDB -> application/data smoke validation
```

PowerShell is the orchestration layer. AWS CLI v2 owns transfer scheduling, multipart operations, concurrency, and retry behavior. SQL Server owns backup creation, backup checksums, restore semantics, and database consistency checks.

## Capability boundary

| Area | LAB / POC implementation in this repository | PRODUCTION-HARDENED recommendation |
|---|---|---|
| Backup | Example native FULL/DIFF/LOG scripts | SQL Agent orchestration, monitoring, tested schedules, HA-aware design |
| Transfer | Manual/schedulable PowerShell invoking AWS CLI v2 sync | Managed scheduling, alerting, metrics, controlled AWS CLI configuration and change management |
| IAM | Example separated writer/reader policies | Temporary role credentials, trust policies, permission boundaries/SCPs, audited KMS and bucket policies |
| S3 protection | Documented lab design; not provisioned by scripts | Block Public Access, Versioning, approved Object Lock, HTTPS-only bucket policy, lifecycle, logging/monitoring |
| Encryption | S3 default encryption is assumed/configured outside scripts; TLS is provided by AWS CLI HTTPS | Approved SSE-KMS design where required, protected KMS key, tested key recovery and least privilege |
| Verification | CLI exit code, optional stored S3 checksum validation on download, path/size comparison, SQL VERIFYONLY/HEADERONLY | Protected checksum manifest/object inventory, version-ID recovery, scheduled isolated restores and alerting |
| DR | Repeatable manual runbook and supporting scripts | Orchestrated recovery environment, approvals, DNS/application dependencies, recurring exercises and operational ownership |
| RPO/RTO | Definitions and results template with no fabricated results | Business-approved targets, monitoring, repeated measurements, capacity and archive-tier testing |
| Compliance | Security and retention design guidance only | Organization-specific legal/control mapping, evidence, audit and formal assessment |

## Security language

- **Offsite is not automatically air-gapped.** S3 remains online and reachable through authorized APIs. Versioning, Object Lock, separation of duties, credential isolation, and independent administration can create stronger logical isolation, but they are not physical offline media.
- **Ransomware resilience is layered, not guaranteed.** Versioning can retain prior versions; Object Lock can protect selected versions from deletion for a retention period. Neither replaces least privilege, credential protection, monitoring, recovery testing, or correct version selection.
- **Encryption is not configured by the transfer scripts.** S3 encrypts objects according to bucket/object settings; AWS CLI uses HTTPS unless someone deliberately changes endpoint/TLS behavior. SSE-KMS requires separately tested KMS permissions and key availability during recovery.
- **No compliance claim is made.** Object Lock and retention features may support a control objective, but this repository does not establish SOC 2, HIPAA, GDPR, SEC, FINRA, or other compliance.

## Validation layers

Each layer proves something different:

1. AWS CLI exit code: the transfer command completed successfully.
2. S3 inventory/checksum evidence: the expected object/version exists and compatible stored checksums validate when available.
3. Path/size comparison: expected backup files correspond; size alone is not content-integrity proof.
4. `RESTORE HEADERONLY`: captures backup metadata.
5. `RESTORE VERIFYONLY`: checks backup readability/completeness and stored SQL backup checksums when present; it does not prove full recoverability.
6. Actual isolated restore: exercises the selected recovery chain.
7. `DBCC CHECKDB`: checks database allocation and logical consistency after restore.
8. Application/data smoke tests: establish usability at the intended recovery point.

## Requirements

- Windows PowerShell 5.1 or later on Windows. The transfer scripts target Windows PowerShell 5.1 compatibility; PowerShell 7 is not the documented validation baseline.
- AWS CLI v2 available in `PATH`.
- SQL Server and tools appropriate to the backup version.
- A private S3 bucket/prefix and approved identities.
- `Scripts/settings.json`, copied from `Scripts/settings.json.template` and excluded from source control.

## Documentation path

1. [V2 architecture and capability guide](Documents/14-v2-architecture-and-capability-guide.md)
2. [Environment preparation](Documents/01-environment-preparation.md)
3. [Local backup storage](Documents/02-local-backup-storage.md)
4. [Backup generation](Documents/03-backup-generation.md)
5. [Upload to S3](Documents/04-upload-to-s3.md)
6. [Recovery download](Documents/05-recovery-download.md)
7. [Restore and validation](Documents/06-restore-validation.md)
8. [S3 security model](Documents/08-s3-security-model-v2.md)
9. [SQL backup verification](Documents/09-sql-backup-verification.md)
10. [Backup-chain utility](Documents/10-get-backup-chain.md)
11. [Retention model](Documents/11-backup-retention-model.md)
12. [End-to-end DR runbook](Documents/12-end-to-end-dr-validation-runbook.md)
13. [RPO/RTO measurement](Documents/13-rpo-rto-measurement-framework.md)
14. [Reusable results template](Results/dr-validation-results-template.md)

## Demonstrated versus not demonstrated

Demonstrated by the project artifacts and documented lab evidence:

- generation and S3 transfer of SQL backup files;
- hierarchy-preserving upload/download using AWS CLI v2;
- SQL backup metadata inspection and candidate chain reporting;
- a documented restore-validation path.

Not demonstrated as an operational guarantee:

- a physical air gap;
- automatic recovery environment provisioning or unattended SQL restore;
- a universal RPO/RTO value;
- cross-Region or cross-account recovery;
- KMS disaster recovery or customer-managed key availability;
- production Object Lock/lifecycle deployment;
- continuous monitoring/alerting; or
- compliance certification.

## Lessons learned

- Transfer orchestration is simpler and more reliable when AWS CLI v2 owns concurrency, multipart transfer, and retries.
- Exit-code success is necessary but not equivalent to SQL backup integrity or recoverability.
- A restore chain must be selected from SQL metadata, not filenames alone.
- Offsite retention and local staging retention are different controls; S3 Lifecycle, not `sync --delete`, manages cloud expiration.
- Recovery independence must be tested after the source SQL Server and backup share are unavailable.
- RPO and RTO are measured outcomes, not marketing statements.

## Future enhancements

- Infrastructure as Code for bucket, policies, roles, KMS, lifecycle, logging, and recovery compute.
- Temporary role credential delivery suitable for non-AWS Windows hosts.
- Protected upload manifests with object version IDs and full-object checksums.
- Automated inventory reconciliation and alerting without automating destructive restore decisions.
- Cross-account/Region recovery design and KMS dependency testing.
- Scheduled isolated restore exercises with retained evidence and trend reporting.

## Lab environment

The original POC used an Azure Windows Server 2019 VM, SQL Server 2019 Developer Edition, and Amazon S3. These are examples, not production sizing or a supported-platform matrix.

## Author

James Santos — Cloud Virtuoso Tech (CVT)

*Tech solutions played in harmony.*

