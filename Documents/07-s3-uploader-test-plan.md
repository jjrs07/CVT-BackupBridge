# S3 Uploader Test Plan

## 1. Purpose

This plan validates the refactored `Scripts/powershell/S3_Uploader.ps1`, which uses AWS CLI v2 `aws s3 sync` to upload SQL Server backup files.

The plan verifies configuration validation, file filtering, path preservation, idempotent reruns, AWS failure handling, structured logging, scheduler-visible exit codes, UNC access, and multipart transfers.

## 2. Scope and safety

- Test only the uploader. `S3_Downloader.ps1` is out of scope.
- Do not change AWS infrastructure automatically.
- Use a non-production AWS account and an existing disposable bucket or prefix.
- Do not change bucket policies, IAM policies, versioning, Object Lock, encryption, lifecycle policies, or networking as part of automated execution.
- Use a unique prefix such as `s3://existing-test-bucket/cvt-uploader-tests/<run-id>/`.
- Simulate credential and network failures only in isolated test processes or on a lab host.
- Never delete or rename the operator's normal AWS credential files.
- Tests may create and remove synthetic local files and may upload test objects only to the approved disposable prefix.
- Cleanup of test objects must be a separately approved activity. The uploader itself must never use `--delete`.

## 3. Prerequisites

- Windows PowerShell 5.1.
- AWS CLI v2 available for positive tests.
- An existing test bucket/prefix.
- A test identity with the minimum permissions needed for positive tests, normally scoped `s3:ListBucket` and `s3:PutObject`.
- A dedicated local source directory.
- A dedicated log directory.
- A test `settings.json`.
- Read-only validation access using `s3api head-object` and `s3api list-objects-v2`.
- A service account or equivalent identity for the UNC-path test.

## 4. Execution and evidence

Run the uploader and capture its process exit code immediately:

```powershell
powershell.exe -NoProfile -File .\Scripts\powershell\S3_Uploader.ps1
$actualExitCode = $LASTEXITCODE
```

Collect this evidence for every test:

- Test ID and execution timestamp.
- Sanitized `settings.json`.
- Local source inventory with relative path, byte length, and modification time.
- Console output.
- Relevant records from `S3Upload.log`.
- Actual process exit code.
- S3 object inventory beneath the test prefix.
- Object `ContentLength`, ETag, checksum metadata when available, and version ID when applicable.
- Pass or fail decision with notes.

Do not treat a multipart ETag as the MD5 hash of the complete file.

## 5. AWS CLI exit-code reference

| Code | Meaning relevant to this plan |
|---:|---|
| 0 | Command completed successfully. |
| 1 | One or more S3 transfers failed. |
| 2 | CLI parsing failure or one or more S3 files were skipped. |
| 252 | Invalid syntax, unknown parameter, or invalid parameter value. |
| 253 | Invalid local configuration or credentials were unavailable. |
| 254 | AWS processed the request and returned a service error. |
| 255 | General runtime or connectivity failure. |

Where AWS CLI versions can classify the same failure differently, the test requires a nonzero result and exact propagation of the actual `$LASTEXITCODE` into the script's exit code and final log record.

## 6. Test scenarios

### TC-01: Source directory does not exist

**Setup**

Configure a nonexistent `BackupRootPath`. Keep all other settings valid.

**Action**

Run the uploader.

**Expected result**

Execution stops before AWS CLI synchronization. No S3 object is created.

**Expected exit code**

`1`

**Expected log message**

Current implementation writes no structured log entry. Console error contains:

```text
Source directory does not exist or is not accessible
```

**Pass/fail criteria**

Pass if the exit code is 1, AWS CLI synchronization is not invoked, no object is created, and the console reports the missing source. Fail if the script returns 0 or attempts a transfer.

### TC-02: Source directory is empty

**Setup**

Create an empty source directory and select an unused S3 prefix.

**Action**

Run the uploader.

**Expected result**

No object is created. The sync completes successfully because there is no eligible work.

**Expected exit code**

`0`

**Expected log message**

```text
event=SYNC_START
event=TRANSFER_POLICY
event=SYNC_COMPLETE
ExitCode=0
FinalResult=SUCCESS
```

