import { LightningElement, api } from "lwc";
import getContext from "@salesforce/apex/SignalRoomController.getContext";
import { reduceErrors, formatDate, tourRect } from "c/signalRoomUtils";
import { TOURS } from "c/signalRoomTour";

const VIEWS = [
    { view: "dashboard", label: "Dashboard", icon: "utility:home", subtitle: "Where the value is and how the field is acting on it" },
    { view: "pointers", label: "Pointers", icon: "utility:lightning_extension", subtitle: "Customer-level opportunities identified by the engine" },
    { view: "account", label: "Account 360", icon: "utility:company", subtitle: "One hospital: trend, product lines, surgeons, tenders and pointers" },
    { view: "signalroom", label: "Signal Room", icon: "utility:groups", subtitle: "Same 7 questions every 7 days" },
    { view: "contracts", label: "Contracts", icon: "utility:contract", subtitle: "Committed volumes vs delivered, month by month" },
    { view: "market", label: "Market", icon: "utility:world", subtitle: "Hospital procedure volumes from the national joint registry" },
    { view: "tenders", label: "Tenders", icon: "utility:announcement", subtitle: "Public tenders from TED, Find a Tender and Public Contracts Scotland, matched to accounts" }
];
const ADMIN_VIEWS = [{ view: "admin", label: "Rules & Data", icon: "utility:settings", subtitle: "Rules, engine runs, demo data and account scope" }];
const GUIDE_VIEW = { view: "guide", label: "Guide", icon: "utility:help", subtitle: "Every page explained: where the data comes from, how it is calculated, and a demo script" };
const SCOPE_KEY = "signalRoom.scope";
const COUNTRY_KEY = "signalRoom.country";

/**
 * Signal Room portal shell: identify (pointers), activate (account 360 & decisions)
 * and execute (weekly signal room). Used as a Lightning tab and on the Experience site.
 */
export default class SignalRoomApp extends LightningElement {
    @api fullScreen = false;
    @api brandName = "Contoso Medical";
    @api appName = "Signal Room";

