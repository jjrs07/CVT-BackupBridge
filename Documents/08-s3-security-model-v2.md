# CVT BackupBridge v2 Amazon S3 Security Model

## 1. Purpose

This document defines two Amazon S3 security profiles for CVT BackupBridge v2:

- **LAB MODE**: safe and reproducible for learners.
- **PRODUCTION-HARDENED MODE**: designed for regulated or security-sensitive SQL Server backup workloads.

This is an architecture and control specification only. It does not provision or modify S3 buckets, KMS keys, IAM roles, bucket policies, lifecycle rules, or other AWS resources.

## 2. Security objectives

The S3 design must:

1. Keep SQL Server backups private.
2. Encrypt backups in transit and at rest.
3. Limit each workload to its operational responsibility.
4. Preserve recoverable versions after accidental or malicious changes.
5. Prevent the normal Backup Writer from deleting protected recovery points.
6. Constrain access to the intended AWS account, bucket, and prefix.
7. Balance retention, recovery time, cost, and operational safety.
8. Produce auditable separation between backup writes, recovery reads, and security administration.

## 3. Threat model

The design considers:

- Compromise of the SQL Server or backup source host.
- Compromise of a recovery host.
- Stolen AWS credentials.
- Accidental overwrite or deletion.
- Ransomware using valid workload credentials.
- Malicious or mistaken IAM and bucket-policy changes.
- Insecure HTTP transport.
- Uncontrolled storage growth from current, noncurrent, and multipart data.
- Loss of access caused by a disabled or deleted customer-managed KMS key.
- Misconfigured retention that makes data undeletable longer than intended.

The model does not claim to protect against full compromise of every administrative control plane, AWS account root credentials, all organization administrators, and the KMS and S3 security administrators simultaneously. Production resilience requires organizational controls beyond a single bucket.

## 4. Why offsite backup is not automatically an air gap

Copying a backup from an on-premises or Azure-hosted SQL Server to Amazon S3 creates geographic and platform separation, but it does not automatically create an air gap.

If the source server retains online credentials that can overwrite or delete the S3 copy, ransomware or an attacker controlling that server can reach both the source and the backup. The backup is offsite but remains online and logically connected.

A stronger logical air gap requires layers such as:

- A Backup Writer that cannot read or delete existing backups.
- Versioning so overwrites create recoverable prior versions.
- Object Lock so protected versions cannot be deleted before retention expires.
- Separate security-administrator and recovery identities.
- No governance-bypass permission for ordinary workloads.
- Short-lived credentials and tightly controlled trust policies.
- Independent logging and alerting.
- For higher assurance, a separate backup account and controlled cross-account replication.

Physical offline media can provide a different kind of air gap. S3 immutability is an online, policy-enforced control and should be described as a logical air gap component, not as automatically offline storage.

## 5. Reference architecture

```text
SQL backup source server
  |
  | Backup Writer role
  | List designated prefix + PutObject + AbortMultipartUpload
  v
Amazon S3 backup bucket
  - Block Public Access
  - Versioning
  - default encryption
  - HTTPS-only bucket policy
  - lifecycle policy
  - Object Lock according to profile
  |
  | Recovery Reader role
  | List designated prefix + GetObject
  v
Isolated recovery host

Separate security administration
  - bucket configuration
  - KMS key administration
  - retention administration
  - governance bypass, if approved
  - lifecycle and policy changes
```

The Backup Writer and Recovery Reader policies are documented under `Scripts/iam/`.

## 6. Profile summary

