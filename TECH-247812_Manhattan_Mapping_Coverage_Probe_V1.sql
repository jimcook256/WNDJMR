/*
================================================================================
SCRIPT NAME:    TECH-247812_Manhattan_Mapping_Coverage_Probe_V1.sql
TICKET ID:      TECH-247812  (builds on TECH-231527)
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-09
MODIFIED:       2026-11-09
VERSION:        v1.0  (DIAGNOSTIC, read-only, not deployed)

PURPOSE:
    Accessorial charges and pay reach Manhattan as (acc_index, value) rows
    through two mapping tables. A TMW charge or pay code with no index in them
    is not sent. This probe lists, for charges billed and pay posted since
    @since, which codes are mapped, which are in the table without an index,
    and which are missing entirely, with the dollars at stake. It also shows
    what the last run actually sent, and how the current mappings differ from
    the older copies kept beside them.

SOURCE SYSTEM:  MANH, TMW_LIVE on CTG-SQLAAG02 (PROD)
TARGET SYSTEM:  Ad hoc (SSMS)

BUSINESS LOGIC:
    - Mapping tables (columns verified from the 11/09 lineage run):
        manh_cht_itemcode_Mapping: cht_basis, cht_itemcode, cht_description,
            counted, Cost_manh_acc_index, Reve_manh_acc_index
        manh_pyt_itemcode_Mapping: pyt_basis, pyt_itemcode, pyt_description,
            counted, Cost_manh_acc_index, Reve_manh_acc_index
    - Charges = TMW_LIVE.dbo.invoicedetail on invoices billed on or after
      @since (invoiceheader.ivh_billdate). Pay = TMW_LIVE.dbo.paydetail with
      pyd_transdate on or after @since.
    - Status: NOT IN MAPPING (no row); IN MAPPING, NO INDEX (row, both indexes
      NULL); MAPPED (at least one index). What an index value of 0 means is not
      documented, so raw index values are shown, not interpreted.
    - Not every charge is expected in the mapping: linehaul and fuel go in
      manh_shipment tariff columns, not accessorials. Read Result 1 with that
      in mind and confirm any unexpected NOT IN MAPPING code with the sproc
      source (usp_ns_manh_shipment_accessorial, vwPAList_cht_itemcode_manh).
    - Result 4 compares to the Stakeholder Guide figure: AIT guaranteed miles,
      minimum charges and stop charges missing from revenue, $22,314 on 10
      lines, in the 11/03 run.
    - Needs no server-level rights (no DMVs).

CHANGE LOG:
    2026-11-09 - J.Cook - [TECH-247812] - v1.0 initial build

DEPENDENCIES:
    - MANH.dbo.manh_cht_itemcode_Mapping, manh_pyt_itemcode_Mapping and the
      older copies _08_01_2013, _11_26 (both) and _Original
    - MANH.dbo.manh_shipment_accessorial, manh_dispatch_accessorial,
      PA_Customer_updated_loads
    - TMW_LIVE.dbo.invoiceheader, invoicedetail, chargetype, paydetail, paytype

NOTES:
    - Schema_Verification, TMW_Live (tmw_live_schema.json, 2026-07-28):
        invoiceheader ivh_hdrnumber int NOT NULL; ivh_billdate datetime NULL
        invoicedetail ivh_hdrnumber int NULL; ord_hdrnumber int NULL;
                      cht_itemcode varchar(6) NULL; ivd_charge money NULL
        chargetype    cht_itemcode varchar(6) NOT NULL;
                      cht_description varchar(30) NOT NULL
        paydetail     lgh_number int NULL; pyt_itemcode varchar(6) NULL;
                      pyd_amount money NULL; pyd_transdate datetime NULL
        paytype       pyt_itemcode varchar(6) NOT NULL;
                      pyt_description varchar(30) NULL
      MANH columns as returned by the 11/09 run. PA_Customer_updated_loads
      .ordnumber type is not verified; read with TRY_CONVERT(int, RTRIM(...)).
    - The MANH tables hold only the last run, so Results 3 and 4 describe the
      11/03 run, not May to now. Results 1, 2 and 5 are TMW-side and cover
      everything since @since.
================================================================================
*/

USE MANH;
GO
SET NOCOUNT ON;

DECLARE @since datetime = '2026-05-01';   -- change to widen or narrow the window

