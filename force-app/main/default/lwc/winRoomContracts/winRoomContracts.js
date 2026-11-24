import { LightningElement, api } from "lwc";
import getContracts from "@salesforce/apex/WinRoomController.getContracts";
import getContract from "@salesforce/apex/WinRoomController.getContract";
import saveContract from "@salesforce/apex/WinRoomController.saveContract";
import deleteContract from "@salesforce/apex/WinRoomController.deleteContract";
import getProductLines from "@salesforce/apex/WinRoomController.getProductLines";
import searchAllAccounts from "@salesforce/apex/WinRoomController.searchAllAccounts";
import LightningConfirm from "lightning/confirm";
import { money, pct, formatDate, todayIso, decoratePointer, reduceErrors, tourRect } from "c/winRoomUtils";

const HEALTH_CLASS = {
    Under: "wr-health wr-health_under",
    Over: "wr-health wr-health_over",
    "On track": "wr-health wr-health_ok",
    "Not started": "wr-health"
};

function signed(ratio) {
    if (ratio === null || ratio === undefined) return "–";
    return `${ratio >= 0 ? "+" : ""}${pct(ratio)}`;
}

/** Volume contracts: committed vs delivered per month, variance, run-rate and projection. */
export default class WinRoomContracts extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    /** Tour support: opens the first contract, or goes back to the list. */
    @api
    async tourAction(action) {
        if (action === "open-first" && !this.detail) {
            if (!this.list) await this.loadList();
            const first = ((this.list && this.list.contracts) || [])[0];
            if (first) await this.openContract(first.contractId);
        } else if (action === "back" && this.detail) {
            this.back();
        }
    }

    @api isAdmin = false;
    _refreshKey;
    list;
    detail;
    error;
    loading = false;
    busy = false;
    search = "";
    health = "";
    editing;
    productLines = [];
    accountResults = [];

    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(v) {
        const changed = this._refreshKey !== undefined && v !== this._refreshKey;
        this._refreshKey = v;
        if (changed) this.reload();
    }

    connectedCallback() {
        this.loadList();
    }

    reload() {
        if (this.detail) this.openContract(this.detail.contract.contractId);
        this.loadList();
    }

    async loadList() {
        this.loading = true;
        try {
            this.list = await getContracts({ filterJson: JSON.stringify({ search: this.search, health: this.health }) });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    async openContract(contractId) {
        this.loading = true;
        try {
            this.detail = await getContract({ contractId });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------------------------------------------------------------- list view model
    get showList() {
        return !this.detail && !this.editing;
    }
    get showDetail() {
        return this.detail && !this.editing;
    }
    get kpis() {
        const d = this.list || { byHealth: {} };
        const h = d.byHealth || {};
        return [
            { key: "total", label: "Contracts", value: `${d.total || 0}`, hint: `${d.renewals || 0} ending within 6 months` },
            { key: "under", label: "Under-delivering", value: `${h.Under || 0}`, hint: "below commitment beyond tolerance", cls: h.Under ? "wr-kpi-value wr-overdue" : "wr-kpi-value" },
            { key: "over", label: "Over-delivering", value: `${h.Over || 0}`, hint: "volume above the contracted tier" },
            { key: "ok", label: "On track", value: `${h["On track"] || 0}`, hint: "within tolerance" },
            { key: "comp", label: "Delivered vs committed", value: pct(d.compliance), hint: `${money(d.deliveredValue)} of ${money(d.committedValue)} to date` }
        ].map((k) => ({ cls: "wr-kpi-value", ...k }));
    }
    get healthOptions() {
        return [
            { label: "All", value: "" },
            { label: "Under-delivering", value: "Under" },
            { label: "Over-delivering", value: "Over" },
            { label: "On track", value: "On track" },
            { label: "Ending within 6 months", value: "Renewal" }
        ];
    }
    get contracts() {
        return ((this.list && this.list.contracts) || []).map((c) => ({
            ...c,
            healthClass: HEALTH_CLASS[c.health] || "wr-health",
            term: `${formatDate(c.startDate)} – ${formatDate(c.endDate)}`,
            progressStyle: `width:${c.monthsTotal ? Math.min(100, (c.monthsElapsed / c.monthsTotal) * 100) : 0}%`,
            progressText: `${c.monthsElapsed} of ${c.monthsTotal} months`,
            complianceText: pct(c.compliancePct),
            varianceText: `${c.varianceValue >= 0 ? "+" : ""}${money(c.varianceValue)}`,
            varianceClass: c.varianceValue < 0 ? "wr-num wr-overdue" : "wr-num",
            annualText: money(c.annualValue),
            endsText: c.daysToEnd === null || c.daysToEnd === undefined ? "" : c.daysToEnd < 0 ? "ended" : `${c.daysToEnd} days`,
            endsClass: c.daysToEnd !== null && c.daysToEnd >= 0 && c.daysToEnd <= 180 ? "wr-tag wr-tag_accent" : "wr-faint",
            lineCount: `${(c.lines || []).length} line(s)`
        }));
    }
    get hasContracts() {
        return this.contracts.length > 0;
    }

    // ---------------------------------------------------------------- detail view model
    get c() {
        return this.detail.contract;
    }
    get comparedFromText() {
        return formatDate(this.c.comparedFrom);
    }
    get detailHealthClass() {
        return HEALTH_CLASS[this.c.health] || "wr-health";
    }
    get detailKpis() {
        const c = this.c;
        return [
            { key: "comp", label: "Delivered vs committed", value: pct(c.compliancePct), hint: `${money(c.deliveredValue)} of ${money(c.committedValue)}` },
            { key: "var", label: "Variance to date", value: `${c.varianceValue >= 0 ? "+" : ""}${money(c.varianceValue)}`, hint: `tolerance ±${c.tolerance}%` },
            { key: "annual", label: "Annual contract value", value: money(c.annualValue), hint: `${(c.lines || []).length} line(s)` },
            { key: "term", label: "Term", value: `${c.monthsElapsed} / ${c.monthsTotal} months`, hint: c.daysToEnd >= 0 ? `ends in ${c.daysToEnd} days` : "ended" }
        ];
    }
    get detailLines() {
        return (this.c.lines || []).map((l) => {
            const months = (l.months || []).map((m, i) => {
                const variance = l.delivered[i] - l.committed[i];
                return {
                    key: `${l.lineId}-${i}`,
                    month: m,
                    committed: l.committed[i],
                    delivered: l.delivered[i],
                    variance: `${variance >= 0 ? "+" : ""}${variance}`,
                    varianceClass: variance < 0 ? "wr-num wr-overdue" : variance > 0 ? "wr-num over" : "wr-num",
                    cumulative: `${l.cumulativeVariance[i] >= 0 ? "+" : ""}${l.cumulativeVariance[i]}`,
                    cumulativeClass: l.cumulativeVariance[i] < 0 ? "wr-num wr-overdue" : "wr-num"
                };
            }).reverse();
            return {
                ...l,
                healthClass: HEALTH_CLASS[l.status] || "wr-health",
                facts: [
                    { key: "q", label: "Committed / month", value: `${l.monthlyQty}` },
                    { key: "d", label: "Delivered to date", value: `${l.deliveredToDate} / ${l.committedToDate}` },
                    { key: "v", label: "Variance to date", value: signed(l.variancePct) },
                    { key: "r", label: "Run-rate (6 months)", value: `${l.runRate} / month (${signed(l.runRatePct)})` },
                    { key: "p", label: "Projected at term end", value: `${l.projectedTotal} / ${l.totalCommitment}` },
                    { key: "u", label: "Contracted price", value: money(l.unitPrice) }
                ],
                series: [
                    { label: "Committed", values: l.committed },
                    { label: "Delivered", values: l.delivered }
                ],
                monthRows: months,
                hasMonths: months.length > 0
            };
        });
    }
    get pointers() {
        return ((this.detail && this.detail.pointers) || []).map(decoratePointer);
    }
    get hasPointers() {
        return this.pointers.length > 0;
    }

    // ---------------------------------------------------------------- actions
    handleSearch(e) {
        window.clearTimeout(this._t);
        const v = e.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._t = window.setTimeout(() => {
            this.search = v;
            this.loadList();
        }, 350);
    }
    handleHealth(e) {
        this.health = e.detail.value;
        this.loadList();
    }
    open(e) {
        this.openContract(e.currentTarget.dataset.id);
    }
    back() {
        this.detail = undefined;
        this.loadList();
    }
    openPointer(e) {
        this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: e.currentTarget.dataset.id } }));
    }
    openAccount(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent("openaccount", { detail: { accountId: e.currentTarget.dataset.id } }));
    }

    // ---------------------------------------------------------------- editor
    async ensureProductLines() {
        if (!this.productLines.length) {
            this.productLines = await getProductLines();
        }
    }
    get productLineOptions() {
        return this.productLines.map((l) => ({ label: l.Name, value: l.Id, hint: l.Category__c }));
    }
    async newContract() {
        await this.ensureProductLines();
        this.editing = {
            id: null, name: "", reference: "", accountId: null, accountName: "", startDate: todayIso(0), endDate: todayIso(365 * 3),
            status: "Active", tolerance: 10, notes: "", lines: [this.blankLine(0)], deletedLineIds: []
        };
    }
    async editContract() {
        await this.ensureProductLines();
        const c = this.c;
        this.editing = {
            id: c.contractId, name: c.name, reference: c.reference || "", accountId: c.accountId, accountName: c.accountName,
            startDate: c.startDate, endDate: c.endDate, status: c.recordStatus || "Active", tolerance: c.tolerance, notes: c.notes || "",
            lines: (c.lines || []).map((l, i) => ({ key: `l${i}`, id: l.lineId, productLineId: l.productLineId, label: l.label, monthlyQty: l.monthlyQty, unitPrice: l.unitPrice })),
            deletedLineIds: []
        };
    }
    blankLine(i) {
        return { key: `n${Date.now()}${i}`, id: null, productLineId: null, label: "", monthlyQty: null, unitPrice: null };
    }
    get statusOptions() {
        return ["Draft", "Active", "Expired", "Terminated"].map((s) => ({ label: s, value: s }));
    }
    get editLines() {
        return (this.editing.lines || []).map((l, i) => ({ ...l, index: i }));
    }
    get hasAccountResults() {
        return this.accountResults.length > 0;
    }
    handleField(e) {
        const f = e.target.dataset.field;
        const v = e.detail && e.detail.value !== undefined ? e.detail.value : e.target.value;
        this.editing = { ...this.editing, [f]: v };
    }
    handleLine(e) {
        const i = Number(e.target.dataset.index);
        const f = e.target.dataset.field;
        const v = e.detail && e.detail.value !== undefined ? e.detail.value : e.target.value;
        const lines = [...this.editing.lines];
        const line = { ...lines[i], [f]: v };
        if (f === "productLineId") {
            const pl = this.productLines.find((x) => x.Id === v);
            if (pl) {
                if (!line.label) line.label = pl.Name;
                if (!line.unitPrice) line.unitPrice = pl.Avg_Price__c;
            }
        }
        lines[i] = line;
        this.editing = { ...this.editing, lines };
    }
    addLine() {
        this.editing = { ...this.editing, lines: [...this.editing.lines, this.blankLine(this.editing.lines.length)] };
    }
    removeLine(e) {
        const i = Number(e.currentTarget.dataset.index);
        const lines = [...this.editing.lines];
        const [removed] = lines.splice(i, 1);
        const deleted = removed.id ? [...this.editing.deletedLineIds, removed.id] : this.editing.deletedLineIds;
        this.editing = { ...this.editing, lines, deletedLineIds: deleted };
    }
    async searchAccount(e) {
        const term = e.target.value;
        this.editing = { ...this.editing, accountName: term, accountId: null };
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
        this.editing = { ...this.editing, accountId: e.currentTarget.dataset.id, accountName: e.currentTarget.dataset.name };
        this.accountResults = [];
    }
    cancelEdit() {
        this.editing = undefined;
    }
    async save() {
        const ed = this.editing;
        if (!ed.accountId) {
            this.error = "Select an account from the list.";
            return;
        }
        this.busy = true;
        try {
            const id = await saveContract({
                contractJson: JSON.stringify({
                    contract: {
                        id: ed.id, name: ed.name, reference: ed.reference, accountId: ed.accountId, startDate: ed.startDate,
                        endDate: ed.endDate, status: ed.status, tolerance: ed.tolerance, notes: ed.notes
                    },
                    lines: ed.lines.map((l) => ({ id: l.id, productLineId: l.productLineId, label: l.label, monthlyQty: l.monthlyQty, unitPrice: l.unitPrice })),
                    deletedLineIds: ed.deletedLineIds
                })
            });
            this.editing = undefined;
            this.error = undefined;
            await this.openContract(id);
            this.loadList();
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    async remove() {
        const ok = await LightningConfirm.open({ message: `Delete the contract "${this.c.name}" and its lines?`, label: "Delete contract", theme: "error" });
        if (!ok) return;
        try {
            await deleteContract({ contractId: this.c.contractId });
            this.back();
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }
}
