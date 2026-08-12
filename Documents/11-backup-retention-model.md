# CVT BackupBridge Retention Model

## 1. Purpose

This document separates short local operational retention from longer Amazon S3 offsite retention for CVT BackupBridge.

No AWS infrastructure or local files are changed by this document.

## 2. Core principle

```text
LOCAL RETENTION
  Short staging and operational-recovery window
  Managed by a separate local cleanup process
                    |
                    v
S3 CLOUD RETENTION
  Longer offsite, ransomware, and historical window
  Managed by S3 Lifecycle, Versioning, and Object Lock
```

`S3_Uploader.ps1` transfers eligible backup files. It is not a retention engine.

The uploader must never use:

```text
aws s3 sync --delete
```

Deleting a local staging file must not delete its S3 object. S3 expiration must be controlled by reviewed S3 Lifecycle rules, subject to Versioning and Object Lock.

## 3. Retention objectives

The policy must preserve usable recovery sets rather than isolated files.

A point-in-time recovery set normally requires:

1. One conventional FULL backup.
2. Optionally, a compatible DIFFERENTIAL based on that FULL.
3. Every required TRANSACTION LOG backup after the selected base through the target time.

Deleting one required log can make every later log unusable for that chain. File age alone is therefore insufficient for local cleanup and policy approval.

## 4. Recommended example policy

The following is an example baseline. Adjust it for database size, change rate, RPO, RTO, ransomware dwell time, legal obligations, storage cost, and tested restore duration.

### 4.1 Policy summary

| Location/type | Example retention | Purpose |
|---|---:|---|
| Local FULL | Newest 2 successful conventional full anchors; normally no more than 8 days | Fast restore and cloud-outage buffer |
| Local DIFF | All compatible differentials associated with retained local full anchors; normally no more than 8 days | Fast local recovery |
| Local LOG | All logs required from retained full/differential bases; normally no more than 8 days | Preserve complete local PIT chains |
| S3 FULL | 365 days | 90-day PIT support plus older full-completion recovery points |
| S3 DIFF | 90 days | Operational PIT and faster recovery within the cloud window |
| S3 LOG | 90 days | Operational PIT window |
| Incomplete multipart uploads | Abort after 7 days in S3 Lifecycle | Avoid orphaned-part cost |

The 365-day FULL policy does not provide 365 days of point-in-time recovery when DIFF and LOG objects expire at 90 days. From day 91 through day 365, the retained FULL represents recovery to that full backup’s completion time only.

### 4.2 Recovery windows

```text
Days 0–8
  Local + S3
  Fast local recovery and full cloud protection

Days 9–30
  S3 Standard
  Full 90-day point-in-time chain

Days 31–90
  S3 Standard-IA
  Full 90-day point-in-time chain with retrieval charges

Days 91–365
  FULL backups only in S3 Glacier Flexible Retrieval
  Historical full-completion restore points; archive restore required

After day 365
  Expire unless a legal, regulatory, or approved archive policy requires longer retention
```

## 5. LOCAL RETENTION

### 5.1 Purpose

Local storage is a staging and operational-recovery tier. It provides:

- Fast restore without waiting for cloud download.
- Retry capacity after S3 transfer failure.
- A buffer during network or AWS interruption.
- Time to verify SQL backup metadata and readability.
- At least one fallback chain while a new full is being created or validated.

Local retention is not the authoritative long-term retention tier.

### 5.2 Chain-aware cleanup gate

A local file becomes eligible for cleanup only when all applicable conditions are true:

1. The SQL backup job succeeded with `CHECKSUM`.
2. The uploader completed with AWS CLI exit code 0.
3. The expected S3 key and exact byte length exist.
4. Compatible S3 checksum or manifest verification succeeded where available.
5. `RESTORE HEADERONLY` captured expected metadata.
6. `RESTORE VERIFYONLY` succeeded and checksum availability was recorded.
7. S3 Versioning and the intended Object Lock retention are confirmed.
8. Removing the file does not break every retained local recovery chain.
9. The minimum number of full anchors remains locally available.
10. The cleanup action is logged and independently monitored.

Do not treat object-name existence as successful cloud protection.

### 5.3 Example local cleanup algorithm

Per database:

1. Identify conventional FULL anchors from SQL metadata.
2. Retain the newest two verified FULL anchors.
3. Retain compatible DIFF backups for those anchors.
4. Retain every LOG required from each retained base through the latest local recovery point.
5. Do not delete the previous chain until the newer full and its first subsequent log are uploaded and verified.
6. Apply the eight-day cap only where it does not violate the minimum-chain rule.
7. Stop cleanup and alert when metadata cannot establish a valid chain.

