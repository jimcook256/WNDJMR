# TECH-247812 Mapping Coverage Results (V1)

Script: `TECH-247812_Manhattan_Mapping_Coverage_Probe_V1.sql` | Run: 2026-11-09 on CTG-SQLAAG02 (MANH) | Window for Results 1 and 2: since 2026-05-01
Results 1 and 2 cover every customer and fleet in TMW. Results 3 and 4 cover only the last Manhattan run (the 11/03 run list, 2,314 orders).

## Headline: three figures in the Stakeholder Guide are reproduced exactly
| Guide figure | What the data shows | Check |
| --- | --- | --- |
| $22,314 on 10 lines missing from revenue (AIT, minimum, stop charges) | AITWGM $11,214.80 (4 lines) + MIN $10,949.20 (3 lines) + STOPF $150.00 (3 lines) = $22,314.00 on 10 lines. These are the only non-linehaul charge codes on the run's orders that are NOT IN MAPPING | Exact |
| $10,071.68 of accessorials billed after the copy | Mapped invoice lines on the run's orders total $2,244,789.81. `manh_shipment_accessorial` holds $2,234,718.13. Difference $10,071.68 | Exact |
| $1,428,531.77 load-level pay reconciled to the penny | `manh_dispatch_accessorial` acc_index 58 ($1,423,921.09) + 59 ($4,603.18) + 67 ($7.50) = $1,428,531.77 | Exact |

The guide's figures describe what Manhattan received. The mapping tables are why the other items are absent.

## What is sent, by acc_index (last run)
| Table | acc_index | Rows | Orders | Total value | Likely content |
| --- | --- | --- | --- | --- | --- |
| manh_shipment_accessorial | 2 | 22 | 22 | $3,355.56 | Charge codes mapped to revenue index 2 (detention, layover) |
| manh_shipment_accessorial | 4 | 1 | 1 | $283.40 | Lumper and driver load/unload |
| manh_shipment_accessorial | 6 | 2,129 | 2,129 | $2,192,371.74 | Fuel surcharge codes (FUELMI, FFS, FUELRE, RE, MXMILE, FSCPAD, EF, SP all map to 5/6) |
| manh_shipment_accessorial | 10 | 73 | 73 | $13,009.13 | Miscellaneous accessorials |
| manh_shipment_accessorial | 11 | 2,268 | 2,266 | $3,275.00 | Stop and other accessorials |
| manh_shipment_accessorial | 18 | 935 | 935 | $22,423.30 | Tolls (TC, TCRPM map to 17/18) |
| manh_dispatch_accessorial | 58 | 2,557 | 2,051 | $1,423,921.09 | Driver pay (mileage, per diem, minimum guarantee, deductions) |
| manh_dispatch_accessorial | 59 | 27 | 27 | $4,603.18 | Lumper, load locks, unload pay |
| manh_dispatch_accessorial | 67 | 1 | 1 | $7.50 | Tolls reimbursement |

The "likely content" column comes from matching codes to indexes in Result 1 and 2, not from the sproc source.

Indexes defined in the mapping tables but not sent in the last run: charge cost 3, 5, 8, 9, 12, 14, 16, 17; charge revenue 13, 15; pay cost 53, 62, 64, 66; pay revenue 54, 60, 61, 63, 68. The shipment sproc appears to send only charge revenue indexes and the dispatch sproc only pay cost indexes; confirm against the sproc source.

## Result 4: the run's invoice lines by mapping status
| Status | Lines | Orders | Amount |
| --- | --- | --- | --- |
| MAPPED | 6,381 | 2,303 | $2,244,789.81 |
| NOT IN MAPPING | 2,345 | 2,301 | $6,410,610.24 |

Of the NOT IN MAPPING dollars, linehaul is $6,388,296.24 (LHD $4,205,339.82 and LHF $2,182,956.42), which belongs in the manh_shipment tariff columns. The other $22,314.00 is AITWGM, MIN and STOPF above. Confirm the linehaul figure against `SUM(tariff_rev)` on manh_shipment.

