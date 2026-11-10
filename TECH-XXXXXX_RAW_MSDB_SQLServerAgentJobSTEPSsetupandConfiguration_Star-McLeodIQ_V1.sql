/*
================================================================================
SCRIPT NAME:    TECH-XXXXXX_RAW_MSDB_SQLServerAgentJobSTEPSsetupandConfiguration_Star-McLeodIQ_V1.sql
TICKET ID:      TECH-XXXXXX
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-10
MODIFIED:       2026-11-10
VERSION:        v1.0

PURPOSE:
    Corrected query for the DOMO Workbench job
    RAW_MSDB_SQLServerAgentJobSTEPSsetupandConfiguration-Star-MCleodIQ.
    That job was running a copy of the JobSetupandConfiguration (sysjobs)
    query, so the dataset had no StepID/StepNo/StepType/ExecutableCommand
    columns and every Star-McLeodIQ row was dropped by the INNER JOIN on
    StepID in the combined SQL Agent view. This is the same steps query used
    by the other four servers (source: ...JobSTEPSsetupandConfiguration-ctg-sqlaag01).

SOURCE SYSTEM:  msdb on STAR-MCLEODIQ (Workbench DSN STAR-MCLEODIQ)
TARGET SYSTEM:  DOMO Dataset RAW_MSDB_SQLServerAgentJobSTEPSsetupandConfiguration-Star-MCleodIQ

BUSINESS LOGIC:
    - One row per SQL Agent job step
    - Step type, run-as proxy, success/failure actions decoded to text
    - SourceServerName = UPPER(@@SERVERNAME), same as the other four servers

CHANGE LOG:
    2026-11-10 - J.Cook - TECH-XXXXXX - Replace wrong (sysjobs) query with steps query

DEPENDENCIES:
    - msdb.dbo.sysjobsteps
    - msdb.dbo.sysjobs
    - msdb.dbo.sysproxies

NOTES:
    - Workbench will see a schema change (new columns); accept it or clear and reload the dataset
    - Expect about 34 rows (matches JobStepsExecution-Star-McLeodIQ)
    - Paste everything from "use msdb" down into the Workbench job's query box
================================================================================
*/

use msdb

------------------------------------------------------------------------------------------------------------------------------------------------------
-- RAW_MSDB_SQLServerAgentJobSTEPSsetupandConfiguration-Star-McLeodIQ		Janice Morgan 10/23/26 -- loaded to DOMO
------------------------------------------------------------------------------------------------------------------------------------------------------

 SELECT
    sJOB.job_id AS JobID
    , sJOB.name AS JobName
    , sJSTP.step_uid AS StepID
    , sJSTP.step_id AS StepNo
    , sJSTP.step_name AS StepName
    , CASE sJSTP.subsystem
        WHEN 'ActiveScripting' THEN 'ActiveX Script'
        WHEN 'CmdExec' THEN 'Operating system (CmdExec)'
        WHEN 'PowerShell' THEN 'PowerShell'
        WHEN 'Distribution' THEN 'Replication Distributor'
        WHEN 'Merge' THEN 'Replication Merge'
        WHEN 'QueueReader' THEN 'Replication Queue Reader'
        WHEN 'Snapshot' THEN 'Replication Snapshot'
        WHEN 'LogReader' THEN 'Replication Transaction-Log Reader'
        WHEN 'ANALYSISCOMMAND' THEN 'SQL Server Analysis Services Command'
        WHEN 'ANALYSISQUERY' THEN 'SQL Server Analysis Services Query'
        WHEN 'SSIS' THEN 'SQL Server Integration Services Package'
        WHEN 'TSQL' THEN 'Transact-SQL script (T-SQL)'
        ELSE sJSTP.subsystem
      END AS StepType
    , sPROX.name AS RunAs
    , sJSTP.database_name AS [Database]
    , sJSTP.command AS ExecutableCommand
    , CASE sJSTP.on_success_action
        WHEN 1 THEN 'Quit the job reporting success'
        WHEN 2 THEN 'Quit the job reporting failure'
        WHEN 3 THEN 'Go to the next step'
        WHEN 4 THEN 'Go to Step: '
                    + QUOTENAME(CAST(sJSTP.on_success_step_id AS VARCHAR(3)))
                    + ' '
                    + sOSSTP.step_name
      END AS OnSuccessAction
    , sJSTP.retry_attempts AS RetryAttempts
    , sJSTP.retry_interval AS [RetryInterval (Minutes)]
    , CASE sJSTP.on_fail_action
        WHEN 1 THEN 'Quit the job reporting success'
        WHEN 2 THEN 'Quit the job reporting failure'
        WHEN 3 THEN 'Go to the next step'
        WHEN 4 THEN 'Go to Step: '
                    + QUOTENAME(CAST(sJSTP.on_fail_step_id AS VARCHAR(3)))
                    + ' '
                    + sOFSTP.step_name
      END AS OnFailureAction
	, getdate() as AddedonDate
	,OBJECT_NAME(@@PROCID) as AddedbyApplication
	,UPPER(@@SERVERNAME) as SourceServerName
FROM
    msdb.dbo.sysjobsteps AS sJSTP with(nolock)
    INNER JOIN msdb.dbo.sysjobs AS sJOB with(nolock)
        ON sJSTP.job_id = sJOB.job_id
    LEFT JOIN msdb.dbo.sysjobsteps AS sOSSTP with(nolock)
        ON sJSTP.job_id = sOSSTP.job_id
        AND sJSTP.on_success_step_id = sOSSTP.step_id
    LEFT JOIN msdb.dbo.sysjobsteps AS sOFSTP with(nolock)
        ON sJSTP.job_id = sOFSTP.job_id
        AND sJSTP.on_fail_step_id = sOFSTP.step_id
    LEFT JOIN msdb.dbo.sysproxies AS sPROX with(nolock)
        ON sJSTP.proxy_id = sPROX.proxy_id
