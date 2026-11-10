# Magic ETL Build Spec: MSDB SQL Agent, All Servers

**Ticket:** TECH-XXXXXX (rename this file once the ticket number is known)
**Author:** Jim Cook (BI Group) | **Version:** V1 | **Created:** 2026-11-10

## Purpose
Combine the 25 per-server Workbench datasets (5 datasets x 5 servers) into 5 all-server datasets in one Magic ETL, so downstream cards, the Power Apps job-review screen and the failure triage all read one dataset per topic.

## ETL name
`ETL_MSDB_SQLServerAgent_AllServers`

## Servers (the 5 branches' inputs)
| Server label | Dataset suffix as published |
|---|---|
| CTG-SQLAAG01 | `-ctg-sqlaag01` |
| CTG-SQLAAG02 | `-ctg-sqlaag02` |
| CTG-SQLGPCL01 | `-ctg-sqlgpcl01` |
| HQ-SQL-TM1 | `-hq-sql-tm1` (JobHistory: `-HQ-SQL-TM1`) |
| STAR-MCLEODIQ | `-Star-McLeodIQ` (STEPS setup: `-Star-MCleodIQ`) |

## Flows (build 5 independent flows on one canvas)

Every flow is: 5 Input Datasets, then (JobHistory only) 5 Add Constants tiles, then 1 Append Rows tile, then 1 Output Dataset.

| # | Input datasets (x5, one per server) | Add Constants | Output dataset |
|---|---|---|---|
| 1 | `RAW_MSDB_SQLServerAgentJobHistory-<srv>` | **Yes**: `SourceServerName` = server label | `MSDB_SQLServerAgentJobHistory_AllServers` |
| 2 | `RAW_MSDB_SQLServerAgentJobSetupandConfiguration-<srv>` | No (query already returns `SourceServerName` via `@@SERVERNAME`) | `MSDB_SQLServerAgentJobSetupandConfiguration_AllServers` |
| 3 | `RAW_MSDB_SQLServerAgentJobSTEPSsetupandConfiguration-<srv>` | No (has `SourceServerName`) | `MSDB_SQLServerAgentJobSTEPSsetupandConfiguration_AllServers` |
| 4 | `RAW_MSDB_SQLServerAgentJobStepsExecution-<srv>` | No (has `SourceServerName`) | `MSDB_SQLServerAgentJobStepsExecution_AllServers` |
| 5 | `RAW_MSDB_SQLServerAgentSchedule-<srv>` | No (has `SourceServerName`) | `MSDB_SQLServerAgentSchedule_AllServers` |

### Append Rows settings (all 5 flows)
- Append by **column name**, not position.
- Keep **all columns** from every input.
- Leave "Remove duplicate rows" **off**. Duplicates are not expected, and JobHistory has about 3.6M rows.

### JobHistory extra step (flow 1)
After Append, add one **Add Formula** tile:
`JobServerKey` = `CONCAT(`SourceServerName`, '|', `JobName`)`
This makes a safe join key, because the same job name can exist on more than one server.

### Optional: failure flag (flow 1)
Add Formula `IsFailed` = `CASE WHEN `Status` = 'Failed' THEN 1 ELSE 0 END`. Aggregate it in a Beast Mode on the card, not in the ETL.

## Checks before enabling the schedule
1. Row count of each output = sum of its 5 inputs.
2. `SourceServerName` is populated on every row and shows 5 distinct values.
3. Compare the schema of the 5 inputs in each flow. Flow 3's inputs come from two different queries (the Star server's is shorter), so confirm the columns line up.
4. Schedule: trigger **on dataset update** of the 5 JobHistory inputs, or hourly at :30 during 6-18, after the Workbench jobs finish.

## Later: replacing the Workbench jobs
Once the linked-server stored procedure exists, these 25 inputs can be replaced by 5 central-table datasets and this ETL retired.
