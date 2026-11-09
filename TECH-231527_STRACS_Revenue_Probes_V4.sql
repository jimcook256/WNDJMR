/*
================================================================================
SCRIPT NAME:    TECH-231527_STRACS_Revenue_Probes_V4.sql
TICKET ID:      TECH-231527
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-09
MODIFIED:       2026-11-09
VERSION:        v4.0  (DIAGNOSTIC, read-only, not deployed)

PURPOSE:
    Follow-up to V3. V3 showed every order that did not match TMW invoices is
    not yet invoiced (status AVL) or cancelled. V4 answers what STRACS reports
    for those uninvoiced orders: does STRACS carry real revenue on orders TMW
    has not billed (7 of the 9 V3 orders have ord_totalcharge = 0.01), and how
    much of the Profit Analyzer revenue sits on unbilled orders?

SOURCE SYSTEM:  MANH, STRACS, TMW_LIVE on CTG-SQLAAG02 (PROD)
TARGET SYSTEM:  Ad hoc (SSMS)

BUSINESS LOGIC:
    - Run orders = MANH.dbo.PA_Customer_updated_loads (2,314 on 11/09/2026,
      confirmed against the 11/03 run in V3).
    - "Invoiced" = the order has at least one TMW_LIVE.dbo.invoiceheader row
      (invoiceheader.ord_hdrnumber). "Uninvoiced" = none.
    - Op Rev (as DOMO computes it) = LINEHAUL + OTHER; FSC is separate.
      Both are shown, plus EMERGENCY_FSC and REEFER_UPCHARGE, so the total can
      be read either way.
    - Result 4 finds orders that passed the V2/V3 invoice comparison on lines
      that are not attached to any invoice (ivh_hdrnumber 0 or NULL), so a
      "match" there is against unbilled rating lines, not an invoice.

CHANGE LOG:
    2026-11-03 - J.Cook - [TECH-231527] - v1.0 initial probes
    2026-11-03 - J.Cook - [TECH-231527] - v2.0 EMERGENCY_FSC / REEFER_UPCHARGE
    2026-11-09 - J.Cook - [TECH-231527] - v3.0 drop reconciliation, still-off
                 drill-down
    2026-11-09 - J.Cook - [TECH-231527] - v4.0 STRACS revenue on uninvoiced
                 orders

DEPENDENCIES:
    - STRACS.dbo.CVENDW_2
    - MANH.dbo.PA_Customer_updated_loads
    - TMW_LIVE.dbo.orderheader, invoiceheader, invoicedetail

NOTES:
    - Read-only. Writes only to tempdb (#PA, #S, #H, #O, #D).
    - Schema_Verification, TMW_Live (tmw_live_schema.json, 2026-07-28):
        orderheader   ord_hdrnumber int NOT NULL; ord_status varchar(6);
                      ord_invoicestatus varchar(6); ord_billto varchar(8);
                      ord_totalcharge float
        invoiceheader ord_hdrnumber int (nullable)
        invoicedetail ord_hdrnumber int; ivh_hdrnumber int (nullable)
      STRACS.CVENDW_2 columns as verified in V2 (INFORMATION_SCHEMA 11/03/2026).
================================================================================
*/

USE MANH;
GO
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#PA') IS NOT NULL DROP TABLE #PA;
IF OBJECT_ID('tempdb..#S')  IS NOT NULL DROP TABLE #S;
IF OBJECT_ID('tempdb..#H')  IS NOT NULL DROP TABLE #H;
IF OBJECT_ID('tempdb..#O')  IS NOT NULL DROP TABLE #O;
IF OBJECT_ID('tempdb..#D')  IS NOT NULL DROP TABLE #D;

/* Run orders, numeric only */
SELECT DISTINCT TRY_CONVERT(int, RTRIM(ordnumber)) AS ord
INTO   #PA
FROM   dbo.PA_Customer_updated_loads WITH (NOLOCK)
WHERE  TRY_CONVERT(int, RTRIM(ordnumber)) IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX ix_PA ON #PA (ord);

/* STRACS per order */
SELECT  s.ORDER_#                         AS ord,
        SUM(ISNULL(s.LINEHAUL, 0))        AS LH,
        SUM(ISNULL(s.FUEL_SURCHARGE, 0))  AS FSC,
        SUM(ISNULL(s.OTHER, 0))           AS OTH,
        SUM(ISNULL(s.EMERGENCY_FSC, 0))   AS EFSC,
        SUM(ISNULL(s.REEFER_UPCHARGE, 0)) AS REEF,
        MAX(s.LastUpdatedTimestamp)       AS LastUpd
INTO    #S
FROM    STRACS.dbo.CVENDW_2 s WITH (NOLOCK)
JOIN    #PA p ON p.ord = s.ORDER_#
GROUP BY s.ORDER_#;

CREATE UNIQUE CLUSTERED INDEX ix_S ON #S (ord);