| Control | LAB MODE | PRODUCTION-HARDENED MODE |
|---|---|---|
| Dedicated bucket | Required | Required; preferably dedicated backup account |
| Block Public Access | All four settings at bucket; account-level recommended | All four at organization/account and bucket |
| Object Ownership | Bucket owner enforced recommended | Bucket owner enforced |
| ACL use | None | None |
| Versioning | Enabled | Enabled; never suspend |
| Object Lock | Enabled only on a purpose-built lab bucket | Enabled after approved retention design |
| Default retention | Governance, 1 day | Governance or Compliance according to policy |
| Compliance mode | Do not use for lab objects | Use only for validated regulatory/business requirement |
| Legal hold | Not used | Controlled exception for investigations/litigation |
| Default encryption | SSE-S3 | SSE-KMS with customer-managed symmetric key |
| S3 Bucket Key | Not applicable to SSE-S3 | Enabled unless a documented constraint prevents it |
| IAM model | Separate Writer and Reader roles | Separate Writer, Reader, S3 admin, KMS admin, retention admin |
| HTTPS-only policy | Required | Required; minimum TLS policy recommended where compatible |
| Delete access | Not granted to Writer/Reader | Not granted to Writer/Reader |
| Governance bypass | Dedicated lab cleanup identity only | Break-glass retention admin only |
| Lifecycle | Short lab cleanup after retention | RPO/RTO/legal/cost-driven tiers |
| Logging | CloudTrail management events; data events recommended | CloudTrail data events, alerts, inventory, configuration monitoring |
| Cross-account copy | Optional learning extension | Recommended for higher resilience |

## 7. LAB MODE

### 7.1 Purpose

LAB MODE demonstrates private storage, least privilege, version recovery, encryption, and immutability while keeping cost and operational risk manageable.

### 7.2 Lab bucket isolation

Use a new, dedicated, disposable bucket only for the Object Lock exercise. Do not enable Object Lock on a shared training, application, log-delivery, or production bucket.

This is necessary because after Object Lock is enabled:

- Object Lock cannot be disabled for the bucket.
- Bucket versioning cannot be suspended.
- The bucket cannot be used as a destination for S3 server access logs.

The bucket itself can be deleted only after all protected versions, delete markers, and other objects become eligible and are removed.

### 7.3 Lab Block Public Access

Enable all four S3 Block Public Access settings on the bucket:

- Block public ACLs.
- Ignore public ACLs.
- Block new public bucket or access-point policies.
- Restrict public bucket or access-point policies.

Also enable account-level Block Public Access when the training account does not intentionally host public S3 content.

BackupBridge has no public-access requirement.

### 7.4 Lab versioning

Enable S3 Versioning.

Learners should demonstrate:

1. Upload version 1 of a test backup.
2. Upload different content to the same key.
3. Observe version 2 becoming current.
4. Confirm version 1 remains recoverable.
5. Add a delete marker without permanently deleting protected versions.
6. Recover by removing the delete marker using a separately authorized lab administrator.

Versioning strengthens resilience by preserving earlier object versions after overwrite and by making an unversioned delete create a delete marker rather than immediately destroying all history. Versioning alone is not immutability: a principal with version-deletion permission can permanently delete a specific version.

### 7.5 Lab Object Lock recommendation

Use:

- Object Lock: enabled at bucket creation.
- Default retention: enabled.
- Mode: **Governance**.
- Period: **1 day**.
- Legal hold: disabled.
- Compliance mode: not used.
- Test files: small synthetic `.bak` and `.trn` files only.
- Cleanup authority: a dedicated lab administrator, not the Backup Writer or Recovery Reader.
- Cleanup permission: `s3:BypassGovernanceRetention` only for that lab administrator and only on the lab bucket.

Why one day:

- It is long enough to demonstrate that ordinary deletion and version deletion are blocked.
- It limits storage cost and delays before normal cleanup.
- It avoids a multiweek lock caused by a learner entering an excessive retention period.
- Governance mode retains a controlled recovery path for an authorized instructor if a lab must be reset.

Before enabling Object Lock, verify the account date/time, intended bucket, default duration, and cleanup identity. Do not use a wildcard governance-bypass policy.

### 7.6 Governance Mode

Governance Mode protects an object version from overwrite or deletion unless the caller has `s3:BypassGovernanceRetention` and explicitly requests bypass.

Use Governance Mode for:

- Labs and preproduction validation.
- Environments where emergency override is required.
- Retention policies not governed by immutable regulatory rules.

