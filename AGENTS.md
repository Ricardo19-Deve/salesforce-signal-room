# Notes for maintainers and AI coding assistants

## Where things are

| Need | File |
| --- | --- |
| What a class does | The header comment at the top of every Apex class |
| Rule semantics and defaults | `docs/rules.md`, `WinRoomRules` |
| Design decisions, data model | `docs/architecture.md` |
| Demo data | `WinRoomMockData` (archetypes) and `scripts/apex/seed-demo-data.apex` |
| Public tender feeds | `WinRoomTenders` (requests, parsing, store, matching), `WinRoomTenderSync` (batch per source, schedule) |
| User guide shown in the portal | `lwc/winRoomGuide/guideContent.js` |
| Page tours and the guide's block-by-block tables | `lwc/winRoomTour/winRoomTour.js` (one source); each page exposes `tourRect(selector)` and, if needed, `tourAction(action)` |

## Rules of this codebase

1. **Pointers come from rules.** `WinRoomEngine` decides whether a pointer exists; `WinRoomAIService` only explains it. Do not let model output create, value or prioritise pointers.
2. **Every pointer is explainable.** A new rule type must fill `Rationale__c` with the numbers it used and put them in the evidence `facts`; add a chart series when there is a time series.
3. **Re-runs are safe.** Keep the signature stable (rule | account | product line | surgeon | tender). `save()` must never change the status, owner or decision of an Accepted, Rejected or Converted pointer.
4. **One pointer per customer × product.** Generic signals (peer white space) lose to specific ones; keep that in the dedupe in `evaluateAccount`.
5. **User mode.** Controller queries use `AccessLevel.USER_MODE` and DML uses `as user`. Admin-only methods call `requireAdmin()` (custom permission `Win_Room_Admin`). Add new objects and fields to both permission sets.
6. **No credentials.** The AI service calls `callout:Win_Room_LLM` only. Never add API keys, endpoints with keys or custom settings that hold secrets.
7. **Neutral UI.** Use `c-win-room-select`, `c-win-room-segmented`, `.wr-btn`, `.wr-input`, `.wr-switch` and the `--wr-*` tokens from `winRoomStyles`. Do not use themed base components (`lightning-button`, `lightning-combobox`, `lightning-input`) or global SLDS utility classes: they pick up the org's brand colour and are not available on LWR sites.
8. **Charts.** Four series at most, colours in the fixed `SERIES_COLORS` order, always with a legend and the table view.
9. **Developer Edition storage.** Keep the compact demo mode (18 months, one row per line and month) working; a Developer Edition org has 5 MB of data.
10. **Real data stays out of the repository.** Demo data is generated and fictitious. The only real data the module uses is the public registry export, which users download themselves; never commit registry files, customer names, contracts or prices from a real organisation.
11. **Contracts and registry.** Change compliance logic only in `WinRoomContracts` (portal and rules share it). Registry imports must never overwrite account links (`Account__c`, `Match_Status__c`) and must exclude the current, incomplete month.
12. **Tenders.** Read public APIs anonymously and within fair-use limits (paged, one batch item per source or window, all callouts before any DML). A sync must never overwrite `Account__c`, a confirmed / ignored match or a human status (Submitted, Won, Lost). Keep tender data out of the repository like the registry data.
13. **Guide and tours.** When a calculation, a rule type or a page changes, update `guideContent.js` and the page's steps in `winRoomTour.js` in the same change. Tour targets are CSS selectors inside the page template (prefer a `data-tour` attribute), `drawer:<selector>` for the pointer drawer, or shell targets (`nav`, `filters`, `run`, `guide`). Actions: `open-first`, `back`, `expand-first`, `tab:<key>`, `close-drawer`; mark blocks that only exist with data as `optional`.
14. **Demo users.** Demo reps are Chatter Free users created with the welcome e-mail switched off (`DMLOptions.EmailHeader`). Never create users that send e-mail or consume a Salesforce licence for demo data.
15. **Tests.** `WinRoomTest` runs as a user with `Win_Room_Admin`. Extend it for new rule types (plant the pattern in `WinRoomMockData.pattern` and assert the pointer type).

## Commands

```bash
sf project deploy start -o <org> -d force-app -l RunSpecifiedTests -t WinRoomTest
sf apex run -o <org> -f scripts/apex/seed-demo-data.apex
npm run lint
npm test
```
