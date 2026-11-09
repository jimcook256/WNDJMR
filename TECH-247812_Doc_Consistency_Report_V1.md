# Manhattan documentation consistency report

Documents read: 6 (June2026.md, May2026.md, PipelineReference.docx, SKILL.md, StakeholderGuide.docx, Timeline.md)

Sproc files read: not supplied (timeline not checked against source)

## 1. Facts stated differently across documents
### Feeder sproc count: CONFLICT
- **14**
  - `PipelineReference.docx`: ...at of the SSRS Business Requirements Column Definitions table. Of the 14 feeder sprocs, 5 have been read line by line; the other 9 are described from their...
  - `SKILL.md`: ...| Source control | Access | |---|---|---|---| | Daily feeder sprocs (14 named — `usp_ns_manh_shipment`, etc.) | Covenant Dev | **MANH Azure DevOps...
- **16**
  - `PipelineReference.docx`: ...es There are 14 unique feeder sprocs, not 16. The Confluence list has 16 entries, but usp_ns_manh_dispatch_accessorial and usp_ns_manh_shipment each a...
  - `Timeline.md`: ...e":** the parent implies earlier phases that were never reviewed. - **11 of 16 feeder sprocs unread;** staging tables (tmpPAListSegments, tmpPAListOrdLegSt...

### Sprocs read line by line: CONFLICT
- **5 read / 9 unread**
  - `PipelineReference.docx`: ...iness Requirements Column Definitions table. Of the 14 feeder sprocs, 5 have been read line by line; the other 9 are described from their names only and are...
- **5 read / 11 unread**
  - `Timeline.md`: ...e":** the parent implies earlier phases that were never reviewed. - **11 of 16 feeder sprocs unread;** staging tables (tmpPAListSegments, tmpPAListOrdLegStopEvents, PA_C...

