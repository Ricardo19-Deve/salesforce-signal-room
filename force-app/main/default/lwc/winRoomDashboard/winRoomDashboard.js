import { LightningElement, api } from "lwc";
import getDashboard from "@salesforce/apex/WinRoomController.getDashboard";
import { CATEGORIES, CATEGORY_META, money, pct, decoratePointer, reduceErrors, tourRect } from "c/winRoomUtils";

export default class WinRoomDashboard extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    _scope;
    _country;
    _refreshKey;
    data;
    error;
    loading = false;

    @api
    get scope() {
        return this._scope;
    }
    set scope(v) {
        this._scope = v;
        this.scheduleLoad();
    }
    @api
    get country() {
        return this._country;
    }
    set country(v) {
        this._country = v;
        this.scheduleLoad();
    }
    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(v) {
        this._refreshKey = v;
        this.scheduleLoad();
    }

    connectedCallback() {
        this.scheduleLoad();
    }

    /** Coalesces the property setters fired on first render into one server call. */
    scheduleLoad() {
        if (this._pending) return;
        this._pending = true;
        Promise.resolve().then(() => {
            this._pending = false;
            this.load();
        });
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getDashboard({ scope: this._scope, country: this._country || null });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    status(name) {
        const s = (this.data && this.data.byStatus && this.data.byStatus[name]) || {};
        return { count: s.count || 0, value: s.value || 0 };
    }

    get kpis() {
        if (!this.data) return [];
        const nw = this.status("New");
        const acc = this.status("Accepted");
        const conv = this.status("Converted");
        const rej = this.status("Rejected");
        const decided = acc.count + conv.count + rej.count;
        const adoption = decided + nw.count > 0 ? decided / (decided + nw.count) : null;
        const acceptance = decided > 0 ? (acc.count + conv.count) / decided : null;
        return [
            { key: "open", label: "Open value at stake", value: money(nw.value + acc.value), hint: `${nw.count + acc.count} open pointers per year` },
            { key: "new", label: "Awaiting review", value: `${nw.count}`, hint: money(nw.value) },
            { key: "adoption", label: "Reviewed by reps", value: pct(adoption), hint: `${decided} decisions · ${pct(acceptance)} accepted` },
            { key: "pipe", label: "Pipeline created", value: money(this.data.pipeline), hint: `${this.data.converted} opportunities · ${money(this.data.won)} won` },
            {
                key: "cmt",
                label: "Open commitments",
                value: `${this.data.openCommitments}`,
                hint: `${this.data.overdueCommitments} overdue or blocked`,
                hintClass: this.data.overdueCommitments > 0 ? "wr-kpi-hint wr-overdue" : "wr-kpi-hint"
            }
        ].map((k) => ({ hintClass: "wr-kpi-hint", ...k }));
    }

    get quadrants() {
        const byCat = {};
        ((this.data && this.data.byCategory) || []).forEach((c) => (byCat[c.label] = c));
        return CATEGORIES.map((c) => ({
            key: c,
            label: c,
            icon: CATEGORY_META[c].icon,
            hint: CATEGORY_META[c].hint,
            count: (byCat[c] && byCat[c].count) || 0,
            value: money(byCat[c] && byCat[c].value)
        }));
    }

    bars(list) {
        const rows = list || [];
        const max = Math.max(1, ...rows.map((r) => Number(r.value) || 0));
        return rows.map((r) => ({
            key: r.label,
            label: r.label,
            value: money(r.value),
            count: r.count,
            style: `width:${Math.max(1, ((Number(r.value) || 0) / max) * 100)}%`
        }));
    }
    get countryBars() {
        return this.bars(this.data && this.data.byCountry);
    }
    get typeBars() {
        return this.bars(this.data && this.data.byType);
    }
    get rulePerformance() {
        return ((this.data && this.data.byRule) || [])
            .map((r) => {
                const decided = r.accepted + r.rejected;
                return {
                    key: r.label,
                    label: r.label,
                    total: r.total,
                    accepted: r.accepted,
                    rejected: r.rejected,
                    rate: decided ? pct(r.accepted / decided) : "–",
                    rateClass: decided && r.accepted / decided < 0.4 ? "wr-num wr-overdue" : "wr-num"
                };
            })
            .sort((a, b) => b.total - a.total);
    }
    get top() {
        return ((this.data && this.data.top) || []).map(decoratePointer);
    }
    get hasTop() {
        return this.top.length > 0;
    }

    openPointer(event) {
        this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: event.currentTarget.dataset.id } }));
    }
    openAccount(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent("openaccount", { detail: { accountId: event.currentTarget.dataset.id } }));
    }
}
