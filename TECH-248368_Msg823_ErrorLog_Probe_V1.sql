/*
================================================================================
SCRIPT NAME:    TECH-248368_Msg823_ErrorLog_Probe_V1.sql
TICKET ID:      TECH-248368
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
MODIFIED:       2026-11-16
VERSION:        v1.0

PURPOSE:
    Read-only probe for the Msg 823 / OS error 59 (network error reading
    \\10.4.1.85\...\TMW_Live.mdf) hit at 2026-11-16 09:07 ET while testing
    CTG_RateReview_sp on DEV. Collects SQL Server error log evidence, file I/O
    stall stats, suspect pages and last good CHECKDB for the DBA team.
    (Windows OS log is pulled by the companion PowerShell script.)

SOURCE SYSTEM:  The DEV SQL Server instance where the 823 occurred
TARGET SYSTEM:  SSMS result grid (read-only)

BUSINESS LOGIC:
    - Window: 2026-11-16 08:30 to 10:00 server-local time (edit @From / @To)
    - Scans current + 6 archived SQL error logs
    - Nothing is changed; NO DBCC CHECKDB is run (DBA decision)

CHANGE LOG:
    2026-11-16 - J.Cook - TECH-248368 - Initial build

DEPENDENCIES:
    - xp_readerrorlog (needs sysadmin or equivalent), sys.master_files,
      sys.dm_io_virtual_file_stats, msdb.dbo.suspect_pages

NOTES:
    - Server log times are SERVER-LOCAL; the error was reported 09:07 -05:00.
    - If the instance is in an AG, run on each replica that served the read.
================================================================================
*/

SET NOCOUNT ON;

DECLARE @From DATETIME = '2026-11-16 08:30';
DECLARE @To   DATETIME = '2026-11-16 10:00';

-- 1) SQL Server error log: everything in the window, current + 6 archives
IF OBJECT_ID('tempdb..#ErrLog') IS NOT NULL DROP TABLE #ErrLog;
CREATE TABLE #ErrLog (LogNo INT, LogDate DATETIME, ProcessInfo NVARCHAR(100), LogText NVARCHAR(MAX));

DECLARE @n INT = 0;
WHILE @n <= 6
BEGIN
    BEGIN TRY
        INSERT INTO #ErrLog (LogDate, ProcessInfo, LogText)
        EXEC master.dbo.xp_readerrorlog @n, 1, NULL, NULL, @From, @To, N'asc';
        UPDATE #ErrLog SET LogNo = @n WHERE LogNo IS NULL;
    END TRY
    BEGIN CATCH
        PRINT 'Could not read error log ' + CAST(@n AS VARCHAR(2)) + ': ' + ERROR_MESSAGE();
    END CATCH;
    SET @n += 1;
END;

SELECT LogNo, LogDate, ProcessInfo, LogText
FROM   #ErrLog
ORDER BY LogDate;

-- 2) Only the lines that matter: I/O / network / 823-825 / TMW_Live / file path
SELECT LogNo, LogDate, ProcessInfo, LogText
FROM   #ErrLog
WHERE  LogText LIKE '%823%' OR LogText LIKE '%824%' OR LogText LIKE '%825%'
    OR LogText LIKE '%I/O%' OR LogText LIKE '%network%' OR LogText LIKE '%TMW_Live%'
    OR LogText LIKE '%10.4.1.85%' OR LogText LIKE '%error: 59%' OR LogText LIKE '%15 seconds%'
    OR LogText LIKE '%Severity: 2%'
ORDER BY LogDate;
GO

-- 3) Where TMW_Live files live (UNC path?) and their state
SELECT  DB_NAME(mf.database_id) AS DbName, mf.name AS LogicalName,
        mf.physical_name, mf.type_desc, mf.state_desc,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,1)) AS SizeMB
FROM    sys.master_files mf
WHERE   DB_NAME(mf.database_id) = 'TMW_Live';
GO

-- 4) File I/O latency since instance start (high stall = storage/network slowness)
SELECT  DB_NAME(vfs.database_id) AS DbName, mf.physical_name,
        vfs.num_of_reads, vfs.num_of_writes,
        vfs.io_stall_read_ms,
        CAST(vfs.io_stall_read_ms * 1.0 / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(18,1)) AS AvgReadMs,
        vfs.io_stall_write_ms,
        CAST(vfs.io_stall_write_ms * 1.0 / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(18,1)) AS AvgWriteMs
FROM    sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN    sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
WHERE   DB_NAME(vfs.database_id) = 'TMW_Live';
GO

-- 5) Pages SQL Server has flagged (823/824 etc). Rows here = follow up with DBA
SELECT  DB_NAME(sp.database_id) AS DbName, sp.file_id, sp.page_id,
        sp.event_type, sp.error_count, sp.last_update_date
FROM    msdb.dbo.suspect_pages sp WITH (NOLOCK)
ORDER BY sp.last_update_date DESC;
GO

-- 6) Last clean consistency check + current DB state
SELECT  d.name, d.state_desc, d.page_verify_option_desc,
        DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS LastGoodCheckDbTime
FROM    sys.databases d
WHERE   d.name = 'TMW_Live';
GO
