/**
 * Interactive tour per page. A step targets an element of the shell ("nav", "filters", "run", "guide", "tour")
 * or of the current page ("page:<css selector>", measured by the page component's tourRect()).
 * Steps whose target is not on screen (e.g. no account selected yet) are shown without a spotlight.
 */
const SHELL_END = [
    {
        target: "run",
        title: "Engine status",
        body: "When the rules engine last ran and how it ended. Pointers are refreshed by each run; decisions taken by reps are never overwritten.",
        data: "Latest engine run log (WR Runs)."
    },
    {
        target: "guide",
        title: "Need more detail?",
        body: "The guide explains every page, every formula and the live rule settings, and has a 10-minute demo script. The tour button next to the page title replays this tour.",
        data: ""
    }
];

export const TOURS = {
    dashboard: [
        {
            target: "nav",
            title: "Welcome to the Win Room",
            body: "Identify opportunities in the sales data, act on them, review them every week and control contracts, market and tenders. Each tab is one step of that loop.",
            data: ""
        },
        {
            target: "filters",
            title: "Whose work and where",
            body: "All = every pointer you can see. Mine = pointers assigned to you. My team = you and the people who report to you (manager on the user record). Country narrows everything on this page and on Pointers.",
            data: "Pointer owner (Assigned To) and the user hierarchy."
        },
        {
            target: "page:.wr-grid_5",
            title: "Headline numbers",
            body: "Open value at stake (New + Accepted pointers, per year), how many wait for a decision, the share already reviewed by reps, the pipeline created from pointers and the open win room commitments.",
            data: "WR Pointers, linked Opportunities and WR Commitments."
        },
        {
            target: "page:.wr-grid_4",
            title: "Four kinds of opportunity",
            body: "Win back (churn, switches, contract shortfalls), cross-sell (attach, capital pull-through, white space), surgeons & site expansion, and new accounts & tenders. Value and count of open pointers per category.",
            data: "Open pointers grouped by rule category."
        },
        {
            target: "page:.wr-grid_2.row",
            title: "Where the value is",
            body: "Open value by country and by pointer type, largest first. Use it to decide where the team spends the week.",
            data: "Open pointers grouped by country and type."
        },
        {
            target: "page:[data-tour='top']",
            title: "Top 10 to act on",
            body: "The open pointers with the highest priority score: 60% value at stake (log scale), 25% rule weight, 15% urgency. Click one to see why it exists.",
            data: "Priority score calculated by the engine for each pointer."
        },
        {
            target: "page:[data-tour='rules']",
            title: "Is each rule useful?",
            body: "Accepted vs rejected per rule. Below 40% acceptance the rule produces noise: an admin tunes its thresholds in Rules & Data, without code.",
            data: "Rep decisions on pointers, per rule."
        },
        ...SHELL_END
    ],
    pointers: [
        {
            target: "filters",
            title: "Scope and country",
            body: "The same All / Mine / My team and country filters as the dashboard.",
            data: "Pointer owner and country."
        },
        {
            target: "page:.wr-toolbar",
            title: "Find the right pointers",
            body: "Search by account or title, filter by category, status and priority, and sort by priority, value or due date.",
            data: ""
        },
        {
            target: "page:.list",
            title: "One row = one opportunity at one account",
            body: "Type, value at stake per year, priority score, due date and owner. Open a row to see the facts, the monthly chart, the rationale and the playbook, then accept (and create an Opportunity) or reject with a reason.",
            data: "Pointers created by the rules engine from monthly sales, surgeons, tenders, contracts and market volumes."
        },
        ...SHELL_END
    ],
    account: [
        {
            target: "page:.side",
            title: "Pick a hospital",
            body: "Search any account with a Win Room profile. Pointers, contracts and tenders also open this page.",
            data: "WR Account Profiles."
        },
        {
            target: "page:.kpis",
            title: "The account in four numbers",
            body: "Our revenue in the last 12 months (and the trend), estimated share of wallet (revenue / procedures x basket price), open value at stake and procedures per year (registry or estimate).",
            data: "Monthly sales, account profile and registry volumes when the hospital is mapped."
        },
        {
            target: "page:[data-tour='pointers']",
            title: "Every opportunity at this hospital",
            body: "The pointers of the account by category, with their value and status.",
            data: "WR Pointers of the account."
        },
        {
            target: "page:[data-tour='trend']",
            title: "Revenue trend",
            body: "Monthly revenue per category over 24 months. Hover for values, or switch to the table view.",
            data: "Monthly sales (WR Sales)."
        },
        {
            target: "page:[data-tour='lines']",
            title: "Product lines",
            body: "Units and revenue per line in the last 12 months; growth compares the last 6 months with the same months a year earlier. Lines in red are falling fast.",
            data: "Monthly sales per product line."
        },
        {
            target: "page:[data-tour='tenders']",
            title: "Tenders",
            body: "Public tenders linked to this hospital, with the deadline and a link to the official notice.",
            data: "Tender sync (TED, Find a Tender) and demo tenders."
        },
        ...SHELL_END
    ],
    winroom: [
        {
            target: "page:.side",
            title: "Sessions per team",
            body: "One win room per team per week. Pick a team and a session, or plan the next one.",
            data: "WR Sessions."
        },
        {
            target: "page:.kpis",
            title: "Since the last win room",
            body: "Wins, new pointers and decisions since the previous session of the team.",
            data: "Opportunities and pointers changed since the last session date."
        },
        {
            target: "page:[data-tour='q1']",
            title: "The same 7 questions every 7 days",
            body: "Wins and losses, new pointers and owners, accepted pointers without action, overdue commitments, stuck opportunities (no stage change in 21 days) and tenders closing in 30 days. The system prepares every answer.",
            data: "Pointers, Opportunities, commitments and tenders linked to accounts."
        },
        {
            target: "page:[data-tour='q7']",
            title: "Commit",
            body: "The last question records what the team commits to for next week, with an owner, a due date and the pointer it moves. Next week starts by reviewing these.",
            data: "WR Commitments."
        },
        ...SHELL_END
    ],
    contracts: [
        {
            target: "page:.wr-grid_5",
            title: "Contract health",
            body: "How many contracts, how many are on track, under or over the committed volume, and how many end within 6 months.",
            data: "WR Contracts compared with monthly sales."
        },
        {
            target: "page:.section",
            title: "Committed vs delivered",
            body: "Each contract with its delivered share of the commitment to date and the variance. Open one to see every line month by month, the 6-month run-rate and the projection to the end of the term.",
            data: "Contract lines (units per month) and sales units of the same product line and account."
        },
        ...SHELL_END
    ],
    market: [
        {
            target: "page:.wr-grid_4",
            title: "The registry at a glance",
            body: "Hospitals in the registry, hip and knee procedures per year, and how much of that volume is mapped to our accounts.",
            data: "UK National Joint Registry public statistics (CSV export)."
        },
        {
            target: "page:.wr-toolbar",
            title: "Filter and import",
            body: "Search, filter by region, sector and mapping. Admins import the NJR CSV files here; the browser keeps the last 24 complete months and sends one record per hospital.",
            data: ""
        },
        {
            target: "page:.list",
            title: "Hospital volumes and share of wallet",
            body: "Procedures in the last 12 months, year-on-year trend and market value (volumes x basket price). When a hospital is linked to an account, its volumes replace the estimate and share of wallet uses real counts.",
            data: "Registry volumes; our revenue from the linked account's sales."
        },
        ...SHELL_END
    ],
    tenders: [
        {
            target: "page:.wr-grid_4",
            title: "Open tenders",
            body: "Notices with a deadline ahead, their estimated value in EUR, how many close within 30 days and how many are linked to accounts (only those become pointers).",
            data: "TED (EU), Find a Tender (UK) and Public Contracts Scotland public APIs."
        },
        {
            target: "page:[data-tour='feeds']",
            title: "Sources (admins)",
            body: "Each portal with its CPV filter, lookback and the result of the last sync. Sync now or schedule a daily sync.",
            data: "Public procurement APIs, read anonymously."
        },
        {
            target: "page:.wr-toolbar",
            title: "Filters",
            body: "Status, source, country, category and account mapping.",
            data: ""
        },
        {
            target: "page:.list",
            title: "Each notice",
            body: "Title (link to the official notice), buyer, category, value in EUR (and in the notice currency), deadline and the matched account. Expand a row for the description and CPV codes. Admins confirm or change the account link.",
            data: "Buyer matched to accounts of the same country by name."
        },
        ...SHELL_END
    ],
    admin: [
        {
            target: "page:.wr-tabs",
            title: "Rules & Data",
            body: "Rules, engine runs, data (demo data, demo team, account scope) and product lines.",
            data: ""
        },
        {
            target: "page:.wr-card",
            title: "Rules without code",
            body: "Each rule has a type, thresholds, windows, weight and a playbook. Edit one, add a new rule of any type, or deactivate it. Run the engine to apply the changes; decisions on existing pointers are kept.",
            data: "WR Rules."
        },
        ...SHELL_END
    ]
};