The Backup Writer, Recovery Reader, normal operators, and automation must not have bypass permission.

### 7.7 Compliance Mode

Do not apply Compliance Mode to lab objects.

In Compliance Mode:

- A protected version cannot be deleted by any IAM principal.
- The AWS account root user cannot delete it.
- Retention mode cannot be changed.
- Retention cannot be shortened.
- Early deletion is not an operational recovery option.

Compliance Mode should be explained and, if desired, demonstrated through screenshots or instructor-provided evidence rather than by locking learner-created resources. It is appropriate only after legal, regulatory, retention, cost, and operational approval.

### 7.8 Lab encryption

Use default SSE-S3.

All new S3 objects receive a baseline of SSE-S3 automatically, but explicitly retaining SSE-S3 as the bucket default makes the lab intent visible and teachable.

Benefits:

- No KMS key policy is required.
- No KMS request charges.
- Lower risk of making backups unreadable through key disablement or deletion.
- Sufficient for demonstrating server-side encryption.

Tradeoff:

- It does not provide customer-controlled key policies, independent key disablement, or per-key CloudTrail audit boundaries.

### 7.9 Lab IAM

Use distinct roles or profiles:

- Backup Writer: prefix-scoped `ListBucket`, `PutObject`, and `AbortMultipartUpload`.
- Recovery Reader: prefix-scoped `ListBucket` and `GetObject`.
- Lab Security Administrator: bucket configuration and approved Governance bypass.
- No `DeleteObject` or `DeleteObjectVersion` for Writer or Reader.

Use short-lived credentials where practical. Do not embed access keys in `settings.json` or scripts.

### 7.10 Lab lifecycle

Recommended starting pattern:

- Abort incomplete multipart uploads after 1 day.
- Do not transition the small training objects to Glacier classes.
- Expire current and noncurrent versions only after Governance retention has expired and the exercise evidence is complete.
- Use a short total lab retention, such as 7 days, where the training account's cleanup policy allows it.

Lifecycle expiration cannot delete a version while Object Lock retention or legal hold still protects it. A lifecycle rule is not an override for Object Lock.

## 8. PRODUCTION-HARDENED MODE

### 8.1 Account and bucket isolation

Use a dedicated backup bucket. For higher assurance, place the bucket in a dedicated backup or security account separate from the workload account.

Cross-account design improves resilience because compromise of the source workload account does not automatically grant administration over the destination bucket, KMS key, retention settings, or protected versions.

Use an organization-controlled deployment pipeline and prevent workload administrators from changing the backup bucket policy, lifecycle, Object Lock, or KMS key.

### 8.2 Production Block Public Access

Enable all four Block Public Access settings:

- At AWS Organizations level where feasible.
- At account level.
- At bucket level.

Continuously evaluate the settings with AWS Config/Security Hub or equivalent controls. BackupBridge does not need public access, website hosting, public ACLs, or anonymous principals.

Use S3 Object Ownership with bucket owner enforced so ACLs are disabled and authorization is policy-based.

### 8.3 Production versioning

Enable Versioning before ingesting production backups.

Versioning:

- Preserves previous content after a same-key overwrite.
- Allows recovery after delete-marker creation.
- Is required by Object Lock.
- Supports version-specific forensic and recovery workflows.

Do not grant Writer or Reader:

- `s3:DeleteObjectVersion`.
- `s3:ListBucketVersions` unless a separately approved version-recovery workflow requires it.
- Permission to suspend versioning.

Versioning increases storage usage. Lifecycle rules must explicitly address noncurrent versions after retention requirements are satisfied.

### 8.4 Production Object Lock

Enable Object Lock only after completing:

- Business retention approval.
- Legal and regulatory review.
- RPO and RTO analysis.
- Storage-growth and cost modeling.
- Lifecycle compatibility testing.
- Recovery exercises.
- Governance-bypass or Compliance-mode decision.
- Administrative and break-glass runbooks.