    view = "dashboard";
    ctx;
    error;
    scope = "all";
    country = "";
    selectedPointerId;
    selectedAccountId;
    guideSection = "overview";
    tourOn = false;
    tourIndex = 0;
    tourBox;
    tourBusy = false;
    tourDir = 1;
    tourToken = 0;
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
        return this.fullScreen ? "sr-app sr-app_full" : "sr-app";
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
    get isSignalRoom() {
        return this.view === "signalroom";
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
            { label: "Mine", value: "mine" },
            { label: "My team", value: "team" }
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
        return `run-chip sr-status sr-status_${r ? r.Status__c.toLowerCase() : "expired"}`;
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
        if (this.tourOn) this.endTour();
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

    // ---------------------------------------------------------------- tour
    get hasTour() {
        return !!TOURS[this.view];
    }
    get tourSteps() {
        return TOURS[this.view] || [];
    }
    get tourStep() {
        return this.tourSteps[this.tourIndex] || {};
    }
    get tourCount() {
        return `${this.tourIndex + 1} of ${this.tourSteps.length} · ${this.current.label}`;
    }
    get tourFirst() {
        return this.tourIndex === 0;
    }
    get tourNextLabel() {
        return this.tourIndex === this.tourSteps.length - 1 ? "Finish" : "Next";
    }
    get tourPopClass() {
        return this.tourBusy ? "tour-pop tour-pop_busy" : "tour-pop";
    }
    get tourMissing() {
        return !this.tourBox && !this.tourBusy;
    }
    get progressStyle() {
        return `width:${Math.round(((this.tourIndex + 1) / this.tourSteps.length) * 100)}%`;
    }
    get shadeClass() {
        return this.tourBox ? "tour-shade" : "tour-shade tour-shade_full";
    }
    get shadeStyle() {
        const b = this.tourBox;
        if (!b) return "";
        const pad = 6;
        return `top:${b.top - pad}px;left:${b.left - pad}px;width:${b.width + pad * 2}px;height:${b.height + pad * 2}px`;
    }
    get popStyle() {
        const w = 380;
        const h = 250;
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        const b = this.tourBox;
        if (!b) return `top:${Math.max(16, vh / 2 - h / 2)}px;left:${Math.max(16, vw / 2 - w / 2)}px`;
        let top;
        let left = Math.min(Math.max(16, b.left), vw - w - 16);
        if (b.top + b.height + 16 + h < vh) {
            top = b.top + b.height + 16;
        } else if (b.top - 16 - h > 0) {
            top = b.top - 16 - h;
        } else {
            // Large block: keep the card inside it, top right.
            top = Math.max(16, Math.min(b.top + 16, vh - h - 16));
            left = Math.max(16, Math.min(b.left + b.width - w - 16, vw - w - 16));
        }
        return `top:${top}px;left:${left}px`;
    }
    startTour() {
        this.selectedPointerId = undefined;
        this.tourIndex = 0;
        this.tourDir = 1;
        this.tourOn = true;
        this._onMove = () => this.measureTour(false);
        window.addEventListener("scroll", this._onMove, true);
        window.addEventListener("resize", this._onMove);
        this.showTourStep();
    }
    endTour() {
        this.tourOn = false;
        this.tourBox = undefined;
        this.tourToken = (this.tourToken || 0) + 1;
        window.removeEventListener("scroll", this._onMove, true);
        window.removeEventListener("resize", this._onMove);
    }
    disconnectedCallback() {
        if (this.tourOn) this.endTour();
    }
    tourNext() {
        if (this.tourBusy) return;
        if (this.tourIndex >= this.tourSteps.length - 1) {
            this.endTour();
            return;
        }
        this.tourIndex++;
        this.tourDir = 1;
        this.showTourStep();
    }
    tourBack() {
        if (this.tourBusy || this.tourIndex === 0) return;
        this.tourIndex--;
        this.tourDir = -1;
        this.showTourStep();
    }
    handleTourKey(e) {
        if (e.key === "Escape") this.endTour();
        else if (e.key === "ArrowRight" || e.key === "Enter") this.tourNext();
        else if (e.key === "ArrowLeft") this.tourBack();
    }
    /**
     * Runs the step's action (open a record, switch tab...), then waits until its block is rendered: pages load
     * their data asynchronously. Optional steps whose block never appears are skipped in the direction of travel.
     */
    async showTourStep() {
        const token = (this.tourToken || 0) + 1;
        this.tourToken = token;
        const step = this.tourStep;
        this.tourBusy = true;
        try {
            await this.runTourAction(step.action);
        } catch (e) {
            // an action that fails only means the block may not be on screen
        }
        let box = null;
        const attempts = step.optional ? 10 : 24;
        for (let attempt = 0; attempt < attempts && token === this.tourToken; attempt++) {
            box = this.findTourBox(true);
            if (box) break;
            // eslint-disable-next-line no-await-in-loop
            await this.tourWait(attempt < 4 ? 80 : 150);
        }
        if (token !== this.tourToken) return;
        this.tourBusy = false;
        if (!box && step.optional) {
            const next = this.tourIndex + this.tourDir;
            if (next >= 0 && next < this.tourSteps.length) {
                this.tourIndex = next;
                this.showTourStep();
                return;
            }
        }
        this.tourBox = box;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            this.measureTour(false);
            const nextBtn = this.template.querySelector(".tour-next");
            if (nextBtn) nextBtn.focus();
        });
    }
    tourWait(ms) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        return new Promise((resolve) => window.setTimeout(resolve, ms));
    }
    async runTourAction(action) {
        if (!action) return;
        if (action === "close-drawer") {
            this.selectedPointerId = undefined;
            return;
        }
        const host = this.template.querySelector("[data-tour-host]");
        if (host && host.tourAction) await host.tourAction(action);
    }
    findTourBox(scroll) {
        const target = this.tourStep.target || "";
        if (target.startsWith("page:")) {
            const host = this.template.querySelector("[data-tour-host]");
            return host && host.tourRect ? host.tourRect(target.slice(5), scroll) : null;
        }
        if (target.startsWith("drawer:")) {
            const drawer = this.template.querySelector("c-signal-room-pointer-detail");
            return drawer && drawer.tourRect ? drawer.tourRect(target.slice(7), scroll) : null;
        }
        return tourRect(this.template, `[data-tour="${target}"]`, scroll);
    }
    measureTour(scroll) {
        if (!this.tourOn || this.tourBusy) return;
        this.tourBox = this.findTourBox(scroll);
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
