import { LightningElement, api } from "lwc";
import getTenders from "@salesforce/apex/WinRoomController.getTenders";
import syncTenders from "@salesforce/apex/WinRoomController.syncTenders";
import saveTenderSource from "@salesforce/apex/WinRoomController.saveTenderSource";
import scheduleTenderSync from "@salesforce/apex/WinRoomController.scheduleTenderSync";
import autoMatchTenders from "@salesforce/apex/WinRoomController.autoMatchTenders";
import setTenderMapping from "@salesforce/apex/WinRoomController.setTenderMapping";
import setTenderStatus from "@salesforce/apex/WinRoomController.setTenderStatus";
import searchAllAccounts from "@salesforce/apex/WinRoomController.searchAllAccounts";
import getJobStatus from "@salesforce/apex/WinRoomController.getJobStatus";
import { money, formatDate, reduceErrors, COUNTRY_NAMES, tourRect } from "c/winRoomUtils";

const POLL_MS = 4000;
const COVERAGE = {
    TED: "EU / EEA notices above the EU thresholds",
    FTS: "UK notices above the UK thresholds (incl. Scotland)",
    PCS: "Scotland, also below the thresholds"
};
const STATUSES = ["Open", "Submitted", "Won", "Lost", "Cancelled", "Closed"];
const CATEGORIES = ["Knee", "Hip", "Knee & Hip", "Robotics", "Trauma", "Orthopaedics"];

/**
 * Tender radar: public tenders read from TED, Find a Tender and Public Contracts Scotland, matched to accounts.
 * Admins manage the sources, run the sync and confirm buyer-to-account links.
 */
