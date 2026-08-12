# BackupBridge IAM Separation of Duties

## Architecture overview

BackupBridge uses two independent IAM identities:

```text
SQL backup source server
  -> Backup Writer role/identity
  -> s3://<BUCKET_NAME>/<PREFIX>/

Recovery host
  -> Recovery Reader role/identity
  -> s3://<BUCKET_NAME>/<PREFIX>/
```

The Backup Writer can list only the designated prefix and upload objects into it. The Recovery Reader can list only that prefix and download its objects. Neither example grants object deletion, bucket administration, ACL management, policy management, or broad `s3:*` access.

These files are identity-based policy examples. They do not create roles, users, instance profiles, bucket policies, or AWS resources.

## Files

- `backup-writer-policy.json`: attach only to the source-server workload identity.
- `recovery-reader-policy.json`: attach only to the recovery workload identity.

The older `Scripts/cvt-s3-policy.json` combines upload, download, and delete permissions across an entire bucket. It should not be used as the production permission model for the separated roles.

## Placeholders

Replace these placeholders during an approved deployment:

| Placeholder | Meaning | Example format |
|---|---|---|
| `<ACCOUNT_ID>` | AWS account that owns the S3 bucket | Twelve-digit account ID |
| `<BUCKET_NAME>` | Existing backup bucket name only | `example-sql-backups` |
| `<PREFIX>` | Backup/recovery key prefix without leading or trailing slash | `backupbridge/production` |

Do not put `s3://` in `<BUCKET_NAME>`. Keep `<PREFIX>` identical to the prefix configured for the uploader and downloader.

S3 ARNs do not contain an account ID. The policies use `aws:ResourceAccount` to ensure the selected bucket is owned by `<ACCOUNT_ID>`.

## Backup Writer policy

### Purpose

The Backup Writer is intended for `S3_Uploader.ps1` running on the SQL backup source server. It supports local-to-S3 `aws s3 sync` without granting recovery or deletion capabilities.

### Included permissions

#### `s3:ListBucket`

Resource:

```text
arn:aws:s3:::<BUCKET_NAME>
```

Why it is needed:

`aws s3 sync` lists destination objects to determine which local files are new or changed. `ListBucket` is a bucket-level action, so its resource must be the bucket ARN rather than an object ARN.

The `s3:prefix` condition limits listing to:

```text
<PREFIX>
<PREFIX>/*
```

The writer cannot use this statement to enumerate unrelated prefixes.

#### `s3:PutObject`

Resource:

```text
arn:aws:s3:::<BUCKET_NAME>/<PREFIX>/*
```

Why it is needed:

It authorizes new or updated backup objects beneath the designated prefix. For multipart transfers, `PutObject` is the IAM action used by create-multipart-upload, upload-part, and complete-multipart-upload operations.

It does not grant permission to read, delete, tag, change ACLs, or administer the bucket.

#### `s3:AbortMultipartUpload`

Resource:

```text
arn:aws:s3:::<BUCKET_NAME>/<PREFIX>/*
```

Why it is needed:

It allows AWS CLI to stop and clean up a multipart upload that cannot be completed. Without cleanup, uploaded parts can remain billable until removed by an authorized operation or lifecycle rule.

It cannot abort multipart uploads outside the designated prefix.

### Deliberately excluded

- `s3:GetObject`: recovery/read capability is not required by local-to-S3 sync.
- `s3:DeleteObject` and `s3:DeleteObjectVersion`: the uploader does not use `--delete`.
- `s3:ListAllMyBuckets`: the workload already knows its bucket.
- `s3:GetBucketLocation`: the scripts pass an explicit AWS Region.
- `s3:ListBucketMultipartUploads`: normal AWS CLI transfer does not need bucket-wide enumeration of in-progress uploads.
- `s3:ListMultipartUploadParts`: not pre-granted because the CLI tracks parts for its own active transfer. Add it only if testing and CloudTrail prove it necessary for the deployed CLI behavior.
- ACL, tagging, retention, legal-hold, policy, lifecycle, encryption-configuration, replication, and bucket-administration actions.
- `s3:*`.

