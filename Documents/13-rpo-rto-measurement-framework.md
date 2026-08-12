# CVT BackupBridge v2: RPO/RTO Measurement Framework

## Purpose

This framework makes BackupBridge DR exercises measurable and comparable. It defines metric boundaries, evidence, calculations, and reporting rules. It contains no benchmark claims; values remain placeholders until an actual test is performed.

Use it with the end-to-end DR validation runbook and create one completed results record per database, recovery target, and test attempt.

## Measurement principles

- Use UTC timestamps in ISO 8601 format with millisecond precision where the tool supports it.
- Synchronize source, transfer, recovery, and observer clocks before testing; record observed clock skew.
- Use monotonic elapsed timers for durations when available. Wall-clock subtraction is evidence, not the preferred timer.
- Record bytes as exact integers. Display GiB only as a secondary value using 1 GiB = 1,073,741,824 bytes.
- Record start and end boundaries consistently; do not remove setup, retry, archive retrieval, or validation time from end-to-end RTO.
- Preserve raw logs and SQL output. A manually entered result must reference evidence.
- Report failed attempts. Do not replace them with a successful rerun under the same test ID.
- Use N/A only when a stage is genuinely not part of the selected recovery chain, such as a restore with no DIFFERENTIAL.
- Use NOT MEASURED when a stage occurred but reliable evidence is unavailable.

## Timing architecture

```text
Source loss declared (RTO start)
  -> infrastructure and access preparation
  -> archive retrieval wait, if applicable
  -> S3 download
  -> transfer validation
  -> VERIFYONLY and metadata/chain analysis
  -> FULL restore
  -> optional DIFF restore
  -> LOG restore sequence
  -> RECOVERY
  -> DBCC CHECKDB
  -> application/data validation
  -> service accepted (RTO stop)
```

Report both:

- **Technical restore duration:** first SQL restore command start through database ONLINE after RECOVERY.
- **Validated-service RTO:** source-loss declaration through completion of every mandatory recovery, integrity, and smoke-test gate.

Technical restore duration is useful for SQL tuning but is not the complete business RTO.

## Metric dictionary

| Metric | Start / source | End / calculation | Unit | Required evidence |
|---|---|---|---|---|
| Source database size | Immediately before FULL backup | Sum allocated data and log file sizes; optionally record used data separately | bytes / GiB | SQL query output |
| FULL backup size | Resulting FULL file set | Sum exact file lengths | bytes / GiB | File inventory and backup history |
| DIFFERENTIAL backup size | Resulting DIFF file set | Sum exact file lengths | bytes / GiB | File inventory and backup history |
| LOG backup size | Each log or measured log set | Exact file length; never silently average | bytes / GiB | File inventory and backup history |
| Compression ratio | Source database size / compressed FULL size | Ratio, plus size-reduction percentage | ratio / percent | Source-size and backup-size evidence |
| FULL backup duration | SQL reports FULL start | SQL reports FULL finish | seconds | `msdb` history or captured command timestamps |
| DIFFERENTIAL backup duration | DIFF start | DIFF finish | seconds | Same |
| LOG backup duration | Each LOG start | Each LOG finish | seconds | Same; report min/median/max for a set only with raw rows |
| S3 synchronization duration | Uploader transfer invocation | AWS CLI completion/exit | seconds | Structured uploader log |
| Upload throughput | Bytes confirmed uploaded / synchronization duration | Count only bytes transferred in that run | MiB/s | AWS output/log plus before/after inventory |
| S3 download duration | Downloader transfer invocation | AWS CLI completion/exit | seconds | Structured downloader log |
| Download throughput | Bytes actually downloaded / download duration | Count only bytes transferred in that run | MiB/s | AWS output/log plus local/cloud reconciliation |
| Transfer validation duration | Reconciliation/checksum start | Integrity gate complete | seconds | Validation log |
| RESTORE VERIFYONLY duration | First selected VERIFYONLY start | Last selected VERIFYONLY finish | seconds | SQL output per backup set |
| Chain-analysis duration | Metadata scan start | Reviewed chain accepted | seconds | `Get-BackupChain.ps1` log/report and review timestamp |
| FULL restore duration | FULL RESTORE starts | FULL command completes | seconds | SQL command output/restore history |
| DIFFERENTIAL restore duration | DIFF RESTORE starts | DIFF command completes | seconds or N/A | SQL output/history |
| LOG restore duration | First selected LOG starts | Last selected LOG command completes | seconds | Per-log and aggregate output/history |
| RECOVERY duration | `WITH RECOVERY` starts | Database becomes ONLINE | seconds | SQL output and state query |
| DBCC CHECKDB duration | CHECKDB starts | CHECKDB completes | seconds | Complete DBCC output |
| Application/data validation duration | Mandatory smoke checks start | Acceptance gate completes | seconds | Test output and sign-off |
| Infrastructure preparation duration | Source loss/RTO start | Recovery compute, storage, SQL, network, IAM/KMS access ready | seconds | Infrastructure/access evidence |
| Archive retrieval duration | Restore request accepted | Every required archived object is temporarily readable | seconds or N/A | S3 restore evidence |
| Total recovery duration | Declared source loss | Validated service accepted | seconds | Coordinator timeline |