### Days from completion to copy: CONFLICT
- **15 days**
  - `PipelineReference.docx`: ...daily process | Vendor side | Executes the 14 sprocs, pulling orders 15 days after completion (11 days before Nov 2023) | Active, mechanism untraced Mon...
  - `SKILL.md`: ...NH DB on `CTG-SQLAAG02` (PROD), pulling completed-order TMW data **15 days after order completion** (was 11 days until Nov 2023; changed per Ed Ker...
  - `Timeline.md`: ...ESTWLD fleet code (hardcoded x2) 2023-11 : data pull moved 11d to 15d post-completion (Ed Kern) 2024-06/07 : TECH-144279 duplicate...
- **about two weeks**
  - `StakeholderGuide.docx`: ...number looks wrong When did the load complete? Manhattan copies loads about two weeks after they complete. Anything changed in TMW after that is not in the...

### Tractor Fleet fix status: CONFLICT
- **applied in View**
  - `PipelineReference.docx`: ...91629). Current fleet, not fleet at time of load. Defect TECH-231527, corrected in the View (9.12) Order Total | float | TMW_Live.dbo.[orderheader].[ord_totalcha...
- **in progress**
  - `SKILL.md`: ...CTIVE — TECH-231527: Tractor Fleet is historically wrong **Status**: In Progress. Read this before answering any Tractor Fleet question. **Confirmed...
  - `Timeline.md`: ...d Jan 2025 2026-07 : TECH-231527 incorrect Tractor Fleet - CURRENT WORK [MAJOR] ``` ## Not traced / unconfirmed (shown so nobody assumes com...

### Tractor Fleet leg rule: CONFLICT
- **leg the order tractor ran**
  - `June2026.md`: ...eader tractor, fleet read from the stamped legheader.trc_fleet on the leg that tractor ran, not from TractorProfile) --- ## What the fix does Today the repor...
  - `May2026.md`: ...eader tractor, fleet read from the stamped legheader.trc_fleet on the leg that tractor ran, not from TractorProfile) --- ## What the fix does Today the repor...
- **first leg**
  - `PipelineReference.docx`: ...t stamped on the order's leg. Project notes disagree on the leg rule (first leg vs majority miles); confirm before citing 10. Known risks and open...
  - `SKILL.md`: ...)`** derived from `tmw_live.dbo.legheader.trc_fleet` on the order's **first leg** (`ORDER BY lgh_number ASC`), with a fallback to the order-level fle...
- **majority miles**
  - `PipelineReference.docx`: ...the order's leg. Project notes disagree on the leg rule (first leg vs majority miles); confirm before citing 10. Known risks and open gaps Review the 9...

### Load mode into DOMO: CONFLICT
- **replace / full reload**
  - `June2026.md`: ...rrent fleet, which equals what DOMO shows today because the flow is full-reload on a live view. One compare against a production export confirms it...
  - `May2026.md`: ...rrent fleet, which equals what DOMO shows today because the flow is full-reload on a live view. One compare against a production export confirms it...
  - `PipelineReference.docx`: ...analyzer over SAP Sybase Open Client 16.0 (CLG-MAN2019, user profit), REPLACE upload | Active DOMO Workbench, RAW_Tmw_Live_Orderheader | Workbench...
  - `SKILL.md`: ...ata` — guid `229084ae-045c-4147-bcff-426bd1178364` **Version chain**: REPLACE (full truncate-and-reload each run) **Grain**: one row per `Manhattan...
- **append**
  - `Timeline.md`: ...L(lgh_tractor, ord_tractor)`. → the 57 corrections. 2. **Staleness:** monthly append, no reconciliation of priors → ~1,652 stale fleet values on the overl...

### Order-header window: CONFLICT
- **rolling 24 months**
  - `June2026.md`: ...June2026_fleet_changes_detail.csv ## Full 2-year context Across the rolling 2-year window the fix changes 248,445 of 599,336 orders (about 41%). That is...
  - `May2026.md`: ..._May2026_fleet_changes_detail.csv ## Full 2-year context Across the rolling 2-year window the fix changes 248,445 of 599,336 orders (about 41%). That is...
  - `PipelineReference.docx`: ...RAW_Tmw_Live_Orderheader | Workbench | TMW orderheader plus 6 joins, rolling 2-year ord_bookdate window; source of Tractor Fleet | Active, shared by 32 D...
  - `SKILL.md`: ...is only true of the left input.** The TMW-side Workbench SQL has a rolling 2-year `ord_bookdate` window (see below). Orders booked before that cutoff g...
- **calendar-year cutoff**
  - `PipelineReference.docx`: ...MW Workbench SQL (orderheader plus 6 joins, orders booked on or after Jan 1 two calendar years back). Joined on ManhattanOrderNumber = ord_number, FULL OUTER. Colum...
  - `SKILL.md`: ...date as date) >= DATEADD(yy, DATEDIFF(yy,0,GETDATE())-2, 0)` — i.e. Jan 1 of two calendar years ago. **Any Manhattan order booked before that cutoff gets NULL Trac...
  - `StakeholderGuide.docx`: ...s lose TMW details such as fleet and trailer type | Every load before Jan 1 two calendar years back Mileage rules | Billed miles are TMW's total miles at the time o...

### Stale-figure watch: CONFLICT
- **57 corrections**
  - `Timeline.md`: ...`usp_ns_manh_dispatch` uses `ISNULL(lgh_tractor, ord_tractor)`. → the 57 corrections. 2. **Staleness:** monthly append, no reconciliation of priors → ~1,6...
- **1,652 stale values**
  - `Timeline.md`: ...ons. 2. **Staleness:** monthly append, no reconciliation of priors → ~1,652 stale fleet values on the overlap. A full refresh fixes these; the 57 need...

### Run size tested: consistent
- **2,314 orders**
  - `StakeholderGuide.docx`: ...run we tested, revenue was changed in TMW after the snapshot on 32 of 2,314 orders (1.4%). 2. What O.R. means in this report Operating ratio (O.R...

## 2. What feeds what: join types and keys
### Join statements found: 18
- `bill to = bill to` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `customer = cmp_id` : full outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = ivd_ord_hdrnumber` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = ord_hdrnumber` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = ord_number` : full outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = order` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = order_#` : inner : ok [`PipelineReference.docx`, `SKILL.md`]
- `manhattanordernumber = pro number` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]
- `orig city = cty_code` : left outer : ok [`PipelineReference.docx`, `SKILL.md`]

### Same left key matched to different partners (informational: expected for the order key, see Gotcha #2)
- `manhattanordernumber` is joined to: ivd_ord_hdrnumber; ord_hdrnumber; ord_number; order; order_#; pro number

## 3. Timeline
### Entries parsed: 19 (from Timeline.md)
- `2011-07-15` DJT builds core sprocs (shipment + dispatch) "Rollup by Legheader" [MA
- `2011-11-18` DJT tariff_rate cast fixes
- `2012-03-28` DJT Mexico mileage handling
- `2013-05-13` DJT orig/dest-vs-leg city fix
- `2013-06-06` L.Moore #4989 zip continuity
- `2016-04-27` intercompany transfer (shipment_acc)
- `2016-09-29` L.Moore #51155 intercompany (dispatch_acc)
- `2017-08-28` L.Moore CSD-497 Mexico fees  <- CSD-497 appears in no other document
- `2020-04` SQL Agent jobs MANH_PA_FF / FF2 DISABLED [RISK]
- `2021-03-18` J.Hartin TECH-46748 BU/division
- `2021-04-01` J.Hartin csr/planner update
- `2021-10-11` TECH-68118 import MANH to DOMO begins (parent TECH-54808 Final Phase)   <- TECH-54808 appears in no other document
- `2022-01-19` TECH-68118 DOMO dataset LIVE, customer signoff [MAJOR]
- `2022-01-20` A.Pereira TECH-73336 adds ESTWLD fleet code (hardcoded x2)
- `2023-11` data pull moved 11d to 15d post-completion (Ed Kern)
- `2024-06/07` TECH-144279 duplicate miles (LegHeader trigger) - workaround only [RIS
- `2024-07-26` TECH-147849 reload Jan-Apr 2024  <- TECH-147849 appears in no other document
- `2025-02` TECH-167811 reload Jan 2025  <- TECH-167811 appears in no other document
- `2026-07` TECH-231527 incorrect Tractor Fleet - CURRENT WORK [MAJOR]

## Summary: 8 fact conflicts, 0 join issues, 4 timeline entries to review