IF OBJECT_ID('tempdb..#ChtMap') IS NOT NULL DROP TABLE #ChtMap;
IF OBJECT_ID('tempdb..#PytMap') IS NOT NULL DROP TABLE #PytMap;
IF OBJECT_ID('tempdb..#PA')     IS NOT NULL DROP TABLE #PA;

/* One row per code even if the mapping table repeats a code across bases */
SELECT  cht_itemcode,
        COUNT(*)                     AS MapRows,
        MAX(cht_basis)               AS Basis,
        MAX(counted)                 AS Counted,
        MAX(Cost_manh_acc_index)     AS CostIdx,
        MAX(Reve_manh_acc_index)     AS ReveIdx
INTO    #ChtMap
FROM    dbo.manh_cht_itemcode_Mapping
GROUP BY cht_itemcode;

SELECT  pyt_itemcode,
        COUNT(*)                     AS MapRows,
        MAX(pyt_basis)               AS Basis,
        MAX(counted)                 AS Counted,
        MAX(Cost_manh_acc_index)     AS CostIdx,
        MAX(Reve_manh_acc_index)     AS ReveIdx
INTO    #PytMap
FROM    dbo.manh_pyt_itemcode_Mapping
GROUP BY pyt_itemcode;

SELECT DISTINCT TRY_CONVERT(int, RTRIM(ordnumber)) AS ord
INTO   #PA
FROM   dbo.PA_Customer_updated_loads WITH (NOLOCK)
WHERE  TRY_CONVERT(int, RTRIM(ordnumber)) IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX ix_PA ON #PA (ord);

/* Result 1: charge codes billed since @since, by mapping status */
WITH Billed AS (
    SELECT  d.cht_itemcode,
            COUNT(*)                         AS Lines,
            COUNT(DISTINCT d.ord_hdrnumber)  AS Orders,
            SUM(ISNULL(d.ivd_charge, 0))     AS Amount
    FROM    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK)
    JOIN    TMW_LIVE.dbo.invoiceheader h WITH (NOLOCK) ON h.ivh_hdrnumber = d.ivh_hdrnumber
    WHERE   h.ivh_billdate >= @since
    GROUP BY d.cht_itemcode
)
SELECT  b.cht_itemcode,
        ct.cht_description,
        b.Lines, b.Orders, b.Amount,
        m.MapRows, m.Counted, m.CostIdx, m.ReveIdx,
        CASE WHEN m.cht_itemcode IS NULL THEN 'NOT IN MAPPING'
             WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 'IN MAPPING, NO INDEX'
             ELSE 'MAPPED' END AS Status
FROM    Billed b
LEFT JOIN TMW_LIVE.dbo.chargetype ct WITH (NOLOCK) ON ct.cht_itemcode = b.cht_itemcode
LEFT JOIN #ChtMap m ON m.cht_itemcode = b.cht_itemcode
ORDER BY CASE WHEN m.cht_itemcode IS NULL THEN 0
              WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 1 ELSE 2 END,
         ABS(b.Amount) DESC;

/* Result 2: pay codes posted since @since, by mapping status */
WITH Paid AS (
    SELECT  p.pyt_itemcode,
            COUNT(*)                         AS Lines,
            COUNT(DISTINCT p.lgh_number)     AS Legs,
            SUM(ISNULL(p.pyd_amount, 0))     AS Amount
    FROM    TMW_LIVE.dbo.paydetail p WITH (NOLOCK)
    WHERE   p.pyd_transdate >= @since
    GROUP BY p.pyt_itemcode
)
SELECT  p.pyt_itemcode,
        pt.pyt_description,
        p.Lines, p.Legs, p.Amount,
        m.MapRows, m.Counted, m.CostIdx, m.ReveIdx,
        CASE WHEN m.pyt_itemcode IS NULL THEN 'NOT IN MAPPING'
             WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 'IN MAPPING, NO INDEX'
             ELSE 'MAPPED' END AS Status
FROM    Paid p
LEFT JOIN TMW_LIVE.dbo.paytype pt WITH (NOLOCK) ON pt.pyt_itemcode = p.pyt_itemcode
LEFT JOIN #PytMap m ON m.pyt_itemcode = p.pyt_itemcode
ORDER BY CASE WHEN m.pyt_itemcode IS NULL THEN 0
              WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 1 ELSE 2 END,
         ABS(p.Amount) DESC;