Use immutable object versions for the required retention window. The bucket's default retention ensures ordinary uploads inherit protection without requiring the Backup Writer to hold `PutObjectRetention`.

Do not grant the Backup Writer:

- `s3:DeleteObject`.
- `s3:DeleteObjectVersion`.
- `s3:PutObjectRetention`.
- `s3:PutObjectLegalHold`.
- `s3:BypassGovernanceRetention`.

The writer's job is to add backup data, not control its destruction or retention.

### 8.5 Choosing Governance or Compliance

#### Governance recommendation

Use Governance Mode when:

- The business requires immutability against workloads and normal administrators.
- A formally controlled emergency override must remain possible.
- Retention has not been established as an unalterable regulatory requirement.

Place `s3:BypassGovernanceRetention` in a separate break-glass role:

- No standing assignment to humans or workloads.
- MFA and short session duration.
- Approval workflow.
- Restricted bucket and prefix.
- CloudTrail alerting on role assumption and bypass requests.
- No access from the source or recovery host.

#### Compliance recommendation

Use Compliance Mode when:

- A legal, regulatory, or contractual requirement mandates non-bypassable WORM retention.
- The exact retention period is approved.
- Cost and data-residency impacts are understood.
- Operational teams accept that neither administrators nor root can shorten retention or delete protected versions early.

Do not choose Compliance Mode merely because it sounds more secure. Incorrect retention can make data impossible to remove until expiry. Start with a dedicated preproduction Governance-mode design and promote to Compliance only after validation.

### 8.6 Production default encryption

Recommended default:

- SSE-KMS.
- Customer-managed symmetric KMS key.
- Fully qualified key ARN.
- Automatic key rotation where compatible with policy.
- S3 Bucket Key enabled.

SSE-S3 remains cryptographically strong and is the lower-complexity option. Production should choose SSE-KMS when the organization requires customer-controlled key policy, separation of key administration, revocation boundaries, or KMS audit evidence.

Do not use SSE-C for BackupBridge. Customer-provided data keys increase operational and recovery risk and are unnecessary for the documented workflow.

### 8.7 Customer-managed KMS key model

Use a dedicated KMS key for the backup domain or environment. Avoid sharing the key with unrelated applications.

Separate duties:

- KMS administrators can manage key configuration but should not automatically decrypt backup data.
- Backup Writer receives only the cryptographic permissions required to write encrypted objects.
- Recovery Reader receives only the permissions required to decrypt recovery objects.
- S3 security administrators should not automatically administer the KMS key.
- Key deletion scheduling requires a separate break-glass/change-control process.

Typical workload permissions must be validated with CloudTrail and the exact S3 workflow:

- Writer: commonly `kms:GenerateDataKey`; multipart and checksum behavior can require `kms:Decrypt`.
- Reader: `kms:Decrypt`.
- Both: exact key ARN and `kms:ViaService` constrained to S3 in the selected Region where appropriate.
- Use encryption-context conditions that bind use to the backup bucket/prefix where the operation supports them.

Never grant `kms:*`. Never allow the Backup Writer to administer, disable, or schedule deletion of the key.

KMS availability is part of backup availability. A disabled or deleted key can make SSE-KMS data unrecoverable. Protect the key policy, monitor state changes, use deletion waiting periods, and test recovery.

### 8.8 S3 Bucket Keys

Enable an S3 Bucket Key with default SSE-KMS unless a documented compatibility or audit requirement prevents it.

Benefits:

- Reduces direct request traffic from S3 to KMS.
- Reduces KMS request cost for high-volume backup objects.

Tradeoffs:

- Changes the KMS request and audit pattern; CloudTrail may show fewer object-level KMS events.
- Does not remove the need for correct KMS key and IAM policies.
- Applies to new objects according to bucket/object settings; existing objects require a separate approved re-encryption process if they must adopt the setting.

### 8.9 Production IAM separation of duties

Minimum identities:

1. **Backup Writer**
   - List designated prefix.
   - Put objects into the prefix.
   - Abort failed multipart uploads.
   - KMS write-use permissions when SSE-KMS is enabled.
   - No read, delete, retention, governance-bypass, or administration.

