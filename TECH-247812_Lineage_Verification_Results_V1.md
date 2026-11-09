# TECH-247812 Lineage Verification Results (V1)

Script: `TECH-247812_Manhattan_Lineage_Verification_V2.sql` | Run on: CTG-SQLAAG02 (MANH) | Run date: 2026-11-09 | Run by: CVEN\coojim
Status: run. msdb is not readable by this login, so Result 5 needs the DBA.

## Headline findings
1. **MANH keeps only the last run, not history.** manh_shipment holds 2,314 rows (the 11/03 run list) and manh_dispatch 2,393 (the 2,393 legs in the Stakeholder Guide). May-to-current data cannot be pulled from these tables. History must come from MANH database backups, the DOMO dataset, or Manhattan.
2. **All 14 documented sprocs exist and none is undocumented.**
3. **Divisions are set by three mechanisms**, not one: the `MANH_Divisions` table (33 rows, run by MANH_Update_Divisions), a hardcoded fleet map in two sprocs, and usp_manh_BusUnit_Division_Updates_STAR.
4. **Accessorials are sent as (acc_index, value) through two mapping tables** (`manh_cht_itemcode_Mapping` 154 rows, `manh_pyt_itemcode_Mapping` 113 rows). A charge or pay code with no index is not sent. This is the likely mechanism behind "charges not sent."
5. **The ord_number join key is safe for the current run:** 2,314 of 2,314 run orders have ord_number equal to ord_hdrnumber.
6. **Dependencies the documents do not list:** STRACS.dbo.CVENDW_2 and STARDW_2 (read by usp_Fill_PA_Customer_updated_loads, so STRACS helps select the run list), ITQ.dbo.CTG_ForeignMiles and CTG_ForeignMilesBilled_Mexico (read by usp_ns_manh_shipment), the user-parameters table ctg_MANH_tbl_UserParameters, and the thirdparty tables.

## Result 1: documented sprocs vs what exists
All 14 FOUND, no UNDOCUMENTED. Dates are last modification only, so earlier edits are not visible.

| # | Sproc | Created | Last modified | Note |
| --- | --- | --- | --- | --- |
| 1 | MANH_Update_Divisions | 2015-11-13 | 2015-11-16 | |
| 2 | sp_manh_CAN_TempZips | 2013-05-13 | 2024-06-21 | Edit near TECH-144279 (Jun/Jul 2024) |
| 3 | sp_manh_MEX_TempZips | 2013-04-11 | 2024-06-21 | Same |
| 4 | usp_Fill_PA_Customer_updated_loads | 2012-07-19 | 2024-07-03 | Same |
| 5 | usp_LoadUserParms | 2012-07-19 | 2012-08-01 | |
| 6 | usp_manh_BusUnit_Division_Updates_STAR | 2012-07-31 | 2012-08-01 | Documents date it to TECH-46748, 03/18/2021; last change here is 2012 |
| 7 | usp_manh_Fill_tmpPAListSegments | 2012-07-19 | 2013-05-13 | Matches the 2013-05-13 timeline entry |
| 8 | usp_ns_manh_cust_name | 2012-07-19 | 2017-10-26 | |
| 9 | usp_ns_manh_dispatch | 2012-07-19 | 2022-01-20 | Matches TECH-73336 (ESTWLD), 2022-01-20 |
| 10 | usp_ns_manh_dispatch_accessorial | 2012-07-19 | 2022-01-20 | Same |
| 11 | usp_ns_manh_shipment | 2012-07-19 | 2022-01-20 | Same timestamp as 9 and 10 |
| 12 | usp_ns_manh_shipment_accessorial | 2012-07-19 | 2021-04-15 | |
| 13 | usp_ns_manh_shipment_accessorial_42716 | 2016-04-27 | 2016-04-27 | The 42716 suffix is the date 4/27/16 |
| 14 | usp_ns_manh_trailer | 2012-07-19 | 2021-04-23 | |

No sproc was modified in Nov 2023, so the 11-to-15-day change was not a code edit. It is probably a value in `ctg_MANH_tbl_UserParameters` (set by usp_LoadUserParms). Check that table.

