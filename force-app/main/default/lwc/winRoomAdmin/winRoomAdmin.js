import { LightningElement } from "lwc";
import LightningConfirm from "lightning/confirm";
import getRules from "@salesforce/apex/WinRoomController.getRules";
import saveRule from "@salesforce/apex/WinRoomController.saveRule";
import resetRules from "@salesforce/apex/WinRoomController.resetRules";
import runEngine from "@salesforce/apex/WinRoomController.runEngine";
import getRuns from "@salesforce/apex/WinRoomController.getRuns";
import getDataStats from "@salesforce/apex/WinRoomController.getDataStats";
import getProfiles from "@salesforce/apex/WinRoomController.getProfiles";
import updateProfile from "@salesforce/apex/WinRoomController.updateProfile";
import getProductLines from "@salesforce/apex/WinRoomController.getProductLines";
import generateMockData from "@salesforce/apex/WinRoomController.generateMockData";
import purgeMockData from "@salesforce/apex/WinRoomController.purgeMockData";
import getJobStatus from "@salesforce/apex/WinRoomController.getJobStatus";
import { money, statusClass, reduceErrors } from "c/winRoomUtils";

const RULE_HELP = {
    WINBACK_SOFT: "Recent window vs. same window last year. Threshold = min. drop; Recent = window months.",
    WINBACK_HARD: "No units in the Recent months; previous Lookback months must reach Min value.",
    ATTACH: "Target/anchor units below Expected ratio x (1 - Threshold). Prior-year ratio decides win back vs cross-sell.",
    CAPITAL_PULLTHROUGH: "Anchor capital line used, target workflow not. Expected ratio = robotic share of hip cases.",
    PEER_WHITESPACE: "Line bought by at least Threshold % of hospitals in the same segment, never by this one.",
    SURGEON_SITE: "Surgeon uses Contoso elsewhere, operates here without Contoso. Threshold = share of cases winnable.",
    NEW_SURGEON: "Affiliation started in the last Recent months, no Contoso cases. Threshold = share of cases winnable.",
    TENDER_RADAR: "Open tender with deadline within Lookback months. Threshold = win probability.",
    SHARE_OF_WALLET: "Contoso revenue / estimated market below Threshold. Expected ratio = target share."
};
const POLL_MS = 3000;

export default class WinRoomAdmin extends LightningElement {
    rules = [];
    runs = [];
    stats;
    profiles = [];
    lines = [];
    error;
    message;
    editing;
    busy = false;
    assignToMe = true;
    runAfter = true;
    jobId;
    job;
    tab = "rules";

    connectedCallback() {
        this.refreshAll();
    }
    disconnectedCallback() {
        window.clearTimeout(this._poll);
    }