2. **Recovery Reader**
   - List recovery prefix.
   - Get current objects.
   - KMS decrypt when SSE-KMS is enabled.
   - No write, delete, retention, or administration.

3. **S3 Security Administrator**
   - Manages bucket configuration, policies, lifecycle, and monitoring.
   - Does not automatically receive object-content access.

4. **KMS Administrator**
   - Manages the customer-managed key.
   - Does not automatically receive S3 object access or routine decrypt permission.

5. **Retention/Break-glass Administrator**
   - Governance bypass only when Governance Mode is selected.
   - No standing workload use.
   - MFA, approval, time-limited session, and alerting.

6. **Recovery Coordinator**
   - Assumes Recovery Reader only during controlled recovery tests or incidents.

Use role trust policies, permission boundaries, SCPs, session policies, and VPC endpoint policies as defense in depth. Avoid IAM users with long-lived access keys.

### 8.10 Why the Backup Writer should not delete backups

The source server is a high-risk identity because it processes production data and runs scheduled automation. If it can delete backup objects or versions, compromise of the source can destroy the recovery path.

The Backup Writer should normally be append/update capable but not destruction capable:

- No `s3:DeleteObject`.
- No `s3:DeleteObjectVersion`.
- No `s3:BypassGovernanceRetention`.
- No retention-policy changes.
- No bucket-policy or lifecycle changes.

Versioning and Object Lock ensure that even when the Writer uploads a new version to the same key, protected earlier versions remain recoverable.

### 8.11 Bucket policy

The bucket policy is a guardrail, not a replacement for least-privilege identity policies.

Required production guardrails:

- Explicitly deny non-TLS requests using `aws:SecureTransport = false`.
- Restrict allowed principals to approved workload and administration roles.
- Restrict access to the expected AWS account or organization.
- Deny attempts to use public ACLs where ACLs are not already disabled.
- When SSE-KMS is mandatory, deny writes that do not use the approved encryption configuration, while confirming compatibility with bucket default encryption and the uploader.
- Deny destructive operations by workload roles.
- Where supported by the network design, restrict workload access through an approved S3 VPC endpoint.
- Protect policy and Object Lock configuration changes through identity controls and SCPs.

HTTPS-only conceptual statement:

