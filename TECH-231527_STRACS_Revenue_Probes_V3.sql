/*
================================================================================
SCRIPT NAME:    TECH-231527_STRACS_Revenue_Probes_V3.sql
TICKET ID:      TECH-231527
AUTHOR:         Jim Cook (BI Group)
CREATED:        2026-11-09
MODIFIED:       2026-11-09
VERSION:        v3.0  (DIAGNOSTIC, read-only, not deployed)

PURPOSE:
    Follow-up to V2. V2 showed EMERGENCY_FSC + REEFER_UPCHARGE close the
    STRACS-vs-invoice gap on 2,301 of 2,303 orders. V3 answers what is left:
      (A) why 2,303 orders compared when the run had 2,314 (11 dropped by the
          inner joins), and
      (B) why orders 6500058 and 6499220 still differ: STRACS carries linehaul
          the TMW invoice lines do not.
    The "still off" orders are found dynamically, not hardcoded.

SOURCE SYSTEM:  MANH, STRACS, TMW_LIVE on CTG-SQLAAG02 (PROD)
TARGET SYSTEM:  Ad hoc (SSMS)

BUSINESS LOGIC:
    - Run orders = MANH.dbo.PA_Customer_updated_loads (last pull). Confirm the
      Result 1 count against the 2,314 loads in the 11/03/2026 run before
      trusting the comparison; the table is overwritten by each pull.
    - ordnumber converted with TRY_CONVERT; non-numeric rows are counted, not
      allowed to abort the batch.
    - "Still off" = ABS(LH + FSC + OTH + EFSC + REEF - InvTotal) > $1.
    - Result 2 also tests whether a dropped order exists in orderheader as
      ord_hdrnumber vs ord_number (the open ord_number / ord_hdrnumber key
      question on the Manhattan OrderHeader join).
    - Invoice lines are pulled by invoicedetail.ord_hdrnumber AND by the
      invoiceheader that points at the order, so a linehaul line stamped with
      a different order number but the same invoice is still found.

CHANGE LOG:
    2026-11-03 - J.Cook - [TECH-231527] - v1.0 initial probes
    2026-11-03 - J.Cook - [TECH-231527] - v2.0 gap analysis with
                 EMERGENCY_FSC and REEFER_UPCHARGE
    2026-11-09 - J.Cook - [TECH-231527] - v3.0 TRY_CONVERT on ordnumber; drop
                 reconciliation; invoice-line and header drill-down on the
                 orders still off

DEPENDENCIES:
    - STRACS.dbo.CVENDW_2
    - MANH.dbo.PA_Customer_updated_loads
    - TMW_LIVE.dbo.orderheader, invoiceheader, invoicedetail

NOTES:
    - Read-only. Writes only to tempdb (#PA, #S, #I, #Off).
    - Schema_Verification, TMW_Live (tmw_live_schema.json, 2026-07-28):
        orderheader   ord_hdrnumber int NOT NULL; ord_number char(12) NOT NULL;
                      ord_status, ord_invoicestatus varchar(6); ord_billto
                      varchar(8); ord_totalcharge float; ord_bookdate,
                      ord_completiondate datetime
        invoiceheader ivh_hdrnumber int NOT NULL; ord_hdrnumber int;
                      ivh_invoicenumber varchar(12); ivh_invoicestatus
                      varchar(6); ivh_definition varchar(6); ivh_billdate
                      datetime; ivh_totalcharge money
        invoicedetail ivd_number int NOT NULL; ivh_hdrnumber int;
                      ord_hdrnumber int; cht_itemcode varchar(6);
                      ivd_description varchar(60); ivd_charge money
      STRACS.CVENDW_2 columns as verified in V2 (INFORMATION_SCHEMA 11/03/2026).
      MANH.dbo.PA_Customer_updated_loads.ordnumber: type not verified here,
      handled with TRY_CONVERT(int, RTRIM(...)).
================================================================================
*/

