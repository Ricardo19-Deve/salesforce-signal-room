/**
 * Guide content: one section per page plus the calculations, data sources and a demo script.
 * Blocks: { p }, { list: [] }, { steps: [] }, { formula }, { note }, { table: { head: [], rows: [[]] } }, { h }.
 * A section with `view` gets an "Open page" button; `rules: true` renders the live rule table.
 */
export const SECTIONS = [
    {
        id: "overview",
        title: "How the Win Room works",
        lead: "A win room inside Salesforce: rules find customer-level opportunities in the sales data, reps act on them with the evidence in front of them, and a weekly rhythm turns them into commitments.",
        blocks: [
            { h: "The loop" },
            {
                steps: [
                    "Identify - the engine reads monthly sales per account and product line, surgeon affiliations, tenders, contracts and market volumes, and runs the active rules. Each hit becomes a pointer: one opportunity at one account, with its value at stake.",
                    "Activate - each pointer explains itself (facts, chart, rationale, next best action). The rep accepts it and creates an Opportunity, or rejects it with a reason.",
                    "Execute - the weekly win room asks the same 7 questions every 7 days and records commitments with an owner and a due date.",
                    "Control - contracts compare committed with delivered volume every month; the market view and the tender radar bring public data, so value and timing are not guesses."
                ]
            },
            { h: "Design principles" },
            {
                list: [
                    "Explainable before intelligent: rules are deterministic and every number on a pointer can be traced back to the sales lines that produced it. AI only writes the summary and talking points; it never decides that a pointer exists.",
                    "In the CRM, not next to it: pointers, opportunities, commitments and accounts share one data model and one security model.",
                    "Business-owned: thresholds, weights and playbooks are records an admin edits in Rules & Data. The acceptance rate per rule shows which rule needs tuning.",
                    "Decisions are never lost: re-running the engine updates the numbers of a pointer but never its status, owner or decision."
                ]
            },
            { h: "Where the data comes from" },
            {
                table: {
                    head: ["Data", "Source", "How it gets in", "Refresh"],
                    rows: [
                        ["Monthly sales (units, revenue) per account and product line", "ERP sell-in. In this org: generated demo data", "Integration or data load into WR Sales; demo generator in Rules & Data", "Monthly"],
                        ["Product lines and average prices", "Product master", "WR Product Lines (Rules & Data)", "When prices change"],
                        ["Account profile: segment, size band, procedures / yr, owner", "CRM + market data", "WR Account Profiles; procedures replaced by registry volumes when mapped", "Quarterly / on import"],
                        ["Surgeons and affiliations", "CRM / field intelligence", "WR Surgeons and WR Affiliations", "Continuous"],
                        ["Public tenders", "TED (EU), Find a Tender (UK), Public Contracts Scotland", "Tenders page: Sync now or daily schedule", "Daily"],
                        ["Hospital procedure volumes", "UK National Joint Registry (public statistics)", "Market page: CSV export imported in the browser", "Monthly / quarterly"],
                        ["Volume contracts", "Contract management", "Contracts page (admins) or data load", "When signed"],
                        ["Opportunities", "Salesforce Opportunities", "Created from accepted pointers", "Live"]
                    ]
                }
            },
            { note: "Everything in this org except the public tenders and the registry volumes is demo data generated with planted patterns, so each rule has something to find." },
            { note: "Every page has a Tour button next to its title: it highlights each block of the page in turn and explains what it is for and where its data comes from. Use it in demos and for onboarding." }
        ]
    },
    {
        id: "demo",
        title: "Demo script (10 minutes)",
        lead: "A route through the portal that shows the full loop. Each step names the page and what to point at.",
        blocks: [
            {
                steps: [
                    "Dashboard (1 min) - switch the scope between All, Mine and My team to show that each rep and each manager sees their own work. Then: open value at stake, how many pointers wait for review, the share already reviewed by reps and the pipeline created. Point at the rule performance table: it is the feedback loop.",
                    "Pointers (2 min) - sort by priority, filter a category, open the top pointer. Walk through the facts, the chart and the rationale: every number comes from the sales lines. Generate the AI summary, then accept and create the Opportunity.",
                    "Account 360 (1 min) - from the pointer, open the account: revenue trend, product lines, surgeons, tenders, contracts, market volume and all pointers of the hospital in one view.",
                    "Contracts (2 min) - open a contract that is under-delivering: committed vs delivered per month, cumulative variance, 6-month run-rate and the projection to the end of the term. Show the contract pointer it raised.",
                    "Market (1 min) - registry hospitals with hip and knee volumes, matched to accounts. Explain that share of wallet uses these real procedure counts.",
                    "Tenders (1 min) - real open tenders from the public portals, filtered by CPV code, with buyer matched to accounts. Linked tenders become Tender radar pointers.",
                    "Win Room (2 min) - the 7 questions, the brief and the commitments with owner and due date. Close with: same questions every week, so nothing that matters is skipped."
                ]
            },
            { note: "Before the demo: run the engine in Rules & Data (or regenerate demo data) so the pointers are fresh, and run a tender sync so the deadlines are current." }
        ]
    },
    {
        id: "dashboard",
        view: "dashboard",
        title: "Dashboard",
        lead: "Where the value is and how the field is acting on it. The Scope and Country filters at the top apply to this page and to Pointers: All = every pointer you can see, Mine = pointers assigned to you, My team = you and the users whose manager you are (the Manager field on the user record).",
        blocks: [
            { h: "Indicators" },
            {
                table: {
                    head: ["Indicator", "How it is calculated"],
                    rows: [
                        ["Open value at stake", "Sum of the value at stake of pointers with status New or Accepted (annual value)."],
                        ["Awaiting review", "Pointers with status New: nobody has decided on them yet."],
                        ["Reviewed by reps", "Decided pointers (Accepted, Converted, Rejected) divided by decided + New. The hint shows the acceptance rate: (Accepted + Converted) / decided."],
                        ["Pipeline created", "Amount of the Opportunities created from pointers; the hint shows how many and the amount already won."],
                        ["Open commitments", "Win room commitments not done yet; the hint counts overdue or blocked ones."]
                    ]
                }
            },
            { h: "Charts and tables" },
            {
                list: [
                    "Open value by pointer type and by country: open pointers grouped by type / country, bar length = value at stake.",
                    "Top 10 pointers: the open pointers with the highest priority score. Click one to open it.",
                    "Rule performance: pointers, accepted and rejected per rule. An acceptance rate below 40% means the rule produces noise and its thresholds should be tuned in Rules & Data."
                ]
            }
        ]
    },
    {
        id: "pointers",
        view: "pointers",
        title: "Pointers",
        lead: "Customer-level opportunities identified by the engine. One pointer = one opportunity at one account, usually for one product line.",
        blocks: [
            { h: "The list" },
            {
                list: [
                    "Filter by category (Win back, Cross-sell, Surgeons & site expansion, New accounts & tenders), status, priority and search; sort by priority, value or due date.",
                    "Priority (High / Medium / Low) comes from the priority score described in How pointers are calculated.",
                    "Due date: when the next action is expected (e.g. 14 days before a tender deadline)."
                ]
            },
            { h: "The pointer detail" },
            {
                list: [
                    "Facts: the numbers that triggered the rule (e.g. units last 6 months vs a year earlier, peers that buy the line, days to the tender deadline).",
                    "Chart: the monthly series behind the facts, with a table view for exact values.",
                    "Rationale and next best action: plain text from the rule playbook, filled with the account's numbers.",
                    "AI summary (optional): why it matters, what to do, next best actions, talking points and discovery questions. Generated from the pointer facts only; without an AI connection a rule-based summary is shown."
                ]
            },
            { h: "Decisions" },
            {
                table: {
                    head: ["Status", "Meaning"],
                    rows: [
                        ["New", "Created by the engine, not reviewed yet."],
                        ["Accepted", "The rep agrees and will act. Next step: create the Opportunity."],
                        ["Converted", "An Opportunity was created from the pointer (amount and close date prefilled from the value at stake)."],
                        ["Rejected", "Not relevant, with a mandatory reason. Feeds the acceptance rate per rule."],
                        ["Expired", "A New pointer that the latest engine run no longer detects (the situation resolved itself)."]
                    ]
                }
            }
        ]
    },
    {
        id: "account",
        view: "account",
        title: "Account 360",
        lead: "One hospital on one page: open it from any pointer, contract, tender or search.",
        blocks: [
            {
                table: {
                    head: ["Block", "Content and calculation"],
                    rows: [
                        ["Revenue last 12 months", "Sum of our sales revenue in the last 12 complete months. Hint: last 6 months vs the same 6 months a year earlier."],
                        ["Est. share of wallet", "Our 12-month revenue / estimated market. Market = knee procedures x knee basket + hip procedures x hip basket (basket = sum of the average prices of a typical construct)."],
                        ["Open value at stake", "Value of the account's New and Accepted pointers."],
                        ["Procedures / yr", "Knee and hip procedures from the account profile. 'registry (NJR)' when a registry hospital is mapped to the account, otherwise 'estimate'."],
                        ["Revenue trend by category", "Monthly revenue per category over 24 months (line chart with table view)."],
                        ["Product lines", "Units and revenue per line in the last 12 months; growth = last 6 months vs the same months a year earlier."],
                        ["Surgeons, tenders, contracts, market", "Affiliated surgeons, tenders linked to the account (with a link to the notice), its contracts with health, and the registry volumes."],
                        ["Improvement pointers", "All pointers of the account, any status."]
                    ]
                }
            }
        ]
    },
    {
        id: "winroom",
        view: "winroom",
        title: "Win Room",
        lead: "The weekly meeting of a team: the same 7 questions every 7 days, prepared by the system.",
        blocks: [
            {
                steps: [
                    "What did we win or lose since the last win room? (Opportunities closed since the previous session.)",
                    "Which new pointers landed - who owns them?",
                    "Which accepted pointers have no opportunity or action yet?",
                    "Which commitments are overdue or blocked?",
                    "Where are opportunities stuck (no stage change in 21 days)?",
                    "Which tenders close in the next 30 days? (Open tenders linked to accounts.)",
                    "What do we commit to for next week? (Commitments with owner, due date and optional pointer.)"
                ]
            },
            { p: "Each session has notes and a brief (AI or rule-based) that summarises the 7 answers. Completing a session closes it; the next one starts from where it ended." }
        ]
    },
    {
        id: "contracts",
        view: "contracts",
        title: "Contracts",
        lead: "Volume commitments (e.g. 10 hip cups per month for 3 years) compared with what was actually delivered, month by month.",
        blocks: [
            { h: "Calculations per contract line" },
            {
                table: {
                    head: ["Measure", "How it is calculated"],
                    rows: [
                        ["Committed", "Monthly quantity x months elapsed. Counting starts at the later of the contract start and the first month with sales of the line."],
                        ["Delivered", "Units sold of the contract's product line to the account in the same months (from the sales data)."],
                        ["Variance to date", "Delivered - committed, in units and as % of committed."],
                        ["Run-rate (6 months)", "Average delivered units per month over the last 6 complete months, and its % vs the monthly commitment."],
                        ["Projected at term end", "Delivered to date + run-rate x remaining months, compared with the total commitment."],
                        ["Status", "Under or Over when the variance to date is beyond the contract tolerance (default 10%), otherwise On track. The contract health is the worst line."]
                    ]
                }
            },
            { h: "Pointers raised by contracts" },
            {
                list: [
                    "Contract compliance: a line is Under (or Over) to date AND its run-rate is still beyond the rule threshold. Shortfall value = the larger of the annual gap at the current run-rate (gap per month x 12 x contracted price) and the backlog (missing units x price). Overrun value = the annual revenue above the commitment, a reason to renegotiate the tier.",
                    "Contract renewal: an active contract ends within 6 months (rule lookback), so the renewal starts before a tender is published."
                ]
            }
        ]
    },
    {
        id: "market",
        view: "market",
        title: "Market",
        lead: "Hip and knee procedure volumes per hospital from the UK National Joint Registry (NJR), public statistics.",
        blocks: [
            {
                steps: [
                    "Download the NJR StatsOnline CSV exports (NHS and independent sector) and use Import NJR CSV. The files are parsed in the browser: no scraping and no callout.",
                    "Per hospital the last 24 complete months are kept (the current, incomplete month is excluded): hips and knees in the last 12 months, the 12 months before, and the monthly series.",
                    "Auto-match links hospitals to accounts by name: words are compared after removing noise words (hospital, NHS, trust...). Score >= 95% links automatically; >= 60% with a distinctive shared word is a suggestion to confirm. A trust-level match scores slightly lower than a hospital match.",
                    "When a hospital is linked, its volumes replace the estimate on the account profile (Volume source = NJR), so share of wallet and the Low share of wallet rule use real procedure counts."
                ]
            },
            {
                table: {
                    head: ["Column", "Calculation"],
                    rows: [
                        ["Hips / Knees per yr", "Procedures by operation date in the last 12 complete months."],
                        ["YoY", "(last 12 months - previous 12 months) / previous 12 months."],
                        ["Market value", "Hips x hip basket + knees x knee basket."],
                        ["Our revenue 12m / Share of wallet", "Sales of the linked account in the last 12 months, divided by the market value of all its linked hospitals."]
                    ]
                }
            }
        ]
    },
    {
        id: "tenders",
        view: "tenders",
        title: "Tenders",
        lead: "Real public tenders from the official procurement portals, filtered to the product categories and matched to accounts.",
        blocks: [
            { h: "Sources" },
            {
                table: {
                    head: ["Portal", "Coverage", "How it is read"],
                    rows: [
                        ["TED - Tenders Electronic Daily", "EU / EEA notices above the EU thresholds", "Search API v3 (anonymous). The query filters CPV prefixes, contract-notice types, publication date and optionally buyer countries."],
                        ["Find a Tender", "UK notices above the UK thresholds, including Scotland", "OCDS release packages (tender stage) read in 30-day windows with cursor paging; CPV filter applied in Salesforce."],
                        ["Public Contracts Scotland", "Scotland, also below the thresholds", "OCDS notices per month. Inactive by default: the portal currently sends an incomplete TLS certificate chain, which Salesforce rejects."]
                    ]
                }
            },
            { h: "What happens in a sync" },
            {
                steps: [
                    "Each active source is read with its CPV prefixes (default 33183 orthopaedic implants, prostheses and bone fixation, and 33141770 fracture fixation devices; a notice is in scope when any of its lots uses one of them). The first sync looks back the configured number of days; later syncs start one day before the last run.",
                    "Each notice is normalised: title, buyer, country, publication date, the earliest deadline still ahead, CPV codes, estimated value (procedure value, or the sum of the lots) and a link to the official notice.",
                    "Values are converted to EUR with the org's currency rates (indicative rates if the org has a single currency).",
                    "Category: Robotics, Knee & Hip, Knee, Hip or Trauma from words in the title and description in the main EU languages, otherwise Orthopaedics.",
                    "Duplicates: a notice with the same buyer and title already stored from another portal is skipped.",
                    "Matching: the buyer name is compared with accounts of the same country, after removing noise words in several languages and accents. Each part of the name is also scored (\"Regional Health Service. Hospital X\"). A link is automatic only when the score is >= 95% and at least two words agree; >= 60% becomes a suggestion to confirm.",
                    "Notices whose deadline has passed are closed. Statuses set by people (Submitted, Won, Lost) and account links are never overwritten by a sync."
                ]
            },
            { h: "From tender to pointer" },
            { p: "The Tender radar rule reads open tenders linked to an account whose deadline is within the rule lookback (default 2 months). Value at stake = estimated value x win probability (rule threshold, default 35%). Urgency is 100 when 14 days or less are left, 75 up to 30 days, otherwise 50. Run the engine after a sync to refresh these pointers." },
            { note: "Public data, reuse allowed with attribution: TED (Publications Office of the EU), Find a Tender and Public Contracts Scotland (Open Government Licence v3.0)." }
        ]
    },
    {
        id: "admin",
        view: "admin",
        title: "Rules & Data (admins)",
        lead: "Where admins tune the engine and manage data.",
        blocks: [
            {
                list: [
                    "Rules: activate, deactivate and tune each rule in a dialog that shows only the parameters its type uses (threshold %, minimum value, lookback and recent months, expected ratio, product lines, weight, description and playbook). New rule adds a rule of any of the 11 types, e.g. a second soft-churn rule with a stricter threshold for one product family. Rules you added can be deleted; default rules can only be deactivated, and Reset rules restores them.",
                    "Engine runs: Run engine starts the two batches (benchmarks, then evaluation per account); the history shows pointers new, updated and expired per run.",
                    "Product lines: codes, categories and average prices used for values and baskets.",
                    "Account scope: which account profiles the engine evaluates and who owns them.",
                    "Demo team: creates six fictitious reps (Chatter Free users, no welcome e-mail, no Salesforce licence) whose manager is you, so the Mine and My team filters show different numbers.",
                    "Demo data: generate fictitious sales with planted patterns (sandbox only), spread across you and your demo team, or purge it. A compact mode keeps the data small in Developer Edition orgs."
                ]
            }
        ]
    },
    {
        id: "calc",
        title: "How pointers are calculated",
        rules: true,
        lead: "Every rule is a record with generic parameters. The engine interprets them per rule type, on complete months only (the current month is excluded) and over up to 24 months of history.",
        blocks: [
            { h: "Rule types" },
            {
                table: {
                    head: ["Type", "Fires when", "Value at stake (per year)"],
                    rows: [
                        ["Win-back soft", "Revenue of a line in the recent months dropped at least the threshold % vs the same months a year earlier.", "The revenue gap, annualised."],
                        ["Win-back hard", "No units in the recent months for a line that sold at least the minimum value in the lookback before.", "The lost 12-month revenue."],
                        ["Attach / partial switch", "Units of a target line per unit of an anchor line are below the expected ratio minus the threshold. If the account used to buy at the expected ratio, it is a partial switch (win back); otherwise a cross-sell gap.", "Missing units x average price, annualised."],
                        ["Capital pull-through", "The account uses an anchor capital workflow but not the target workflow, although it has the procedure volume.", "Expected cases x price, plus the implants it protects."],
                        ["Peer white space", "At least the threshold % of hospitals in the same segment (minimum 4 peers) buy a line this account does not.", "Peer average revenue for the line, scaled by account size."],
                        ["Surgeon site expansion", "A surgeon who buys from us at one hospital also operates at this one, with no usage here.", "Surgeon procedures x winnable share x basket."],
                        ["New surgeon", "A surgeon joined in the recent months and has no cases with us yet.", "Procedures x winnable share x basket."],
                        ["Tender radar", "An open tender linked to the account closes within the lookback.", "Estimated value x win probability."],
                        ["Share of wallet", "Our 12-month revenue / estimated market is below the threshold.", "Target share x market - our revenue."],
                        ["Contract compliance", "A contract line is under or over its commitment to date and over the last 6 months.", "Annual gap at run-rate (or the backlog) x contracted price."],
                        ["Contract renewal", "An active contract ends within the lookback months.", "Annual contract value."]
                    ]
                }
            },
            { h: "Priority score (0-100)" },
            { formula: "score = 0.60 x value score + 0.25 x (rule weight x 20) + 0.15 x urgency" },
            {
                list: [
                    "Value score = 100 x ln(1 + value / 5,000) / ln(201): logarithmic, so 1M per year scores 100 and small values still count.",
                    "Rule weight: 1-5, set per rule (how much the business trusts the signal).",
                    "Urgency: 0-100 from the rule, e.g. days left before a tender deadline.",
                    "Priority: High when the score is 65 or more, Medium from 45, otherwise Low."
                ]
            },
            { h: "One pointer per opportunity" },
            {
                list: [
                    "Per account and product line only one pointer is kept: a specific signal beats Peer white space, and between specific signals the highest score wins. Contract pointers are kept per contract line.",
                    "Each pointer has a signature (rule, account, product line, surgeon, tender or contract). A re-run updates the numbers of the same pointer and never changes its status, owner or decision.",
                    "New pointers that a run no longer detects become Expired."
                ]
            }
        ]
    },
    {
        id: "setup",
        title: "Setup, roles and routines",
        lead: "What an admin sets up once, and the routines that keep the data fresh.",
        blocks: [
            { h: "Who can do what" },
            {
                table: {
                    head: ["Role", "Permission set", "Can"],
                    rows: [
                        ["Rep / field user", "Win Room User", "See pointers, accounts, contracts, market and tenders they have access to; accept, reject and convert pointers; run win rooms and record commitments."],
                        ["Manager", "Win Room User + Manager field on the reps", "Everything a rep can, plus the My team scope over their direct reports."],
                        ["Admin", "Win Room Admin", "Rules (edit, new, delete custom), engine runs, demo data and demo team, account scope, contracts editor, registry import and matching, tender sources, sync and matching, tender status."]
                    ]
                }
            },
            { h: "Routines" },
            {
                table: {
                    head: ["Routine", "How", "When"],
                    rows: [
                        ["Load sales", "Integration or data load into WR Sales (account x product line x month)", "Monthly, after month end"],
                        ["Run the engine", "Rules & Data > Run engine now, or a scheduled batch", "After each sales load, or weekly"],
                        ["Tender sync", "Tenders > Sync now, or Daily sync at 06:00", "Daily"],
                        ["Registry volumes", "Market > Import NJR CSV, then check suggestions", "Monthly or quarterly"],
                        ["Review rule performance", "Dashboard > Rule performance; tune rules below 40% acceptance", "Monthly"],
                        ["Win room", "Win Room > plan the session of the week per team", "Weekly"]
                    ]
                }
            },
            { h: "First use checklist" },
            {
                steps: [
                    "Assign the permission sets (Win Room User to reps, Win Room Admin to admins) and set the Manager field of the reps.",
                    "Check the product lines and their average prices (Rules & Data > Product lines).",
                    "Load sales and account profiles, or generate demo data in a sandbox.",
                    "Set the account scope and rollout phase (Rules & Data > Data).",
                    "Run the engine and check the run log (Rules & Data > Engine runs).",
                    "Optional: import registry volumes, run a tender sync, configure the AI connection.",
                    "Run the tour on each page with the team."
                ]
            }
        ]
    },
    {
        id: "datamodel",
        title: "Data model",
        lead: "Every object the Win Room uses. Account and Opportunity are standard; everything else is part of the module.",
        blocks: [
            {
                table: {
                    head: ["Object", "One record is", "Filled by"],
                    rows: [
                        ["WR Sales", "Units and revenue of one product line at one account in one month", "ERP load / demo generator"],
                        ["WR Product Line", "A product family or component with its code, category and average price", "Admin"],
                        ["WR Account Profile", "Win Room settings of an account: country, segment, size, procedures, phase, scope, rep", "Admin / demo generator / registry"],
                        ["WR Surgeon, WR Affiliation", "A surgeon and the hospitals where they operate", "CRM / demo generator"],
                        ["WR Rule", "A rule: type, thresholds, windows, weight, playbook", "Admin"],
                        ["WR Run", "One engine run with its counts and errors", "Engine"],
                        ["WR Pointer", "One opportunity at one account: value, score, rationale, evidence, decision, owner", "Engine, then reps"],
                        ["WR Session, WR Commitment", "A weekly win room and the actions agreed in it or on a pointer", "Teams"],
                        ["WR Contract, WR Contract Line", "A volume commitment and its units per month per product line", "Admin / contract load"],
                        ["WR Market Site", "A registry hospital with its hip and knee volumes and linked account", "Registry import"],
                        ["WR Tender, WR Tender Source", "A public notice with its buyer, value, deadline and linked account; the portals and their filters", "Tender sync / demo generator"],
                        ["Opportunity", "Created from an accepted pointer, linked back to it", "Reps"]
                    ]
                }
            }
        ]
    },
    {
        id: "troubleshooting",
        title: "Troubleshooting",
        blocks: [
            {
                table: {
                    head: ["Symptom", "Cause and fix"],
                    rows: [
                        ["No pointers at all", "The engine has not run, or no account is in scope. Rules & Data > Data: check the scope, then Run engine now and look at Engine runs."],
                        ["A pointer I expected is missing", "The rule is inactive, the value is below its minimum, the account is out of scope, or a more specific pointer exists for the same account and product line."],
                        ["Too many irrelevant pointers of one rule", "Raise its threshold or minimum value, or lower its weight; check its acceptance rate on the dashboard."],
                        ["My team shows the same as Mine", "Nobody has you as Manager. Set the Manager field of your reps (or create the demo team in a sandbox)."],
                        ["A tour step says there is no data", "That block only appears with data (e.g. contracts or registry volumes for the account). The other steps still apply."],
                        ["Tender sync shows an error", "The result column of the source has the message. Public Contracts Scotland fails TLS validation from Salesforce and stays inactive; other errors are usually temporary portal outages."],
                        ["A tender is linked to the wrong account", "Admins unlink it and link the right account, or ignore it. Confirmed links are never changed by a sync."],
                        ["Share of wallet looks wrong", "Check the procedures on the account profile (registry or estimate) and the average prices of the product lines."]
                    ]
                }
            }
        ]
    },
    {
        id: "faq",
        title: "Questions you may get",
        blocks: [
            {
                table: {
                    head: ["Question", "Answer"],
                    rows: [
                        ["Is the data real?", "The tenders and the registry volumes are real public data. Sales, surgeons and contracts in this org are generated demo data with planted patterns."],
                        ["Does it need AI?", "No. Without an AI connection every screen works and summaries are rule-based. AI only writes text from the pointer facts."],
                        ["What if a pointer is wrong?", "Reject it with a reason. The acceptance rate per rule on the dashboard shows when a rule needs tuning, and the admin changes its thresholds without code."],
                        ["How does it scale?", "The engine runs as two batches (benchmarks, then evaluation per account) on monthly aggregates; tender sync and matching run as a batch per source."],
                        ["Who sees what?", "Salesforce security applies: users see the accounts and pointers they have access to. Admin actions need the Win Room admin permission. My team follows the Manager field of the users."],
                        ["Can we add our own rules?", "Yes. Rules & Data > New rule: pick one of the 11 rule types, set its thresholds and playbook, and run the engine. No code or deployment."]
                    ]
                }
            }
        ]
    }
];
