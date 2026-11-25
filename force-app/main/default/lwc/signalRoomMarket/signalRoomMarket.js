import { LightningElement, api } from "lwc";
import getMarket from "@salesforce/apex/SignalRoomController.getMarket";
import importMarket from "@salesforce/apex/SignalRoomController.importMarket";
import autoMatchMarket from "@salesforce/apex/SignalRoomController.autoMatchMarket";
import setMarketMapping from "@salesforce/apex/SignalRoomController.setMarketMapping";
import searchAllAccounts from "@salesforce/apex/SignalRoomController.searchAllAccounts";
import { money, pct, formatDate, reduceErrors, tourRect } from "c/signalRoomUtils";

const HISTORY = 24;
const CHUNK = 150;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Splits one CSV line, honouring double-quoted fields. */
function splitCsv(line) {
    const out = [];
    let cur = "";
    let quoted = false;
    for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (quoted) {
            if (ch === '"' && line[i + 1] === '"') {
                cur += '"';
                i++;
            } else if (ch === '"') {
                quoted = false;
            } else {
                cur += ch;
            }
        } else if (ch === '"') {
            quoted = true;
        } else if (ch === ",") {
            out.push(cur);
            cur = "";
        } else {
            cur += ch;
        }
    }
    out.push(cur);
    return out;
}

/**
 * Parses NJR StatsOnline exports (NHS and Independent Sector) and returns one aggregate per hospital for the last
 * 24 months: 12-month and prior 12-month hip / knee volumes (by operation date) and the monthly series.
 */
export function parseNjr(texts) {
    const rows = [];
    texts.forEach((text) => {
        const lines = text.split(/\r?\n/);
        const h = lines.findIndex((l) => l.startsWith("Provider Type"));
        if (h < 0) throw new Error("This does not look like an NJR StatsOnline export (no 'Provider Type' header).");
        const header = splitCsv(lines[h]);
        const col = (name) => header.indexOf(name);
        const c = {
            provider: col("Provider Type"), year: col("Year"), month: col("Month#"), region: col("Region Name"),
            orgCode: col("Trust Code") >= 0 ? col("Trust Code") : col("Company Code"),
            orgName: col("Trust Name") >= 0 ? col("Trust Name") : col("Company Name"),
            hospital: col("Hospital"), total: col("Completed Procedures (by Operation Date)"),
            hip: col("Hip Procedures (by Operation Date)"), knee: col("Knee Procedures (by Operation Date)")
        };
        if ([c.year, c.month, c.hospital, c.hip, c.knee].some((x) => x < 0)) {
            throw new Error("Unexpected NJR file layout: hip / knee columns not found.");
        }
        for (let i = h + 1; i < lines.length; i++) {
            if (!lines[i]) continue;
            const f = splitCsv(lines[i]);
            const year = parseInt(f[c.year], 10);
            const month = parseInt(f[c.month], 10);
            if (!year || !month) continue;
            rows.push({
                p: year * 12 + (month - 1), provider: f[c.provider], region: f[c.region], orgCode: f[c.orgCode],
                orgName: f[c.orgName], hospital: f[c.hospital], total: +f[c.total] || 0, hip: +f[c.hip] || 0, knee: +f[c.knee] || 0
            });
        }
    });
    if (!rows.length) throw new Error("No data rows found.");
    // The export includes the current month, which is still incomplete: stop at the last full month.
    const now = new Date();
    const lastFull = now.getFullYear() * 12 + now.getMonth() - 1;
    const last = Math.min(Math.max(...rows.map((r) => r.p)), lastFull);
    const first = last - HISTORY + 1;
    const months = [];
    for (let p = first; p <= last; p++) months.push(`${MONTHS[p % 12]} ${String(Math.floor(p / 12)).slice(2)}`);
    const sites = new Map();
    rows.forEach((r) => {
        if (r.p < first || r.p > last) return;
        const key = `${r.provider}|${r.orgCode}|${r.hospital}`;
        if (!sites.has(key)) {
            sites.set(key, {
                key, name: r.hospital, providerType: r.provider, orgCode: r.orgCode, orgName: r.orgName, region: r.region,
                hip12: 0, knee12: 0, hipPrior: 0, kneePrior: 0, total12: 0,
                months, hip: new Array(HISTORY).fill(0), knee: new Array(HISTORY).fill(0)
            });
        }
        const s = sites.get(key);
        const i = r.p - first;
        s.hip[i] += r.hip;
        s.knee[i] += r.knee;
        if (i >= HISTORY - 12) {
            s.hip12 += r.hip;
            s.knee12 += r.knee;
            s.total12 += r.total;
        } else {
            s.hipPrior += r.hip;
            s.kneePrior += r.knee;
        }
    });
    const asOf = `${Math.floor(last / 12)}-${String((last % 12) + 1).padStart(2, "0")}-01`;
    return [...sites.values()].map((s) => ({ ...s, asOf }));
}

