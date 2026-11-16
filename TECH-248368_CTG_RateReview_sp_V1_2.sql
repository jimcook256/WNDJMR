/*
================================================================================
SCRIPT NAME:    TECH-248368_CTG_RateReview_sp_V1_2.sql
TICKET ID:      TECH-248368
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-16
MODIFIED:       2026-11-16
VERSION:        v1.2

PURPOSE:
    Add tariff HEADER rates (TMW_LIVE.dbo.tariffheader.tar_rate - flat per-mile /
    RPM rates with no row/column grid) to the Rate Review SSRS report so Revenue
    can audit them. Existing lane-based (tariffrate) logic is unchanged.

SOURCE SYSTEM:  TMW_LIVE (via BISoxReports.dbo.CTG_RateReview_sp)
TARGET SYSTEM:  SSRS /Covenant Reports Production/Revenue Reports/Rate Review
                (RDL unchanged - same 27 output columns, same names/types)

BUSINESS LOGIC:
    - NEW rows RecordType = 'Header'
    - Source: tariffheader with tar_rate > 0 and tar_updateon in [@StartDate, @EndDate]
    - One row per tariffkey (customer) attached to the tariff, INCLUDING ended keys
      (Expires column shows trk_enddate) - e.g. tariff 41785 ended 2026-08-15
    - Tariffs that already return lane rows (tariffrate.tra_rate > 0) are excluded
      so nothing is duplicated
    - OldRate / RateChange = 0 for Header rows (no header rate history table)
    - Lane columns blank; LocationKey = 'HEADER-<tar_number>'

CHANGE LOG:
    2026-11-16 - J.Cook - TECH-248368 - V1.2: removed active-key (trk_enddate) filter; tariff 41785 (ended 2026-08-15) was excluded
    2026-11-16 - J.Cook - TECH-248368 - Header-rate rows added (see inline markers)
    2026-11-16 - J.Cook - TECH-248368 - V1.1: added USE BISoxReports (ALTER must run in the proc's database)
    (prior history preserved in the original header comment below)

DEPENDENCIES:
    - TMW_LIVE.dbo.tariffheader / tariffkey / tariffrate / tariffrowcolumn / city
      / company / ttrheader / ttrdetail

NOTES:
    - ALTER of an existing SOX-scoped proc (BISoxReports). Needs SOX QA / DevOps.
    - Roll back: re-deploy the 2025-02-06 definition (prev version in DevOps).
    - ASSUMPTIONS TO CONFIRM WITH REVENUE: (1) tar_updateon is the right
      "added/changed" date, (2) tar_mincharge for Minimum, (3) exclude tariffs that
      already have grid rates, (4) ended tariff keys are included (Expires shows the end date).
================================================================================
*/

USE BISoxReports;   -- Jim Cook | TECH-248368
GO

ALTER PROCEDURE [dbo].[CTG_RateReview_sp]
    (@StartDate DATETIME
    ,@EndDate DATETIME
    )
AS