There should normally be no upload-related `AWS_CLI_OUTPUT` entry.

**Pass/fail criteria**

Pass if no object exists under the prefix and the final result is success. Fail if an object is created or the script fails.

### TC-03: One new BAK file

**Setup**

Create:

```text
<source>\DatabaseA\FULL\DatabaseA_FULL_001.bak
```

Use a new S3 prefix.

**Action**

Run the uploader.

**Expected result**

One object is created at:

```text
<prefix>/DatabaseA/FULL/DatabaseA_FULL_001.bak
```

The S3 content length equals the local byte length.

**Expected exit code**

`0`

**Expected log message**

```text
event=AWS_CLI_OUTPUT message="upload:
event=SYNC_COMPLETE message="ExitCode=0 ... FinalResult=SUCCESS"
```

**Pass/fail criteria**

Pass if exactly one object exists at the expected key with the correct size. Fail on omission, unexpected upload, or path flattening.

### TC-04: One new TRN file

**Setup**

Create:

```text
<source>\DatabaseA\LOG\DatabaseA_LOG_001.trn
```

**Action**

Run the uploader.

**Expected result**

One object is created with the same relative path and byte length.

**Expected exit code**

`0`

**Expected log message**

An upload event references `DatabaseA_LOG_001.trn`, followed by a successful `SYNC_COMPLETE`.

**Pass/fail criteria**

Pass if the expected object exists with matching size. Fail if it is absent, renamed, or placed under a different hierarchy.

### TC-05: Multiple databases

**Setup**

Create:

```text
<source>\DatabaseA\FULL\DatabaseA_FULL_001.bak
<source>\DatabaseA\LOG\DatabaseA_LOG_001.trn
<source>\DatabaseB\FULL\DatabaseB_FULL_001.bak
<source>\DatabaseB\LOG\DatabaseB_LOG_001.trn
```

**Action**

Run the uploader.

**Expected result**

All four files upload under their respective database paths.

**Expected exit code**

`0`

**Expected log message**

Four upload-related `AWS_CLI_OUTPUT` records and a successful `SYNC_COMPLETE`.

**Pass/fail criteria**

Pass if exactly four objects exist at the expected keys with matching sizes. Fail on collision, omission, flattening, or unexpected upload.

### TC-06: FULL, DIFF, and LOG directory structure

**Setup**

Create:

```text
<source>\SQL01\DatabaseA\FULL\DatabaseA_FULL_001.bak
<source>\SQL01\DatabaseA\DIFF\DatabaseA_DIFF_001.bak
<source>\SQL01\DatabaseA\LOG\DatabaseA_LOG_001.trn
```

**Action**

Run the uploader.

**Expected result**

The complete relative hierarchy below `BackupRootPath` is preserved in S3.

**Expected exit code**

`0`

**Expected log message**

One upload entry for each file and a successful `SYNC_COMPLETE`.

**Pass/fail criteria**

Pass if `SQL01/DatabaseA/FULL`, `DIFF`, and `LOG` appear exactly as expected. Fail if any component is discarded or transformed.

### TC-07: Non-backup files do not upload

**Setup**

Create:

```text
DatabaseA.bak
DatabaseA.trn
notes.txt
restore.sql
archive.zip
DatabaseA.bak.tmp
settings.json
```

**Action**

Run the uploader.

**Expected result**

Only `DatabaseA.bak` and `DatabaseA.trn` upload.

**Expected exit code**

`0`

**Expected log message**

Upload messages reference only the two eligible files. Final result is success.

**Pass/fail criteria**

Pass if S3 contains only the two eligible objects. Fail if any excluded file uploads.

Also repeat with `.BAK`, `.TRN`, and mixed-case extensions to establish actual filter behavior.

### TC-08: Unchanged backup already exists

**Setup**

Complete TC-03 successfully. Do not modify the local file. Record S3 object size, last-modified timestamp, ETag, and version ID when available.

**Action**

Run the uploader again.

**Expected result**

AWS CLI skips the unchanged file.

**Expected exit code**

`0`

**Expected log message**

`SYNC_START` and successful `SYNC_COMPLETE` appear, with no upload entry for the unchanged file.

