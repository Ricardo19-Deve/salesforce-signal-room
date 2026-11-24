import { LightningElement, api } from "lwc";
import searchAccounts from "@salesforce/apex/WinRoomController.searchAccounts";
import getAccount360 from "@salesforce/apex/WinRoomController.getAccount360";
import { CATEGORIES, CATEGORY_META, decoratePointer, money, pct, formatDate, daysUntil, reduceErrors, tourRect } from "c/winRoomUtils";

export default class WinRoomAccount360 extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    _accountId;
    _refreshKey;
    accounts = [];
    term = "";
    data;
    error;
    loading = false;

    @api
    get accountId() {
        return this._accountId;
    }
    set accountId(v) {
        if (v && v !== this._accountId) {
            this._accountId = v;
            this.loadAccount();
        }
    }
    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(v) {
        const changed = this._refreshKey !== undefined && v !== this._refreshKey;
        this._refreshKey = v;
        if (changed && this._accountId) this.loadAccount();
    }

    connectedCallback() {
        this.loadList();
    }

    async loadList() {
        try {
            this.accounts = await searchAccounts({ term: this.term });
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    async loadAccount() {
        this.loading = true;
        try {
            this.data = await getAccount360({ accountId: this._accountId });
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    get accountRows() {
        return this.accounts.map((a) => ({
            ...a,
            cls: a.accountId === this._accountId ? "acc acc_active" : "acc",
            valueText: money(a.openValue),
            scopeTag: a.inScope ? "wr-tag wr-tag_good" : "wr-tag"
        }));
    }
    get hasData() {
        return !!this.data;
    }
    get account() {
        return this.data.account;
    }
    get profile() {
        return this.data.profile || {};
    }
    get profileLine() {
        const p = this.profile;
        return [p.Segment__c, p.Size_Band__c, p.Phase__c, p.Has_Robot__c ? "surgical robot" : null].filter((x) => x).join(" · ");
    }
    get kpis() {
        const last = this.data.last12 || 0;
        const growth = this.data.growth6;
        const open = (this.data.pointers || []).filter((p) => p.status === "New" || p.status === "Accepted");
        const openValue = open.reduce((s, p) => s + (Number(p.value) || 0), 0);
        const market =
            (this.profile.Knee_Procedures__c || 0) * 2920 + (this.profile.Hip_Procedures__c || 0) * 2880;
        return [
            { key: "rev", label: "Contoso revenue last 12 months", value: money(last), hint: growth === null || growth === undefined ? "" : `${growth >= 0 ? "+" : ""}${pct(growth, 1)} last 6 months vs a year earlier` },
            { key: "sow", label: "Est. share of wallet", value: market ? pct(last / market) : "–", hint: `market ≈ ${money(market)} / yr` },
            { key: "open", label: "Open value at stake", value: money(openValue), hint: `${open.length} open pointers` },
            {
                key: "proc",
                label: "Procedures / yr",
                value: `${this.profile.Knee_Procedures__c || 0} knees`,
                hint: `${this.profile.Hip_Procedures__c || 0} hips · ${this.profile.Volume_Source__c === "NJR" ? "registry (NJR)" : "estimate"}`
            }
        ];
    }
    get quadrants() {
        const pointers = (this.data.pointers || []).map(decoratePointer);
        return CATEGORIES.map((c) => {
            const items = pointers.filter((p) => p.category === c);
            const open = items.filter((p) => p.status === "New" || p.status === "Accepted");
            return {
                key: c,
                label: c,
                icon: CATEGORY_META[c].icon,
                total: money(open.reduce((s, p) => s + (Number(p.value) || 0), 0)),
                items,
                empty: items.length === 0
            };
        });
    }
    get lines() {
        return (this.data.lines || [])
            .map((l) => ({
                ...l,
                key: l.line,
                last: money(l.last12),
                units: Math.round(l.units12 || 0),
                growthText: l.growth === null || l.growth === undefined ? "–" : `${l.growth >= 0 ? "+" : ""}${pct(l.growth)}`,
                growthCls: l.growth !== null && l.growth !== undefined && l.growth < -0.15 ? "wr-num wr-overdue" : "wr-num"
            }))
            .sort((a, b) => b.last12 - a.last12);
    }
    get surgeons() {
        return (this.data.affiliations || []).map((a) => ({
            ...a,
            key: a.surgeonId,
            since: a.since ? String(a.since).substring(0, 4) : "",
            zbTag: a.usesZb ? "wr-tag wr-tag_good" : "wr-tag",
            zbText: a.usesZb ? "Uses Contoso here" : "No Contoso here",
            role: a.primary ? "Primary" : "Secondary site"
        }));
    }
    get tenders() {
        return (this.data.tenders || []).map((t) => {
            const d = daysUntil(t.Deadline__c);
            return {
                ...t,
                deadline: formatDate(t.Deadline__c),
                left: t.Status__c === "Open" && d !== null && d >= 0 ? `${d} days` : "",
                value: money(t.Estimated_Value__c)
            };
        });
    }
    get opportunities() {
        return (this.data.opportunities || []).map((o) => ({ ...o, amount: money(o.Amount), close: formatDate(o.CloseDate) }));
    }
    get contracts() {
        const cls = { Under: "wr-health wr-health_under", Over: "wr-health wr-health_over", "On track": "wr-health wr-health_ok" };
        return (this.data.contracts || []).map((c) => ({
            ...c,
            healthClass: cls[c.health] || "wr-health",
            complianceText: pct(c.compliancePct),
            term: `${formatDate(c.startDate)} – ${formatDate(c.endDate)}`,
            lineText: (c.lines || []).map((l) => `${l.label}: ${l.deliveredToDate} / ${l.committedToDate}`).join(" · ")
        }));
    }
    get hasContracts() {
        return this.contracts.length > 0;
    }
    get market() {
        return this.data.market;
    }
    get hasMarket() {
        return !!(this.data && this.data.market);
    }
    get marketSites() {
        return ((this.market && this.market.sites) || []).map((s, i) => ({ ...s, key: `m${i}` }));
    }
    get marketAsOf() {
        return this.market && this.market.asOf ? formatDate(this.market.asOf) : "";
    }
    openContracts() {
        this.dispatchEvent(new CustomEvent("openview", { detail: { view: "contracts" } }));
    }
    get hasTenders() {
        return this.tenders.length > 0;
    }
    get hasOpps() {
        return this.opportunities.length > 0;
    }

    handleSearch(event) {
        window.clearTimeout(this._t);
        const v = event.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._t = window.setTimeout(() => {
            this.term = v;
            this.loadList();
        }, 300);
    }
    selectAccount(event) {
        this._accountId = event.currentTarget.dataset.id;
        this.loadAccount();
    }
    openPointer(event) {
        this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: event.currentTarget.dataset.id } }));
    }
}
