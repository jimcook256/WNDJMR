# TECH-231527 — STRACS Revenue Probe Findings (V1)

Prepared by: Jim Cook, Covenant BI | Started: 2026-11-09 | Status: V2 results in, V3 pending
Scripts: `TECH-231527_STRACS_Revenue_Probes_V2.sql` (run), `TECH-231527_STRACS_Revenue_Probes_V3.sql` (not yet run)

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

## Open questions V3 should answer
- Why 2,303 compared vs 2,314 (11 dropped by inner joins): in STRACS? in invoices? ord_hdrnumber vs ord_number?
- Is `PA_Customer_updated_loads` still the 11/03 population? (`RunOrders` vs 2,314)
- Orders 6500058 / 6499220: linehaul unbilled, under another order number, or on another invoice?
- Why V1's $31,190 gap differs from today's $32,305.91 (population or STRACS changes after 11/03)

## V3 results (paste here)

### Result 1 — join counts
_pending_

### Result 2 — dropped orders
_pending_

### Result 3 — STRACS rows, still-off orders
_pending_

### Result 4 — invoice lines, still-off orders
_pending_

### Result 5 — order status, still-off orders
_pending_

## Decisions to carry to the Stakeholder Guide
- [ ] Add REEFER_UPCHARGE (~$34.7K on 2,303 orders) to the Op Rev decision list, beside AIT / minimum / stop charges
- [ ] Change "about two weeks" to "about 15 days" (copy timing)
- [ ] Note STRACS is read live, not snapshotted, so revenue can change after 11/03