USE MANH;
GO
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#PA')  IS NOT NULL DROP TABLE #PA;
IF OBJECT_ID('tempdb..#S')   IS NOT NULL DROP TABLE #S;
IF OBJECT_ID('tempdb..#I')   IS NOT NULL DROP TABLE #I;
IF OBJECT_ID('tempdb..#Off') IS NOT NULL DROP TABLE #Off;

/* Run orders, numeric only */
SELECT DISTINCT TRY_CONVERT(int, RTRIM(ordnumber)) AS ord
INTO   #PA
FROM   dbo.PA_Customer_updated_loads WITH (NOLOCK)
WHERE  TRY_CONVERT(int, RTRIM(ordnumber)) IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX ix_PA ON #PA (ord);

/* STRACS per order */
SELECT  s.ORDER_#                         AS ord,
        COUNT(*)                          AS StracsRows,
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

/* TMW invoice lines per order */
SELECT  d.ord_hdrnumber      AS ord,
        COUNT(*)             AS InvLines,
        SUM(d.ivd_charge)    AS InvTotal
INTO    #I
FROM    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK)
JOIN    #PA p ON p.ord = d.ord_hdrnumber
GROUP BY d.ord_hdrnumber;

CREATE UNIQUE CLUSTERED INDEX ix_I ON #I (ord);

/* Orders in both sources that are still off after EFSC and REEF */
SELECT  p.ord,
        s.LH, s.FSC, s.OTH, s.EFSC, s.REEF, s.LastUpd, s.StracsRows,
        i.InvTotal, i.InvLines,
        s.LH + s.FSC + s.OTH + s.EFSC + s.REEF - i.InvTotal AS Gap
INTO    #Off
FROM    #PA p
JOIN    #S  s ON s.ord = p.ord
JOIN    #I  i ON i.ord = p.ord
WHERE   ABS(s.LH + s.FSC + s.OTH + s.EFSC + s.REEF - i.InvTotal) > 1;