## Result 2: what each sproc reads or writes (static dependencies)
| # | Sproc | Reads from TMW_LIVE | Other dependencies |
| --- | --- | --- | --- |
| 1 | MANH_Update_Divisions | legheader, orderheader | manh_dispatch, manh_dispatch_accessorial, manh_shipment, manh_shipment_accessorial, manh_divisions |
| 2, 3 | sp_manh_CAN / MEX_TempZips | City, statecountry | manh_CAN / MEX_TempZips, tmpPAListOrdLegStopEvents |
| 4 | usp_Fill_PA_Customer_updated_loads | event, eventcodetable, expedite_audit, orderheader, STATECOUNTRY | STRACS.CVENDW_2, STRACS.STARDW_2, ctg_MANH_tbl_UserParameters, PA_Customer_updated_loads, tmp tables, calls usp_manh_Fill_tmpPAListSegments |
| 5 | usp_LoadUserParms | none | ctg_MANH_tbl_UserParameters |
| 6 | usp_manh_BusUnit_Division_Updates_STAR | OrderHeader | all manh_* output tables, PA_Customer_updated_loads |
| 7 | usp_manh_Fill_tmpPAListSegments | city, legheader, STATECOUNTRY | PA_Customer_updated_loads, tmpPAListOrdLegStopEvents, tmpPAListSegments |
| 8 | usp_ns_manh_cust_name | company, OrderHeader | manh_cust_name, PA_Customer_updated_loads |
| 9 | usp_ns_manh_dispatch | legheader, manpowerprofile, orderheader, stops, tractorprofile | manh_dispatch, tmp tables |
| 10 | usp_ns_manh_dispatch_accessorial | legheader, manpowerprofile, orderheader, paydetail, referencenumber | manh_dispatch_accessorial, manh_pyt_itemcode_Mapping, vwPAList_pyt_itemcode2 |
| 11 | usp_ns_manh_shipment | company, expedite_audit, orderheader, paydetail, paytype, stops, Thirdpartyassignment, thirdpartyprofile, Thirdpartyrelationship | ITQ.CTG_ForeignMiles, ITQ.CTG_ForeignMilesBilled_Mexico, manh_shipment |
| 12 | usp_ns_manh_shipment_accessorial | chargetype, invoicedetail, orderheader, referencenumber | manh_shipment_accessorial, vwPAList_cht_itemcode_manh |
| 13 | usp_ns_manh_shipment_accessorial_42716 | orderheader | manh_shipment_accessorial, vwPAList_cht_itemcode_manh |
| 14 | usp_ns_manh_trailer | city, legheader, orderheader, trailerprofile | manh_trailer, vwManh_MEX_TempZips_AndMiles |

Consistent with the Pipeline Reference: usp_ns_manh_shipment reads no tractorprofile, and usp_ns_manh_dispatch reads tractorprofile. Dependency lists miss dynamic SQL and temp tables.

## Result 3: hardcoded fleet-to-division codes
Found in exactly two modules: `usp_ns_manh_dispatch` and `usp_ns_manh_dispatch_accessorial` (ESTENG 1, ESTWLD 2, MACH-1 1, PERDED 1 in each). Not in the shipment or trailer sprocs. MA and UT were not searched.

## Result 4: staging tables
Text-match results, so a lead not a proof (any INSERT INTO in a module can match):
- `PA_Customer_updated_loads`: written by usp_Fill_PA_Customer_updated_loads.
- `tmpPAListOrdLegStopEvents`: written by usp_Fill_PA_Customer_updated_loads (most likely), plus matched in the CAN/MEX sprocs, usp_manh_Fill_tmpPAListSegments, dispatch, dispatch_accessorial, shipment and trailer. The Pipeline Reference listed this one as not identified.
- `tmpPAListSegments`: written by usp_manh_Fill_tmpPAListSegments.

## Result 5: SQL Agent jobs
Not readable: SELECT denied on msdb.dbo.sysjobs and sysjobsteps. Ask the DBA (DataStrike) to run the two queries in Result 5 of the script. Until then, the April 2020 disablement of MANH_PA_FF and MANH_PA_FF2 is unconfirmed.

## Result 6: manh_* tables (what Covenant sends)
| Table | Rows | Columns | Note |
| --- | --- | --- | --- |
| manh_shipment | 2,314 | 45 | One row per order. Equals the 11/03 run |
| manh_dispatch | 2,393 | 49 | One row per leg |
| manh_trailer | 2,393 | 19 | |
| manh_shipment_accessorial | 5,428 | 5 | (shipment, bus_unit, division, acc_index, value) |
| manh_dispatch_accessorial | 2,585 | 9 | Adds driver, move_type, acc_index, value |
| manh_cust_name | 89 | 5 | |
| MANH_Divisions | 33 | 4 | Company, Truck_Division, MANH_Division, ID |
| manh_cht_itemcode_Mapping | 154 | 6 | Charge code to Cost and Revenue acc index. Older copies: _08_01_2013 (130), _11_26 (86) |
| manh_pyt_itemcode_Mapping | 113 | 6 | Pay code to Cost and Revenue acc index. Older copies: _11_26 (125), _Original (248) |
| manh_CAN_TempZips, manh_MEX_TempZips | 0 | 11 | Working tables, empty |

