/**
 * Page tours: one step per block of every page, shared by the interactive tour (winRoomApp) and the guide
 * (winRoomGuide, "Block by block" tables), so the documentation and the tour never drift apart.
 *
 * Step fields
 *   target   "nav" | "filters" | "run" | "guide" | "tour"            element of the shell
 *            "page:<css selector>"                                    element of the current page (tourRect)
 *            "drawer:<css selector>"                                  element of the open pointer drawer
 *   action   run before the step: "open-first" (first account / session / contract / pointer), "back",
 *            "expand-first" (first tender), "tab:<key>" (Rules & Data tab), "close-drawer"
 *   optional the step is skipped when its block is not on screen (e.g. no contract on this account)
 *   title, body, data (where the data comes from)
 */
const GUIDE_STEP = {
    target: "guide",
    title: "Guide and tour",
    body: "The Guide (top right) documents every page block by block, with the formulas, the data sources and a demo script. The Tour button next to each page title replays this walk-through at any time. Use the keyboard: arrows to move, Esc to stop.",
    data: ""
};

export const TOURS = {
    dashboard: [
        {
            target: "nav",
            title: "Welcome to the Win Room",
            body: "Each tab is one step of the loop: Dashboard (where the value is), Pointers (the opportunities), Account 360 (one hospital), Win Room (the weekly meeting), Contracts (committed vs delivered), Market (registry volumes), Tenders (public notices) and, for admins, Rules & Data.",
            data: ""
        },
        {
            target: "filters",
            title: "Scope and country",
            body: "All = every pointer you can see. Mine = pointers assigned to you. My team = you plus the users whose manager you are (Manager field on the user). Country limits everything to one country. Both filters apply to this page and to Pointers, and are remembered in this browser.",
            data: "Pointer owner (Assigned To), user hierarchy, pointer country."
        },
        {
            target: "run",
            title: "Engine status",
            body: "When the rules engine last ran and how it ended. Each run re-evaluates every in-scope account: new opportunities become pointers, existing ones get fresh numbers, and pointers no longer detected expire. Decisions taken by reps are never overwritten.",
            data: "Latest engine run log (WR Runs)."
        },
        {
            target: "page:.wr-grid_5 > :nth-child(1)",
            title: "Open value at stake",
            body: "The yearly value of every open pointer (status New or Accepted). Each pointer has its own value: e.g. the revenue lost by a churning line, the missing units x price of a partial switch, or a tender value x win probability.",
            data: "Sum of Value at Stake of open pointers."
        },
        {
            target: "page:.wr-grid_5 > :nth-child(2)",
            title: "Awaiting review",
            body: "Pointers nobody has decided on yet (status New), and their value. This is the work queue of the reps.",
            data: "Pointers with status New."
        },
        {
            target: "page:.wr-grid_5 > :nth-child(3)",
            title: "Reviewed by reps",
            body: "Adoption: decided pointers (accepted, converted or rejected) as a share of decided + new. The hint shows the acceptance rate, accepted or converted / decided.",
            data: "Pointer statuses."
        },
        {
            target: "page:.wr-grid_5 > :nth-child(4)",
            title: "Pipeline created",
            body: "Amount of the Opportunities created from pointers, how many, and how much of it is already won. This is the business result of the Win Room.",
            data: "Opportunities linked to pointers."
        },
        {
            target: "page:.wr-grid_5 > :nth-child(5)",
            title: "Open commitments",
            body: "Actions agreed in win rooms or on pointers that are not done yet; the hint counts the overdue or blocked ones.",
            data: "WR Commitments."
        },
        {
            target: "page:.wr-grid_4",
            title: "Four kinds of opportunity",
            body: "Win back: churn, partial switches to a competitor and contract shortfalls. Cross-sell: missing components, capital pull-through and white space against similar hospitals. Surgeons & site expansion: surgeons who use us elsewhere and new surgeons. New accounts & tenders: tender radar, low share of wallet and contract renewals. Value and number of open pointers per category.",
            data: "Open pointers grouped by rule category."
        },
        {
            target: "page:.wr-grid_2.row > :nth-child(1)",
            title: "Open value by country",
            body: "Where the value is, country by country, with the number of open pointers. Use it to split the effort across the field teams.",
            data: "Open pointers grouped by country."
        },
        {
            target: "page:.wr-grid_2.row > :nth-child(2)",
            title: "Open value by pointer type",
            body: "Which kind of signal carries the most value right now (e.g. tenders, share of wallet, contract shortfall). A good starting point for the weekly priorities.",
            data: "Open pointers grouped by type."
        },
        {
            target: "page:[data-tour='top']",
            title: "Top 10 pointers",
            body: "The ten open pointers with the highest priority score. Score = 60% value at stake (logarithmic, 1M per year = 100) + 25% rule weight + 15% urgency. High from 65, Medium from 45. Click a row to open the pointer, or the account name to open Account 360.",
            data: "Priority score calculated by the engine for each pointer."
        },
        {
            target: "page:[data-tour='rules']",
            title: "Rule performance",
            body: "Pointers created, accepted and rejected per rule, and the acceptance rate. Below 40% the rule produces noise and an admin should tune its thresholds in Rules & Data. This is the feedback loop that keeps the engine credible.",
            data: "Rep decisions on pointers, per rule."
        },
        GUIDE_STEP
    ],
    pointers: [
        {
            target: "filters",
            title: "Scope and country",
            body: "The same All / Mine / My team and country filters as the dashboard; the list below follows them.",
            data: "Pointer owner and country."
        },
        {
            target: "page:.wr-search",
            title: "Search",
            body: "Find a pointer by its title, the account name or its WR number.",
            data: ""
        },
        {
            target: "page:.wr-toolbar",
            title: "Filters and sort",
            body: "Status (New, Accepted, Converted, Rejected, Expired; open by default), category, pointer type and priority. Sort by priority score, value at stake or due date.",
            data: ""
        },
        {
            target: "page:.summary",
            title: "What the filters return",
            body: "Number of pointers and their total value at stake per year for the current filters.",
            data: ""
        },
        {
            target: "page:.list",
            title: "One row = one opportunity at one account",
            body: "Priority, WR number, title, account and country, pointer type, value at stake per year, priority score (bar), due date, status and owner. Only one pointer is kept per account and product line: a specific signal beats the generic peer comparison.",
            data: "Pointers created by the rules engine from sales, surgeons, tenders, contracts and market volumes."
        },
        {
            target: "drawer:.head",
            action: "open-first",
            title: "The pointer",
            body: "Clicking a row opens the pointer. The header shows its rule, category and type, priority, status, account and country, then value at stake per year, priority score, due date and owner.",
            data: "WR Pointer."
        },
        {
            target: "drawer:.actions",
            title: "Decide",
            body: "Accept it (you will act), create an Opportunity (amount and close date prefilled from the value at stake, linked to the pointer), or reject it with a reason. Rejections feed the rule performance table. Decided pointers can be re-opened.",
            data: "Pointer status, Opportunity."
        },
        {
            target: "drawer:[data-tour='why']",
            title: "Why this pointer",
            body: "The rationale in plain words, the facts that triggered the rule (e.g. units last 6 months vs a year earlier) and the monthly chart behind them, with a table view. Every number can be traced back to the sales lines.",
            data: "Evidence stored by the engine on the pointer."
        },
        {
            target: "drawer:[data-tour='ai']",
            title: "AI insight (optional)",
            body: "Generates the why, the what, next best actions, talking points and discovery questions from the pointer facts only. Without an AI connection a rule-based summary is shown. The model never decides whether a pointer exists.",
            data: "Pointer facts sent to the configured model."
        },
        {
            target: "drawer:[data-tour='playbook']",
            title: "Playbook",
            body: "The recommended actions for this rule, written by the business in Rules & Data.",
            data: "Next best action of the rule."
        },
        {
            target: "drawer:[data-tour='commitments']",
            title: "Commitments",
            body: "Concrete actions on this pointer with an owner and a due date. They show up in the weekly win room until they are done.",
            data: "WR Commitments linked to the pointer."
        },
        { ...GUIDE_STEP, action: "close-drawer" }
    ],
    account: [
        {
            target: "page:.side",
            title: "Pick a hospital",
            body: "Search and select any account with a Win Room profile; the list shows the country and the open pointers. Pointers, contracts and tenders also open this page.",
            data: "WR Account Profiles."
        },
        {
            target: "page:.kpis",
            action: "open-first",
            title: "The account in four numbers",
            body: "Our revenue in the last 12 months (and last 6 months vs a year earlier), estimated share of wallet (our revenue / market, market = knee procedures x knee basket + hip procedures x hip basket), open value at stake and procedures per year, from the registry when the hospital is mapped, otherwise an estimate.",
            data: "Monthly sales, account profile, registry volumes."
        },
        {
            target: "page:[data-tour='pointers']",
            title: "Pointers by category",
            body: "Every pointer of this hospital, in the four categories, with value and status. Click one to open it.",
            data: "WR Pointers of the account."
        },
        {
            target: "page:[data-tour='market']",
            optional: true,
            title: "Market volume",
            body: "Hip and knee procedures per year of the registry hospitals linked to this account, with the trend. They replace the estimate in share of wallet.",
            data: "UK National Joint Registry (public statistics)."
        },
        {
            target: "page:[data-tour='contracts']",
            optional: true,
            title: "Contracts",
            body: "Volume commitments of the account with their health (On track / Under / Over) and delivered vs committed.",
            data: "WR Contracts and monthly sales."
        },
        {
            target: "page:[data-tour='trend']",
            title: "Revenue trend by category",
            body: "Monthly revenue per category over 24 months. Hover for the values of a month, or switch to the table view.",
            data: "Monthly sales (WR Sales)."
        },
        {
            target: "page:[data-tour='lines']",
            title: "Product lines",
            body: "Units and revenue per product line in the last 12 months; growth = last 6 months vs the same 6 months a year earlier. Falling lines are flagged.",
            data: "Monthly sales per product line."
        },
        {
            target: "page:[data-tour='surgeons']",
            title: "Surgeons",
            body: "Surgeons who operate at this hospital, their procedures per year, whether this is their primary or secondary site, and whether they already use our products here.",
            data: "WR Surgeons and Affiliations."
        },
        {
            target: "page:[data-tour='tenders']",
            title: "Tenders",
            body: "Public tenders linked to this hospital: title (link to the official notice), deadline and days left, estimated value and status.",
            data: "Tender sync (TED, Find a Tender) and demo tenders."
        },
        {
            target: "page:[data-tour='opps']",
            title: "Open opportunities",
            body: "The open Opportunities of the account, including the ones created from pointers.",
            data: "Salesforce Opportunities."
        },
        GUIDE_STEP
    ],
    winroom: [
        {
            target: "page:.side",
            title: "Team and sessions",
            body: "Choose the team (a country, or All), plan a session for a date and pick a session from the list. The planned session of the week opens by default.",
            data: "WR Sessions."
        },
        {
            target: "page:.session-head",
            action: "open-first",
            title: "The session",
            body: "Date, team and status. Brief writes a short briefing of the 7 answers for the facilitator (AI or rule-based); Complete closes the session, and the next one compares with it.",
            data: "WR Session."
        },
        {
            target: "page:.kpis",
            title: "Since the last win room",
            body: "Opportunities won, new pointers, pointers accepted and converted since the previous session of the same team.",
            data: "Opportunities and pointers changed since the last session date."
        },
        {
            target: "page:.index",
            title: "The 7 questions",
            body: "The same 7 questions every 7 days, with how many items each has this week. Click one to jump to it.",
            data: ""
        },
        {
            target: "page:.brief",
            optional: true,
            title: "Briefing",
            body: "Headline and highlights of the week, generated from the answers below.",
            data: "Agenda of the session, optional AI model."
        },
        {
            target: "page:[data-tour='q1']",
            title: "1 · Wins and losses",
            body: "Opportunities created from pointers that were closed won or lost since the last win room. Celebrate and learn.",
            data: "Opportunities linked to pointers."
        },
        {
            target: "page:[data-tour='q2']",
            title: "2 · New pointers and owners",
            body: "Pointers created since the last session, plus high-priority pointers still waiting for a decision. Each one needs an owner who reviews it this week.",
            data: "New pointers."
        },
        {
            target: "page:[data-tour='q3']",
            title: "3 · Accepted without action",
            body: "Pointers accepted but without an Opportunity or a commitment yet: agreed in principle, not moving.",
            data: "Accepted pointers without Opportunity or open commitment."
        },
        {
            target: "page:[data-tour='q4']",
            title: "4 · Overdue or blocked commitments",
            body: "Commitments past their due date or flagged as blocked. Mark them done or unblock them in the meeting.",
            data: "WR Commitments."
        },
        {
            target: "page:[data-tour='q5']",
            title: "5 · Stuck opportunities",
            body: "Opportunities from pointers without a stage change in 21 days.",
            data: "Opportunity stage history."
        },
        {
            target: "page:[data-tour='q6']",
            title: "6 · Tenders closing in 30 days",
            body: "Open tenders linked to the team's accounts with a deadline in the next 30 days, so no tender is missed.",
            data: "Tenders linked to accounts."
        },
        {
            target: "page:[data-tour='q7']",
            title: "7 · Commitments for next week",
            body: "What the team commits to: an action, an owner, a due date and optionally the pointer it moves. Next week starts by reviewing these.",
            data: "WR Commitments."
        },
        {
            target: "page:[data-tour='notes']",
            title: "Notes",
            body: "Free notes of the meeting, saved on the session.",
            data: "WR Session notes."
        },
        GUIDE_STEP
    ],
    contracts: [
        {
            target: "page:.wr-grid_5",
            title: "Contract health",
            body: "Number of contracts, then how many are On track, Under-delivering or Over-delivering (delivered vs committed to date, beyond the contract tolerance, 10% by default), and how many end within 6 months.",
            data: "WR Contracts compared with monthly sales."
        },
        {
            target: "page:.wr-toolbar",
            title: "Search and filter",
            body: "Search by contract or account, filter by health. Admins create a new contract here: account, term, tolerance and one line per product line with the units per month and the contracted price.",
            data: ""
        },
        {
            target: "page:.scroll",
            title: "Contracts",
            body: "Contract, account, term, health, delivered vs committed to date (bar), variance to date in units and %, annual contract value and end date. Click a row for the detail.",
            data: "Contract lines (units per month) and sales units of the same product line and account."
        },
        {
            target: "page:.detail-head",
            action: "open-first",
            title: "Contract detail",
            body: "Name, account and status. Admins edit the contract (term, tolerance, lines) or delete it.",
            data: "WR Contract."
        },
        {
            target: "page:.kpis",
            title: "Contract to date",
            body: "Committed and delivered units to date, variance, the projection at the end of the term and the annual contract value. Counting starts at the later of the contract start and the first month with sales.",
            data: "Contract lines and monthly sales."
        },
        {
            target: "page:.facts",
            title: "One line of the contract",
            body: "For each product line: units committed per month, contracted price, delivered vs committed, the 6-month run-rate (average of the last 6 complete months) and the projection at term end (delivered + run-rate x remaining months).",
            data: "Contract line and sales units."
        },
        {
            target: "page:.line-body .chart",
            title: "Committed vs delivered, month by month",
            body: "The committed and the delivered units of the line per month. A gap that keeps growing is a shortfall; a line above the commitment is an overrun.",
            data: "Monthly sales units."
        },
        {
            target: "page:.months",
            title: "Monthly table",
            body: "The same numbers as a table, with the cumulative variance, for exact figures and export.",
            data: ""
        },
        {
            target: "page:[data-tour='cpointers']",
            title: "Pointers on this contract",
            body: "Contract shortfall, overrun and renewal pointers raised by the engine for this contract. Shortfall value = annual gap at the current run-rate (or the backlog) x contracted price.",
            data: "Pointers of the contract rules."
        },
        { ...GUIDE_STEP, action: "back" }
    ],
    market: [
        {
            target: "page:.wr-grid_4",
            title: "The registry at a glance",
            body: "Hospitals in the registry, hip and knee procedures in the last 12 complete months, and the share of that volume mapped to our accounts.",
            data: "UK National Joint Registry public statistics (CSV export)."
        },
        {
            target: "page:.wr-toolbar",
            title: "Filter, match and import",
            body: "Search, filter by region, sector (NHS or independent) and mapping status. Admins re-run the automatic matching or import the NJR CSV files: the browser keeps the last 24 complete months and sends one record per hospital, with no scraping and no callout.",
            data: ""
        },
        {
            target: "page:.list",
            title: "Hospitals",
            body: "Hospital and trust, region, sector, hips and knees in the last 12 months, year-on-year trend, market value (volumes x basket price), the linked account, our revenue in 12 months and the share of wallet.",
            data: "Registry volumes; our revenue from the linked account's sales."
        },
        {
            target: "page:.account-cell",
            title: "Matching to accounts",
            body: "Hospitals are matched to accounts by name: 95% similarity links automatically, 60% with a distinctive shared word becomes a suggestion. Admins confirm, pick another account or ignore. A linked hospital's volumes replace the estimate on the account profile.",
            data: "Name similarity between registry hospitals and accounts."
        },
        {
            target: "page:.source",
            title: "Source and licence",
            body: "The registry, the date of the data and the conditions of use.",
            data: ""
        },
        GUIDE_STEP
    ],
    tenders: [
        {
            target: "page:.wr-grid_4",
            title: "Open tenders",
            body: "Notices with a deadline ahead, their estimated value in EUR, how many close within 30 days and how many are linked to accounts. Only linked tenders become tender radar pointers.",
            data: "TED (EU), Find a Tender (UK) and Public Contracts Scotland public APIs."
        },
        {
            target: "page:[data-tour='feeds']",
            optional: true,
            title: "Sources (admins)",
            body: "Each portal with its CPV filter (default orthopaedic implants and fracture fixation), countries (TED), lookback and the result of the last sync. Sync now reads the portals; Daily sync at 06:00 schedules it.",
            data: "Public procurement APIs, read anonymously."
        },
        {
            target: "page:.wr-toolbar",
            title: "Filters",
            body: "Search by title, buyer or account; filter by status (open by default), source, country, category and account mapping. Admins re-run the automatic matching.",
            data: ""
        },
        {
            target: "page:.title-cell",
            title: "The notice",
            body: "Title (link to the official notice) and the buyer as published. Category comes from keywords in the title and description (knee, hip, trauma, robotics) in several languages.",
            data: "Notice fields from the portal."
        },
        {
            target: "page:.list tbody tr:first-child td:nth-child(4)",
            title: "Value and deadline",
            body: "Estimated value converted to EUR (the notice currency below it), the earliest deadline still ahead and the days left; within 14 days it turns red.",
            data: "Procedure value or sum of the lots; org currency rates."
        },
        {
            target: "page:.account-cell",
            title: "Account matching",
            body: "The buyer is matched to accounts of the same country after removing accents and noise words. Automatic links need 95% and two agreeing words; otherwise a suggestion to confirm. Admins confirm, link another account or ignore.",
            data: "Buyer name vs account names."
        },
        {
            target: "page:.detail-row",
            action: "expand-first",
            title: "Details",
            body: "Description, reference, publication date, CPV codes and the value in both currencies. Admins set the status: Submitted, Won, Lost or Cancelled; a sync never overwrites it.",
            data: "Notice fields from the portal."
        },
        {
            target: "page:.source",
            title: "Sources and licences",
            body: "Where the notices come from and their reuse conditions.",
            data: ""
        },
        GUIDE_STEP
    ],
    admin: [
        {
            target: "page:.wr-tabs",
            action: "tab:rules",
            title: "Rules & Data",
            body: "Four tabs: Rules (what the engine looks for), Engine runs (history), Data (demo data, demo team, account scope) and Product lines (codes and prices).",
            data: ""
        },
        {
            target: "page:.push",
            title: "Rule actions",
            body: "Reset to defaults restores the default rules and thresholds; New rule adds a rule of any of the 11 types; Run engine now applies the rules to every in-scope account.",
            data: ""
        },
        {
            target: "page:.wr-table",
            title: "Rules",
            body: "Active switch, name and description, type, category, weight (1-5, how much the business trusts the signal), threshold, minimum value at stake, lookback / recent windows, product lines and expected ratio. The pencil opens the rule in a dialog that shows only the parameters of its type.",
            data: "WR Rules."
        },
        {
            target: "page:.wr-card",
            action: "tab:runs",
            title: "Engine runs",
            body: "Each run with its status, start, duration, accounts processed and pointers new, updated and expired, and who started it. Errors are shown under the run.",
            data: "WR Runs."
        },
        {
            target: "page:.stats",
            action: "tab:data",
            title: "Data in the org",
            body: "How many profiles (and in scope), sales rows, surgeons, tenders, pointers, win rooms and rules exist.",
            data: "Record counts."
        },
        {
            target: "page:.wr-grid_3 > :nth-child(1)",
            title: "Generate demo data",
            body: "Creates profiles on hospital accounts, surgeons, tenders, contracts, win rooms and 24 months of sales (18 in Developer Edition orgs) with planted patterns, so every rule finds something. Accounts are spread across you and your demo team. Safe to re-run.",
            data: ""
        },
        {
            target: "page:.wr-grid_3 > :nth-child(2)",
            title: "Demo team",
            body: "Creates six fictitious reps whose manager is you (Chatter Free users, no welcome e-mail, no licence), so Mine and My team show different numbers.",
            data: ""
        },
        {
            target: "page:.wr-grid_3 > :nth-child(3)",
            title: "Purge demo data",
            body: "Deletes every Win Room record flagged as demo, plus engine runs. Opportunities and real tenders are kept.",
            data: ""
        },
        {
            target: "page:[data-tour='scope']",
            title: "Account scope",
            body: "Every profiled account feeds the peer benchmarks; only in-scope accounts get pointers. Set the rollout phase and the in-scope switch per account; the rep column is the default pointer owner.",
            data: "WR Account Profiles."
        },
        {
            target: "page:.wr-card",
            action: "tab:lines",
            title: "Product lines",
            body: "Code, name, system, category, component, average price and capital flag. Codes are used by the rules (anchor / target lines) and prices value the pointers and the market baskets.",
            data: "WR Product Lines."
        },
        { ...GUIDE_STEP, action: "tab:rules" }
    ]
};
