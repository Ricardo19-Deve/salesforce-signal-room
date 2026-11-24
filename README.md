# Salesforce Win Room

A **win room** for field sales, built natively on Salesforce with Apex and Lightning Web Components. A rules engine reads monthly sell-in and finds **customer-level opportunities** ("pointers"). Reps review them with the numbers behind each one and an optional AI summary, then accept, reject or turn them into Opportunities. A **weekly win room** asks the same 7 questions every 7 days, so the opportunities turn into committed actions. **Contracts** track committed volumes against what was delivered, a **market** view shows hospital procedure volumes from a public registry, and a **tender radar** reads real public tenders from the official EU and UK procurement APIs. A built-in **guide** explains every page, where its data comes from and how each number is calculated, and an interactive **tour** on every page highlights each block and explains it, for demos and onboarding.

This is a neutral open-source reference with fictitious data. The demo domain is orthopaedic implants (knees, hips, surgical robots) sold to hospitals, but the engine, the data model and the portal are generic. The only real data is optional and public: the UK National Joint Registry procedure volumes, which you download yourself, and public tender notices, which the org reads from the official APIs. Neither is included in the repository.

| Module | What it shows |
| --- | --- |
| **Rules engine** | 15 configurable rules in 11 types, in four categories: **win back** (soft / hard churn, partial switch to a competitor), **cross-sell** (component pull-through, capital pull-through, white space vs. peer hospitals), **surgeons & site expansion** (surgeon uses us at another hospital, new surgeon) and **new accounts & tenders** (tender radar, low share of wallet / greenfield, contract renewal). Contract rules flag **shortfalls** and **overruns** against the committed volume. Two batches (peer benchmarks, then evaluation) scale to large customer bases. |
| **Explainable pointers** | Every pointer stores the facts that triggered it, a monthly chart and a plain-language rationale. Value at stake and a 0–100 priority score (value, rule weight, urgency) rank the work. There is **one pointer per customer × product**, and a specific signal always beats the generic peer comparison. |
| **Safe re-runs** | Pointers are matched on a signature. Re-running the engine updates the numbers but **never overwrites a rep's decision**, and undecided pointers that are no longer detected expire. |
| **Activation** | Accept, reject with a reason (the dashboard shows the acceptance rate per rule, a feedback loop for tuning), or create an Opportunity in the org's first open stage, linked to the pointer. |
| **AI "why and what"** | Optional. An OpenAI-compatible model, reached through a **Named Credential** (`Win_Room_LLM`), writes the why, the what, next best actions, talking points, discovery questions and risks, plus a briefing for the win room facilitator. Without it, a rule-based summary is shown, so nothing breaks. |
| **Weekly win room** | Sessions per team, with the 7 questions: wins and losses, new pointers, accepted pointers without action, overdue commitments, stuck opportunities, tenders closing soon, and commitments for next week. |
| **Contracts** | Volume commitments per account and product line (e.g. *10 cups per month for 3 years*). Committed vs delivered month by month, cumulative variance, 6-month run-rate, projection at term end and a status (On track / Under / Over against a tolerance). Under-delivery becomes a win-back pointer, over-delivery a renegotiation pointer, and contracts ending within 6 months a renewal pointer. |
| **Market (public registry)** | Upload the public CSV export of the UK **National Joint Registry** (NJR StatsOnline): the browser keeps the last 24 complete months and stores one record per hospital with its hip / knee volumes and trend. Hospitals are matched to Accounts by hospital or trust name (suggestions need a distinctive shared word; admins confirm). Mapped accounts use the real volumes for share of wallet and peer sizing. No scraping and no callout. |
| **Public tenders** | A sync reads **TED** (EU / EEA, Search API v3), **Find a Tender** (UK, OCDS) and **Public Contracts Scotland** (OCDS), anonymously and within the portals' fair-use limits. Notices are filtered by CPV prefix (default: orthopaedic implants and fracture fixation), normalised (title, buyer, country, earliest open deadline, lots summed, value converted to EUR, link to the official notice), categorised from multilingual keywords and de-duplicated across portals. Buyers are matched to Accounts of the same country (accents and noise words removed in several languages, each part of the name scored, automatic links need two agreeing words). Linked open tenders feed the tender radar rule; human statuses and links survive every sync. Runs on demand or daily. |
| **In-portal guide** | The documentation of the module, inside it: every page with a block-by-block table (the same text as the tour, from one source), each formula, the rule types and the live rule settings, setup and roles, routines, data model, troubleshooting, FAQ and a 10-minute demo script. Each page has a *How this page works* link to its section. |
| **Interactive tour** | A *Tour* button next to every page title dims the screen, highlights each block of the page in turn (about 100 steps over 8 pages) and explains what it is for, how it is calculated and where its data comes from. The tour opens what it needs by itself (first account, session, contract or pointer, Rules & Data tabs, an expanded tender), waits for the data to load and skips blocks that have no data. Step counter, back / next, keyboard, follows scrolling. |
| **Team scope** | *All / Mine / My team* on the dashboard and the pointer list. My team = you and the users whose manager you are (standard `User.ManagerId`). The demo creates six fictitious reps (Chatter Free users, no welcome e-mail, no licence) reporting to you and spreads the accounts across the team. |
| **Admin without code** | Thresholds, windows, product lines and playbooks are edited in a dialog that shows only the parameters each rule type uses; *New rule* adds a rule of any of the 11 types, and custom rules can be deleted (defaults only deactivated). The engine runs on demand, account scope is set per rollout phase, and demo data can be generated and purged. |
| **Neutral UI** | Custom dropdowns, switches and buttons render the same in every org, whatever the org's brand colour. The portal runs as a Lightning tab or full screen on an Experience Cloud (LWR) site. |

