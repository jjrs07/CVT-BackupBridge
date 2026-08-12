# 01 - Environment Preparation

## Purpose

Prepare a learner-safe BackupBridge lab. These steps describe prerequisites; the repository does not provision Azure, AWS, SQL Server, IAM, S3, KMS, lifecycle, Versioning, or Object Lock.

For the authoritative capability boundary, read [the v2 architecture guide](14-v2-architecture-and-capability-guide.md).

## LAB / POC implementation

The demonstrated lab used:

- an Azure VM to simulate an on-premises Windows SQL Server;
- Windows Server 2019 and SQL Server 2019 Developer Edition;
- a dedicated local backup volume;
- a private S3 bucket;
- AWS CLI v2; and
- Windows PowerShell 5.1+.

These are examples, not production sizing or a full support matrix. Use supported operating-system, SQL Server, PowerShell, and AWS CLI versions in any new deployment.

## Production-hardened recommendation

Use Infrastructure as Code, separate accounts/administration where required, temporary workload credentials, centralized logging/monitoring, tested KMS recovery, and business-approved retention/RPO/RTO. See the [S3 security model](08-s3-security-model-v2.md).

## 1. Recovery objectives and cost controls

Before creating resources:

1. Define database scope, required point-in-time window, RPO, RTO, retention, ransomware threat model, and evidence requirements.
2. Select a Region and recovery location consistent with data residency and latency requirements.
3. Establish cloud budgets and alerts.
4. Obtain approval for any Object Lock retention. Object Lock can prevent deletion and increase cost.

Do not claim a target RPO/RTO until it is measured with the project runbook.

## 2. Source SQL Server lab host

Create an isolated learner VM or use a local hypervisor. A reasonable lab starting point is 2 vCPU and 8 GiB RAM, adjusted for the test database. Restrict RDP, patch Windows and SQL Server, and install SSMS or `sqlcmd` as appropriate.

Prepare separate paths where practical:

```text
F:\Data
G:\Logs
T:\TempDB
H:\SQLBackups
H:\SQLRestore
C:\Logs
```

The dedicated backup path reduces contention and prevents backup growth from filling the OS volume. It is still local staging and not offsite protection.

Use AdventureWorks or disposable test databases. The scripts under `Scripts/SQL` that grow data/logs are workload simulators; inspect them and run only in an approved lab.

## 3. S3 bucket prerequisites

Create a dedicated private bucket/prefix through the approved process.

### LAB / POC baseline

- Block Public Access enabled.
- Default SSE-S3 encryption.
- HTTPS access.
- Dedicated non-production prefix.
- Versioning enabled when testing version recovery.
- Object Lock only in a purpose-built disposable bucket using the short Governance-mode lab design in the security guide.

### Production-hardened baseline

- Account- and bucket-level Block Public Access.
- HTTPS-only bucket policy.
- Versioning kept enabled.
- Approved Object Lock mode/retention when required.
- SSE-KMS with a customer-managed key only when its operational and recovery dependencies are accepted.
- Lifecycle aligned with retention and restore-time objectives.
- CloudTrail, inventory/monitoring, alerts, and protected administration.

S3 offsite storage is not automatically an air gap. It remains online. Versioning and Object Lock can strengthen ransomware resilience but must be combined with isolated credentials and administration.

## 4. IAM and credentials

Use the separated examples under `Scripts/iam`:

- Backup Writer for the source/upload host.
- Recovery Reader for the separate recovery host.

Do not use `Scripts/cvt-s3-policy.json` as the v2 production policy; it is a legacy combined lab artifact with read/write/delete capability.

### LAB / POC

If the learning environment cannot deliver role credentials, a dedicated IAM user with no console access may be used temporarily. Scope it to the appropriate v2 policy, protect/rotate the key, and remove it after the exercise. This is a lab compromise, not the preferred architecture.

### Production-hardened

Prefer temporary credentials from roles/federation and separate writer/recovery trust paths. For non-AWS Windows hosts, use an organization-approved workload identity or role-assumption pattern. This repository does not implement credential vending.

Never place credentials in scripts, `settings.json`, Git, logs, screenshots, or documentation. Do not copy Backup Writer credentials to recovery.

## 5. AWS CLI v2 and PowerShell

Install AWS CLI v2 from the approved source and verify:

```powershell
aws --version
aws sts get-caller-identity
```

The transfer scripts require Windows PowerShell 5.1 or later and explicitly reject AWS CLI v1. They are designed against Windows PowerShell 5.1; PowerShell 7 is not the documented validation baseline.

AWS CLI v2 internally manages transfer concurrency, multipart work, and request retries. The PowerShell scripts do not maintain their own queues or concurrency settings.

## 6. Configuration

Copy `Scripts/settings.json.template` to `Scripts/settings.json` and set:

```json
{
  "S3Bucket": "s3://<bucket>/<optional-prefix>",
  "AWSRegion": "<region>",
  "BackupRootPath": "H:\\SQLBackups",
  "RestoreRootPath": "H:\\SQLRestore",
  "LogDirectory": "C:\\Logs"
}
```

`settings.json` contains environment metadata, not credentials, and is ignored by Git. `S3Bucket` may contain a bucket name or S3 URI/prefix.

## Validation checklist

- [ ] Lab/non-production source and separate recovery hosts are identified.
- [ ] Source SQL Server is online and patched.
- [ ] Backup/restore/log paths exist with least-privilege filesystem access.
- [ ] S3 bucket/prefix is private and in the intended account/Region.
- [ ] Encryption, Versioning, Object Lock, and lifecycle states are recorded—not assumed.
- [ ] Writer and reader identities are separate and least privilege.
- [ ] AWS CLI v2 and Windows PowerShell 5.1+ are available.
- [ ] `settings.json` contains no secret.
- [ ] RPO/RTO and retention expectations are documented as targets pending measurement.

Next: [02 - Local Backup Storage](02-local-backup-storage.md).