/* Result 3: what the last run actually sent, by acc_index */
SELECT  'manh_shipment_accessorial' AS SentTable,
        acc_index,
        COUNT(*)                    AS Rows_,
        COUNT(DISTINCT shipment)    AS Orders,
        SUM(CAST(value AS float))   AS TotalValue
FROM    dbo.manh_shipment_accessorial
GROUP BY acc_index
UNION ALL
SELECT  'manh_dispatch_accessorial',
        acc_index,
        COUNT(*),
        COUNT(DISTINCT shipment),
        SUM(CAST(value AS float))
FROM    dbo.manh_dispatch_accessorial
GROUP BY acc_index
ORDER BY SentTable, acc_index;

/* Result 3b: indexes defined in the mapping tables that the last run never sent */
WITH Defined AS (
    SELECT 'cht Cost' AS Src, Cost_manh_acc_index AS idx FROM dbo.manh_cht_itemcode_Mapping WHERE Cost_manh_acc_index IS NOT NULL
    UNION SELECT 'cht Reve', Reve_manh_acc_index FROM dbo.manh_cht_itemcode_Mapping WHERE Reve_manh_acc_index IS NOT NULL
    UNION SELECT 'pyt Cost', Cost_manh_acc_index FROM dbo.manh_pyt_itemcode_Mapping WHERE Cost_manh_acc_index IS NOT NULL
    UNION SELECT 'pyt Reve', Reve_manh_acc_index FROM dbo.manh_pyt_itemcode_Mapping WHERE Reve_manh_acc_index IS NOT NULL
),
Sent AS (
    SELECT DISTINCT acc_index FROM dbo.manh_shipment_accessorial
    UNION
    SELECT DISTINCT acc_index FROM dbo.manh_dispatch_accessorial
)
SELECT  d.Src, d.idx AS DefinedIndex, 'not sent in last run' AS Note
FROM    Defined d
LEFT JOIN Sent s ON s.acc_index = d.idx
WHERE   s.acc_index IS NULL
ORDER BY d.Src, d.idx;

/* Result 4: the last run's invoice lines by mapping status (compare to $22,314 on 10 lines) */
SELECT  CASE WHEN m.cht_itemcode IS NULL THEN 'NOT IN MAPPING'
             WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 'IN MAPPING, NO INDEX'
             ELSE 'MAPPED' END AS Status,
        COUNT(*)                         AS Lines,
        COUNT(DISTINCT d.ord_hdrnumber)  AS Orders,
        SUM(ISNULL(d.ivd_charge, 0))     AS Amount
FROM    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK)
JOIN    #PA p ON p.ord = d.ord_hdrnumber
LEFT JOIN #ChtMap m ON m.cht_itemcode = d.cht_itemcode
GROUP BY CASE WHEN m.cht_itemcode IS NULL THEN 'NOT IN MAPPING'
              WHEN m.CostIdx IS NULL AND m.ReveIdx IS NULL THEN 'IN MAPPING, NO INDEX'
              ELSE 'MAPPED' END
ORDER BY Status;

/* Result 4b: the unmapped codes on the last run's orders, largest first */
SELECT  d.cht_itemcode,
        ct.cht_description,
        COUNT(*)                         AS Lines,
        COUNT(DISTINCT d.ord_hdrnumber)  AS Orders,
        SUM(ISNULL(d.ivd_charge, 0))     AS Amount,
        CASE WHEN m.cht_itemcode IS NULL THEN 'NOT IN MAPPING' ELSE 'IN MAPPING, NO INDEX' END AS Status
FROM    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK)
JOIN    #PA p ON p.ord = d.ord_hdrnumber
LEFT JOIN #ChtMap m ON m.cht_itemcode = d.cht_itemcode
LEFT JOIN TMW_LIVE.dbo.chargetype ct WITH (NOLOCK) ON ct.cht_itemcode = d.cht_itemcode
WHERE   m.cht_itemcode IS NULL OR (m.CostIdx IS NULL AND m.ReveIdx IS NULL)
GROUP BY d.cht_itemcode, ct.cht_description,
         CASE WHEN m.cht_itemcode IS NULL THEN 'NOT IN MAPPING' ELSE 'IN MAPPING, NO INDEX' END
ORDER BY ABS(SUM(ISNULL(d.ivd_charge, 0))) DESC;