```json
{
  "Sid": "DenyInsecureTransport",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": [
    "arn:aws:s3:::<BUCKET_NAME>",
    "arn:aws:s3:::<BUCKET_NAME>/*"
  ],
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

This is an example fragment, not a complete deployable bucket policy.

If enforcing a minimum TLS version, test all AWS CLI, SDK, replication, inventory, monitoring, and service integrations before deployment.

### 8.12 HTTPS-only access

All BackupBridge data-plane traffic must use HTTPS/TLS. The AWS CLI does this by default, but a bucket-policy explicit deny prevents accidental or malicious HTTP access regardless of client configuration.

Do not use `--no-verify-ssl`. If enterprise TLS inspection is required, deploy and reference an approved CA bundle rather than disabling certificate validation.

### 8.13 Production lifecycle management

Lifecycle policy must align with:

- Full, differential, and transaction-log recovery chains.
- RPO and point-in-time recovery requirements.
- RTO and storage-class restore latency.
- Legal and regulatory retention.
- Object Lock retain-until dates.
- Noncurrent versions.
- Cost forecasts.
- Replication status, if cross-account replication is used.

Illustrative pattern only:

- Keep recent restore-chain data in S3 Standard or Intelligent-Tiering for rapid recovery.
- Transition older eligible versions to Glacier Instant Retrieval, Flexible Retrieval, or Deep Archive only when their retrieval time and minimum-duration charges meet RTO and cost requirements.
- Retain noncurrent versions through the ransomware-recovery window.
- Expire current and noncurrent versions only after retention obligations expire.
- Abort incomplete multipart uploads after an approved short interval such as 7 days.
- Remove expired delete markers when safe.
- Keep at least the required complete FULL/DIFF/LOG chain in a recovery-compatible tier.

Do not independently expire transaction logs without verifying that the remaining chain can meet point-in-time recovery objectives.

Object Lock takes precedence over lifecycle deletion: lifecycle cannot permanently delete a protected version before retention expires or while legal hold is active.

### 8.14 Retention considerations

Retention is not a single number. Define:

- Operational fast-recovery window.
- Ransomware dwell-time window.
- Monthly/quarterly/yearly archival requirements.
- Legal and regulatory minimums and maximums.
- Database-specific RPO/RTO.
- Expected daily full, differential, and log volume.
- Version-growth from same-key updates.
- Restore testing frequency.
- KMS and archival retrieval costs.
- Right-to-delete or data-minimization obligations where applicable.

Use immutable, timestamped object keys to reduce accidental overwrite and simplify chain selection. Bucket default retention protects each new version independently.

Periodically prove that retained objects form a restorable SQL Server chain. Storage retention without recovery validation is not sufficient.

## 9. Ransomware resilience

### 9.1 Versioning

Versioning strengthens resilience because an overwrite creates a new object version and a simple delete creates a delete marker. Earlier versions can remain recoverable.

Limit: versioning does not stop an identity with `DeleteObjectVersion` from permanently deleting a specific version.

### 9.2 Object Lock

Object Lock adds WORM protection to specified versions. During retention, protected versions resist deletion or overwrite according to Governance or Compliance semantics.

Limit: Object Lock does not prevent new versions or delete markers from being created. Recovery procedures must identify and retrieve the correct protected version.

### 9.3 Combined effect

Together:

- Ransomware may upload encrypted replacements, but prior versions remain.
- A compromised Writer lacks version deletion.
- Object Lock prevents protected versions from being permanently removed during the retention window.
- Separate recovery credentials allow restoration without giving the source host read access.

This is materially stronger than an ordinary offsite copy with shared read/write/delete credentials.

## 10. Lifecycle and retention flow

```text
Upload immutable timestamped backup
  -> current hot recovery window
  -> optional colder storage transition
  -> noncurrent/protected retention window
  -> retention expires
  -> lifecycle eligibility
  -> controlled expiration

Incomplete multipart upload
  -> short grace period
  -> lifecycle abort
