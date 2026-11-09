/*
================================================================================
SCRIPT NAME:    TECH-247812_Manhattan_Lineage_Verification_V1.sql
TICKET ID:      TECH-247812  (builds on TECH-231527)
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-09
MODIFIED:       2026-11-09
VERSION:        v1.0  (DIAGNOSTIC, read-only, not deployed)

PURPOSE:
    Checks, against the live servers, the statements the Manhattan documents
    make about the stored procedures and what feeds what: the 14 feeder sprocs,
    what each reads, which staging tables they depend on, where the hardcoded
    fleet-to-division map lives, whether any Agent job runs them, which manh_*
    tables hold what Covenant sends, and two open questions (the ord_number vs
    ord_hdrnumber join key, and the legheader trigger behind TECH-144279).
    Pair with TECH-247812_Doc_Consistency_Check_V1.py, which checks the
    documents against each other and against the sproc source.

SOURCE SYSTEM:  MANH, msdb, TMW_LIVE on CTG-SQLAAG02 (PROD)
TARGET SYSTEM:  Ad hoc (SSMS)

BUSINESS LOGIC:
    - Documented sproc list = the 14 names in the Pipeline Reference (section 3).
    - Result 1 shows each documented name as FOUND or MISSING, and lists any
      other procedure whose name starts with the same prefixes as UNDOCUMENTED.
    - Dependencies (Result 2) come from sys.sql_expression_dependencies. They
      miss dynamic SQL and temp tables, so treat an empty row as "not proven".
    - Results 5 and 6 need msdb and VIEW SERVER STATE rights. If a permission is
      missing the batch stops at that statement; run the earlier results alone.
    - Run in the MANH database. TMW_LIVE objects use three-part names.

CHANGE LOG:
    2026-11-09 - J.Cook - [TECH-247812] - v1.0 initial build

DEPENDENCIES:
    - MANH catalog views (sys.procedures, sys.sql_modules,
      sys.sql_expression_dependencies, INFORMATION_SCHEMA.COLUMNS,
      sys.dm_exec_procedure_stats, sys.dm_db_partition_stats)
    - msdb.dbo.sysjobs, msdb.dbo.sysjobsteps
    - TMW_LIVE.dbo.orderheader, TMW_LIVE.dbo.legheader (and its triggers)
    - MANH.dbo.PA_Customer_updated_loads

NOTES:
    - Schema_Verification, TMW_Live (tmw_live_schema.json, 2026-07-28):
        orderheader  ord_hdrnumber int NOT NULL; ord_number char(12) NOT NULL;
                     ord_bookdate datetime NULL
        legheader    lgh_number int NOT NULL; ord_hdrnumber int NULL
      MANH objects are read from catalog views, so no column names are assumed.
      PA_Customer_updated_loads.ordnumber type is not verified; it is read with
      TRY_CONVERT(int, RTRIM(ordnumber)).
    - Finding to confirm with Result 8: legheader.lgh_number is NOT NULL in the
      schema extract, so the NULL-vs-0 duplicate pattern in TECH-144279 cannot
      be NULL on legheader itself. It would sit in a MANH table (the ticket named
      expedite_audit). Result 8 confirms the column is NOT NULL on the live table.
================================================================================
*/

USE MANH;
GO
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#Doc') IS NOT NULL DROP TABLE #Doc;

CREATE TABLE #Doc (seq int NOT NULL PRIMARY KEY, name sysname NOT NULL);
INSERT INTO #Doc (seq, name) VALUES
 (1,  'MANH_Update_Divisions'),
 (2,  'sp_manh_CAN_TempZips'),
 (3,  'sp_manh_MEX_TempZips'),
 (4,  'usp_Fill_PA_Customer_updated_loads'),
 (5,  'usp_LoadUserParms'),
 (6,  'usp_manh_BusUnit_Division_Updates_STAR'),
 (7,  'usp_manh_Fill_tmpPAListSegments'),
 (8,  'usp_ns_manh_cust_name'),
 (9,  'usp_ns_manh_dispatch'),
 (10, 'usp_ns_manh_dispatch_accessorial'),
 (11, 'usp_ns_manh_shipment'),
 (12, 'usp_ns_manh_shipment_accessorial'),
 (13, 'usp_ns_manh_shipment_accessorial_42716'),
 (14, 'usp_ns_manh_trailer');