-------------------------------------------------------------------------------------------------------------------------------------------------
----  Original created by Larry Moore
----  Created By: Tariq Khan
----  Date......: 10/09/18
----  Purpose...: Pull rate changes and determine the amount of the change
----
-------------------------------------------------------------------------------------------------------------------------------------------------
-- Modified Author   Task  Description
-- 10/09/18 Tariq Khan  PMO-488  Created  (CTGIT-2097)
-- 09/23/19 Stephen Lewers Tech-7194 Select records by last_updatedate instead of tra_activedate (per Larry Moore's suggestion)
--           include Mileage Table from Company table
-- 10/08/19 Stephen Lewers Tech-7194a Mandy Christopher requested 'Before' to not be displayed.
-- 05/15/20 Stephen Lewers Tech-24784 'String or binary data would be truncated' error with #TariffRates.LocationKey
-- 08/20/22 Cody Roof  TECH-91967  Add the person that updated the rate
--  06/30/23 Rodney BLevins TECH-113812 Added effective date
--  02/06/2025  Dale Shofner TECH-164314 Moved from BInonsoxreports to BIsoxreports and added to Binonsoxreports.dbo.ctg_Soxscopedreports
--           inventory.
--  11/16/2026  Jim Cook  TECH-248368 Added tariff header (tariffheader.tar_rate) rates as RecordType 'Header'
-------------------------------------------------------------------------------------------------------------------------------------------------

---- EXEC CTG_RateReview_sp '2023-06-01','2023-06-30'

--DECLARE @StartDate DATETIME = '2019-08-01'
--DECLARE @EndDate   DATETIME = '2019-08-31'


SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;


IF OBJECT_ID('tempdb.dbo.#Tariffs','U') IS NOT NULL
    BEGIN
    DROP TABLE #Tariffs;
    END;

IF OBJECT_ID('tempdb.dbo.#TariffRates','U') IS NOT NULL
    BEGIN
    DROP TABLE #TariffRates;
    END;


IF OBJECT_ID('tempdb.dbo.#Changes','U') IS NOT NULL
    BEGIN
    DROP TABLE #Changes;
    END;

IF OBJECT_ID('tempdb.dbo.#RecordsToPull','U') IS NOT NULL
    BEGIN
    DROP TABLE #RecordsToPull;
    END;


IF OBJECT_ID('tempdb.dbo.#BillTos','U') IS NOT NULL
    BEGIN
    DROP TABLE #BillTos;
    END;

IF OBJECT_ID('tempdb.dbo.#HeaderRates','U') IS NOT NULL        -- Jim Cook | TECH-248368
    BEGIN                                                      -- Jim Cook | TECH-248368
    DROP TABLE #HeaderRates;                                   -- Jim Cook | TECH-248368
    END;                                                       -- Jim Cook | TECH-248368



CREATE TABLE #BillTos
(
    CustomerID VARCHAR(10)
   ,TarNumber  INT
);

CREATE TABLE #Tariffs
(
    Tariff#     INT
   ,Origin      CHAR(6)
   ,Destination CHAR(6)
);

CREATE TABLE #TariffRates
(
    Tariff#        INT
   ,OriginRegion   VARCHAR(50)
   ,OriginCity     VARCHAR(255)
   ,OriginState    VARCHAR(50)
   ,OriginZip      VARCHAR(50)
   ,OriginZipRange VARCHAR(255)
   ,DestRegion     VARCHAR(50)
   ,DestCity       VARCHAR(255)
   ,DestState      VARCHAR(50)
   ,DestZip        VARCHAR(50)
   ,DestZipRange   VARCHAR(255)
   ,Rate           MONEY
   ,last_updateby  VARCHAR(255)--TECH-91967
   ,OldRate        MONEY
   ,Minimum        MONEY
   ,Active         VARCHAR(20)
   ,Expires        VARCHAR(20)
   ,ColumnBasis    CHAR(6)
   ,RowBasis       CHAR(6)
--      ,LocationKey    VARCHAR(255)  -- Tech-24784
   ,LocationKey    VARCHAR(MAX)   -- Tech-24784
   ,LocationID     INT
   ,RecordType     VARCHAR(20)
   ,RecordID       INT IDENTITY
   ,Modified    DATETIME    -- Tech-7194
   ,trk_startdate  DATETIME    --TECH-113812
);

CREATE TABLE #HeaderRates                                       -- Jim Cook | TECH-248368
(                                                               -- Jim Cook | TECH-248368
    Tariff#        INT                                          -- Jim Cook | TECH-248368
   ,Company        VARCHAR(6)                                   -- Jim Cook | TECH-248368
   ,CustomerID     VARCHAR(10)                                  -- Jim Cook | TECH-248368
   ,CustomerName   VARCHAR(100)                                 -- Jim Cook | TECH-248368
   ,Rate           MONEY                                        -- Jim Cook | TECH-248368
   ,Minimum        MONEY                                        -- Jim Cook | TECH-248368
   ,Active         VARCHAR(20)                                  -- Jim Cook | TECH-248368
   ,Expires        VARCHAR(20)                                  -- Jim Cook | TECH-248368
   ,Modified       DATETIME                                     -- Jim Cook | TECH-248368
   ,MileageTable   VARCHAR(4)                                   -- Jim Cook | TECH-248368
   ,last_updateby  VARCHAR(256)                                 -- Jim Cook | TECH-248368
   ,StartDate      DATETIME                                     -- Jim Cook | TECH-248368
);                                                              -- Jim Cook | TECH-248368


CREATE TABLE #Changes
(
    TariffNumber INT
);


SET @EndDate = DATEADD(D,1,CAST(@EndDate AS DATE))

-- Find rates that have changed

INSERT INTO #Changes
    (TariffNumber
 )
SELECT DISTINCT tar_number
FROM TMW_LIVE.dbo.tariffrate
--WHERE tra_activedate >= @StartDate  -- Tech-7194
--  AND tra_activedate < @EndDate   -- Tech-7194
WHERE last_updatedate >= @StartDate   -- Tech-7194
  AND last_updatedate < @EndDate   -- Tech-7194
/* dates available in TMW_LIVE.dbo.tariffrate:  -- Tech-7194
 tra_retired
,last_updatedate
,tra_activedate
*/

-- Get Tariffs

INSERT INTO #Tariffs
    (
     Tariff#
    ,Origin
    ,Destination
    )
SELECT DISTINCT
     tk.tar_number
    ,CASE
      WHEN tar_rowbasis IN('OCT','OST','OZF','OZP','TTROR')
      THEN tar_rowbasis
      ELSE tar_colbasis
    END
    ,CASE
      WHEN tar_rowbasis IN('DCT','DST','DZF','DZP','TTRDR')
      THEN tar_rowbasis
      ELSE tar_colbasis
    END
FROM #Changes
JOIN tmw_live.dbo.tariffkey tk on TariffNumber = tk.tar_number
JOIN tmw_live.dbo.tariffheader th ON tk.tar_number = th.tar_number;


-- Get Rate and Lanes for each tariff
-- OCT = Origin City, OST = Origin State, OZF = Origin Zip Full, OZP = Origin 3-digit zip, TTROR = Origin Region
-- DCT = Dest City,   DST = Dest State,   DZF = Dest Zip Full,   DZP = Dest 3-digit zip,   TTRDR = Dest Region

INSERT INTO #TariffRates
    (
     Tariff#
    ,OriginRegion
    ,OriginCity
    ,OriginState
    ,OriginZip
    ,OriginZipRange
    ,DestRegion
    ,DestCity
    ,DestState
    ,DestZip
    ,DestZipRange
    ,Rate
    ,last_updateby --TECH-91967
    ,Minimum
    ,Active
    ,Expires
    ,ColumnBasis
    ,RowBasis
    ,Modified       -- Tech-7194
    ,trk_startdate     --TECH-113812
    )
SELECT
     Tariff#
    ,CASE
      WHEN tar_rowbasis = 'TTROR'
      THEN r.trc_matchvalue
      WHEN tar_colbasis = 'TTROR'
      THEN c.trc_matchvalue
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis = 'OCT'
      THEN ISNULL(c2.cty_name,r.trc_matchvalue)
      WHEN tar_colbasis = 'OCT'
      THEN ISNULL(c1.cty_name,c.trc_matchvalue)
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('OCT','OST')
      THEN ISNULL(c2.cty_state,r.trc_matchvalue)
      WHEN tar_colbasis IN('OCT','OST')
      THEN ISNULL(c1.cty_state,c.trc_matchvalue)
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('OZF')
      THEN r.trc_matchvalue
      WHEN tar_colbasis IN('OZF')
      THEN c.trc_matchvalue
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('OZP')
      THEN CASE
       WHEN ISNULL(r.trc_multimatch,'') != ''
       THEN r.trc_multimatch
       ELSE r.trc_matchvalue
       END
      WHEN tar_colbasis IN('OZP')
      THEN CASE
       WHEN ISNULL(c.trc_multimatch,'') != ''
       THEN c.trc_multimatch
       ELSE c.trc_matchvalue
       END
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis = 'TTRDR'
      THEN r.trc_matchvalue
      WHEN tar_colbasis = 'TTRDR'
      THEN c.trc_matchvalue
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis = 'DCT'
      THEN ISNULL(c2.cty_name,r.trc_matchvalue)
      WHEN tar_colbasis = 'DCT'
      THEN ISNULL(c1.cty_name,c.trc_matchvalue)
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('DCT','DST')
      THEN ISNULL(c2.cty_state,r.trc_matchvalue)
      WHEN tar_colbasis IN('DCT','DST')
      THEN ISNULL(c1.cty_state,c.trc_matchvalue)
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('DZF')
      THEN r.trc_matchvalue
      WHEN tar_colbasis IN('DZF')
      THEN c.trc_matchvalue
      ELSE ''
    END
    ,CASE
      WHEN tar_rowbasis IN('DZP')
      THEN CASE
       WHEN ISNULL(r.trc_multimatch,'') != ''
       THEN r.trc_multimatch
       ELSE r.trc_matchvalue
       END
      WHEN tar_colbasis IN('DZP')
      THEN CASE
       WHEN ISNULL(c.trc_multimatch,'') != ''
       THEN c.trc_multimatch
       ELSE c.trc_matchvalue
       END
      ELSE ''
    END
    ,tra_rate
    ,tr.last_updateby --TECH-91967
    ,ISNULL(tra_minrate,0)
    ,CAST(tra_activedate AS DATE)
    ,CAST(tra_retired AS DATE)
    ,tar_rowbasis
    ,tar_colbasis
    ,tr.last_updatedate      -- Tech-7194
    ,tk.trk_startdate     --TECH-113812
FROM #Tariffs
JOIN TMW_LIVE.dbo.tariffheader th ON Tariff# = th.tar_number
JOIN TMW_LIVE.dbo.tariffrate tr ON Tariff# = tr.tar_number
JOIN tmw_live.dbo.tariffrowcolumn c ON c.trc_number = trc_number_col
LEFT JOIN tmw_live.dbo.tariffkey tk ON tk.tar_number = Tariff#
                 AND c.trc_rowcolumn = 'C'
LEFT JOIN tmw_live.dbo.city c1 ON CAST(c1.cty_code AS VARCHAR) = c.trc_matchvalue
JOIN tmw_live.dbo.tariffrowcolumn r ON r.trc_number = trc_number_row
                 AND r.trc_rowcolumn = 'R'
LEFT JOIN tmw_live.dbo.city c2 ON CAST(c2.cty_code AS VARCHAR) = r.trc_matchvalue
WHERE tra_rate > 0;

-- Load Zip Ranges that are defined as Regions

UPDATE #TariffRates
 SET
    OriginZipRange =
    (
    SELECT
        STUFF(
         (
         SELECT
           ', '+td1.ttrd_value
         FROM tmw_live.dbo.ttrheader th1
          JOIN tmw_live.dbo.ttrdetail td1  ON th1.ttr_number = td1.ttr_number
         WHERE th1.ttr_code = OriginRegion
           AND td1.ttrd_include_or_exclude = 'I' FOR
         XML PATH(''),TYPE
         ) .value('.','varchar(255)'),1,1,'')
    FROM tmw_live.dbo.ttrheader th2
     JOIN tmw_live.dbo.ttrdetail td2  ON th2.ttr_number = td2.ttr_number
    WHERE th2.ttr_code = OriginRegion
      AND td2.ttrd_include_or_exclude = 'I'
    GROUP BY
        td2.ttr_number
    )
 WHERE
    OriginRegion != '';

UPDATE #TariffRates
 SET
    DestZipRange =
    (
    SELECT
        STUFF(
         (
         SELECT
           ', '+td1.ttrd_value
         FROM tmw_live.dbo.ttrheader th1
          JOIN tmw_live.dbo.ttrdetail td1 ON th1.ttr_number = td1.ttr_number
         WHERE th1.ttr_code = DestRegion
           AND td1.ttrd_include_or_exclude = 'I' FOR
         XML PATH(''),TYPE
         ) .value('.','varchar(255)'),1,1,'')
    FROM tmw_live.dbo.ttrheader th2
     JOIN tmw_live.dbo.ttrdetail td2 ON th2.ttr_number = td2.ttr_number
    WHERE th2.ttr_code = DestRegion
      AND td2.ttrd_include_or_exclude = 'I'
    GROUP BY
        td2.ttr_number
    )
 WHERE
    DestRegion != '';


UPDATE #TariffRates
   SET LocationKey = OriginRegion + OriginCity + OriginState + OriginZip + OriginZipRange
           + DestRegion + DestCity + DestState + DestZip + DestZipRange

-- Create a Key for each Origin - Destination combo

    SELECT DISTINCT LocationKey 'LKey'
    INTO #RecordsToPull
    FROM #TariffRates
    --WHERE Active >= @StartDate AND Active < @EndDate   -- Tech-7194
    WHERE Modified >= @StartDate AND Modified < @EndDate   -- Tech-7194

-- Add sequence number for each location key

    ;WITH CTE AS
    (
    SELECT LocationKey, RecordID
   ,row_number() OVER (PARTITION BY LocationKey ORDER BY Active) GROUPSEQ
    FROM #TariffRates
    )
    UPDATE #TariffRates
    SET LocationID = GROUPSEQ
    FROM CTE
    WHERE #TariffRates.RecordID = CTE.RecordID


    INSERT INTO #BillTos
    ( CustomerID
     ,TarNumber
    )
    SELECT
     DISTINCT trk_billto, Tariff#
    FROM #Tariffs
 JOIN TMW_LIVE.dbo.tariffkey ON tar_number = Tariff#


/*   Explanation by Larry Moore about the Record Types: Tech-7194a  10/04/19 21:22
“New” rates are new tariffs that have been added.
“Before” is the rate before the tariff was changed.
“After” is the rate after the tariff was changed.
*/

    UPDATE T1
     SET OldRate = ISNULL((SELECT TOP 1 T2.Rate FROM #TariffRates T2 WHERE T2.Tariff# = T1.Tariff# AND T2.LocationKey = T1.LocationKey and T2.LocationID = (T1.LocationID - 1)), 0)
 FROM #TariffRates T1


    UPDATE T1
 SET RecordType = CASE
                       WHEN T3.MaxLoc = 1
     THEN 'New'
     WHEN T1.LocationID % 2 = 0
     THEN 'After'
     ELSE 'Before'
                      END
 FROM #TariffRates T1
 CROSS APPLY (SELECT MAX(LocationID) 'MaxLoc' FROM #TariffRates T2 WHERE T2.Tariff# = T1.Tariff# AND T2.LocationKey = T1.LocationKey) T3


-- Header (flat) rates: tariffheader.tar_rate with no lane grid                              -- Jim Cook | TECH-248368
-- One row per active tariffkey (customer). Tariffs already returning lane rows are skipped. -- Jim Cook | TECH-248368
INSERT INTO #HeaderRates                                                                     -- Jim Cook | TECH-248368
    (                                                                                        -- Jim Cook | TECH-248368
     Tariff#                                                                                 -- Jim Cook | TECH-248368
    ,Company                                                                                 -- Jim Cook | TECH-248368
    ,CustomerID                                                                              -- Jim Cook | TECH-248368
    ,CustomerName                                                                            -- Jim Cook | TECH-248368
    ,Rate                                                                                    -- Jim Cook | TECH-248368
    ,Minimum                                                                                 -- Jim Cook | TECH-248368
    ,Active                                                                                  -- Jim Cook | TECH-248368
    ,Expires                                                                                 -- Jim Cook | TECH-248368
    ,Modified                                                                                -- Jim Cook | TECH-248368
    ,MileageTable                                                                            -- Jim Cook | TECH-248368
    ,last_updateby                                                                           -- Jim Cook | TECH-248368
    ,StartDate                                                                               -- Jim Cook | TECH-248368
    )                                                                                        -- Jim Cook | TECH-248368
SELECT                                                                                       -- Jim Cook | TECH-248368
     thh.tar_number                                                                          -- Jim Cook | TECH-248368
    ,cmp.cmp_revtype1                                                                        -- Jim Cook | TECH-248368
    ,tkh.trk_billto                                                                          -- Jim Cook | TECH-248368
    ,cmp.cmp_name                                                                            -- Jim Cook | TECH-248368
    ,thh.tar_rate                                                                            -- Jim Cook | TECH-248368
    ,ISNULL(thh.tar_mincharge,0)                                                             -- Jim Cook | TECH-248368
    ,CAST(CAST(tkh.trk_startdate AS DATE) AS VARCHAR(20))                                    -- Jim Cook | TECH-248368
    ,CAST(CAST(tkh.trk_enddate AS DATE) AS VARCHAR(20))                                      -- Jim Cook | TECH-248368
    ,thh.tar_updateon                                                                        -- Jim Cook | TECH-248368
    ,ISNULL(cmp.cmp_mileagetable,'')                                                         -- Jim Cook | TECH-248368
    ,thh.tar_updateby                                                                        -- Jim Cook | TECH-248368
    ,tkh.trk_startdate                                                                       -- Jim Cook | TECH-248368
FROM TMW_LIVE.dbo.tariffheader thh                                                           -- Jim Cook | TECH-248368
JOIN TMW_LIVE.dbo.tariffkey tkh ON tkh.tar_number = thh.tar_number                           -- Jim Cook | TECH-248368
LEFT JOIN TMW_LIVE.dbo.company cmp ON cmp.cmp_id = tkh.trk_billto                            -- Jim Cook | TECH-248368
WHERE thh.tar_rate > 0                                                                       -- Jim Cook | TECH-248368
  AND thh.tar_updateon >= @StartDate                                                         -- Jim Cook | TECH-248368
  AND thh.tar_updateon < @EndDate                                                            -- Jim Cook | TECH-248368
  AND NOT EXISTS (SELECT 1 FROM TMW_LIVE.dbo.tariffrate trh                                  -- Jim Cook | TECH-248368
                  WHERE trh.tar_number = thh.tar_number AND trh.tra_rate > 0);               -- Jim Cook | TECH-248368


    SELECT
     RecordType
    ,Tariff#
    ,cmp_revtype1 'Company'
    ,CustomerID
    ,cmp_name 'CustomerName'
    ,OriginRegion
    ,OriginCity
    ,OriginState
    ,OriginZip
    ,OriginZipRange
    ,DestRegion
    ,DestCity
    ,DestState
    ,DestZip
    ,DestZipRange
    ,Rate
    ,OldRate
    ,CASE
        WHEN OldRate = 0
        THEN 0
        ELSE Rate - OldRate
     END 'RateChange'
    ,Minimum
    ,Active
    ,Expires
    ,LocationKey
    ,LocationID
    ,Modified            -- Tech-7194
    ,ISNULL(cmp_mileagetable,'') 'MileageTable'   -- Tech-7194
    ,last_updateby -- TECH-91967
    ,trk_startdate as 'StartDate'       --TECH-113812
 FROM #TariffRates
 JOIN #RecordsToPull ON LocationKey = LKey
 JOIN #BillTos on TarNumber = Tariff#
 LEFT JOIN TMW_LIVE.dbo.company ON cmp_id = CustomerID
 WHERE Modified >= @StartDate AND Modified < @EndDate   -- Tech-7194
 and #TariffRates.RecordType <> 'Before'      -- Tech-7194a

 UNION ALL                                                -- Jim Cook | TECH-248368
 SELECT                                                   -- Jim Cook | TECH-248368
     'Header'                                             -- Jim Cook | TECH-248368
    ,Tariff#                                              -- Jim Cook | TECH-248368
    ,Company                                              -- Jim Cook | TECH-248368
    ,CustomerID                                           -- Jim Cook | TECH-248368
    ,CustomerName                                         -- Jim Cook | TECH-248368
    ,''                                                   -- Jim Cook | TECH-248368  OriginRegion
    ,''                                                   -- Jim Cook | TECH-248368  OriginCity
    ,''                                                   -- Jim Cook | TECH-248368  OriginState
    ,''                                                   -- Jim Cook | TECH-248368  OriginZip
    ,''                                                   -- Jim Cook | TECH-248368  OriginZipRange
    ,''                                                   -- Jim Cook | TECH-248368  DestRegion
    ,''                                                   -- Jim Cook | TECH-248368  DestCity
    ,''                                                   -- Jim Cook | TECH-248368  DestState
    ,''                                                   -- Jim Cook | TECH-248368  DestZip
    ,''                                                   -- Jim Cook | TECH-248368  DestZipRange
    ,Rate                                                 -- Jim Cook | TECH-248368
    ,CAST(0 AS MONEY)                                     -- Jim Cook | TECH-248368  OldRate
    ,0                                                    -- Jim Cook | TECH-248368  RateChange
    ,Minimum                                              -- Jim Cook | TECH-248368
    ,Active                                               -- Jim Cook | TECH-248368
    ,Expires                                              -- Jim Cook | TECH-248368
    ,'HEADER-' + CAST(Tariff# AS VARCHAR(12))             -- Jim Cook | TECH-248368  LocationKey
    ,1                                                    -- Jim Cook | TECH-248368  LocationID
    ,Modified                                             -- Jim Cook | TECH-248368
    ,MileageTable                                         -- Jim Cook | TECH-248368
    ,last_updateby                                        -- Jim Cook | TECH-248368
    ,StartDate                                            -- Jim Cook | TECH-248368
 FROM #HeaderRates                                        -- Jim Cook | TECH-248368

 ORDER BY Tariff#, CustomerID,  LocationKey, LocationID