/* Result 5: how the current mappings differ from the older copies kept beside them */
SELECT  'charge' AS Kind, 'vs _08_01_2013' AS Compared,
        COALESCE(c.cht_itemcode, o.cht_itemcode) AS ItemCode,
        c.Cost_manh_acc_index AS CurCost, c.Reve_manh_acc_index AS CurReve,
        o.Cost_manh_acc_index AS OldCost, o.Reve_manh_acc_index AS OldReve,
        CASE WHEN c.cht_itemcode IS NULL THEN 'only in old copy'
             WHEN o.cht_itemcode IS NULL THEN 'only in current'
             ELSE 'index changed' END AS Change
FROM    dbo.manh_cht_itemcode_Mapping c
FULL OUTER JOIN dbo.manh_cht_itemcode_Mapping_08_01_2013 o ON o.cht_itemcode = c.cht_itemcode
WHERE   c.cht_itemcode IS NULL OR o.cht_itemcode IS NULL
   OR   ISNULL(c.Cost_manh_acc_index, -1) <> ISNULL(o.Cost_manh_acc_index, -1)
   OR   ISNULL(c.Reve_manh_acc_index, -1) <> ISNULL(o.Reve_manh_acc_index, -1)
UNION ALL
SELECT  'charge', 'vs _11_26',
        COALESCE(c.cht_itemcode, o.cht_itemcode),
        c.Cost_manh_acc_index, c.Reve_manh_acc_index,
        o.Cost_manh_acc_index, o.Reve_manh_acc_index,
        CASE WHEN c.cht_itemcode IS NULL THEN 'only in old copy'
             WHEN o.cht_itemcode IS NULL THEN 'only in current'
             ELSE 'index changed' END
FROM    dbo.manh_cht_itemcode_Mapping c
FULL OUTER JOIN dbo.manh_cht_itemcode_Mapping_11_26 o ON o.cht_itemcode = c.cht_itemcode
WHERE   c.cht_itemcode IS NULL OR o.cht_itemcode IS NULL
   OR   ISNULL(c.Cost_manh_acc_index, -1) <> ISNULL(o.Cost_manh_acc_index, -1)
   OR   ISNULL(c.Reve_manh_acc_index, -1) <> ISNULL(o.Reve_manh_acc_index, -1)
UNION ALL
SELECT  'pay', 'vs _11_26',
        COALESCE(c.pyt_itemcode, o.pyt_itemcode),
        c.Cost_manh_acc_index, c.Reve_manh_acc_index,
        o.Cost_manh_acc_index, o.Reve_manh_acc_index,
        CASE WHEN c.pyt_itemcode IS NULL THEN 'only in old copy'
             WHEN o.pyt_itemcode IS NULL THEN 'only in current'
             ELSE 'index changed' END
FROM    dbo.manh_pyt_itemcode_Mapping c
FULL OUTER JOIN dbo.manh_pyt_itemcode_Mapping_11_26 o ON o.pyt_itemcode = c.pyt_itemcode
WHERE   c.pyt_itemcode IS NULL OR o.pyt_itemcode IS NULL
   OR   ISNULL(c.Cost_manh_acc_index, -1) <> ISNULL(o.Cost_manh_acc_index, -1)
   OR   ISNULL(c.Reve_manh_acc_index, -1) <> ISNULL(o.Reve_manh_acc_index, -1)
UNION ALL
SELECT  'pay', 'vs _Original',
        COALESCE(c.pyt_itemcode, o.pyt_itemcode),
        c.Cost_manh_acc_index, c.Reve_manh_acc_index,
        o.Cost_manh_acc_index, o.Reve_manh_acc_index,
        CASE WHEN c.pyt_itemcode IS NULL THEN 'only in old copy'
             WHEN o.pyt_itemcode IS NULL THEN 'only in current'
             ELSE 'index changed' END
FROM    dbo.manh_pyt_itemcode_Mapping c
FULL OUTER JOIN dbo.manh_pyt_itemcode_Mapping_Original o ON o.pyt_itemcode = c.pyt_itemcode
WHERE   c.pyt_itemcode IS NULL OR o.pyt_itemcode IS NULL
   OR   ISNULL(c.Cost_manh_acc_index, -1) <> ISNULL(o.Cost_manh_acc_index, -1)
   OR   ISNULL(c.Reve_manh_acc_index, -1) <> ISNULL(o.Reve_manh_acc_index, -1)
ORDER BY Kind, Compared, Change, ItemCode;