`Get-BackupChain.ps1` can assist with chain analysis, but cleanup automation should have its own review, dry-run, containment, and audit controls.

### 5.4 Local capacity protection

Monitor:

- Free space and projected exhaustion time.
- Backup generation rate.
- Age of oldest and newest complete local chains.
- S3 upload lag.
- Verification backlog.
- Cleanup failures.

Storage pressure must not silently authorize deletion of the only valid chain.

## 6. S3 CLOUD RETENTION

### 6.1 Purpose

S3 is the longer offsite tier for:

- Regional/platform separation.
- Ransomware dwell-time coverage.
- Version recovery.
- Object Lock immutability.
- Historical restore points.
- Legal or regulatory retention where applicable.

Cloud retention is managed by S3 Lifecycle, not by the uploader, downloader, or SQL backup scripts.

### 6.2 Prefix-based policy mapping

BackupBridge uses:

```text
<PREFIX>/<Server>/<Database>/FULL/
<PREFIX>/<Server>/<Database>/DIFF/
<PREFIX>/<Server>/<Database>/LOG/
```

Lifecycle rules can filter by these prefixes. Because server and database precede backup type, production Infrastructure as Code will generally create database-specific/type-specific rules or introduce approved object tags/archive prefixes for scalable policy grouping.

Lifecycle rules operate on object age, prefix, tags, and version state. They do not understand SQL Server LSN continuity. Policy design must be validated against recovery-chain requirements before deployment.

## 7. S3 storage-class model

### 7.1 S3 Standard: days 0–30

Use S3 Standard for all FULL, DIFF, and LOG objects during the highest-probability recovery period.

Benefits:

- Millisecond access.
- No archive-restore staging.
- No minimum storage duration.
- Best fit for incident triage and rapid recovery.

Cost tradeoff:

- Highest storage cost among the listed multi-AZ classes.

### 7.2 S3 Standard-IA: days 30–90

Transition all three backup types to Standard-IA at day 30 when recovery access is expected less than monthly but millisecond access remains important.

Benefits:

- Lower storage cost than Standard.
- Immediate access and high throughput.

Tradeoffs:

- Retrieval fees.
- 30-day minimum storage duration.
- 128-KB minimum billable object size.
- Slightly lower availability target than Standard.

The example retains objects in Standard-IA for approximately 60 days, satisfying its minimum duration before DIFF and LOG expiration at day 90.

Do not use One Zone-IA for the authoritative offsite backup tier; it is not resilient to loss of an Availability Zone.

### 7.3 Glacier Flexible Retrieval: FULL days 90–365

Transition retained FULL backups from Standard-IA to S3 Glacier Flexible Retrieval at day 90.

Benefits:

- Lower long-term storage cost.
- Appropriate for backups accessed rarely.
- Expedited, Standard, and Bulk retrieval choices.

Tradeoffs:

- Object must be restored before normal download.
- Expedited retrieval is typically 1–5 minutes and can require provisioned capacity for predictability.
- Standard retrieval is typically 3–5 hours.
- Bulk retrieval is typically 5–12 hours.
- Retrieval and request charges apply according to tier.
- 90-day minimum storage duration.

The object remains in Flexible Retrieval for about 275 days in this example, exceeding the minimum duration.

### 7.4 Glacier Instant Retrieval alternative

Use S3 Glacier Instant Retrieval instead of Flexible Retrieval when historical FULLs must remain immediately readable and millisecond retrieval is required.

Tradeoff:

- Higher storage and data-access cost than Flexible Retrieval.
- Retrieval fees and a 90-day minimum duration.
- No archive restore request is required.

This is appropriate when RTO cannot tolerate archive staging but quarterly-or-rarer access is expected.

### 7.5 Glacier Deep Archive alternative

Use S3 Glacier Deep Archive only for multi-year archival copies where RTO allows long retrieval delay.

Typical implications:

- Standard retrieval around 12 hours.
- Bulk retrieval up to approximately 48 hours.
- 180-day minimum storage duration.
- Lowest storage cost among these options.

Deep Archive is inappropriate for the operational 90-day PIT window. It may be appropriate for annual or regulatory FULL archives when a 12–48-hour retrieval delay is explicitly accepted.

## 8. Example S3 Lifecycle intent

This is a control specification, not deployable JSON.

### FULL rule