/* Result 1: how many run orders survive each join */
SELECT  (SELECT COUNT(*) FROM dbo.PA_Customer_updated_loads WITH (NOLOCK))                      AS SourceRows,
        (SELECT COUNT(*) FROM dbo.PA_Customer_updated_loads WITH (NOLOCK)
          WHERE TRY_CONVERT(int, RTRIM(ordnumber)) IS NULL)                                     AS NonNumericRows,
        (SELECT COUNT(*) FROM #PA)                                                              AS RunOrders,
        (SELECT COUNT(*) FROM #PA p JOIN #S s ON s.ord = p.ord)                                 AS InStracs,
        (SELECT COUNT(*) FROM #PA p JOIN #I i ON i.ord = p.ord)                                 AS InInvoice,
        (SELECT COUNT(*) FROM #PA p JOIN #S s ON s.ord = p.ord JOIN #I i ON i.ord = p.ord)      AS InBoth,
        (SELECT COUNT(*) FROM #PA p LEFT JOIN #S s ON s.ord = p.ord WHERE s.ord IS NULL)        AS MissingStracs,
        (SELECT COUNT(*) FROM #PA p LEFT JOIN #I i ON i.ord = p.ord WHERE i.ord IS NULL)        AS MissingInvoice,
        (SELECT COUNT(*) FROM #S WHERE StracsRows > 1)                                          AS OrdersWithMultipleStracsRows,
        (SELECT COUNT(*) FROM #Off)                                                             AS StillOff;

/* Result 2: orders dropped by the inner joins, with what TMW knows about them */
SELECT  p.ord,
        CASE WHEN s.ord IS NULL THEN 'NO'  ELSE 'yes' END  AS InStracs,
        CASE WHEN i.ord IS NULL THEN 'NO'  ELSE 'yes' END  AS InInvoice,
        CASE WHEN oh.ord_hdrnumber IS NULL THEN 'NO' ELSE 'yes' END   AS IsOrdHdrnumber,
        CASE WHEN oh2.ord_hdrnumber IS NULL THEN 'no' ELSE 'YES' END  AS IsOrdNumber,
        COALESCE(oh.ord_number, oh2.ord_number)                 AS ord_number,
        COALESCE(oh.ord_status, oh2.ord_status)                 AS ord_status,
        COALESCE(oh.ord_invoicestatus, oh2.ord_invoicestatus)   AS ord_invoicestatus,
        COALESCE(oh.ord_billto, oh2.ord_billto)                 AS ord_billto,
        COALESCE(oh.ord_bookdate, oh2.ord_bookdate)             AS ord_bookdate,
        COALESCE(oh.ord_completiondate, oh2.ord_completiondate) AS ord_completiondate,
        COALESCE(oh.ord_totalcharge, oh2.ord_totalcharge)       AS ord_totalcharge
FROM    #PA p
LEFT JOIN #S s ON s.ord = p.ord
LEFT JOIN #I i ON i.ord = p.ord
LEFT JOIN TMW_LIVE.dbo.orderheader oh  WITH (NOLOCK) ON oh.ord_hdrnumber = p.ord
LEFT JOIN TMW_LIVE.dbo.orderheader oh2 WITH (NOLOCK) ON RTRIM(oh2.ord_number) = CAST(p.ord AS varchar(12))
WHERE   s.ord IS NULL OR i.ord IS NULL
ORDER BY p.ord;

/* Result 3: STRACS rows behind each still-off order */
SELECT  o.ord, s.ORDER_#, s.LINEHAUL, s.FUEL_SURCHARGE, s.OTHER,
        s.EMERGENCY_FSC, s.REEFER_UPCHARGE, s.LastUpdatedTimestamp
FROM    #Off o
JOIN    STRACS.dbo.CVENDW_2 s WITH (NOLOCK) ON s.ORDER_# = o.ord
ORDER BY o.ord, s.LastUpdatedTimestamp;

/* Result 4: every invoice line for each still-off order, found by order number
   and by the invoice header that points at the order */
WITH OrdInvoices AS (
    SELECT o.ord, h.ivh_hdrnumber
    FROM   #Off o
    JOIN   TMW_LIVE.dbo.invoiceheader h WITH (NOLOCK) ON h.ord_hdrnumber = o.ord
),
Lines AS (
    SELECT o.ord AS OffOrd, d.ivd_number
    FROM   #Off o
    JOIN   TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK) ON d.ord_hdrnumber = o.ord
    UNION
    SELECT oi.ord, d.ivd_number
    FROM   OrdInvoices oi
    JOIN   TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK) ON d.ivh_hdrnumber = oi.ivh_hdrnumber
)
SELECT  l.OffOrd,
        d.ivd_number,
        d.ord_hdrnumber      AS ivd_ord_hdrnumber,
        d.ivh_hdrnumber,
        h.ivh_invoicenumber,
        h.ivh_invoicestatus,
        h.ivh_definition,
        h.ivh_billdate,
        d.cht_itemcode,
        d.ivd_description,
        d.ivd_charge
FROM    Lines l
JOIN    TMW_LIVE.dbo.invoicedetail d WITH (NOLOCK) ON d.ivd_number = l.ivd_number
LEFT JOIN TMW_LIVE.dbo.invoiceheader h WITH (NOLOCK) ON h.ivh_hdrnumber = d.ivh_hdrnumber
ORDER BY l.OffOrd, d.ivh_hdrnumber, d.ivd_number;

/* Result 5: order status for each still-off order */
SELECT  o.ord, o.Gap, o.LastUpd AS StracsLastUpd,
        oh.ord_number, oh.ord_status, oh.ord_invoicestatus, oh.ord_billto,
        oh.ord_bookdate, oh.ord_completiondate, oh.ord_totalcharge
FROM    #Off o
LEFT JOIN TMW_LIVE.dbo.orderheader oh WITH (NOLOCK) ON oh.ord_hdrnumber = o.ord
ORDER BY ABS(o.Gap) DESC;
