# CVT BackupBridge v2: DR Measurement Results Template

> Copy this file for each test attempt. Replace every `<placeholder>`. Use `N/A` only when a stage did not apply and `NOT MEASURED` when evidence is unavailable. Do not enter estimated or fabricated benchmark values.

## 1. Test identity and objectives

| Field | Result |
|---|---|
| Test ID | `<test-id>` |
| Attempt | `<attempt-number>` |
| Test date/time UTC | `<yyyy-mm-ddThh:mm:ss.sssZ>` |
| Repository commit/release | `<commit-or-release>` |
| Database | `<database-name>` |
| Source SQL instance/version | `<source-instance-and-version>` |
| Recovery SQL instance/version | `<recovery-instance-and-version>` |
| S3 bucket/prefix/Region | `<redacted-bucket-prefix-and-region>` |
| Recovery target UTC | `<timestamp-or-latest>` |
| Required RPO | `<duration>` |
| Required RTO | `<duration>` |
| RTO start event | `<defined-event>` |
| RTO stop event | `<defined-event>` |
| Test owner / recovery DBA / application owner | `<names-or-roles>` |
| Evidence root/index | `<reference>` |

## 2. Environment and workload context

| Field | Result | Evidence |
|---|---:|---|
| Source database allocated bytes | `<bytes>` | `<evidence-id>` |
| Source database allocated GiB | `<GiB>` | `<evidence-id>` |
| Data allocated bytes | `<bytes>` | `<evidence-id>` |
| Log allocated bytes | `<bytes>` | `<evidence-id>` |
| Recovery model | `<FULL-or-other>` | `<evidence-id>` |
| Average data-change rate, if measured | `<value-and-unit-or-NOT-MEASURED>` | `<evidence-id>` |
| Recovery host CPU / memory | `<configuration>` | `<evidence-id>` |
| Recovery data/log storage | `<type-and-configuration>` | `<evidence-id>` |
| Network path/link context | `<configuration>` | `<evidence-id>` |
| S3 storage class(es) | `<classes>` | `<evidence-id>` |
| Archive restore required | `<yes-no>` | `<evidence-id>` |
| Clock skew observed | `<milliseconds>` | `<evidence-id>` |

## 3. Backup measurements

| Metric | Start UTC | End UTC | Duration seconds | Bytes | Evidence |
|---|---|---|---:|---:|---|
| FULL backup | `<timestamp>` | `<timestamp>` | `<seconds>` | `<bytes>` | `<id>` |
| DIFFERENTIAL backup | `<timestamp-or-N/A>` | `<timestamp-or-N/A>` | `<seconds-or-N/A>` | `<bytes-or-N/A>` | `<id>` |
| LOG backup 1 | `<timestamp>` | `<timestamp>` | `<seconds>` | `<bytes>` | `<id>` |
| LOG backup 2 | `<timestamp-or-add-rows>` | `<timestamp>` | `<seconds>` | `<bytes>` | `<id>` |

| Derived backup metric | Formula | Result |
|---|---|---:|
| FULL compression ratio | source allocated bytes / FULL bytes | `<ratio>` |
| FULL compression reduction | (1 - FULL bytes / source allocated bytes) * 100 | `<percent>` |
| Configured LOG interval | Schedule setting | `<minutes>` |
| Maximum actual successful LOG interval | Max completion-to-completion interval | `<minutes>` |

## 4. S3 transfer measurements

| Metric | Start UTC | End UTC | Duration seconds | Bytes actually transferred | Throughput MiB/s | Exit code | Evidence |
|---|---|---|---:|---:|---:|---:|---|
| S3 synchronization | `<timestamp>` | `<timestamp>` | `<seconds>` | `<bytes>` | `<MiB/s-or-N/A>` | `<code>` | `<id>` |
| S3 archive retrieval wait | `<timestamp-or-N/A>` | `<timestamp-or-N/A>` | `<seconds-or-N/A>` | N/A | N/A | N/A | `<id>` |
| S3 download | `<timestamp>` | `<timestamp>` | `<seconds>` | `<bytes>` | `<MiB/s-or-N/A>` | `<code>` | `<id>` |
| Transfer integrity validation | `<timestamp>` | `<timestamp>` | `<seconds>` | `<bytes-validated>` | N/A | `<result>` | `<id>` |

Throughput formula: `bytes actually transferred / 1,048,576 / duration seconds`.

## 5. SQL verification and restore measurements