Column names:
- **manh_shipment (45):** shipment, enabled, bus_unit, division, billing_cycle, no_stops, billable_mi, truckload_mi, tarrif_rev, tarrif_rate, rail_rev, rail_cost, customer, nat_acct, shipper, ship_dock_hr, live_ld, orig_zip, orig_arriv_dt, orig_dept_dt, consignee, consig_dock_hr, live_unld, dest_zip, dest_arriv_dt, dest_dept_dt, orig_reg, dest_reg, book_time, pkup_wind_begin_dt, pkup_wind_end_dt, del_wind_begin_dt, del_wind_end_dt, aquire_meth, ship_type, priority, fail_code, cancelled, csr_id, sales_id, planner_id, resched_num, resched_dt, tariff_rev, db_update_dt.
- **manh_dispatch (49):** driver, shipment, ship_bus_unit, ship_division, enabled, move_type, segment_no, orig_dh, dest_dh, loaded_mi, actual_mi, drvr_type, drvr_bus_unit, drvr_division, tractor, tr_bus_unit, tr_division, tr_type, swap, orig_arriv_dt, orig_zip, orig_ramp_id, dest_dept_dt, dest_zip, dest_ramp_id, wkday_oos, wkend_oos, orig_load_dt, orig_dept_dt, dest_arriv_dt, dest_unload_dt, disp_date, next_avail_dt, db_update_dt, dh_driving_hrs, dh_resting_hrs, dh_handling_hrs, dh_waiting_hrs, load_driving_hrs, load_resting_hrs, load_handling_hrs, load_waiting_hrs, planned_dt, planner_id, dispatcher_id, pkup_wind_begin_dt, pkup_wind_end_dt, del_wind_begin_dt, del_wind_end_dt.
- **manh_trailer (19):** shipment, ship_bus_unit, ship_division, customer, trailer, tl_bus_unit, tl_division, tl_type, enabled, move_type, orig_arriv_dt, orig_zip, dest_dept_dt, dest_zip, orig_reg, dest_reg, truckload_mi, disp_seg_no, db_update_dt.

No fleet column is sent. manh_dispatch carries tractor and tr_division only, which confirms Tractor Fleet is built on the Covenant side.

## Result 7: ord_number vs ord_hdrnumber
| Population | Orders | Equal | Differ |
| --- | --- | --- | --- |
| All orders booked since the cutoff | 706,540 | 706,063 | 477 |
| Last Manhattan run list | 2,314 | 2,314 | 0 |

The 477 that differ have alphanumeric order numbers (for example BGRLO1, MJJA1). None is in the run, so `Join OrderHeader` on ord_number is safe for the current run. Only the last run was tested; earlier months are not covered.

## Result 8: legheader
- **Triggers:** none returned for TMW_LIVE.dbo.legheader. TECH-144279 names a trigger as root cause; either it was removed or this login cannot see it.
- **Columns:** lgh_number int NOT NULL, ord_hdrnumber int NULL, trc_fleet varchar NULL. The NULL-vs-0 lgh_number duplicates therefore cannot be NULL on legheader. They belong to `expedite_audit` in TMW_LIVE, which usp_Fill_PA_Customer_updated_loads and usp_ns_manh_shipment both read.

## Documents to correct
- Pipeline Reference: add the STRACS, ITQ, MANH_Divisions, mapping-table and user-parameters dependencies; mark the 42716 suffix as the date 4/27/16; mark tmpPAListOrdLegStopEvents as filled by usp_Fill_PA_Customer_updated_loads; add the column lists above.
- Pipeline Reference section 3 attributes TECH-46748 (03/18/2021) to usp_manh_BusUnit_Division_Updates_STAR, whose last modification is 2012-08-01. Check which sproc that change went into.
- Skill and Timeline: the NULL-vs-0 legheader argument does not hold on legheader.lgh_number.

## Next steps
- [ ] Ask the DBA for the Result 5 queries, and for point-in-time restores of MANH at month-end May to Oct, since the tables keep only the last run.
- [ ] Read `ctg_MANH_tbl_UserParameters` for the 15-day window and its change history.
- [ ] Compare TMW charge and pay codes used since May against the two mapping tables, listing codes with no index (candidate for charges not sent).
- [ ] Pull the MANH_Divisions rows and compare them with the hardcoded fleet map and the division rule in the Stakeholder Guide.
- [ ] Run `MIN` and `MAX` of `db_update_dt` on manh_shipment to confirm the date of the last pull.