| Object age | Action |
|---:|---|
| 0 days | Store in S3 Standard |
| 30 days | Transition to S3 Standard-IA |
| 90 days | Transition to S3 Glacier Flexible Retrieval |
| 365 days | Expire current version if no longer protected |

### DIFFERENTIAL rule

| Object age | Action |
|---:|---|
| 0 days | Store in S3 Standard |
| 30 days | Transition to S3 Standard-IA |
| 90 days | Expire current version if no longer protected |

### LOG rule

| Object age | Action |
|---:|---|
| 0 days | Store in S3 Standard |
| 30 days | Transition to S3 Standard-IA |
| 90 days | Expire current version if no longer protected |

### Shared housekeeping rule

- Abort incomplete multipart uploads after 7 days.
- Remove expired delete markers only when safe.
- Define noncurrent-version transitions and expiration separately.
- Do not permanently expire a version before its approved retention and Object Lock period.

## 9. Versioning and noncurrent versions

In a versioned bucket, current-version expiration normally creates a delete marker. Older versions continue to consume storage until a noncurrent-version Lifecycle action removes them.

Define separately:

- `NoncurrentVersionTransition` for cost control.
- `NoncurrentVersionExpiration` after the ransomware and retention window.
- Number of newer noncurrent versions to retain where appropriate.
- Expired delete-marker cleanup.

Do not set aggressive noncurrent expiration that defeats recovery from overwrite or ransomware. The noncurrent retention window should be at least as long as the approved ransomware-detection/dwell-time window.

Timestamp-based unique BackupBridge filenames reduce routine overwrites, but Versioning remains valuable for accidental key reuse, replacement, and protected recovery history.

## 10. Object Lock interactions

Object Lock protects individual object versions. It does not prevent Lifecycle storage-class transitions.

Key behaviors:

- Lock protection remains throughout Lifecycle transitions.
- Lifecycle cannot delete a locked version before its retain-until date.
- Legal hold also blocks permanent deletion until removed.
- Lifecycle expiration can create a delete marker while protected versions remain.
- Delete markers themselves are not WORM-protected.
- After retention expires, Lifecycle can delete the version when it otherwise qualifies.

Retention and Lifecycle must be aligned:

```text
Object Lock minimum retention <= or = approved protection window
Lifecycle expiration >= required retention window
```

If Object Lock retains all backup types for 90 days, the DIFF/LOG day-90 expiration occurs only after protection ends. If selected FULLs require 365 days of immutable protection, use a separately approved retention operation, dedicated archive prefix/bucket, or other design that applies 365-day retention without granting retention control to the Backup Writer.

The Backup Writer must not normally have:

- `s3:DeleteObject`
- `s3:DeleteObjectVersion`
- `s3:PutObjectRetention`
- `s3:BypassGovernanceRetention`
- Lifecycle or bucket-policy administration

## 11. Restore-time implications

### Standard and Standard-IA

`S3_Downloader.ps1` can download objects directly. Standard-IA adds retrieval charges but no archive-restore delay.

### Glacier Instant Retrieval

Objects remain directly downloadable with millisecond access, subject to retrieval fees.

### Glacier Flexible Retrieval and Deep Archive

These objects are archived. Before running the downloader:

1. Identify the exact FULL/DIFF/LOG chain and S3 version IDs.
2. Submit `RestoreObject` requests for every archived chain member.
3. Select a retrieval tier compatible with RTO.
4. Wait for every temporary restored copy to become available.
5. Set a temporary-copy duration long enough for download and retry.
6. Confirm restore status.
7. Run `S3_Downloader.ps1` only after all required objects are available.

Do not use `--force-glacier-transfer` indiscriminately. A partial chain download is not a usable restore.

Archive retrieval time is additive to SQL restore time. RTO must include:

```text
incident approval
+ chain identification
+ archive retrieval queue/time
+ cloud download
+ RESTORE VERIFYONLY
+ database restore/recovery
+ DBCC CHECKDB
+ application validation
```

## 12. Storage cost versus RTO

Lower-cost classes generally introduce retrieval fees, minimum-duration charges, or retrieval delays.

| Storage class | Relative storage cost | Access model | RTO effect |
|---|---|---|---|
| S3 Standard | Highest in this model | Immediate | Lowest storage-induced delay |
| Standard-IA | Lower | Immediate with retrieval fee | Low delay |
| Glacier Instant Retrieval | Lower archive storage | Immediate with higher retrieval fee | Low delay |
| Glacier Flexible Retrieval | Lower | Restore request; minutes to hours | Material delay |
| Glacier Deep Archive | Lowest | Restore request; hours to roughly 48 hours | Highest delay |