## Screenshots

Captured in a Developer Edition org with the demo data (fictitious hospitals, surgeons and products).

| | |
| --- | --- |
| ![Dashboard](docs/images/01-dashboard.png) Dashboard: value at stake, the four categories, value by country and type, top 10 | ![Filters](docs/images/02-filters.png) Scope switch and country filter |
| ![Pointers](docs/images/03-pointers.png) Pointers: search, filters, priority score, due dates | ![Pointer](docs/images/05-pointer-insight.png) Pointer: rationale, facts, monthly chart, AI insight, playbook, commitments |
| ![Create opportunity](docs/images/06-create-opportunity.png) Create an Opportunity from an accepted pointer | ![Account 360](docs/images/07-account-360.png) Account 360: revenue trend, pointers by category, product lines, surgeons |
| ![Win room](docs/images/08-win-room.png) Weekly win room: same 7 questions every 7 days | ![Rules](docs/images/09-rules.png) Rules: thresholds, windows, product lines, playbooks |
| ![Data](docs/images/10-data.png) Data: demo data, purge and account scope by rollout phase | ![Contracts](docs/images/11-contracts.png) Contracts: health, delivered vs committed, variance, renewals |
| ![Contract](docs/images/12-contract-detail.png) Contract: committed vs delivered per month, run-rate and projection per line | ![Contract pointer](docs/images/14-contract-pointer.png) Contract shortfall pointer with the delivery chart |
| ![Market](docs/images/13-market.png) Market: public NJR hospital volumes (NHS file). The demo accounts are fictitious, so the hospitals stay unlinked | ![Tenders](docs/images/15-tenders.png) Tenders: real open notices from TED and Find a Tender, sources and filters, matched to accounts |
| ![Tender](docs/images/16-tender-detail.png) Tender detail: description, reference, CPV codes, value in the notice currency and in EUR, status | ![Guide](docs/images/17-guide.png) Guide: the loop, design principles and where every piece of data comes from |
| ![Calculations](docs/images/18-guide-calculations.png) Guide: rule types, priority score, dedupe and the live rule settings | ![Team scope](docs/images/19-team-scope.png) My team scope: the pointers of you and your reports |
| ![Tour](docs/images/20-tour.png) Page tour: each block highlighted and explained, with its data source | ![Tour step](docs/images/21-tour-top10.png) Tour step on the top 10 pointers |
| ![Guide blocks](docs/images/24-guide-blocks.png) Guide: every block of a page with what it shows and where the data comes from | ![Tour on a pointer](docs/images/25-tour-pointer.png) The tour opens a pointer by itself and explains the decision buttons |
| ![Tour on a contract](docs/images/26-tour-contract.png) Tour step on the committed vs delivered chart of a contract | ![Tour on a tab](docs/images/27-tour-data-tab.png) The tour switches the Rules & Data tabs by itself |
| ![Rule dialog](docs/images/22-rule-dialog.png) Rule dialog: parameters of the rule type, product lines as chips, playbook | ![New rule](docs/images/23-new-rule.png) New rule of any type, code generated from the name |

## How it works

