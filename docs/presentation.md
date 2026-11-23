# Talk track

**One line.** A win room inside Salesforce: rules find customer-level opportunities in sales data, reps act on them with the evidence in front of them, and a weekly rhythm turns them into commitments.

## The problem (1 minute)

- Opportunities are spotted late, or not at all: a hospital slowly moves one component to a competitor, a surgeon who loves the product starts operating somewhere else, a tender deadline slips past.
- When analytics exist, they live outside the CRM. Reps get a spreadsheet, and nothing connects it to the pipeline or to a weekly follow-up.

## The approach (2 minutes)

1. **Identify.** 15 configurable rules compare each hospital with its own history and with similar hospitals, and create *pointers*: churn, partial switches, missing components, robotic workflows, surgeons, tenders, low share of wallet.
2. **Activate.** Each pointer shows *why*: the numbers, a chart and the rule. An optional AI summary adds talking points and questions. The rep accepts it (and creates an Opportunity) or rejects it with a reason.
3. **Execute.** A weekly win room asks the same 7 questions every 7 days, and commitments have owners and due dates.
4. **Control.** Contracts show committed vs delivered volume month by month; shortfalls, overruns and renewals become pointers. A market view brings public registry volumes per hospital, so share of wallet uses real procedure counts.

## Why it is built this way (1 minute)

- **Explainable before intelligent.** The rules are deterministic, so a rep can challenge any number. AI is used for wording, not for deciding.
- **In the CRM, not next to it.** Pointers, Opportunities and commitments share one data model and one security model, with no integration layer.
- **Business-owned.** Thresholds and playbooks are records, the acceptance rate per rule shows what to tune, and re-runs never lose a decision.

## Demo

Follow the 10-minute script in the [README](../README.md#demo-script-10-minutes).

## Questions you may get

- *Where does the data come from?* Monthly sell-in from the ERP at account × product line level, plus optional surgeon affiliations and tenders. The demo generates fictitious data with planted patterns.
- *Does it need AI?* No. Without the Named Credential every screen works with rule-based summaries.
- *How does it scale?* Two batches (benchmarks, then evaluation, 5 accounts per execute); the queries are aggregated by month.
- *Is the market data real?* Yes, and public: the UK National Joint Registry export, downloaded by the user and parsed in the browser. Everything else in the demo is fictitious.
- *What if a pointer is wrong?* Reject it with a reason. The rule's acceptance rate on the dashboard shows when to tune it.