| Stage | Start UTC | End UTC | Duration seconds | Result | Evidence |
|---|---|---|---:|---|---|
| RESTORE VERIFYONLY - FULL | `<timestamp>` | `<timestamp>` | `<seconds>` | `<pass-fail>` | `<id>` |
| RESTORE VERIFYONLY - DIFF | `<timestamp-or-N/A>` | `<timestamp-or-N/A>` | `<seconds-or-N/A>` | `<pass-fail-N/A>` | `<id>` |
| RESTORE VERIFYONLY - LOG set | `<timestamp>` | `<timestamp>` | `<seconds>` | `<pass-fail>` | `<id>` |
| Metadata and chain analysis/review | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |
| FULL restore | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |
| DIFFERENTIAL restore | `<timestamp-or-N/A>` | `<timestamp-or-N/A>` | `<seconds-or-N/A>` | `<result-or-N/A>` | `<id>` |
| LOG restore sequence | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |
| RECOVERY to ONLINE | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |
| DBCC CHECKDB | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |
| Application/data validation | `<timestamp>` | `<timestamp>` | `<seconds>` | `<result>` | `<id>` |

## 6. Recovery timeline and RTO

| Milestone | UTC timestamp | Elapsed from RTO start | Evidence |
|---|---|---:|---|
| Source loss declared / RTO start | `<timestamp>` | `0` | `<id>` |
| Recovery infrastructure ready | `<timestamp>` | `<seconds>` | `<id>` |
| Required archive objects readable | `<timestamp-or-N/A>` | `<seconds-or-N/A>` | `<id>` |
| Download complete | `<timestamp>` | `<seconds>` | `<id>` |
| Transfer validation complete | `<timestamp>` | `<seconds>` | `<id>` |
| Backup verification and chain accepted | `<timestamp>` | `<seconds>` | `<id>` |
| SQL restore begins | `<timestamp>` | `<seconds>` | `<id>` |
| Database ONLINE | `<timestamp>` | `<seconds>` | `<id>` |
| CHECKDB complete | `<timestamp>` | `<seconds>` | `<id>` |
| Smoke validation accepted / RTO stop | `<timestamp>` | `<seconds>` | `<id>` |

| RTO result | Value |
|---|---:|
| Infrastructure preparation duration | `<seconds>` |
| Archive retrieval duration | `<seconds-or-N/A>` |
| Download duration | `<seconds>` |
| Transfer validation duration | `<seconds>` |
| Verification/chain-analysis duration | `<seconds>` |
| Technical SQL restore duration | `<seconds>` |
| DBCC CHECKDB duration | `<seconds>` |
| Application/data validation duration | `<seconds>` |
| Unattributed/overlapping time explanation | `<description>` |
| **Total validated-service RTO** | `<seconds>` |
| Required RTO | `<seconds>` |
| RTO result | `<PASS-FAIL>` |

## 7. RPO

| Field | Value | Evidence |
|---|---|---|
| Source-loss UTC | `<timestamp>` | `<id>` |
| Latest successful local LOG completion | `<timestamp>` | `<id>` |
| Latest cloud-confirmed continuous LOG recovery point | `<timestamp>` | `<id>` |
| Latest recovered transaction/marker validated | `<timestamp>` | `<id>` |
| Observed RPO | `<duration>` | `<calculation-reference>` |
| Required RPO | `<duration>` | `<requirement-reference>` |
| RPO result | `<PASS-FAIL>` | `<review-reference>` |

Observed RPO formula: `source-loss timestamp - latest validated recovered transaction timestamp`.

Explain schedule deviations, failed/missed log backups, upload lag, chain gaps, clock corrections, and why the selected marker proves the observed recovery point:

`<narrative>`

## 8. Outcome and evidence quality

| Criterion | Result | Evidence / comment |
|---|---|---|
| Source independence proven | `<PASS-FAIL>` | `<id>` |
| Upload and download exit codes successful | `<PASS-FAIL>` | `<id>` |
| Transfer integrity reconciled | `<PASS-FAIL>` | `<id>` |
| Candidate chain accepted without unresolved gap | `<PASS-FAIL>` | `<id>` |
| Restore completed and database ONLINE | `<PASS-FAIL>` | `<id>` |
| DBCC CHECKDB clean | `<PASS-FAIL>` | `<id>` |
| Application/data validation passed | `<PASS-FAIL>` | `<id>` |
| Required RPO met | `<PASS-FAIL>` | `<id>` |
| Required RTO met | `<PASS-FAIL>` | `<id>` |
| Measurement-quality gates met | `<PASS-FAIL>` | `<id>` |
| Overall attempt | `<PASS-FAIL-BLOCKED>` | `<reason>` |

## 9. Deviations, retries, and improvements

| Timestamp UTC | Stage | Deviation/retry | Time impact | Data/RPO impact | Owner/action |
|---|---|---|---:|---|---|
| `<timestamp>` | `<stage>` | `<description>` | `<seconds>` | `<description>` | `<owner-and-action>` |

## 10. Review and sign-off

| Role | Name | Result | UTC timestamp | Signature/reference |
|---|---|---|---|---|
| Recovery DBA | `<name>` | `<result>` | `<timestamp>` | `<reference>` |
| Application owner | `<name>` | `<result>` | `<timestamp>` | `<reference>` |
| Test coordinator | `<name>` | `<result>` | `<timestamp>` | `<reference>` |

Completed results must retain raw evidence references and must not present placeholders, estimates, or a single test as a general performance benchmark.

