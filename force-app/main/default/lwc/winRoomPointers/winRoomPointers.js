import { LightningElement, api } from "lwc";
import getPointers from "@salesforce/apex/WinRoomController.getPointers";
import { CATEGORIES, decoratePointer, money, reduceErrors, tourRect } from "c/winRoomUtils";

const TYPES = [
    "Win-back soft", "Win-back hard", "Partial switch", "Cross-sell", "Peer white space",
    "Capital pull-through", "Surgeon site expansion", "New surgeon", "Tender", "Share of wallet"
];

export default class WinRoomPointers extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    /** Tour support: opens the first pointer of the list in the drawer. */
    @api
    tourAction(action) {
        if (action === "open-first" && this.rows.length) {
            this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: this.rows[0].id } }));
        }
    }

    _scope;
    _country;
    _refreshKey;
    rows = [];
    error;
    loading = false;
    status = "Open";
    category = "";
    priority = "";
    type = "";
    search = "";
    sortBy = "score";

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
            const result = await getPointers({
                filterJson: JSON.stringify({
                    scope: this._scope,
                    country: this._country,
                    status: this.status,
                    category: this.category,
                    priority: this.priority,
                    type: this.type,
                    search: this.search,
                    sortBy: this.sortBy
                })
            });
            this.rows = result.map(decoratePointer);
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    get statusOptions() {
        return ["Open", "New", "Accepted", "Converted", "Rejected", "Expired", "All"].map((s) => ({
            label: s === "Open" ? "Open" : s,
            hint: s === "Open" ? "new + accepted" : undefined,
            value: s
        }));
    }
    get categoryOptions() {
        return [{ label: "All", value: "" }, ...CATEGORIES.map((c) => ({ label: c, value: c }))];
    }
    get priorityOptions() {
        return [{ label: "All", value: "" }, ...["High", "Medium", "Low"].map((c) => ({ label: c, value: c }))];
    }
    get typeOptions() {
        return [{ label: "All", value: "" }, ...TYPES.map((c) => ({ label: c, value: c }))];
    }
    get sortOptions() {
        return [
            { label: "Priority", value: "score" },
            { label: "Value", value: "value" },
            { label: "Due date", value: "due" }
        ];
    }
    get hasRows() {
        return this.rows.length > 0;
    }
    get summary() {
        const total = this.rows.reduce((s, r) => s + (Number(r.value) || 0), 0);
        return `${this.rows.length} pointers · ${money(total)} value at stake per year`;
    }

    handleFilter(event) {
        this[event.target.dataset.field] = event.detail.value;
        this.load();
    }
    handleSearch(event) {
        window.clearTimeout(this._searchTimer);
        const value = event.target.value;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = window.setTimeout(() => {
            this.search = value;
            this.load();
        }, 350);
    }
    openPointer(event) {
        this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: event.currentTarget.dataset.id } }));
    }
    openAccount(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent("openaccount", { detail: { accountId: event.currentTarget.dataset.id } }));
    }
}