### Size query example

Run in the approved source database before backup generation:

```sql
SELECT
    DB_NAME() AS DatabaseName,
    SUM(CAST(size AS bigint)) * 8192 AS AllocatedBytes,
    SUM(CASE WHEN type_desc = 'ROWS' THEN CAST(size AS bigint) ELSE 0 END) * 8192 AS DataAllocatedBytes,
    SUM(CASE WHEN type_desc = 'LOG' THEN CAST(size AS bigint) ELSE 0 END) * 8192 AS LogAllocatedBytes
FROM sys.database_files;
```

State explicitly that compression ratio uses allocated database bytes, not live used-page bytes, unless the test adopts and documents a different denominator.

### Formulas

```text
Compression ratio = source database bytes / FULL backup bytes
Compression reduction percent = (1 - FULL backup bytes / source database bytes) * 100

Upload throughput MiB/s = bytes actually uploaded / 1,048,576 / upload seconds
Download throughput MiB/s = bytes actually downloaded / 1,048,576 / download seconds

Observed RPO = source-loss timestamp - latest validated recovered transaction timestamp
Validated-service RTO = validation-accepted timestamp - source-loss timestamp
```

If a sync transfers zero bytes because objects are unchanged, throughput is N/A, not zero and not infinite. If retries occur, include retry time in duration and identify retransmitted bytes separately when the evidence supports it.

## RPO framework

RPO is the maximum tolerable data-loss window; observed RPO is what the test actually recovered.

With a healthy FULL recovery model and an unbroken log chain, the transaction-log backup interval strongly influences exposure. A 15-minute schedule can leave roughly up to one interval of committed transactions not yet copied offsite when the source and its local backup storage are lost. It is not a guarantee of 15-minute RPO because scheduling delay, backup failure, upload delay, missing S3 objects, log-chain breaks, and clock skew increase exposure.

Measure at least:

- configured LOG interval;
- actual intervals between successful LOG backup completion times;
- time from LOG completion to confirmed availability in S3;
- source-loss time;
- requested recovery target;
- latest continuous log-backed recovery point available in S3; and
- latest transaction or marker validated after restore.

For an offsite RPO, use cloud-confirmed recoverability rather than merely the latest local LOG completion. Alert when either the log backup or its upload misses the defined threshold.

## RTO framework

RTO is the maximum tolerable time to restore an acceptable service. BackupBridge validated-service RTO includes:

1. declaring the source unavailable and initiating the runbook;
2. preparing recovery compute, Windows, storage, SQL Server, network, IAM, KMS, DNS, and operators;
3. waiting for archived S3 objects, if used;
4. downloading and validating the backup set;
5. VERIFYONLY, metadata inspection, and chain review;
6. FULL, optional DIFF, LOG, and RECOVERY processing;
7. DBCC CHECKDB; and
8. application/data smoke validation and acceptance.

Pre-provisioned recovery infrastructure improves RTO but adds standing cost. On-demand preparation reduces cost but increases and makes RTO less predictable. Standard/Standard-IA and Glacier Instant Retrieval support faster retrieval than archive tiers requiring an S3 restore. Backup size, compression, network path, SQL storage throughput, CPU, encryption/KMS access, number of log files, CHECKDB scale, and human approval time all affect RTO.

## Collection workflow

1. Copy `Results/dr-validation-results-template.md` to a new file named with test ID, database, and UTC date.
2. Complete scope and objectives before the test.
3. Capture raw start/end timestamps and evidence references during each stage.
4. Calculate derived values only after raw values are recorded.
5. Reconcile the sum of component times with total elapsed time. Explain overlaps and unattributed gaps; do not force components to sum if work ran concurrently.
6. Compare observed RPO/RTO with approved targets.
7. Have the recovery DBA and test coordinator review calculations.
8. Preserve the completed template with the DR evidence package.

## Validation and quality gates

- No required field remains a placeholder in a completed result.
- Units and formulas are stated.
- Every duration has a start, end, timezone, and evidence reference.
- Every throughput value uses bytes actually transferred, not total source-set size.
- RPO is based on a validated recovered transaction/marker.
- End-to-end RTO includes preparation and mandatory acceptance stages.
- Failed stages and retries remain visible.
- Results do not claim general benchmark performance from one run.

## Troubleshooting

| Problem | Treatment |
|---|---|
| Clock skew | Record skew and correct timestamps; prefer elapsed timers |
| Missing duration evidence | Record NOT MEASURED and fail the measurement-quality gate |
| Sync transferred only some files | Use transferred bytes, not total prefix size |
| Parallel stages overlap | Preserve each duration and report wall-clock total; document overlap |
| Archived objects delay download | Record archive wait separately and include it in RTO |
| Retry succeeds | Include failed-attempt time and retries in end-to-end RTO |
| Multiple databases | Produce separate chains/results and an overall application recovery timeline |

## Assumptions and limitations

- The framework measures an approved test, not production performance.
- SQL and AWS logs provide sufficiently precise timing for the intended analysis.
- Application acceptance criteria are defined outside generic BackupBridge tooling.
- Results are comparable only when database size, change rate, storage class, network, SQL host, configuration, recovery target, and validation scope are recorded.
- No benchmark number should be published until measured and evidence-backed.