**Pass/fail criteria**

Pass if the object is not retransferred and identifying metadata remains unchanged. Fail if it uploads again without a source change.

### TC-09: New backup after previous synchronization

**Setup**

Complete a successful run containing `DatabaseA_FULL_001.bak`. Add `DatabaseA_FULL_002.bak` without changing the first file.

**Action**

Run the uploader again.

**Expected result**

Only the new file uploads. The first object remains unchanged.

**Expected exit code**

`0`

**Expected log message**

One upload event for `DatabaseA_FULL_002.bak`, no upload event for `_001`, and successful completion.

**Pass/fail criteria**

Pass if both objects exist and only the new file transfers during the second run.

### TC-10: Invalid AWS credentials

**Setup**

Use isolated process environment variables or an isolated credentials file containing a syntactically valid but nonexistent access key. Do not replace the operator's credentials.

**Action**

Run with one eligible local backup.

**Expected result**

AWS rejects the request. No object uploads.

**Expected exit code**

Normally `254`. Accept another documented nonzero AWS CLI code only if the final script exit code and log preserve it exactly.

**Expected log message**

An `AWS_CLI_OUTPUT` or exception message contains `InvalidAccessKeyId`, `SignatureDoesNotMatch`, or `UnrecognizedClientException`. `SYNC_COMPLETE` contains `FinalResult=FAILED`.

**Pass/fail criteria**

Pass if no object uploads and the real AWS CLI failure code propagates. Fail if the script reports success or masks the CLI code.

### TC-11: Missing AWS credentials

**Setup**

Use an isolated test process with no credential environment variables, no usable shared profile, no role provider, and metadata lookup disabled where appropriate. Do not delete credential files.

**Action**

Run the uploader.

**Expected result**

AWS CLI reports that credentials cannot be located. No object uploads.

**Expected exit code**

Typically `253`.

**Expected log message**

```text
Unable to locate credentials
event=SYNC_COMPLETE
ExitCode=253
FinalResult=FAILED
```

**Pass/fail criteria**

Pass if no object uploads and code 253 propagates. Fail if the script reports success, substitutes code 1, or obtains unintended credentials.

### TC-12: Invalid S3 bucket name

**Setup**

Set `S3Bucket` to an invalid S3 URI and place one eligible file in the source. For a deterministic service-error variant, use a syntactically valid but nonexistent bucket.

**Action**

Run the uploader.

**Expected result**

AWS CLI rejects the destination and no object uploads.

**Expected exit code**

For invalid syntax, normally `252` or `255`. For a valid but nonexistent bucket, normally `254`.

**Expected log message**

AWS output describes an invalid bucket, invalid endpoint, or `NoSuchBucket`. Final result is failed.

**Pass/fail criteria**

Pass if no object uploads and the actual nonzero CLI code is propagated exactly. Fail if the script returns 0.

### TC-13: IAM permission denied

**Setup**

Use a pre-existing test principal that authenticates but lacks `s3:PutObject` or required bucket-list access for the test prefix. Do not modify IAM automatically.

**Action**

Run with a new eligible backup.

**Expected result**

AWS returns `AccessDenied`. The unauthorized object is not uploaded.

**Expected exit code**

Commonly `1` for a transfer failure or `254` for a service error before transfer.

**Expected log message**

An AWS output entry contains `AccessDenied`; `SYNC_COMPLETE` contains the actual nonzero exit code and `FinalResult=FAILED`.

**Pass/fail criteria**

Pass if no unauthorized object is created and the failure propagates. Fail if the script reports success.

### TC-14: Network interruption

**Setup**

Use a sufficiently large test backup. Prepare a reversible host-side network fault. Do not modify AWS networking.

**Action**

Start the uploader, confirm transfer initiation, interrupt connectivity long enough to exhaust AWS CLI retries, and restore connectivity only after the process fails.

**Expected result**

AWS CLI retries internally and eventually fails. Object existence alone must not be treated as success.

**Expected exit code**

Typically `1`; a failure before transfer scheduling may be `255`.

**Expected log message**

AWS output contains connection, timeout, or endpoint errors. Final result is failed with the actual CLI code.

**Pass/fail criteria**