Cost optimization is valid only when the resulting retrieval time still meets business RTO.

Examples:

- A four-hour RTO normally cannot depend on Deep Archive.
- A one-hour RTO may require Standard, Standard-IA, Glacier Instant Retrieval, or provisioned expedited Flexible Retrieval after testing.
- A 24–72-hour regulatory archive can use Deep Archive if the operational recovery chain remains in faster storage.

Model retrieval charges and the cost of temporarily restored copies for large databases. Test full-chain retrieval, not a single small object.

## 13. Why local and cloud retention differ

Local storage is constrained, online to the SQL workload, and optimized for fast operational recovery. S3 is offsite, more scalable, versioned, lifecycle-managed, and potentially immutable.

Therefore:

- Local retention can be days.
- S3 PIT retention can be months.
- Historical FULL retention can be longer.
- Regulatory archives can be years.

Matching local retention to cloud retention would either exhaust local storage or unnecessarily shorten cloud resilience.

## 14. Lifecycle is the cloud retention engine

Responsibilities:

| Component | Responsibility |
|---|---|
| SQL backup scripts | Create unique FULL, DIFF, and LOG files |
| S3 uploader | Add/update eligible objects and return transfer status |
| Local cleanup process | Delete locally only after verification and chain-aware approval |
| S3 Lifecycle | Transition and expire current/noncurrent cloud versions |
| Object Lock | Prevent early deletion of protected versions |
| Recovery workflow | Select, retrieve, verify, and restore a complete chain |

The uploader must not:

- Add `--delete`.
- Delete S3 objects based on local absence.
- Implement cloud-age expiration.
- Bypass Governance retention.
- Replace Lifecycle with PowerShell cleanup.

## 15. Deployment flow

No deployment is authorized by this document.

For future implementation:

1. Approve RPO, RTO, PIT window, historical window, and legal retention.
2. Inventory database sizes, growth, backup frequency, and compression ratios.
3. Model current and noncurrent storage plus retrieval costs.
4. Verify Object Lock retention and Lifecycle expiration alignment.
5. Express Lifecycle rules as reviewed Infrastructure as Code.
6. Deploy first to a non-production bucket/prefix.
7. Validate transitions, delete markers, noncurrent versions, and locked versions.
8. Run full restore exercises from every intended storage class.
9. Measure end-to-end RTO.
10. Obtain production change approval.

## 16. Validation checklist

- Local cleanup preserves at least two valid full anchors and required chain members.
- No local deletion occurs before upload and SQL verification.
- Uploader command contains no `--delete`.
- FULL, DIFF, and LOG Lifecycle filters target the intended prefixes/tags.
- Standard-IA transition occurs no earlier than day 30.
- Minimum storage-duration charges are understood.
- Operational PIT chain remains directly accessible for the required RTO.
- Glacier restore process is documented and tested.
- Current and noncurrent versions have separate policies.
- Object Lock prevents premature expiration.
- Writer and Reader cannot delete protected objects or manage Lifecycle.
- Expiration periods match approved retention.
- Restore tests use complete chains and record end-to-end duration.

## 17. Risks and cautions

- Lifecycle can apply a technically valid age rule that destroys SQL chain usability.
- A missing LOG limits every later PIT recovery in that chain.
- Archive retrieval can cause an RTO breach.
- Object Lock can increase cost when retention exceeds Lifecycle expiration.
- Aggressive noncurrent expiration weakens ransomware recovery.
- Standard-IA and Glacier minimum-duration charges can erase expected savings.
- Legal hold can prevent expiration indefinitely.
- Retaining FULLs longer than logs must not be misrepresented as PIT retention.

## 18. Assumptions

- BackupBridge keeps the documented server/database/type hierarchy.
- Backup files use timestamp-based unique names.
- The S3 bucket is versioned.
- Object Lock configuration follows the approved security model.
- New production backups contain SQL backup checksums.
- Lifecycle is deployed through Infrastructure as Code.
- Actual requirements may supersede the example 8/90/365-day periods.

## 19. AWS references

- [S3 storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [Lifecycle transition considerations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)
- [S3 Glacier storage classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/glacier-storage-classes.html)
- [Archive retrieval options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects-retrieval-options.html)
- [S3 Lifecycle elements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intro-lifecycle-rules.html)
- [Object Lock and Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html)