```mermaid
flowchart LR
    subgraph Data
        S[(WR_Sales__c<br/>account x product line x month)]
        P[(WR_Account_Profile__c<br/>segment, procedures, phase)]
        A[(WR_Affiliation__c<br/>surgeon x hospital)]
        T[(WR_Tender__c)]
        R[(WR_Rule__c)]
        K[(WR_Contract__c<br/>+ lines)]
        M[(WR_Market_Site__c<br/>registry volumes)]
    end
    subgraph Public[Public APIs]
        TED[TED Search API]
        FTS[Find a Tender OCDS]
        PCS[Public Contracts Scotland OCDS]
    end
    TED & FTS & PCS --> TS[WinRoomTenderSync<br/>CPV filter, dedupe, matching] --> T
    subgraph Engine
        B[WinRoomBenchmarkBatch<br/>peer benchmarks]
        E[WinRoomEngineBatch]
        W[WinRoomEngine<br/>rules, scoring, dedupe]
    end
    subgraph Portal[Lightning Web Components]
        D[Dashboard]
        PT[Pointers + detail]
        AC[Account 360]
        WR[Win room]
        AD[Rules & Data]
    end
    S & P --> B --> E --> W
    S & A & T & R & K --> W
    M -->|mapped volumes| P
    W --> PO[(WR_Pointer__c)]
    PO --> D & PT & AC & WR
    PT -->|accept / reject / convert| PO
    PT -->|create| O[(Opportunity)]
    WR --> C[(WR_Commitment__c)]
    PT -. optional .-> AI[WinRoomAIService<br/>Named Credential]
    AD --> R
```

1. **Identify.** The engine compares each in-scope account with its own history and with peer hospitals of the same segment, and writes pointers with value at stake, priority and evidence.
2. **Activate.** Reps review pointers in the portal (or in an activation workshop), accept or reject them and create Opportunities.
3. **Execute.** The weekly win room reviews progress with the 7 questions and records commitments with an owner and a due date.

More detail is in [docs/architecture.md](docs/architecture.md) and [docs/rules.md](docs/rules.md).

## Install in a Developer Edition org

```bash
sf org login web -a win-room
sf project deploy start -o win-room -d force-app -l RunSpecifiedTests -t WinRoomTest
sf org assign permset -o win-room -n Win_Room_Admin
sf apex run -o win-room -f scripts/apex/seed-demo-data.apex
# optional: six fictitious reps reporting to you, then regenerate in Rules & Data > Data
sf apex run -o win-room -f scripts/apex/create-demo-team.apex
```

Open the **Win Room** app. The seed creates 10 fictitious hospitals and runs the engine; pointers appear after 1–2 minutes (the header shows the engine status).