Pass if the run ends nonzero. If an object exists, it must be a completed object with expected size; no incomplete state may be treated as success.

### TC-15: Partial failed run followed by successful rerun

**Setup**

Create several small backups and one large backup. Arrange a controlled network failure after at least one small object completes.

**Action**

Run once with the fault, restore connectivity, and run again without changing the source files.

**Expected result**

The first run fails. The second skips completed unchanged objects and transfers missing or failed objects.

**Expected exit code**

First run: nonzero, commonly `1`. Second run: `0`.

**Expected log message**

First run ends with `FinalResult=FAILED`. Second run includes upload records only for outstanding files and ends with `FinalResult=SUCCESS`.

**Pass/fail criteria**

Pass if the final object set is complete, sizes match, completed files are not unnecessarily retransferred, and the rerun exits 0.

### TC-16: AWS CLI missing

**Setup**

Start PowerShell with a temporary `PATH` that excludes AWS CLI. Do not uninstall it.

**Action**

Run the uploader.

**Expected result**

Prerequisite validation stops execution before synchronization.

**Expected exit code**

`1`

**Expected log message**

```text
level=ERROR event=PREREQUISITE_FAILED message="AWS CLI was not found in PATH."
```

**Pass/fail criteria**

Pass if the structured error is logged, no AWS request is made, and exit code is 1.

### TC-17: settings.json missing

**Setup**

Use a disposable script copy where neither the parent-directory nor same-directory `settings.json` exists. Do not delete the repository's real configuration.

**Action**

Run the uploader.

**Expected result**

Execution stops before structured logging is initialized.

**Expected exit code**

`1`

**Expected log message**

Current implementation produces no `S3Upload.log` entry. Console output contains:

```text
Configuration file not found. Copy settings.json.template to settings.json and update it.
```

**Pass/fail criteria**

Pass if exit code is 1 and AWS CLI is not invoked.

### TC-18: Invalid AWS Region

**Setup**

Configure `AWSRegion` as `not-a-real-region`, with an otherwise valid bucket and source.

**Action**

Run the uploader.

**Expected result**

AWS CLI fails Region or endpoint resolution. No object uploads.

**Expected exit code**

Typically `255`; some versions may return `252`.

**Expected log message**

AWS output refers to the Region or endpoint. `SYNC_COMPLETE` contains the actual nonzero code and `FinalResult=FAILED`.

**Pass/fail criteria**

Pass if no upload occurs and the exact AWS CLI code propagates. Fail if the script returns 0.

### TC-19: UNC source path

**Setup**

Use a test share such as:

```text
\\TestServer\CVTBackupTest
```

Grant the intended execution identity read and list access. Create:

```text
\\TestServer\CVTBackupTest\DatabaseA\FULL\DatabaseA_FULL_001.bak
```

**Action**

Configure the UNC path and run under the same identity intended for SQL Server Agent or Task Scheduler.

**Expected result**

The backup uploads and its relative hierarchy is preserved.

**Expected exit code**

`0`

**Expected log message**

`SYNC_START` records the UNC source, an upload event appears, and `SYNC_COMPLETE` reports success.

**Pass/fail criteria**

Pass if the correct object exists with matching size and the service identity can access the share. Fail if only the interactive account works or the path changes.

### TC-20: Large backup triggers multipart transfer

**Setup**

Determine the effective multipart threshold:

```powershell
aws configure get default.s3.multipart_threshold
```

If unset, use the AWS CLI default. Create a synthetic `.bak` comfortably larger than the threshold, such as 128 MB or 1 GB. Record its byte length and SHA-256 hash.

**Action**

Run the uploader.

**Expected result**

AWS CLI completes a multipart upload and exposes one completed S3 object.

**Expected exit code**

`0`

**Expected log message**

An upload event appears and `SYNC_COMPLETE` reports exit code 0 and success.

**Pass/fail criteria**

Pass if the object exists, `ContentLength` equals the local byte length, no incomplete result is accepted, and compatible stored checksum metadata validates when available. Do not compare the multipart ETag directly with the full-file MD5.

## 7. Defects identified during test design

### D-01: AWS CLI exit-code masking in Windows PowerShell 5.1 — resolved