## Recovery Reader policy

### Purpose

The Recovery Reader is intended for `S3_Downloader.ps1` running on an isolated recovery host. It supports S3-to-local `aws s3 sync`.

### Included permissions

#### `s3:ListBucket`

Resource:

```text
arn:aws:s3:::<BUCKET_NAME>
```

Why it is needed:

The downloader must list the configured prefix to identify candidate objects and compare them with the local recovery directory. The `s3:prefix` condition prevents listing unrelated keys.

#### `s3:GetObject`

Resource:

```text
arn:aws:s3:::<BUCKET_NAME>/<PREFIX>/*
```

Why it is needed:

It authorizes downloading the current version of backup objects beneath the recovery prefix. It is also sufficient for AWS CLI checksum validation during `GetObject` when stored checksum metadata is available.

### Deliberately excluded

- `s3:PutObject`: a recovery host should not alter backup objects.
- `s3:DeleteObject` and `s3:DeleteObjectVersion`: recovery must not destroy evidence or recovery points.
- `s3:GetObjectVersion`: not required when restoring only current object versions. Add a separately scoped recovery policy if version-specific recovery is required.
- `s3:ListBucketVersions`: not required for current-version sync.
- Multipart upload permissions: the reader does not upload.
- Bucket administration, ACL, tagging, retention, legal-hold, lifecycle, replication, or policy actions.
- `s3:*`.

## Account ownership condition

Both policies use:

```json
"StringEquals": {
  "aws:ResourceAccount": "<ACCOUNT_ID>"
}
```

This reduces the risk of credentials being redirected to a same-named or mistakenly configured bucket in another AWS account. It does not replace exact bucket and prefix ARNs; it complements them.

If these identities also access AWS-managed S3 buckets for unrelated services, keep those permissions in separate policies because the account-ownership condition can intentionally block buckets not owned by `<ACCOUNT_ID>`.

## Blast-radius benefits

Separating the identities prevents one compromised workload from acquiring the complete backup lifecycle:

| Compromised identity | Possible within its prefix | Not granted |
|---|---|---|
| Backup Writer | List and upload objects; abort its failed multipart uploads | Read backups, delete objects, administer bucket |
| Recovery Reader | List and download current backup objects | Upload, overwrite, delete, administer bucket |

Key benefits:

1. A compromised source server cannot normally exfiltrate existing backups through `GetObject`.
2. A compromised recovery host cannot overwrite or poison cloud backups with `PutObject`.
3. Neither role can delete recovery points.
4. Prefix scoping limits exposure when a bucket stores multiple environments, servers, or tenants.
5. Independent roles produce clearer CloudTrail attribution for backup versus recovery activity.
6. Recovery credentials can remain disabled, unassigned, or tightly controlled until a recovery exercise or incident.
7. Each policy can have independent session duration, MFA, network, permission-boundary, and monitoring controls.

Separation of duties does not protect against every threat. The writer can overwrite an existing key because `PutObject` is required by `sync`. Use immutable key naming plus independently reviewed S3 Versioning and, where required, Object Lock to protect prior recovery points. Those controls are outside these example identity policies.

## Encryption tradeoff

These S3-only examples assume SSE-S3, an AWS managed S3 key, or an existing bucket configuration that does not require direct access to a customer-managed KMS key.

If the bucket requires SSE-KMS with a customer-managed key, add a separate key policy/IAM statement scoped to the exact KMS key:

- Backup Writer: typically `kms:GenerateDataKey`; multipart workflows may also require `kms:Decrypt` depending on the operation and checksum/encryption behavior.
- Recovery Reader: `kms:Decrypt`.

Use an exact ARN such as:

