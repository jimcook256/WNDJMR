# TECH-247812 Lineage Verification Results (V1)

Script: `TECH-247812_Manhattan_Lineage_Verification_V1.sql` | Run on: CTG-SQLAAG02 (MANH) | Run date: ____ | Run by: ____
Status: not yet run. Paste each result under its heading.

## Result 1: documented sprocs vs what exists
Expect 14 FOUND. Note any MISSING or UNDOCUMENTED, and last run times.
_pending_

## Result 2: what each sproc reads or writes
_pending_

## Result 3: hardcoded fleet-to-division codes (ESTENG, ESTWLD, MACH-1, PERDED)
Docs say at least two sprocs hold the map. List every module found.
_pending_

## Result 4: staging tables (tmpPAListSegments, tmpPAListOrdLegStopEvents, PA_Customer_updated_loads)
Docs say what fills tmpPAListOrdLegStopEvents is not identified.
_pending_

## Result 5: SQL Agent jobs that mention the sprocs
Docs say MANH_PA_FF and MANH_PA_FF2 were disabled April 2020 and nothing runs the sprocs today.
_pending_

## Result 6: manh_* tables, columns and row counts
Fills the column lists the Pipeline Reference marks pending.
_pending_

## Result 7: ord_number vs ord_hdrnumber
Docs treat this as open. Differs count of 0 means the Join OrderHeader key is safe.
_pending_

## Result 8: legheader triggers and lgh_number nullability
Skill says NULL-vs-0 duplicates on legheader; the schema extract says lgh_number is NOT NULL.
_pending_

## Conclusions
_pending_
