/*
================================================================================
SCRIPT NAME:    TECH-248368_ReportServer_RateReview_RDL_Pull_V1.sql
TICKET ID:      TECH-248368
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
MODIFIED:       2026-11-16
VERSION:        v1.0

PURPOSE:
    Pull the Rate Review SSRS report definition (RDL) and its dataset command
    text from the ReportServer catalog so the header-rate (tariffheader.tar_rate)
    enhancement can be built on the real report logic.

SOURCE SYSTEM:  ReportServer (SSRS catalog DB on the reporting server)
TARGET SYSTEM:  SSMS result grid (read-only)

BUSINESS LOGIC:
    - Report path: /Covenant Reports Production/Revenue Reports/Rate Review
    - Catalog.Type: 2 = Report, 5 = Data Source, 8 = Shared Dataset
    - Content is varbinary; strip UTF-8 BOM (EF BB BF) before casting to XML

CHANGE LOG:
    2026-11-16 - J.Cook - TECH-248368 - Initial build

DEPENDENCIES:
    - ReportServer.dbo.Catalog

NOTES:
    - Read-only. Standard SSRS catalog schema (not in TMW_Live); confirm column
      names in SSMS if the server version differs.
    - Run against the ReportServer database (not ReportServerTempDB).
================================================================================
*/

USE ReportServer;
GO

-- 1) Locate the report and confirm path/ItemID/last modified
SELECT  c.ItemID,
        c.Path,
        c.Name,
        c.Type,
        c.ModifiedDate,
        c.CreationDate
FROM    dbo.Catalog c WITH (NOLOCK)
WHERE   c.Type = 2
  AND   c.Path LIKE '%Revenue Reports/Rate Review%';
GO

-- 2) Dataset names, data sources, and command text (SQL / stored proc) inside the RDL
;WITH RptXml AS (
    SELECT  c.ItemID,
            c.Path,
            CAST(CASE WHEN LEFT(CAST(c.Content AS VARBINARY(3)), 3) = 0xEFBBBF
                      THEN CAST(SUBSTRING(c.Content, 4, DATALENGTH(c.Content)) AS VARCHAR(MAX))
                      ELSE CAST(c.Content AS VARCHAR(MAX))
                 END AS XML) AS Rdl
    FROM    dbo.Catalog c WITH (NOLOCK)
    WHERE   c.Type = 2
      AND   c.Path LIKE '%Revenue Reports/Rate Review%'
)
SELECT  r.Path,
        ds.value('@Name', 'VARCHAR(200)')                                                    AS DataSetName,
        ds.value('(*:Query/*:DataSourceName)[1]', 'VARCHAR(200)')                            AS DataSourceName,
        ds.value('(*:Query/*:CommandType)[1]', 'VARCHAR(50)')                                AS CommandType,   -- NULL = Text
        ds.value('(*:Query/*:CommandText)[1]', 'VARCHAR(MAX)')                               AS CommandText,
        ds.value('(*:SharedDataSet/*:SharedDataSetReference)[1]', 'VARCHAR(500)')            AS SharedDataSetRef
FROM    RptXml r
CROSS APPLY r.Rdl.nodes('/*:Report/*:DataSets/*:DataSet') AS t(ds);
GO

-- 3) Full RDL text (copy the cell, save as .rdl) - for the SOX before/after package
SELECT  c.Path,
        CAST(CASE WHEN LEFT(CAST(c.Content AS VARBINARY(3)), 3) = 0xEFBBBF
                  THEN CAST(SUBSTRING(c.Content, 4, DATALENGTH(c.Content)) AS VARCHAR(MAX))
                  ELSE CAST(c.Content AS VARCHAR(MAX))
             END AS XML) AS RdlXml
FROM    dbo.Catalog c WITH (NOLOCK)
WHERE   c.Type = 2
  AND   c.Path LIKE '%Revenue Reports/Rate Review%';
GO

-- 4) If CommandText is empty, the report uses a shared dataset - find it
SELECT  c.ItemID, c.Path, c.Name, c.ModifiedDate
FROM    dbo.Catalog c WITH (NOLOCK)
WHERE   c.Type = 8
  AND   (c.Name LIKE '%Rate%Review%' OR c.Path LIKE '%Rate Review%');
GO