export default class WinRoomTenders extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    @api isAdmin = false;

    data;
    error;
    message;
    loading = false;
    busy = false;
    search = "";
    status = "Open";
    source = "";
    country = "";
    category = "";
    mapping = "";
    feedEdits = {};
    expanded = {};
    mappingId;
    accountResults = [];
    jobId;

    connectedCallback() {
        this.load();
    }
    disconnectedCallback() {
        window.clearTimeout(this._poll);
        window.clearTimeout(this._t);
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getTenders({
                filterJson: JSON.stringify({
                    search: this.search, status: this.status, source: this.source,
                    country: this.country, category: this.category, mapping: this.mapping
                })
            });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------------------------------------------------------------- view model
    get kpis() {
        const d = this.data || {};
        return [
            { key: "open", label: "Open tenders", value: d.open ?? "–", hint: "Deadline today or later" },
            { key: "value", label: "Open value", value: money(d.openValue), hint: "Sum of estimated values, in EUR" },
            { key: "soon", label: "Closing in 30 days", value: d.closingSoon ?? "–", hint: "Need a bid owner now" },
            { key: "linked", label: "Linked to accounts", value: d.linked ?? "–", hint: "Open tenders the tender radar rule can use" }
        ];
    }
    get feeds() {
        const order = { TED: 0, FTS: 1, PCS: 2 };
        return [...((this.data && this.data.feeds) || [])].sort((a, b) => (order[a.Code__c] ?? 9) - (order[b.Code__c] ?? 9)).map((f) => {
            const edit = this.feedEdits[f.Id];
            const v = { ...f, ...(edit || {}) };
            const err = (f.Last_Status__c || "").startsWith("Error");
            return {
                ...v,
                isTed: f.Code__c === "TED",
                countriesValue: v.Countries__c || "",
                fixedCountry: f.Code__c === "TED" ? "" : "GB",
                coverage: COVERAGE[f.Code__c] || "",
                lastRun: f.Last_Run__c ? formatDate(f.Last_Run__c) : "Never",
                statusClass: err ? "feed-status feed-status_error" : "feed-status",
                dirty: !!edit
            };
        });
    }
    get scheduled() {
        return !!(this.data && this.data.scheduled);
    }
    get syncDisabled() {
        return this.busy || !!this.jobId;
    }
    get syncLabel() {
        if (!this.jobId) return "Sync now";
        const j = this.job;
        return j && j.total ? `Syncing ${j.processed}/${j.total}…` : "Syncing…";
    }
    get statusOptions() {
        return [...STATUSES.map((s) => ({ label: s === "Open" ? "Open (deadline ahead)" : s, value: s })), { label: "All", value: "All" }];
    }
    get sourceOptions() {
        return [{ label: "All sources", value: "" }, ...((this.data && this.data.sources) || []).map((s) => ({ label: s, value: s }))];
    }
    get countryOptions() {
        return [
            { label: "All countries", value: "" },
            ...((this.data && this.data.countries) || []).map((c) => ({ label: COUNTRY_NAMES[c] || c, value: c, hint: c }))
        ];
    }
    get categoryOptions() {
        return [{ label: "All categories", value: "" }, ...CATEGORIES.map((c) => ({ label: c, value: c }))];
    }
    get mappingOptions() {
        return [
            { label: "All", value: "" },
            { label: "Linked", value: "Mapped" },
            { label: "Suggested", value: "Suggested" },
            { label: "Unmatched", value: "Unmatched" },
            { label: "Ignored", value: "Ignored" },
            { label: "Demo data", value: "Demo" }
        ];
    }
    get rows() {
        return ((this.data && this.data.rows) || []).map((r) => {
            const open = r.status === "Open";
            const d = r.daysLeft;
            const isMapped = !!r.accountId;
            const foreign = r.currencyCode && r.currencyCode !== "EUR" && r.originalValue !== null && r.originalValue !== undefined;
            const expanded = !!this.expanded[r.id];
            return {
                ...r,
                countryName: COUNTRY_NAMES[r.country] || r.country || "–",
                category: r.category || "–",
                valueText: r.value === null || r.value === undefined ? "–" : money(r.value),
                originalText: foreign ? `${r.currencyCode} ${Math.round(r.originalValue).toLocaleString("en-GB")}` : "",
                valueNote: r.value === null || r.value === undefined
                    ? "Not published"
                    : foreign
                        ? `${r.currencyCode} ${Math.round(r.originalValue).toLocaleString("en-GB")}, converted to ${money(r.value)}`
                        : money(r.value),
                deadlineText: r.deadline ? formatDate(r.deadline) : "–",
                daysText: !open || d === null || d === undefined || d < 0 ? "" : d === 0 ? "Closes today" : d === 1 ? "1 day left" : `${d} days left`,
                daysClass: open && d !== null && d <= 14 ? "wr-overdue" : "wr-faint",
                publishedText: r.published ? formatDate(r.published) : "–",
                cpvText: r.cpv || "–",
                isMapped,
                canUnlink: this.isAdmin && isMapped && !r.isDemo,
                isSuggested: !isMapped && r.matchStatus === "Suggested",
                isOpen: !isMapped && r.matchStatus !== "Suggested",
                isMapping: r.id === this.mappingId,
                statusTag: r.matchStatus === "Confirmed" ? "wr-tag wr-tag_good" : "wr-tag wr-tag_accent",
                statusClass: open ? "wr-tag wr-tag_accent" : r.status === "Won" ? "wr-tag wr-tag_good" : "wr-tag",
                expanded,
                expandedAttr: expanded ? "true" : "false",
                chevron: expanded ? "utility:chevrondown" : "utility:chevronright",
                rowClass: expanded ? "row row_open" : "row",
                detailKey: `${r.id}-detail`,
                statusActions: ["Open", "Submitted", "Won", "Lost", "Cancelled"].map((s) => ({
                    label: s, value: s, cls: s === r.status ? "wr-btn wr-btn_primary small-btn" : "wr-btn small-btn"
                }))
            };
        });
    }
    get hasRows() {
        return this.rows.length > 0;
    }
    get hasResults() {
        return this.accountResults.length > 0;
    }
    get sourceNote() {
        return "Sources: TED – Tenders Electronic Daily (Publications Office of the EU, reuse allowed with attribution), Find a Tender (UK Cabinet Office, Open Government Licence v3.0), Public Contracts Scotland (Scottish Government, Open Government Licence v3.0). Values are the estimates published by the buyer, converted to EUR. Open each notice for the official documents.";
    }

    // ---------------------------------------------------------------- filters
    handleSearch(e) {
        window.clearTimeout(this._t);
        const v = e.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._t = window.setTimeout(() => {
            this.search = v;
            this.load();
        }, 350);
    }
    handleFilter(e) {
        this[e.target.dataset.field] = e.detail.value;
        this.load();
    }
    toggleRow(e) {
        const id = e.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }
    openAccount(e) {
        this.dispatchEvent(new CustomEvent("openaccount", { detail: { accountId: e.currentTarget.dataset.id } }));
    }

    // ---------------------------------------------------------------- sources & sync
    editFeed(e) {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const value = field === "Active__c" ? e.target.checked : e.target.value;
        this.feedEdits = { ...this.feedEdits, [id]: { ...(this.feedEdits[id] || {}), [field]: value } };
    }
    async saveFeed(e) {
        const id = e.currentTarget.dataset.id;
        const f = this.feeds.find((x) => x.Id === id);
        try {
            await saveTenderSource({
                source: {
                    Id: id, Active__c: f.Active__c, CPV_Prefixes__c: f.CPV_Prefixes__c, Countries__c: f.Countries__c,
                    Lookback_Days__c: f.Lookback_Days__c ? Number(f.Lookback_Days__c) : null, Max_Pages__c: f.Max_Pages__c
                }
            });
            const edits = { ...this.feedEdits };
            delete edits[id];
            this.feedEdits = edits;
            this.message = `${f.Name} saved. The next sync uses the new filters.`;
            await this.load();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    async toggleSchedule(e) {
        const enabled = e.target.checked;
        this.busy = true;
        try {
            await scheduleTenderSync({ enabled });
            this.message = enabled ? "Daily sync scheduled at 06:00." : "Daily sync stopped.";
            await this.load();
        } catch (err) {
            this.error = reduceErrors(err);
        } finally {
            this.busy = false;
        }
    }
    async sync() {
        this.error = undefined;
        try {
            this.jobId = await syncTenders();
            this.job = undefined;
            this.message = "Reading the portals. Notices in scope are stored, then buyers are matched to accounts.";
            this.schedulePoll();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    schedulePoll() {
        window.clearTimeout(this._poll);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._poll = window.setTimeout(() => this.poll(), POLL_MS);
    }
    async poll() {
        try {
            this.job = await getJobStatus({ jobId: this.jobId });
            if (this.job && ["Completed", "Failed", "Aborted"].includes(this.job.status)) {
                this.jobId = undefined;
                await this.load();
                const d = this.data || {};
                this.message = `Sync ${this.job.status.toLowerCase()}. ${d.open} open tenders, ${d.linked} linked to accounts. Run the engine (Rules & Data) to refresh tender pointers.`;
                this.dispatchEvent(new CustomEvent("datachanged"));
            } else {
                this.schedulePoll();
            }
        } catch (err) {
            this.jobId = undefined;
            this.error = reduceErrors(err);
        }
    }
    async rematch() {
        this.busy = true;
        try {
            const c = await autoMatchTenders();
            this.message = `Matching: ${c.auto} linked automatically, ${c.suggested} suggestions, ${c.unmatched} without a matching account.`;
            await this.load();
        } catch (err) {
            this.error = reduceErrors(err);
        } finally {
            this.busy = false;
        }
    }

    // ---------------------------------------------------------------- mapping & status
    async map(tenderId, accountId, status) {
        try {
            await setTenderMapping({ tenderId, accountId, status });
            this.mappingId = undefined;
            this.accountResults = [];
            await this.load();
            this.dispatchEvent(new CustomEvent("datachanged"));
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    confirmMatch(e) {
        const r = this.rows.find((x) => x.id === e.currentTarget.dataset.id);
        this.map(r.id, r.suggestedId, "Confirmed");
    }
    ignore(e) {
        this.map(e.currentTarget.dataset.id, null, "Ignored");
    }
    unmap(e) {
        this.map(e.currentTarget.dataset.id, null, "Unmatched");
    }
    startMap(e) {
        this.mappingId = e.currentTarget.dataset.id;
        this.accountResults = [];
    }
    cancelMap() {
        this.mappingId = undefined;
        this.accountResults = [];
    }
    async searchAccount(e) {
        const term = e.target.value;
        if (!term || term.length < 2) {
            this.accountResults = [];
            return;
        }
        try {
            this.accountResults = await searchAllAccounts({ term });
        } catch (err) {
            this.accountResults = [];
        }
    }
    pickAccount(e) {
        this.map(this.mappingId, e.currentTarget.dataset.id, "Confirmed");
    }
    async setStatus(e) {
        try {
            await setTenderStatus({ tenderId: e.currentTarget.dataset.id, status: e.currentTarget.dataset.status });
            await this.load();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    dismiss() {
        this.message = undefined;
    }
}