```text
arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/<KMS_KEY_ID>
```

Do not add `kms:*` or a wildcard key resource. Validate the exact operations with CloudTrail in a non-production test.

## Assumptions and tradeoffs

- The bucket already exists.
- The same designated prefix is configured in BackupBridge settings.
- The scripts always pass the expected Region.
- The uploader never uses `--delete`.
- The downloader performs current-version recovery rather than version-ID selection.
- The bucket policy, VPC endpoint policy, AWS Organizations SCPs, permission boundaries, and KMS key policy must also allow the intended requests.
- An explicit deny elsewhere overrides these allows.
- These examples do not include console-only permissions because BackupBridge uses AWS CLI v2.
- Root-prefix operation is intentionally not modeled. Use a nonempty dedicated prefix to maintain isolation.

## Deployment flow

No deployment is performed by this repository change.

For an approved deployment:

1. Replace all placeholders offline.
2. Validate both JSON documents syntactically.
3. Run IAM Access Analyzer policy validation.
4. Create two separate workload roles or identities.
5. Attach only the writer policy to the source-server identity.
6. Attach only the reader policy to the recovery identity.
7. Confirm the configured bucket owner account, bucket, prefix, and Region.
8. Test in a non-production prefix.
9. Review CloudTrail for denied or unexpected actions.
10. Promote through the normal Infrastructure as Code and change-control process.

Prefer Terraform or CloudFormation for deployed roles, trust policies, instance profiles, permission boundaries, and policy attachments. These JSON files are permission-policy examples, not a complete identity deployment.

## Validation steps

### Static policy validation

Confirm:

- No `s3:*`.
- No `s3:DeleteObject` or `s3:DeleteObjectVersion`.
- Writer has no `s3:GetObject`.
- Reader has no `s3:PutObject`.
- Bucket listing is conditioned by `s3:prefix`.
- Object resources end in `/<PREFIX>/*`.
- `aws:ResourceAccount` uses the expected bucket-owner account.

### Writer positive tests

- List the designated prefix.
- Upload a small backup.
- Upload a file large enough to trigger multipart transfer.
- Rerun sync and confirm unchanged objects are skipped.

### Writer negative tests

- Attempt to list an unrelated prefix.
- Attempt `GetObject`.
- Attempt `DeleteObject`.
- Attempt upload outside the designated prefix.
- Attempt bucket-policy or lifecycle changes.

All negative tests must be denied.

### Reader positive tests

- List the designated prefix.
- Download a current backup object.
- Validate checksum mode when stored checksum metadata exists.

### Reader negative tests

- Attempt to list an unrelated prefix.
- Attempt `PutObject`.
- Attempt `DeleteObject`.
- Attempt download outside the designated prefix.
- Attempt bucket administration.

All negative tests must be denied.

## Troubleshooting

### AccessDenied during sync listing

Verify that:

- `s3:ListBucket` uses the bucket ARN.
- The script's configured prefix matches `<PREFIX>`.
- The requested prefix matches either `<PREFIX>` or `<PREFIX>/*`.
- The bucket is owned by `<ACCOUNT_ID>`.
- No SCP, permission boundary, session policy, bucket policy, or VPC endpoint policy denies the request.

### AccessDenied during upload

Verify `s3:PutObject` is scoped to the exact object ARN and check whether a customer-managed KMS key requires additional permissions.

### Multipart upload cannot be cleaned up

Verify `s3:AbortMultipartUpload` applies to the intended object prefix. Use CloudTrail to determine whether a narrowly scoped `s3:ListMultipartUploadParts` exception is actually required.

### AccessDenied during download

Verify `s3:GetObject`, the exact object key, bucket ownership condition, bucket policy, and any KMS key policy.

### Checksum is not reported

`--checksum-mode ENABLED` validates an object only when compatible checksum metadata is stored. Legacy objects may not have such metadata; absence of a checksum is not fixed by adding IAM permissions.