```

Lifecycle must never be treated as the source of retention truth. Object Lock and approved retention policy define the minimum protection period; lifecycle manages data after it becomes eligible.

## 11. Assumptions

- BackupBridge continues to use AWS CLI v2.
- The uploader never passes `--delete`.
- The downloader never deletes S3 data.
- The destination is a general-purpose S3 bucket.
- Production deployment will be performed through reviewed Infrastructure as Code.
- Bucket names, prefixes, account IDs, and KMS ARNs will be parameterized.
- CloudTrail, AWS Config, Security Hub, and alerting design will be addressed in the production implementation.
- Cross-account replication is a recommended extension, not provisioned by this document.

## 12. Architectural tradeoffs

| Decision | Benefit | Cost/risk |
|---|---|---|
| SSE-S3 | Simple, no KMS request cost, low lockout risk | Less customer control and separation |
| SSE-KMS customer-managed key | Key policy, revocation boundary, auditability | Cost, policy complexity, key-loss risk |
| S3 Bucket Key | Lower KMS cost and request volume | Fewer direct KMS request events |
| Versioning | Recover overwrite/delete history | Additional storage and lifecycle complexity |
| Governance Object Lock | Strong immutability with controlled override | Bypass role becomes sensitive |
| Compliance Object Lock | Non-bypassable retention | Incorrect retention cannot be shortened |
| Same-account bucket | Simpler deployment | Workload account compromise has broader reach |
| Separate backup account | Stronger control-plane isolation | Cross-account IAM/KMS/operations complexity |
| Cold archive transition | Lower storage cost | Retrieval latency and charges |
| Immutable timestamped keys | Clear chains and reduced overwrite risk | More objects and inventory management |

## 13. Deployment flow

No deployment is authorized by this document.

A future approved implementation should:

1. Approve LAB or PRODUCTION-HARDENED profile.
2. Confirm account, Region, bucket, prefix, RPO, RTO, and retention.
3. Complete legal/regulatory review for Object Lock mode and duration.
4. Model storage, KMS, archive, and recovery costs.
5. Define roles, trust policies, permission boundaries, SCPs, and break-glass access.
6. Define bucket, KMS key, bucket policy, lifecycle, logging, and monitoring as Infrastructure as Code.
7. Validate policies with IAM Access Analyzer.
8. Deploy to a non-production account.
9. Run upload, overwrite, delete, version-recovery, retention, KMS, and restore tests.
10. Review CloudTrail and AWS Config evidence.
11. Conduct a SQL Server recovery exercise.
12. Obtain change approval before production deployment.

## 14. Validation checklist

### LAB MODE

- All four Block Public Access settings enabled.
- Versioning enabled.
- Object Lock enabled only on the dedicated disposable bucket.
- Governance default retention exactly 1 day.
- No legal hold.
- No Compliance-mode objects.
- Writer and Reader lack delete/version-delete permissions.
- Only dedicated lab admin can bypass Governance retention.
- HTTPS-only bucket-policy deny validated.
- Version recovery and delete-marker recovery demonstrated.
- Cleanup succeeds only after retention or approved Governance bypass.

### PRODUCTION-HARDENED MODE

- Dedicated bucket and preferably dedicated backup account.
- Organization/account/bucket Block Public Access.
- Bucket owner enforced Object Ownership.
- Versioning and approved Object Lock configuration.
- Default retention matches approved policy.
- Writer cannot read, delete, bypass, or alter retention.
- Reader cannot write or delete.
- Customer-managed KMS key has separated administration and usage.
- S3 Bucket Key enabled and audit impact accepted.
- HTTPS-only policy and optional minimum TLS control tested.
- Lifecycle aligns with FULL/DIFF/LOG chain, RPO, RTO, and retention.
- Noncurrent versions and incomplete multipart uploads addressed.
- CloudTrail data events and security alerts enabled.
- Key disablement/deletion alerts enabled.
- Restore from protected versions tested.
- No broad `s3:*` or `kms:*` workload permissions.

## 15. Troubleshooting and operational cautions

### Bucket cannot be cleaned up after a lab

Check protected versions, retain-until dates, legal holds, delete markers, and incomplete multipart uploads. Object Lock cannot be disabled after enablement.

### Governance deletion unexpectedly succeeds

Determine whether the caller has `s3:BypassGovernanceRetention` and whether the request explicitly enabled bypass. Remove this permission from routine roles.

### Compliance object cannot be deleted

This is expected before its retain-until date. Retention cannot be shortened. Do not attempt to work around the control.

### Writer receives AccessDenied with SSE-KMS

Review both the IAM policy and KMS key policy. Validate exact key ARN, Region, `kms:GenerateDataKey`, and any multipart-related decrypt requirement using CloudTrail.

### Reader cannot download SSE-KMS objects

Verify `s3:GetObject`, `kms:Decrypt`, the key policy, encryption context, key state, and account/prefix restrictions.

### Lifecycle does not delete an object version

Check Object Lock retention, legal hold, replication status, noncurrent-version settings, and lifecycle filters. Protected versions are intentionally not deleted early.

### Archive restore misses RTO

Move the operational recovery window to a faster storage class and retest. Storage-cost optimization must not violate recovery objectives.

## 16. AWS references

- [S3 Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [S3 Versioning recovery](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshooting-versioning.html)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [Object Lock considerations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html)
- [Default S3 encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-encryption.html)
- [SSE-KMS and S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/specifying-kms-encryption.html)
- [Reducing SSE-KMS cost with S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html)
- [HTTPS-only bucket policy](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
- [S3 Lifecycle elements](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intro-lifecycle-rules.html)
