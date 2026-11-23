import { LightningElement, api } from "lwc";
import getContext from "@salesforce/apex/WinRoomController.getContext";
import { reduceErrors, formatDate } from "c/winRoomUtils";

const VIEWS = [
    { view: "dashboard", label: "Dashboard", icon: "utility:home", subtitle: "Where the value is and how the field is acting on it" },
    { view: "pointers", label: "Pointers", icon: "utility:lightning_extension", subtitle: "Customer-level opportunities identified by the engine" },
    { view: "account", label: "Account 360", icon: "utility:company", subtitle: "One hospital: trend, product lines, surgeons, tenders and pointers" },
    { view: "winroom", label: "Win Room", icon: "utility:groups", subtitle: "Same 7 questions every 7 days" },
    { view: "contracts", label: "Contracts", icon: "utility:contract", subtitle: "Committed volumes vs delivered, month by month" },
    { view: "market", label: "Market", icon: "utility:world", subtitle: "Hospital procedure volumes from the national joint registry" },
    { view: "tenders", label: "Tenders", icon: "utility:announcement", subtitle: "Public tenders from TED, Find a Tender and Public Contracts Scotland, matched to accounts" }
];
const ADMIN_VIEWS = [{ view: "admin", label: "Rules & Data", icon: "utility:settings", subtitle: "Rules, engine runs, demo data and account scope" }];
const GUIDE_VIEW = { view: "guide", label: "Guide", icon: "utility:help", subtitle: "Every page explained: where the data comes from, how it is calculated, and a demo script" };
const SCOPE_KEY = "winRoom.scope";
const COUNTRY_KEY = "winRoom.country";

/**
 * Win Room portal shell: identify (pointers), activate (account 360 & decisions)
 * and execute (weekly win room). Used as a Lightning tab and on the Experience site.
 */
export default class WinRoomApp extends LightningElement {
    @api fullScreen = false;
    @api brandName = "Contoso Medical";
    @api appName = "Win Room";

    view = "dashboard";
    ctx;
    error;
    scope = "all";
    country = "";
    selectedPointerId;
    selectedAccountId;
    guideSection = "overview";
    refreshKey = 0;

    connectedCallback() {
        try {
            this.scope = window.localStorage.getItem(SCOPE_KEY) || "all";
            this.country = window.localStorage.getItem(COUNTRY_KEY) || "";
        } catch (e) {
            // storage not available (e.g. locked-down browser) - keep defaults
        }
        this.loadContext();
    }

    async loadContext() {
        try {
            this.ctx = await getContext();
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    get hostClass() {
        return this.fullScreen ? "wr-app wr-app_full" : "wr-app";
    }
    get navItems() {
        const items = [...VIEWS, ...(this.ctx && this.ctx.isAdmin ? ADMIN_VIEWS : [])];
        return items.map((i) => ({ ...i, cls: i.view === this.view ? "nav-item nav-item_active" : "nav-item" }));
    }
    get isDashboard() {
        return this.view === "dashboard";
    }
    get isPointers() {
        return this.view === "pointers";
    }
    get isAccount() {
        return this.view === "account";
    }
    get isWinRoom() {
        return this.view === "winroom";
    }
    get isContracts() {
        return this.view === "contracts";
    }
    get isMarket() {
        return this.view === "market";
    }
    get isAdminView() {
        return this.view === "admin";
    }
    get isTenders() {
        return this.view === "tenders";
    }
    get showPageGuide() {
        return this.view !== "guide";
    }
    get isGuide() {
        return this.view === "guide";
    }
    get guideBtnClass() {
        return this.view === "guide" ? "guide-btn guide-btn_active" : "guide-btn";
    }
    get isAdmin() {
        return this.ctx && this.ctx.isAdmin;
    }
    get scopeOptions() {
        return [
            { label: "All", value: "all" },
            { label: "Mine", value: "mine" }
        ];
    }
    get countryOptions() {
        const names = { GB: "United Kingdom", DE: "Germany", FR: "France", ES: "Spain", IT: "Italy", PT: "Portugal",
            NL: "Netherlands", BE: "Belgium", CH: "Switzerland", SE: "Sweden", DK: "Denmark", PL: "Poland" };
        const list = (this.ctx && this.ctx.countries) || [];
        return [{ label: "All countries", value: "" }, ...list.map((c) => ({ label: names[c] || c, value: c, hint: c }))];
    }
    get current() {
        return [...VIEWS, ...ADMIN_VIEWS, GUIDE_VIEW].find((v) => v.view === this.view) || VIEWS[0];
    }
    get showFilters() {
        return this.view === "dashboard" || this.view === "pointers";
    }
    get runChipClass() {
        const r = this.ctx && this.ctx.lastRun;
        return `run-chip wr-status wr-status_${r ? r.Status__c.toLowerCase() : "expired"}`;
    }
    get isEmpty() {
        return this.ctx && this.ctx.pointers === 0;
    }
    get lastRunText() {
        const r = this.ctx && this.ctx.lastRun;
        if (!r) return "Engine not run yet";
        const when = r.Finished__c || r.Started__c;
        return `Engine ${r.Status__c.toLowerCase()} · ${formatDate(when)}`;
    }
    get userName() {
        return (this.ctx && this.ctx.userName) || "";
    }
    get userInitials() {
        const n = (this.ctx && this.ctx.userName) || "";
        return n
            .split(" ")
            .filter((p) => p)
            .slice(0, 2)
            .map((p) => p[0])
            .join("")
            .toUpperCase();
    }
    get showDetail() {
        return !!this.selectedPointerId;
    }

    handleNav(event) {
        this.view = event.currentTarget.dataset.view;
    }
    handleScope(event) {
        this.scope = event.detail.value;
        this.persist(SCOPE_KEY, this.scope);
    }
    handleCountry(event) {
        this.country = event.detail.value;
        this.persist(COUNTRY_KEY, this.country);
    }
    persist(key, value) {
        try {
            window.localStorage.setItem(key, value);
        } catch (e) {
            // ignore
        }
    }
    handleOpenPointer(event) {
        this.selectedPointerId = event.detail.pointerId;
    }
    handleOpenAccount(event) {
        this.selectedAccountId = event.detail.accountId;
        this.selectedPointerId = undefined;
        this.view = "account";
    }
    handleCloseDetail() {
        this.selectedPointerId = undefined;
    }
    handlePointerChanged() {
        this.refreshKey++;
    }
    handleDataChanged() {
        this.loadContext();
        this.refreshKey++;
    }
    goAdmin() {
        this.view = "admin";
    }
    openGuide() {
        this.guideSection = "overview";
        this.view = "guide";
    }
    openPageGuide() {
        this.guideSection = this.view;
        this.view = "guide";
    }
    handleGuideNavigate(event) {
        this.view = event.detail.view;
    }
}