/* Result 1: documented sprocs against what exists, with last run (since plan cache) */
WITH Found AS (
    SELECT p.object_id, p.name, p.create_date, p.modify_date
    FROM   sys.procedures p
),
Stats AS (
    SELECT object_id, MAX(last_execution_time) AS LastRun, MAX(execution_count) AS Runs
    FROM   sys.dm_exec_procedure_stats
    WHERE  database_id = DB_ID()
    GROUP BY object_id
)
SELECT  d.seq,
        d.name,
        CASE WHEN f.object_id IS NULL THEN 'MISSING' ELSE 'FOUND' END AS Status,
        f.create_date, f.modify_date,
        s.LastRun, s.Runs
FROM    #Doc d
LEFT JOIN Found f ON f.name = d.name
LEFT JOIN Stats s ON s.object_id = f.object_id
UNION ALL
SELECT  NULL, f.name, 'UNDOCUMENTED', f.create_date, f.modify_date, s.LastRun, s.Runs
FROM    Found f
LEFT JOIN Stats s ON s.object_id = f.object_id
WHERE   (f.name LIKE 'usp[_]ns[_]manh%' OR f.name LIKE 'usp[_]manh%' OR f.name LIKE 'sp[_]manh%' OR f.name LIKE 'MANH%')
  AND   f.name NOT IN (SELECT name FROM #Doc)
ORDER BY 1, 2;

/* Result 2: what each documented sproc reads or writes (static dependencies) */
SELECT  d.seq,
        d.name                                   AS Sproc,
        ISNULL(e.referenced_server_name, '')     AS RefServer,
        ISNULL(e.referenced_database_name, '')   AS RefDb,
        ISNULL(e.referenced_schema_name, '')     AS RefSchema,
        e.referenced_entity_name                 AS RefObject,
        e.is_caller_dependent
FROM    #Doc d
JOIN    sys.procedures p ON p.name = d.name
JOIN    sys.sql_expression_dependencies e ON e.referencing_id = p.object_id
ORDER BY d.seq, RefDb, RefSchema, RefObject;

/* Result 3: hardcoded fleet-to-division codes, in every module in MANH, not only the 14 */
WITH Codes AS (
    SELECT code FROM (VALUES ('ESTENG'), ('ESTWLD'), ('MACH-1'), ('PERDED')) v(code)
)
SELECT  OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS Module,
        (SELECT type_desc FROM sys.objects o WHERE o.object_id = m.object_id) AS ModuleType,
        c.code,
        (LEN(m.definition) - LEN(REPLACE(m.definition, c.code, ''))) / LEN(c.code) AS Occurrences
FROM    sys.sql_modules m
CROSS JOIN Codes c
WHERE   m.definition LIKE '%' + c.code + '%'
ORDER BY Module, c.code;

/* Result 4: who touches the three staging tables (text match, so a lead not a proof) */
WITH Stg AS (
    SELECT n FROM (VALUES ('tmpPAListSegments'), ('tmpPAListOrdLegStopEvents'), ('PA_Customer_updated_loads')) v(n)
)
SELECT  s.n AS StagingTable,
        OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS Module,
        CASE WHEN m.definition LIKE '%INSERT%INTO%' + s.n + '%'
               OR m.definition LIKE '%SELECT%INTO%'  + s.n + '%' THEN 'writes' ELSE 'reads or other' END AS Mentions
FROM    sys.sql_modules m
CROSS JOIN Stg s
WHERE   m.definition LIKE '%' + s.n + '%'
ORDER BY s.n, Mentions DESC, Module;

/* Result 5: SQL Agent jobs that mention the sprocs (msdb). Documented as disabled April 2020. */
SELECT  j.name, j.enabled, j.date_created, j.date_modified,
        st.step_id, st.step_name, st.database_name, LEFT(st.command, 200) AS CommandStart
FROM    msdb.dbo.sysjobs j
JOIN    msdb.dbo.sysjobsteps st ON st.job_id = j.job_id
WHERE   j.name LIKE 'MANH%'
   OR   st.command LIKE '%usp[_]ns[_]manh%'
   OR   st.command LIKE '%usp[_]manh%'
   OR   st.command LIKE '%MANH_Update_Divisions%'
ORDER BY j.name, st.step_id;

/* Result 6: manh_* tables, columns and row counts: the data Covenant sends */
WITH Tbl AS (
    SELECT t.object_id, SCHEMA_NAME(t.schema_id) AS sch, t.name
    FROM   sys.tables t
    WHERE  t.name LIKE 'manh[_]%'
),
Rows_ AS (
    SELECT object_id, SUM(row_count) AS RowCnt
    FROM   sys.dm_db_partition_stats
    WHERE  index_id IN (0, 1)
    GROUP BY object_id
)
SELECT  t.sch + '.' + t.name AS TableName,
        r.RowCnt,
        c.ORDINAL_POSITION, c.COLUMN_NAME, c.DATA_TYPE, c.CHARACTER_MAXIMUM_LENGTH, c.IS_NULLABLE
FROM    Tbl t
LEFT JOIN Rows_ r ON r.object_id = t.object_id
JOIN    INFORMATION_SCHEMA.COLUMNS c ON c.TABLE_SCHEMA = t.sch AND c.TABLE_NAME = t.name
ORDER BY TableName, c.ORDINAL_POSITION;

/* Result 7: ord_number vs ord_hdrnumber, the open join-key question.
   (a) all orders booked since the Workbench cutoff (Jan 1 two calendar years back)
   (b) the orders in the last Manhattan run list */
DECLARE @cutoff datetime = DATEADD(yy, DATEDIFF(yy, 0, GETDATE()) - 2, 0);

SELECT  'All orders since cutoff' AS Population,
        COUNT(*) AS Orders,
        SUM(CASE WHEN RTRIM(oh.ord_number) = CAST(oh.ord_hdrnumber AS varchar(12)) THEN 1 ELSE 0 END) AS NumberEqualsHdr,
        SUM(CASE WHEN RTRIM(oh.ord_number) <> CAST(oh.ord_hdrnumber AS varchar(12)) THEN 1 ELSE 0 END) AS NumberDiffersFromHdr
FROM    TMW_LIVE.dbo.orderheader oh WITH (NOLOCK)
WHERE   oh.ord_bookdate >= @cutoff
UNION ALL
SELECT  'Last Manhattan run list',
        COUNT(*),
        SUM(CASE WHEN RTRIM(oh.ord_number) = CAST(p.ord AS varchar(12)) THEN 1 ELSE 0 END),
        SUM(CASE WHEN oh.ord_hdrnumber IS NULL OR RTRIM(oh.ord_number) <> CAST(p.ord AS varchar(12)) THEN 1 ELSE 0 END)
FROM   (SELECT DISTINCT TRY_CONVERT(int, RTRIM(ordnumber)) AS ord
        FROM   dbo.PA_Customer_updated_loads WITH (NOLOCK)
        WHERE  TRY_CONVERT(int, RTRIM(ordnumber)) IS NOT NULL) p
LEFT JOIN TMW_LIVE.dbo.orderheader oh WITH (NOLOCK) ON oh.ord_hdrnumber = p.ord;

/* Sample of orders where the two numbers differ, newest first */
SELECT TOP 25 oh.ord_hdrnumber, RTRIM(oh.ord_number) AS ord_number, oh.ord_bookdate
FROM    TMW_LIVE.dbo.orderheader oh WITH (NOLOCK)
WHERE   oh.ord_bookdate >= @cutoff
  AND   RTRIM(oh.ord_number) <> CAST(oh.ord_hdrnumber AS varchar(12))
ORDER BY oh.ord_bookdate DESC;

/* Result 8: legheader triggers (TECH-144279 root cause) and lgh_number nullability */
SELECT  tr.name AS TriggerName, tr.is_disabled, tr.is_instead_of_trigger, tr.create_date, tr.modify_date
FROM    TMW_LIVE.sys.triggers tr
WHERE   tr.parent_id = OBJECT_ID('TMW_LIVE.dbo.legheader');

SELECT  c.COLUMN_NAME, c.DATA_TYPE, c.IS_NULLABLE
FROM    TMW_LIVE.INFORMATION_SCHEMA.COLUMNS c
WHERE   c.TABLE_SCHEMA = 'dbo' AND c.TABLE_NAME = 'legheader'
  AND   c.COLUMN_NAME IN ('lgh_number', 'ord_hdrnumber', 'trc_fleet');