## Result 1: charge codes since May (all customers)
- **Mapped** (65 codes), mostly fuel surcharge and standard accessorials: FUELMI $48.7M, FFS $10.2M, GM $1.3M, FUELRE $1.2M, RE $0.9M, TONU, TCRPM, TC, DHF, LU, LAY, STOP and others. Fuel codes map to indexes 5/6, tolls to 17/18, driver-handled items to 3/4, detention and layover to 9/2.
- **Not in mapping:** several hundred codes. Linehaul (LHD $115.96M, LHF $75.34M) is expected. The rest are customer-specific codes for dedicated accounts (Playcore, Hood, Colgate, the feed and live-haul codes and so on), which are billed outside the Expedited population Manhattan covers. They show here only because Result 1 spans all customers.
- **Company-wide, still unmapped, and the same codes seen on the run:** MIN $1,469,717.39 (737 lines), STOPF $1,384,605.00 (1,508 lines), AITWGM $127,486.35 (65 lines). The run itself carries only the $22,314.

## Result 2: pay codes since May (all fleets)
Not in mapping, matching the guide's list of pay items not sent:
| Code | Description | Lines | Amount |
| --- | --- | --- | --- |
| BNSTM | Teaming bonus | 36,013 | $1,365,414.06 |
| REGPAY | Regional pay | 40,351 | $835,102.49 |
| DBLPAY | Doubles pay | 48,492 | $575,991.46 |
| PEAKPY | Peak package pay bonus | 10,261 | $134,341.67 |
| FULTRC | Tractor fuel purchase | 17,175 | -$4,179,799.23 |
| LDMNY | Advance, Comdata card | 9,120 | -$721,772.56 |
| ADV.PA | Advance, personal | 3,493 | -$581,184.74 |
| LAY | Layover pay | 1,084 | $145,236.00 |
| BREAKL | Breakdown, layover | 1,495 | $202,080.30 |

Also unmapped and large: TRIPPY $7.74M, DRVSLY $5.65M, HR $2.66M, DFMLTM $2.48M, ROUTE $1.40M. Mapped: MILES $52.4M, PDIEM $6.9M, GRNT $2.3M, OT $1.0M, DETPAY $1.0M, STOPS $0.8M, and 16 others. Because Result 2 spans all fleets, these dollars are not the Manhattan population. Sizing them for the run's legs needs a leg-level query.

## Result 5: the mapping has changed over time
- **Charges vs the 2013 copy:** 36 codes are only in the current table, 12 only in the 2013 copy. **MIN (minimum charge) was mapped in 2013 (indexes 8/10) and is not mapped now.** The 2013 copy also mapped LHD, LHF, LHC, LHDOM, LHT, LHV, LHW, LHO, FAC, 100LTR and ORDFLT; the current table has none of them. MAX changed from 8/10 to 9/11.
- **Charges vs `_11_26`:** the current table contains everything in `_11_26` plus 68 codes. MIN is in neither.
- **Pay vs `_11_26`:** dozens of codes are only in the current table (mostly deductions and reimbursements at 58/60) and about the same number are only in the old copy. The old copy mapped fuel purchase (FULTRC, FUELMI, FUELRE, FUEL, FUELFE at 53/54), advances (ADV and ADV.* at 59/61), layover and breakdown (LAY, BREAKL, BRKDWN at 52 or 59 / 61), orientation, bonus, holiday, sick and vacation pay. None of these is in the current table.
- **DET and LOAD (pay)** changed cost index from 52 to 58.
- **`manh_pyt_itemcode_Mapping_Original`** holds every row twice (248 rows, 124 codes).
- The copies are not dated in this output, so when each change happened is not known.

## What this means
1. The Stakeholder Guide's "not sent" items are mapping gaps, not copy errors. The data Manhattan received matches the mapping exactly, to the cent.
2. Whether those gaps explain the P&L difference depends on what the new P&L counts. Fuel purchase, advances, layover, regional, team, doubles and peak pay are real cost items that the current pay mapping does not send; the 11_26 and Original copies sent fuel, advances and layover.
3. Fuel surcharge reaches Manhattan as acc_index 6 at $2,192,371.74. STRACS FUEL_SURCHARGE on the same orders is $2,162,546.38, so the two differ by $29,825.36. Not yet explained.

## Next steps
- [ ] Date the mapping copies: `SELECT name, create_date, modify_date FROM sys.tables WHERE name LIKE 'manh%Mapping%'` (or ask the DBA), so the fuel, advance and layover changes can be placed in time.
- [ ] Compare `SUM(tariff_rev)` on manh_shipment with linehaul $6,388,296.24, and explain the $29,825.36 between index 6 and STRACS FUEL_SURCHARGE.
- [ ] Size unmapped pay on the run's legs only (a leg-level query), so the cost side can be compared with the new P&L.
- [ ] Ask the business whether the new P&L counts fuel purchases, advances, layover, regional, team, doubles and peak pay, and AIT, minimum and stop charges.