- **Reps** get `Win_Room_User` (review pointers, decide, run win rooms). **Admins** get `Win_Room_Admin` (rules, engine runs, demo data, scope).
- **Storage.** A Developer Edition org has 5 MB of data. The demo generator detects it and switches to compact mode (18 months of history, about 2,000 sales rows). Other orgs get 24 months.
- **AI (optional).** Create an External Credential with your API key and a Named Credential called `Win_Room_LLM` pointing at an OpenAI-compatible API (for example `https://api.openai.com`), and give users access to the principal. No key is stored in this repository.
- **Market (optional, public data).** Download *Download all NJR statistics* (NHS and/or Independent Sector CSV) from [NJR StatsOnline](https://surgeonprofile.njrcentre.org.uk/Home/StatsIndex) and use **Market → Import NJR CSV**. The data is © NJR; check its terms before any commercial use. In a Developer Edition org the NHS file alone (about 260 hospitals) fits in the 5 MB of storage next to the demo data.
- **Tenders (optional, public data).** The deploy adds Remote Site Settings for the three APIs. Open **Tenders → Sync now** (admins); the first sync reads the last 30 days of TED and 180 days of Find a Tender, later syncs continue from the last run. *Daily sync at 06:00* schedules it. Public Contracts Scotland is inactive by default: its API currently sends an incomplete TLS certificate chain, which Salesforce refuses; Scottish notices above the threshold still arrive through Find a Tender. TED content is reusable with attribution (Publications Office of the EU); Find a Tender and Public Contracts Scotland are under the Open Government Licence v3.0.
- **Portal.** Add the `winRoomApp` component to an LWR Experience Cloud page and set *Full screen* to show it as a standalone portal.

## Demo script (10 minutes)

1. **Dashboard.** Press **Tour** next to the title for a guided walk through the page. Switch *All / Mine / My team*. This is the bottom-up map of opportunities: value at stake, the four categories, value by country and by type, and the top 10.
2. **Pointers.** Filter *Type: Partial switch* and open **Partial switch: Meridian Tibial Tray**.
   - The rationale and the chart show tibial trays dropping while femoral volume continues.
   - **Generate AI insight** adds the why, the what, next best actions, questions and risks.
   - **Accept**, then **Create opportunity**: the Opportunity is linked to the pointer.
3. **Account 360.** Open **Northgate General Hospital** to see soft churn on the knee lines, a surgeon to hunt, a tender closing soon and white space vs. peers.
4. **Win room.** Team **GB**, planned session.
   - Walk through the 7 questions and add a commitment with an owner and a due date.
   - **AI briefing** prepares the facilitator.
5. **Contracts.** Open **Knee system agreement - St Aldric University Hospital**.
   - Femoral components are on track; tibial trays run at about half of the commitment, so the contract is *Under* and the projection ends far below the term commitment.
   - The *Contract shortfall* pointer carries the same chart into the pointer list and the win room.
   - Show the *Over* contract (renegotiate the tier) and the one ending within 6 months (renewal).
6. **Market.** With the NJR file imported, sort by volume: every hospital with its hip and knee procedures, trend and market value; link a hospital to an account to switch its profile to real volumes.
7. **Tenders.** Real open notices from the public portals: show the sources and their CPV filter, expand a notice (value in its currency and in EUR, link to the official notice) and filter *Account: Linked* to see the tenders that feed the tender radar pointers.
8. **Rules & Data.**
   - Edit *Soft churn* (the dialog shows only the parameters of that rule type), change 25% to 30%, then **Run engine now**: decisions are kept and pointers update.
   - **New rule**: add a second soft-churn rule with a stricter threshold, or delete a rule you added.
   - Show the account scope by rollout phase.

Reset before a demo: **Rules & Data → Data → Purge demo data**, then **Generate demo data**, and run **Tenders → Sync now** so the deadlines are current. The **Guide** button (top right) has the same script and the calculations behind every number, if questions come up.

[docs/presentation.md](docs/presentation.md) has a talk track for presenting the project.

## Tests

- **Apex:** 20 tests in `WinRoomTest`, run as a user with the `Win_Room_Admin` permission set, so user-mode access is tested too. All passed in a Developer Edition org on 23 Nov 2026 (classes 87–100% covered). They plant every pattern, run the engine and check that each pointer type is found, that re-runs keep decisions and create no duplicates, the pointer lifecycle, the win room agenda, the AI parsing (mocked callout) and fallback, contract compliance and renewal pointers, the contract editor, the registry import, name matching and volume mapping (with fictitious registry rows), the tender feeds (mocked TED, Find a Tender and Public Contracts Scotland responses: CPV filter, cross-portal dedupe, EUR conversion, categories, buyer matching, preserved decisions, sources and schedule), the demo team and the My team scope, and adding / deleting custom rules.
- **JavaScript:** `npm test` runs Jest on `winRoomUtils`, `winRoomSelect`, the registry CSV parser in `winRoomMarket`, the tender view, the guide and the page tours (25 tests). `npm run lint` runs ESLint.
- **CI:** every push runs ESLint and Jest. To run the Apex tests too, add a repository secret `DEVHUB_SFDX_AUTH_URL` with the *Sfdx Auth Url* of a Dev Hub. The job then creates a one-day scratch org, deploys, runs the tests and deletes the org.

## Project structure

```
force-app/main/default/
  classes/           WinRoomEngine (rules, scoring), WinRoomBenchmarkBatch, WinRoomEngineBatch,
                     WinRoomRules (defaults), WinRoomController (portal API), WinRoomAIService,
                     WinRoomContracts (compliance), WinRoomMarket (registry import and matching),
                     WinRoomTenders (feeds, parsing, matching) + WinRoomTenderSync (batch, schedule),
                     WinRoomMockData + WinRoomMockDataBatch (demo data), WinRoomTest
  lwc/               winRoomApp (shell) and the views: winRoomDashboard, winRoomPointers,
                     winRoomPointerDetail, winRoomAccount360, winRoomSession, winRoomContracts, winRoomMarket,
                     winRoomTenders, winRoomAdmin, winRoomGuide (content in guideContent.js);
                     shared: winRoomSelect, winRoomSegmented, winRoomLineChart, winRoomUtils, winRoomStyles
  objects/           WR_Sales__c, WR_Product_Line__c, WR_Account_Profile__c, WR_Surgeon__c, WR_Affiliation__c,
                     WR_Tender__c, WR_Rule__c, WR_Run__c, WR_Pointer__c, WR_Session__c, WR_Commitment__c,
                     WR_Contract__c, WR_Contract_Line__c, WR_Market_Site__c, WR_Tender_Source__c
  remoteSiteSettings/ TED, Find a Tender, Public Contracts Scotland
  permissionsets/    Win_Room_User, Win_Room_Admin
  customPermissions/ Win_Room_Admin
  applications/ tabs/
scripts/apex/        seed-demo-data.apex, create-demo-team.apex
docs/                architecture, rules, presentation
```

## License

MIT. See [LICENSE](LICENSE).
