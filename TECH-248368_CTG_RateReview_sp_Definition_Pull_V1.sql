/*
================================================================================
SCRIPT NAME:    TECH-248368_CTG_RateReview_sp_Definition_Pull_V1.sql
TICKET ID:      TECH-248368
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
MODIFIED:       2026-11-16
VERSION:        v1.0

PURPOSE:
    Retrieve the source of CTG_RateReview_sp, the stored procedure behind the
    SSRS "Rate Review" report (DataSet1, data source BISoxReports), so header
    rates (tariffheader.tar_rate) can be added to its output.

SOURCE SYSTEM:  BISoxReports data source (database unconfirmed - step 1 finds it)
TARGET SYSTEM:  SSMS result grid (read-only)

BUSINESS LOGIC:
    - RDL (pulled 2026-11-16) passes @StartDate / @EndDate (DateTime)
    - Proc must keep returning these 28 columns, names exact (RDL binds by name):
      RecordType, Tariff#, Company, CustomerID, CustomerName, OriginRegion,
      OriginCity, OriginState, OriginZip, OriginZipRange, DestRegion, DestCity,
      DestState, DestZip, DestZipRange, Rate, OldRate, RateChange, Minimum,
      Active, Expires, LocationKey, LocationID, Modified, MileageTable,
      last_updateby, StartDate (+ Tariff# bound as Int32, Rate/Minimum Decimal)

CHANGE LOG:
    2026-11-16 - J.Cook - TECH-248368 - Initial build
    2026-11-16 - J.Cook - TECH-248368 - V1.1 fix: COLLATE DATABASE_DEFAULT in step 1 (Msg 451 UNION collation conflict)

DEPENDENCIES:
    - sys.sql_modules / sys.procedures in the database hosting CTG_RateReview_sp

NOTES:
    - Read-only.
    - Step 1 is run on the SERVER; if the proc is not in the current database,
      the result tells you which database to USE for step 2.
================================================================================
*/

-- 1) Find which database holds the proc (run on the BISoxReports data source server)
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'SELECT ''' + name + N''' COLLATE DATABASE_DEFAULT AS DbName, s.name COLLATE DATABASE_DEFAULT AS SchemaName, p.name COLLATE DATABASE_DEFAULT AS ProcName, p.modify_date
                 FROM ' + QUOTENAME(name) + N'.sys.procedures p
                 JOIN ' + QUOTENAME(name) + N'.sys.schemas s ON s.schema_id = p.schema_id
                 WHERE p.name = ''CTG_RateReview_sp'' UNION ALL '
FROM sys.databases
WHERE state_desc = 'ONLINE';
SET @sql = LEFT(@sql, LEN(@sql) - LEN(' UNION ALL '));
EXEC sys.sp_executesql @sql;
GO

-- 2) Full definition - switch USE to the DbName returned above (likely BISoxReports)
-- USE BISoxReports;
-- GO
SELECT  OBJECT_SCHEMA_NAME(m.object_id) AS SchemaName,
        OBJECT_NAME(m.object_id)        AS ProcName,
        m.definition
FROM    sys.sql_modules m
WHERE   m.object_id = OBJECT_ID(N'dbo.CTG_RateReview_sp');
GO

-- 3) Parameters (confirm @StartDate / @EndDate types)
SELECT  p.name, TYPE_NAME(p.user_type_id) AS DataType, p.max_length, p.has_default_value
FROM    sys.parameters p
WHERE   p.object_id = OBJECT_ID(N'dbo.CTG_RateReview_sp');
GO

-- 4) Tables/objects the proc depends on
SELECT  DISTINCT d.referenced_database_name, d.referenced_schema_name, d.referenced_entity_name
FROM    sys.sql_expression_dependencies d
WHERE   d.referencing_id = OBJECT_ID(N'dbo.CTG_RateReview_sp')
ORDER BY d.referenced_entity_name;
GO
