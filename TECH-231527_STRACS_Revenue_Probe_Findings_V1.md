# TECH-231527 — STRACS Revenue Probe Findings (V1)

Prepared by: Jim Cook, Covenant BI | Started: 2026-11-09 | Status: V2 and V3 results in
Scripts: `TECH-231527_STRACS_Revenue_Probes_V2.sql` (run), `TECH-231527_STRACS_Revenue_Probes_V3.sql` (run)

## V2 results (run in PROD, CTG-SQLAAG02, MANH)

| Measure | Value |
|---|---|
| Orders compared | 2,303 (run had 2,314) |
| Match, DOMO columns only (LH + FSC + OTHER) | 2,149 (93.3%) |
| Match, plus EMERGENCY_FSC and REEFER_UPCHARGE | 2,301 (99.9%) |
| Invoice total | $8,655,400.05 |
| STRACS, DOMO columns | $8,623,094.14 (invoice higher by $32,305.91) |
| STRACS, all columns | $8,659,248.03 (STRACS higher by $3,847.98) |
| EMERGENCY_FSC | $1,417.00 |
| REEFER_UPCHARGE | $34,736.89 |
| STRACS last updated | 2026-10-05 07:13 to 2026-11-06 14:14 |

### Orders still off (2)

| Order | STRACS LH | STRACS FSC | Invoice total | Invoice lines | Gap |
|---|---|---|---|---|---|
| 6500058 | 2,900.00 | 1,400.00 | 1,400.00 | FFS (FSC Flat) | 2,900.00 |
| 6499220 | 947.98 | 366.58 | 366.58 | MXMILE (FSC - Domestic Mile) | 947.98 |

Both: STRACS has linehaul the TMW invoice lines do not. Sum of gaps = $3,847.98 (matches net).

## Open questions V3 was written to answer (answered below)
- Why 2,303 compared vs 2,314 (11 dropped by inner joins): in STRACS? in invoices? ord_hdrnumber vs ord_number?
- Is `PA_Customer_updated_loads` still the 11/03 population? (`RunOrders` vs 2,314)
- Orders 6500058 / 6499220: linehaul unbilled, under another order number, or on another invoice?
- Why V1's $31,190 gap differs from today's $32,305.91 (population or STRACS changes after 11/03)

## V3 results (run in PROD)

### Result 1 — join counts
Run orders 2,314 (matches the 11/03 run; no non-numeric rows). In STRACS 2,312, in invoices 2,303, in both 2,303. Missing from STRACS 2, missing from invoices 11. No order has more than one STRACS row. Still off: 2.

### Result 2 — dropped orders
11 orders dropped, all with ord_number = ord_hdrnumber (so the order-number key is not a problem for these 11).

| Group | Orders | Status | In STRACS | Invoiced | ord_totalcharge |
|---|---|---|---|---|---|
| Complete, not yet invoiced (bill-to COVCHA09, 9 orders) | 6494119, 6495323, 6495816, 6496464, 6496566, 6496611, 6499149, 6499150, 6499738 | CMP / AVL | yes | no | 0.01 on 7; 15.60 on 6495323; 1,100.00 on 6496566 |
| Cancelled (bill-to ESTRIC24, 2 orders) | 6495432, 6498280 | CAN / XIN | no | no | 0 |

### Result 3 — STRACS rows, still-off orders
One STRACS row each. 6499220: LH 947.98, FSC 366.58. 6500058: LH 2,900.00, FSC 1,400.00. No OTHER, EMERGENCY_FSC or REEFER_UPCHARGE. Last updated 10/15 and 10/14.

### Result 4 — invoice lines, still-off orders
Each order has one invoicedetail line and it is a fuel line (MXMILE 366.58 on 6499220, FFS 1,400.00 on 6500058). Both lines carry ivh_hdrnumber = 0, so they are not attached to any invoice header. There is no linehaul line.

### Result 5 — order status, still-off orders
Both orders: status CMP, invoice status AVL (not yet invoiced). TMW ord_totalcharge equals the STRACS all-column total: 4,300 on 6500058 (2,900 + 1,400) and 1,314.56 on 6499220 (947.98 + 366.58).

## Decisions to carry to the Stakeholder Guide
- [ ] Add REEFER_UPCHARGE (~$34.7K on 2,303 orders) to the Op Rev decision list, beside AIT / minimum / stop charges
- [ ] Change "about two weeks" to "about 15 days" (copy timing)
- [ ] Note STRACS is read live, not snapshotted, so revenue can change after 11/03

## Conclusions from V3
- The probe closes the gap: all 13 orders that did not match are not yet invoiced (11 dropped + 2 still off) or cancelled (2 of the 11).
- STRACS agrees with TMW's order total on the 2 still-off orders; the TMW invoicedetail table is the incomplete side, because the orders are unbilled. Invoice detail is a valid comparison only for invoiced orders.
- STRACS holds rows for the 9 uninvoiced orders even though TMW's order total is 0.01 on 7 of them. What STRACS reports for them is not yet checked.
- The 2 cancelled orders match the guide's "cancelled 2" item.
