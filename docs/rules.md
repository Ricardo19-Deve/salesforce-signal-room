# Rules and configuration

Rules are `WR_Rule__c` records, edited in **Rules & Data → Rules**. **Reset to defaults** restores the values below. After a change, **Run engine now**.

## Fields

| Field | Meaning (depends on the rule type) |
| --- | --- |
| Rule type | Which evaluator runs (table below). |
| Category | Win back, Cross-sell, Surgeons & site expansion, New accounts & tenders. |
| Weight (1–5) | Share of the priority score. |
| Threshold % | Minimum drop, tolerance, penetration, share or probability. |
| Min value at stake | Pointers below this annual value are not created. |
| Lookback / Recent months | Comparison windows. |
| Anchor / Target product lines | Comma-separated product line codes. |
| Expected ratio | Expected target units per anchor unit, robotic share or target share. |
| Next best action | Playbook shown on the pointer and given to the AI as context. |

## Rule types

| Type | Finds | Value at stake |
| --- | --- | --- |
| `WINBACK_SOFT` | Revenue of a line in the last *Recent* months is down at least *Threshold* vs the same months a year earlier. | Annualised gap |
| `WINBACK_HARD` | No units in the last *Recent* months after at least *Min value* in the previous *Lookback* months. | Lost annual revenue |
| `ATTACH` | Target / anchor units over *Lookback* below *Expected ratio* × (1 − *Threshold*). If the ratio was fine a year earlier it is a **partial switch** (win back), otherwise a **cross-sell** gap. | Missing units × price |
| `CAPITAL_PULLTHROUGH` | The anchor capital line (robotic knee) is used but not the target workflow (robotic hip), although the account has hip volume. | Expected cases × (workflow fee + 20% of the hip basket) |
| `PEER_WHITESPACE` | At least *Threshold* of hospitals in the same segment buy a line that this account never bought (needs 4 or more peers). | Peer average × account size factor |
| `SURGEON_SITE` | A surgeon generates sales at another hospital and also operates here without sales. | Procedures × *Threshold* × basket |
| `NEW_SURGEON` | Affiliation started in the last *Recent* months, no sales yet. | Procedures × *Threshold* × basket |
| `TENDER_RADAR` | Open tender with a deadline within *Lookback* months; due date = deadline − 14 days. | Estimated value × *Threshold* (win probability) |
| `SHARE_OF_WALLET` | Revenue / estimated market (procedures × basket) below *Threshold*. | *Expected ratio* × market − revenue |
| `CONTRACT_COMPLIANCE` | A contract line is *Under* (or *Over*) its commitment to date beyond the contract tolerance **and** the last *Recent* months run beyond *Threshold*. Under = **contract shortfall** (win back), over = **contract overrun** (renegotiate). | Annual gap at the current run-rate (shortfall: or the backlog, whichever is larger) |
| `CONTRACT_RENEWAL` | Active contract ending within *Lookback* months; due date = end − 90 days. | Annual contract value |

## Default rules

| Code | Name | Type | Key settings |
| --- | --- | --- | --- |
| `WB_SOFT_CHURN` | Soft churn - volume decline | WINBACK_SOFT | 25% drop, 6-month window, €15k |
| `WB_HARD_CHURN` | Hard churn - product line stopped | WINBACK_HARD | 3 months without orders, €20k in the 12 before |
| `WB_PARTIAL_TIBIA` | Partial switch - tibia trays vs femoral | ATTACH | KNEE_FEM → KNEE_TIB, ratio 1.0, 20% tolerance |
| `WB_HIP_CUP` | Cup share loss - stems without cups | ATTACH | HIP_STEM_T, HIP_STEM_C → HIP_CUP, ratio 0.9 |
| `XS_PATELLA` | Pull-through - patella | ATTACH | KNEE_FEM → KNEE_PAT, ratio 0.6 |
| `XS_LINER` | Attach - liner per cup | ATTACH | HIP_CUP → HIP_LINER, ratio 1.0 |
| `XS_HEADS` | Attach - femoral heads per stem | ATTACH | stems → HIP_HEAD, ratio 1.0 |
| `XS_ROBOT_HIP` | Capital pull-through - robotic hip workflow | CAPITAL_PULLTHROUGH | ROBOT_KNEE → ROBOT_HIP, 40% robotic share |
| `XS_PEER_GAP` | Peer white space | PEER_WHITESPACE | 60% penetration, €15k |
| `SX_SURGEON_SITE` | Surgeon uses us elsewhere - site expansion | SURGEON_SITE | 50% of cases |
| `SX_NEW_SURGEON` | New surgeon - first case target | NEW_SURGEON | joined in the last 6 months, 40% of cases |
| `NT_TENDER` | Tender radar | TENDER_RADAR | deadline within 2 months, 35% win probability |
| `NT_SHARE_OF_WALLET` | Low share of wallet / greenfield | SHARE_OF_WALLET | below 15%, target 30% |
| `CT_COMPLIANCE` | Contract compliance - volume vs commitment | CONTRACT_COMPLIANCE | 10%, 6-month run-rate, €5k |
| `CT_RENEWAL` | Contract renewal - commitment ends soon | CONTRACT_RENEWAL | ends within 6 months |

## Product lines

`WR_Product_Line__c` maps materials to a system and component. The codes are referenced by the rules and by the demo generator: `KNEE_FEM`, `KNEE_TIB`, `KNEE_PAT`, `KNEE_CL`, `BONE_CEMENT`, `PARTIAL_KNEE`, `HIP_CUP`, `HIP_LINER`, `HIP_STEM_T`, `HIP_STEM_C`, `HIP_HEAD`, `ROBOT_KNEE`, `ROBOT_HIP`. The demo product names (Meridian, Unity, Orbit, Summit, Vista, Atlas) are fictitious. Capital lines (robots) are skipped by the churn and peer rules.

## Contracts

`WR_Contract__c` (account, start / end, status, tolerance %, default 10%) with `WR_Contract_Line__c` (product line, committed units per month, contracted unit price). Create and edit them in the **Contracts** view (admins). The comparison starts at the later of the contract start and the first month with sales data, so a contract older than the loaded history is not reported as under-delivered.

## Market volumes (public registry)

`WR_Market_Site__c` holds one record per registry hospital: provider type, trust / company, region, hips and knees for the last 12 and prior 12 complete months, the monthly series and the linked account. The UK source is the public CSV export of the National Joint Registry (NJR StatsOnline, © NJR). Import it in **Market → Import NJR CSV**; the browser parses the file and only aggregates are stored. Matching links a hospital to an account when the hospital or trust name matches exactly (after removing words such as *hospital*, *NHS*, *trust*), and suggests a link when a distinctive word is shared. Linked accounts get `Volume_Source__c = NJR` and the registry volumes in their profile.

## Loading real data

1. Map each ERP material to a product line code.
2. Load monthly sell-in into `WR_Sales__c` (account, product line, period = first day of the month, units, revenue, an external key for upserts). Use 24 months for full year-over-year comparisons.
3. Create one `WR_Account_Profile__c` per account with segment, size and procedures, and set the rollout phase and in-scope flag.
4. Optionally load surgeon affiliations and tenders.
5. Run the engine (or schedule `WinRoomBenchmarkBatch.launch()`).