    async refreshAll() {
        try {
            const [rules, runs, stats, profiles, lines] = await Promise.all([
                getRules(), getRuns(), getDataStats(), getProfiles(), getProductLines()
            ]);
            this.rules = rules;
            this.runs = runs;
            this.stats = stats;
            this.profiles = profiles;
            this.lines = lines;
            this.error = undefined;
            if (runs.length && runs[0].Status__c === "Running") this.schedulePoll();
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    schedulePoll() {
        window.clearTimeout(this._poll);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._poll = window.setTimeout(() => this.poll(), POLL_MS);
    }

    async poll() {
        try {
            if (this.jobId) {
                this.job = await getJobStatus({ jobId: this.jobId });
                if (["Completed", "Failed", "Aborted"].includes(this.job.status)) {
                    this.jobId = undefined;
                }
            }
            this.runs = await getRuns();
            this.stats = await getDataStats();
            const running = this.runs.length && this.runs[0].Status__c === "Running";
            if (this.jobId || running) {
                this.schedulePoll();
            } else {
                this.profiles = await getProfiles();
                this.dispatchEvent(new CustomEvent("datachanged"));
            }
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    // ---------------------------------------------------------------- view model
    get tabs() {
        return [
            ["rules", "Rules"], ["runs", "Engine runs"], ["data", "Data"], ["lines", "Product lines"]
        ].map(([key, label]) => ({
            key, label, selected: key === this.tab ? "true" : "false",
            cls: `wr-tab${key === this.tab ? " wr-tab_active" : ""}`
        }));
    }
    get tab_rules() {
        return this.tab === "rules";
    }
    get tab_runs() {
        return this.tab === "runs";
    }
    get tab_data() {
        return this.tab === "data";
    }
    get tab_lines() {
        return this.tab === "lines";
    }
    selectTab(e) {
        this.tab = e.currentTarget.dataset.tab;
    }
    get ruleRows() {
        return this.rules.map((r) => ({
            ...r,
            help: RULE_HELP[r.Rule_Type__c] || "",
            lookbackText: `${r.Lookback_Months__c || "–"} / ${r.Recent_Months__c || "–"}`,
            thresholdText: r.Threshold_Pct__c !== undefined && r.Threshold_Pct__c !== null ? `${r.Threshold_Pct__c}%` : "–",
            minText: money(r.Min_Value__c),
            lines: [r.Anchor_Lines__c, r.Target_Lines__c].filter((x) => x).join(" → "),
            activeIcon: r.Active__c ? "utility:check" : "utility:dash"
        }));
    }
    get statTiles() {
        if (!this.stats) return [];
        const s = this.stats;
        return [
            ["Account profiles", `${s.profiles}`, `${s.inScope} in scope`],
            ["Sales rows", `${s.sales}`, "monthly sell-in"],
            ["Surgeons", `${s.surgeons}`, `${s.affiliations} affiliations`],
            ["Tenders", `${s.tenders}`, ""],
            ["Pointers", `${s.pointers}`, `${s.convertedOpportunities} converted`],
            ["Win rooms", `${s.sessions}`, `${s.commitments} commitments`],
            ["Rules", `${s.rules}`, `${s.productLines} product lines`]
        ].map(([label, value, hint]) => ({ key: label, label, value, hint }));
    }
    get runRows() {
        return this.runs.map((r) => ({
            ...r,
            cls: statusClass(r.Status__c === "Running" ? "Open" : r.Status__c === "Failed" ? "Blocked" : "Done"),
            started: r.Started__c ? new Date(r.Started__c).toLocaleString() : "",
            duration: r.Finished__c && r.Started__c ? `${Math.round((new Date(r.Finished__c) - new Date(r.Started__c)) / 1000)}s` : ""
        }));
    }
    get profileRows() {
        return this.profiles.map((p) => ({ ...p, repName: p.Rep__r ? p.Rep__r.Name : "" }));
    }
    get phaseOptions() {
        return ["Phase 1", "Phase 2", "Phase 3", "Peer only"].map((p) => ({ label: p, value: p }));
    }
    get lineRows() {
        return this.lines.map((l) => ({ ...l, price: money(l.Avg_Price__c) }));
    }
    get jobText() {
        if (!this.job) return "";
        return `Background job: ${this.job.status} (${this.job.processed || 0}/${this.job.total || 0} batches)${this.job.errors ? " - " + this.job.errors + " errors" : ""}`;
    }
    get ruleTypeOptions() {
        return Object.keys(RULE_HELP).map((k) => ({ label: k, value: k }));
    }
    get categoryOptions() {
        return ["Win back", "Cross-sell", "Surgeons & site expansion", "New accounts & tenders"].map((c) => ({ label: c, value: c }));
    }
    get editHelp() {
        return this.editing ? RULE_HELP[this.editing.Rule_Type__c] : "";
    }

    // ---------------------------------------------------------------- rules
    editRule(e) {
        const r = this.rules.find((x) => x.Id === e.currentTarget.dataset.id);
        this.editing = { ...r };
    }
    cancelEdit() {
        this.editing = undefined;
    }
    handleRuleField(e) {
        const f = e.target.dataset.field;
        let v = e.target.type === "toggle" || e.target.type === "checkbox" ? e.target.checked : e.detail.value !== undefined ? e.detail.value : e.target.value;
        if (["Weight__c", "Threshold_Pct__c", "Min_Value__c", "Lookback_Months__c", "Recent_Months__c", "Expected_Ratio__c"].includes(f)) {
            v = v === "" || v === null ? null : Number(v);
        }
        this.editing = { ...this.editing, [f]: v };
    }
    async saveEditing() {
        this.busy = true;
        try {
            const rule = { ...this.editing };
            delete rule.attributes;
            await saveRule({ rule: { sobjectType: "WR_Rule__c", ...rule } });
            this.editing = undefined;
            this.rules = await getRules();
            this.message = "Rule saved. Run the engine to apply it.";
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    async toggleRule(e) {
        const r = this.rules.find((x) => x.Id === e.currentTarget.dataset.id);
        try {
            await saveRule({ rule: { sobjectType: "WR_Rule__c", Id: r.Id, Active__c: !r.Active__c } });
            this.rules = await getRules();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    async doResetRules() {
        const ok = await LightningConfirm.open({ message: "Reset all rules to the default thresholds?", label: "Reset rules" });
        if (!ok) return;
        try {
            await resetRules();
            this.rules = await getRules();
            this.message = "Rules reset to defaults.";
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    // ---------------------------------------------------------------- engine & data
    async doRun() {
        this.busy = true;
        try {
            await runEngine();
            this.message = "Engine started. Pointers will appear when the run completes.";
            this.runs = await getRuns();
            this.schedulePoll();
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    handleAssign(e) {
        this.assignToMe = e.target.checked;
    }
    handleRunAfter(e) {
        this.runAfter = e.target.checked;
    }
    async doGenerate() {
        this.busy = true;
        try {
            this.jobId = await generateMockData({ assignToMe: this.assignToMe, runEngine: this.runAfter });
            this.message = "Demo data generation started (rules, product lines, profiles, surgeons, tenders, 24 months of sales).";
            this.schedulePoll();
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    async doPurge() {
        const ok = await LightningConfirm.open({
            message: "Delete all Win Room demo data (profiles, sales, surgeons, tenders, pointers, win rooms, runs)? Opportunities created from pointers are kept.",
            label: "Purge demo data",
            variant: "header",
            theme: "error"
        });
        if (!ok) return;
        this.busy = true;
        try {
            this.jobId = await purgeMockData();
            this.message = "Purge started.";
            this.schedulePoll();
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    async toggleScope(e) {
        const p = this.profiles.find((x) => x.Id === e.target.dataset.id);
        try {
            await updateProfile({ profileId: p.Id, inScope: e.target.checked, phase: null });
            this.profiles = await getProfiles();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    async changePhase(e) {
        const p = this.profiles.find((x) => x.Id === e.target.dataset.id);
        try {
            await updateProfile({ profileId: p.Id, inScope: p.In_Scope__c, phase: e.detail.value });
            this.profiles = await getProfiles();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    dismissMessage() {
        this.message = undefined;
    }
}