/* Orders with at least one invoice header */
SELECT DISTINCT h.ord_hdrnumber AS ord
INTO   #H
FROM   TMW_LIVE.dbo.invoiceheader h WITH (NOLOCK)
JOIN   #PA p ON p.ord = h.ord_hdrnumber;

CREATE UNIQUE CLUSTERED INDEX ix_H ON #H (ord);

/* One row per run order: TMW status, STRACS values, invoiced flag */
SELECT  p.ord,
        CASE WHEN h.ord IS NULL THEN 0 ELSE 1 END AS Invoiced,
        oh.ord_status, oh.ord_invoicestatus, oh.ord_billto,
        CAST(ISNULL(oh.ord_totalcharge, 0) AS decimal(18, 2)) AS TmwOrderTotal,
        CASE WHEN s.ord IS NULL THEN 0 ELSE 1 END AS InStracs,
        ISNULL(s.LH, 0)   AS LH,   ISNULL(s.FSC, 0)  AS FSC,
        ISNULL(s.OTH, 0)  AS OTH,  ISNULL(s.EFSC, 0) AS EFSC,
        ISNULL(s.REEF, 0) AS REEF,
        ISNULL(s.LH + s.FSC + s.OTH + s.EFSC + s.REEF, 0) AS StracsAll,
        s.LastUpd
INTO    #O
FROM    #PA p
LEFT JOIN #H h  ON h.ord = p.ord
LEFT JOIN #S s  ON s.ord = p.ord
LEFT JOIN TMW_LIVE.dbo.orderheader oh WITH (NOLOCK) ON oh.ord_hdrnumber = p.ord;

CREATE UNIQUE CLUSTERED INDEX ix_O ON #O (ord);

/* Orders whose invoice lines are all unattached to an invoice header */
SELECT  d.ord_hdrnumber AS ord,
        COUNT(*)        AS Lines,
        SUM(CASE WHEN ISNULL(d.ivh_hdrnumber, 0) > 0 THEN 1 ELSE 0 END) AS AttachedLines
INTO    #D
FROM    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK)
JOIN    #PA p ON p.ord = d.ord_hdrnumber
GROUP BY d.ord_hdrnumber;

CREATE UNIQUE CLUSTERED INDEX ix_D ON #D (ord);

/* Result 1: invoiced vs uninvoiced run orders, STRACS revenue on each */
SELECT  CASE Invoiced WHEN 1 THEN 'Invoiced' ELSE 'Uninvoiced' END AS OrderGroup,
        COUNT(*)                                  AS Orders,
        SUM(InStracs)                             AS InStracs,
        SUM(CASE WHEN StracsAll > 0 THEN 1 ELSE 0 END)  AS WithStracsRevenue,
        SUM(LH + OTH)                             AS Stracs_OpRev,
        SUM(FSC)                                  AS Stracs_FSC,
        SUM(EFSC + REEF)                          AS Stracs_EfscAndReefer,
        SUM(StracsAll)                            AS Stracs_All,
        SUM(TmwOrderTotal)                        AS Tmw_OrderTotal
FROM    #O
GROUP BY Invoiced
ORDER BY Invoiced DESC;

/* Result 2: uninvoiced orders by TMW invoice status */
SELECT  ISNULL(ord_status, '') AS ord_status,
        ISNULL(ord_invoicestatus, '') AS ord_invoicestatus,
        COUNT(*)           AS Orders,
        SUM(InStracs)      AS InStracs,
        SUM(StracsAll)     AS Stracs_All,
        SUM(TmwOrderTotal) AS Tmw_OrderTotal
FROM    #O
WHERE   Invoiced = 0
GROUP BY ord_status, ord_invoicestatus
ORDER BY COUNT(*) DESC;

/* Result 3: uninvoiced orders where STRACS and the TMW order total disagree,
   largest first */
SELECT TOP 50
        ord, ord_status, ord_invoicestatus, ord_billto,
        TmwOrderTotal, LH, FSC, OTH, EFSC, REEF, StracsAll,
        StracsAll - TmwOrderTotal AS StracsMinusTmw, LastUpd
FROM    #O
WHERE   Invoiced = 0
  AND   ABS(StracsAll - TmwOrderTotal) > 1
ORDER BY ABS(StracsAll - TmwOrderTotal) DESC;

/* Result 4: orders that have invoice lines but none attached to an invoice */
SELECT  COUNT(*)                                        AS OrdersWithInvoiceLines,
        SUM(CASE WHEN d.AttachedLines = 0 THEN 1 ELSE 0 END) AS OrdersAllLinesUnattached,
        SUM(CASE WHEN d.AttachedLines = 0 THEN o.StracsAll ELSE 0 END) AS Stracs_All_OnThoseOrders,
        SUM(CASE WHEN d.AttachedLines = 0 THEN o.TmwOrderTotal ELSE 0 END) AS Tmw_OrderTotal_OnThoseOrders
FROM    #D d
JOIN    #O o ON o.ord = d.ord;