export default class SignalRoomMarket extends LightningElement {
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
    region = "";
    provider = "";
    status = "";
    mappingId;
    accountResults = [];

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getMarket({
                filterJson: JSON.stringify({ search: this.search, region: this.region, provider: this.provider, status: this.status })
            });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------------------------------------------------------------- view model
    get hasData() {
        return this.data && this.data.sites > 0;
    }
    get kpis() {
        const d = this.data || {};
        return [
            { key: "sites", label: "Registry hospitals", value: `${d.sites || 0}`, hint: d.asOf ? `data as at ${formatDate(d.asOf)}` : "" },
            { key: "hip", label: "Hip procedures / yr", value: Number(d.hip || 0).toLocaleString(), hint: "last 12 months, by operation date" },
            { key: "knee", label: "Knee procedures / yr", value: Number(d.knee || 0).toLocaleString(), hint: "last 12 months, by operation date" },
            { key: "mapped", label: "Mapped to accounts", value: `${d.mapped || 0}`, hint: `${pct(d.mappedShare, d.mappedShare < 0.1 ? 1 : 0)} of the procedure volume` }
        ];
    }
    get regionOptions() {
        return [{ label: "All", value: "" }, ...((this.data && this.data.regions) || []).map((r) => ({ label: r, value: r }))];
    }
    get providerOptions() {
        return [
            { label: "All", value: "" },
            { label: "NHS", value: "NHS" },
            { label: "Independent", value: "Independent Sector" }
        ];
    }
    get statusOptions() {
        return ["", "Mapped", "Suggested", "Unmatched", "Ignored"].map((s) => ({ label: s || "All", value: s }));
    }
    get rows() {
        return ((this.data && this.data.rows) || []).map((r) => {
            const yoy = r.yoy;
            return {
                ...r,
                hipText: Number(r.hip || 0).toLocaleString(),
                kneeText: Number(r.knee || 0).toLocaleString(),
                yoyText: yoy === null || yoy === undefined ? "–" : `${yoy >= 0 ? "+" : ""}${pct(yoy)}`,
                yoyClass: yoy !== null && yoy !== undefined && yoy < -0.1 ? "sr-num sr-overdue" : "sr-num",
                valueText: money(r.marketValue),
                revenueText: r.revenue === null || r.revenue === undefined ? "–" : money(r.revenue),
                sowText: r.shareOfWallet === null || r.shareOfWallet === undefined ? "–" : pct(r.shareOfWallet),
                providerShort: r.provider === "NHS" ? "NHS" : "Independent",
                isMapped: r.status === "Auto-matched" || r.status === "Confirmed",
                isSuggested: r.status === "Suggested",
                isOpen: r.status === "Unmatched" || r.status === "Ignored" || !r.status,
                isMapping: r.id === this.mappingId,
                statusTag: r.status === "Confirmed" ? "sr-tag sr-tag_good" : r.status === "Auto-matched" ? "sr-tag sr-tag_accent" : "sr-tag"
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
        const d = this.data && this.data.asOf ? formatDate(this.data.asOf) : "-";
        return `Source: National Joint Registry (NJR) StatsOnline, hospital procedure volumes (England, Wales, Northern Ireland, Isle of Man, Guernsey), data as at ${d}. © NJR. Procedures by operation date for consented patients, primary and revision. Check the NJR terms before using the data commercially.`;
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

    // ---------------------------------------------------------------- import
    pickFiles() {
        this.template.querySelector("input.file").click();
    }
    async handleFiles(e) {
        const files = [...e.target.files];
        e.target.value = "";
        if (!files.length) return;
        this.busy = true;
        this.error = undefined;
        try {
            this.message = `Reading ${files.length} file(s)…`;
            const texts = await Promise.all(files.map((f) => f.text()));
            const sites = parseNjr(texts);
            let done = 0;
            for (let i = 0; i < sites.length; i += CHUNK) {
                // eslint-disable-next-line no-await-in-loop
                done += await importMarket({ sitesJson: JSON.stringify(sites.slice(i, i + CHUNK)) });
                this.message = `Imported ${done} of ${sites.length} hospitals…`;
            }
            const counts = await autoMatchMarket();
            this.message = `Imported ${done} hospitals. Matching: ${counts.auto} mapped automatically, ${counts.suggested} suggestions to review, ${counts.unmatched} without a matching account.`;
            await this.load();
            this.dispatchEvent(new CustomEvent("datachanged"));
        } catch (err) {
            this.error = reduceErrors(err);
            this.message = undefined;
        } finally {
            this.busy = false;
        }
    }
    async rematch() {
        this.busy = true;
        try {
            const counts = await autoMatchMarket();
            this.message = `Matching: ${counts.auto} mapped automatically, ${counts.suggested} suggestions, ${counts.unmatched} unmatched.`;
            await this.load();
        } catch (err) {
            this.error = reduceErrors(err);
        } finally {
            this.busy = false;
        }
    }

    // ---------------------------------------------------------------- mapping
    async map(siteId, accountId, status) {
        try {
            await setMarketMapping({ siteId, accountId, status });
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
    dismiss() {
        this.message = undefined;
    }
}
