# Architecture

## Design choices

| Choice | Why |
| --- | --- |
| **Native Salesforce, no external analytics stack** | The pointers, decisions and Opportunities live where reps already work. There is no integration layer between an analytics platform and the CRM, and sharing, field-level security and audit come from the platform. |
| **Deterministic rules, AI for wording only** | A rep must be able to challenge a pointer. Every pointer stores the numbers that triggered it (`Evidence__c`) and a rationale built from them. The model only explains the pointer and suggests the next steps; it never decides whether a pointer exists. |
| **Rules as records, not code** | `SR_Rule__c` holds thresholds, windows, product-line codes, weight and playbook. Admins tune them in the portal and re-run the engine. `SignalRoomRules` only seeds the defaults. |
| **Pointers separate from Opportunities** | Suggestions stay out of the pipeline until a rep accepts them. Rejections record a reason, which is the feedback loop for tuning rules. |
| **Monthly sell-in per account × product line** | This is the grain a CRM can hold for years of history. Product lines group materials by system and component, which is the level at which the rules make sense (femoral vs tibia, cup vs stem). |

## Data model

| Object | Role |
| --- | --- |
| `SR_Product_Line__c` | System × component (e.g. Meridian Knee / Femoral), average price, capital flag. Its code is referenced by the rules. |
| `SR_Account_Profile__c` | One per account: country, segment, size, knee / hip procedures per year, rollout phase, in-scope flag, rep. It keeps `Account` untouched. |
| `SR_Sales__c` | Monthly units and revenue per account × product line (and surgeon when known). In production this is loaded from the ERP. |
| `SR_Surgeon__c`, `SR_Affiliation__c` | Surgeons and the hospitals where they operate (primary or secondary site, start date, source). |
| `SR_Tender__c` | Public tenders: reference, title, buyer, country, category, CPV codes, deadline, value (notice currency and EUR), status, link to the notice, matched account (or suggestion and score). Demo tenders carry `Is_Demo__c`. |
| `SR_Tender_Source__c` | One per portal (TED, Find a Tender, Public Contracts Scotland): active flag, CPV prefixes, countries, lookback, last run and result. |
| `SR_Rule__c` | Rule configuration (see [rules.md](rules.md)). |
| `SR_Run__c` | Engine run log: accounts processed, pointers new / updated / expired, errors. |
| `SR_Pointer__c` | The opportunity: type, category, value, score, priority, rationale, evidence JSON, playbook, AI insight, decision, linked Opportunity, signature. |
| `SR_Session__c`, `SR_Commitment__c` | Weekly signal rooms and the actions committed in them. |
| `SR_Contract__c`, `SR_Contract_Line__c` | Volume commitments: term and tolerance, committed units per month and contracted price per product line. |
| `SR_Market_Site__c` | Hospital from a public procedure registry (UK: NJR) with 12-month hip / knee volumes, trend, monthly series and the linked account. |

All objects use Read/Write sharing; access is granted by the two permission sets. The admin set adds View All / Modify All and the `Signal_Room_Admin` custom permission, which the controller checks for rules, engine runs and demo data.

## Engine

```
SignalRoomBenchmarkBatch (all profiled accounts)
    -> segment x product line: number of buyers and their revenue (last 12 months)
SignalRoomEngineBatch (in-scope accounts, 5 per execute)
    -> SignalRoomEngine.evaluate(): load 24 months of sales, surgeons, tenders
    -> evaluate every active rule
    -> one pointer per customer x product: specific signals beat the peer comparison, then the highest score wins
    -> save(): insert new pointers, refresh existing ones, never touch decided ones
    -> finish(): expire undecided pointers not detected by this run, close the run log
```

**Priority score** (0–100) = 60% value at stake (log scale, €1M = 100) + 25% rule weight (1–5) + 15% urgency (tender deadline, hard churn, new surgeon). High ≥ 65, Medium ≥ 45.

**Contracts.** `SignalRoomContracts.evaluate()` compares committed and delivered units per month and line, and returns variance, cumulative variance, the 6-month run-rate, the projection at term end and a status. The portal and the `CONTRACT_*` rules use the same calculation. Contract pointers are kept apart from the one-pointer-per-product dedupe: a shortfall against a commitment is a different conversation from churn.

**Market volumes.** The registry CSV is parsed in the browser (`signalRoomMarket`), so large files never reach Apex; `SignalRoomMarket` upserts the aggregates, matches hospitals to accounts with a token index and copies the volumes of linked hospitals into the account profiles.

**Tenders.** `SignalRoomTenderSync` is a batch with one item per source (Find a Tender: one per 30-day window), so each portal gets its own callout and heap limits; every item does all its callouts first, then the DML. `SignalRoomTenders` builds the requests, parses TED's search response and OCDS release packages into one shape, converts values to EUR (org currency rates, or indicative rates in single-currency orgs), skips notices already stored from another portal (hash of buyer + title), and matches buyers to accounts of the same country. `finish()` closes notices whose deadline passed and runs the matching. Only tenders linked to an account reach the engine.

**Signature** = rule code | account | product line | surgeon | tender (| contract for contract pointers). It identifies a pointer across runs, so the engine can run daily or after every data load.

## Security

- The controller is `with sharing`; queries run with `AccessLevel.USER_MODE` and DML with `as user`, so object and field permissions apply.
- Admin-only actions (rules, engine, demo data, account scope) check the `Signal_Room_Admin` custom permission.
- The AI service reaches the model only through the `Signal_Room_LLM` Named Credential; no key is stored in Apex, metadata or this repository.

## UI

`signalRoomApp` is the shell (navigation, scope / country filters, engine status, pointer drawer). Each view loads its own data from `SignalRoomController`. Shared pieces:

- `signalRoomSelect`, `signalRoomSegmented`: dropdown and segmented control used instead of `lightning-combobox`, with the same look in every org.
- `signalRoomLineChart`: SVG line chart with a legend, a crosshair tooltip and a table view. The four colours come from a palette validated for colour-vision deficiency, in a fixed order.
- `signalRoomStyles`: design tokens (`--sr-*`) and shared classes, imported by every component. It has no global SLDS dependency, so the components also render on LWR sites.