The original refactor combined `$ErrorActionPreference = 'Stop'` with native stderr redirection through `2>&1`. Windows PowerShell 5.1 can promote native stderr to PowerShell error records before `$LASTEXITCODE` is captured. The script now temporarily uses `Continue` only around native AWS CLI invocations and restores the caller preference afterward, matching the downloader pattern. TC-10 through TC-15 and TC-18 remain required regression tests for exact propagation.

### D-02: Early validation failures are not structured

Missing settings, malformed JSON, missing required values, inaccessible sources, and log-directory creation failures occur before `Write-Log` is available. They do not record structured start, duration, or final-result events.

### D-03: Sync comparison is not a content-integrity comparison

A same-sized changed local file whose timestamp is not newer than the S3 object may be skipped. The uploader does not maintain or compare a checksum manifest.

### D-04: Active SQL backup files can upload

The script does not determine whether SQL Server is still writing a `.bak` or `.trn`. Transport success does not prove the source was a complete SQL Server backup.

### D-05: Symbolic links and reparse points are not explicitly disabled

AWS CLI local uploads follow symbolic links by default unless `--no-follow-symlinks` is supplied. Content outside the intended backup root could be uploaded through a link.

### D-06: Extension matching may be case-sensitive

Only `*.bak` and `*.trn` are included. Uppercase or mixed-case extensions require explicit validation.

### D-07: AWS output is buffered in memory

The script captures all AWS CLI output before logging it. Large inventories can increase memory use, and transfer messages are not logged in real time.

### D-08: Log values are not fully escaped

Newlines are removed, but embedded double quotes are not escaped. Strict key/value parsers may misinterpret a record.

### D-09: Empty and no-change runs are indistinguishable

An empty source, a source containing only excluded files, and a healthy no-change run all finish successfully without an explicit matching-file count or no-work event.

### D-10: Configuration validation is limited

The script checks required values only for nonblank text. It does not validate S3 URI shape, Region format, intended AWS account, named profile, or bucket/prefix reachability before synchronization.

### D-11: No SQL backup-integrity validation

The uploader does not execute or consume evidence from SQL Server backup checksums, `RESTORE VERIFYONLY`, or a recovery-chain manifest.

### D-12: Existing keys can be replaced

The script does not use immutable key naming or `--no-overwrite`. S3 Versioning or Object Lock may mitigate this, but those controls are outside this script and must be verified separately.

## 8. Acceptance gate

The uploader is acceptable for production scheduling only when:

1. TC-01 through TC-20 have documented evidence and pass.
2. AWS CLI exit codes are proven to propagate correctly under Windows PowerShell 5.1.
3. Preflight failures are observable through an agreed logging mechanism.
4. The operating process guarantees that only completed SQL backup files enter the synchronized source.
5. Symlink/reparse-point behavior is explicitly controlled.
6. Extension-case behavior is documented and tested.
7. Multipart verification uses size and compatible checksum metadata rather than ETag assumptions.
8. The execution identity, AWS account, bucket, and prefix are validated operationally.
9. S3 data-protection controls such as Versioning and, where required, Object Lock are reviewed separately without being modified by this test plan.
10. No test or production invocation includes `--delete`.

## 9. Test summary record

Use this table to record execution:

| Test | Date | Tester | Exit code | Log verified | S3 state verified | Result | Evidence/notes |
|---|---|---|---:|---|---|---|---|
| TC-01 | | | | | | | |
| TC-02 | | | | | | | |
| TC-03 | | | | | | | |
| TC-04 | | | | | | | |
| TC-05 | | | | | | | |
| TC-06 | | | | | | | |
| TC-07 | | | | | | | |
| TC-08 | | | | | | | |
| TC-09 | | | | | | | |
| TC-10 | | | | | | | |
| TC-11 | | | | | | | |
| TC-12 | | | | | | | |
| TC-13 | | | | | | | |
| TC-14 | | | | | | | |
| TC-15 | | | | | | | |
| TC-16 | | | | | | | |
| TC-17 | | | | | | | |
| TC-18 | | | | | | | |
| TC-19 | | | | | | | |
| TC-20 | | | | | | | |
