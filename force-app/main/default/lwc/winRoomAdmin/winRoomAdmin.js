import { LightningElement, api } from "lwc";
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
import deleteRule from "@salesforce/apex/WinRoomController.deleteRule";
import createDemoTeam from "@salesforce/apex/WinRoomController.createDemoTeam";
import getContext from "@salesforce/apex/WinRoomController.getContext";
import { money, statusClass, reduceErrors, tourRect } from "c/winRoomUtils";

const MONEY = "Minimum value at stake (EUR / yr)";
/** What each rule type does and which generic parameters it reads (with their meaning for that type). */
const RULE_TYPES = {
    WINBACK_SOFT: {
        label: "Win-back soft (volume decline)", category: "Win back",
        help: "Revenue of a product line in the recent window dropped at least the threshold vs the same window a year earlier. Value = the gap, annualised.",
        fields: { Threshold_Pct__c: "Minimum drop (%)", Min_Value__c: MONEY, Lookback_Months__c: "History used (months)", Recent_Months__c: "Recent window (months)" }
    },
    WINBACK_HARD: {
        label: "Win-back hard (line stopped)", category: "Win back",
        help: "No units in the recent window for a line that sold at least the minimum value in the lookback before. Value = the lost 12-month revenue.",
        fields: { Min_Value__c: "Minimum revenue before the stop (EUR)", Lookback_Months__c: "Lookback before the stop (months)", Recent_Months__c: "Months without orders" }
    },
    ATTACH: {
        label: "Attach / partial switch", category: "Cross-sell",
        help: "Target units per anchor unit are below the expected ratio minus the tolerance. If the account used to buy at the ratio it is a partial switch (win back), otherwise a cross-sell gap.",
        fields: { Expected_Ratio__c: "Expected target units per anchor unit", Threshold_Pct__c: "Tolerance below the ratio (%)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)" },
        lines: { Anchor_Lines__c: "Anchor product lines", Target_Lines__c: "Target product lines" }
    },
    CAPITAL_PULLTHROUGH: {
        label: "Capital pull-through", category: "Cross-sell",
        help: "The account uses the anchor capital line but not the target workflow, although it has the procedure volume.",
        fields: { Expected_Ratio__c: "Share of procedures expected on the workflow (0-1)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)" },
        lines: { Anchor_Lines__c: "Capital line in use", Target_Lines__c: "Workflow line expected" }
    },
    PEER_WHITESPACE: {
        label: "Peer white space", category: "Cross-sell",
        help: "At least the threshold % of hospitals in the same segment (minimum 4 peers) buy a line this account does not.",
        fields: { Threshold_Pct__c: "Share of peers that buy the line (%)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)" }
    },
    SURGEON_SITE: {
        label: "Surgeon site expansion", category: "Surgeons & site expansion",
        help: "A surgeon who buys from us at another hospital also operates here, with no usage at this site.",
        fields: { Threshold_Pct__c: "Share of the surgeon's cases we can win (%)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)" }
    },
    NEW_SURGEON: {
        label: "New surgeon", category: "Surgeons & site expansion",
        help: "A surgeon joined the hospital in the recent window and has no cases with us yet.",
        fields: { Threshold_Pct__c: "Share of cases we can win (%)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)", Recent_Months__c: "Joined within (months)" }
    },
    TENDER_RADAR: {
        label: "Tender radar", category: "New accounts & tenders",
        help: "An open tender linked to the account closes within the lookback. Value = estimated value x win probability.",
        fields: { Threshold_Pct__c: "Win probability (%)", Min_Value__c: MONEY, Lookback_Months__c: "Deadline within (months)" }
    },
    SHARE_OF_WALLET: {
        label: "Share of wallet", category: "New accounts & tenders",
        help: "Our 12-month revenue / estimated market (procedures x basket) is below the threshold. Value = target share x market - our revenue.",
        fields: { Threshold_Pct__c: "Flag below this share (%)", Expected_Ratio__c: "Target share (0-1)", Min_Value__c: MONEY, Lookback_Months__c: "Window (months)" }
    },
    CONTRACT_COMPLIANCE: {
        label: "Contract compliance", category: "Win back",
        help: "A contract line is under or over its commitment to date and over the run-rate window. Shortfall = win back, overrun = renegotiate.",
        fields: { Threshold_Pct__c: "Deviation that triggers (%)", Min_Value__c: MONEY, Recent_Months__c: "Run-rate window (months)" }
    },
    CONTRACT_RENEWAL: {
        label: "Contract renewal", category: "New accounts & tenders",
        help: "An active contract ends within the lookback, so the renewal starts before a tender.",
        fields: { Min_Value__c: MONEY, Lookback_Months__c: "Ends within (months)" }
    }
};
const NUMERIC = ["Weight__c", "Threshold_Pct__c", "Min_Value__c", "Lookback_Months__c", "Recent_Months__c", "Expected_Ratio__c"];
const POLL_MS = 3000;

export default class WinRoomAdmin extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

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

    defaultCodes = [];

    connectedCallback() {
        this.refreshAll();
        getContext()
            .then((c) => {
                this.defaultCodes = c.defaultRuleCodes || [];
            })
            .catch(() => {
                this.defaultCodes = [];
            });
    }
    renderedCallback() {
        // Text areas inside the dialog are filled imperatively: the value binding is not applied on first render.
        if (!this.editing) return;
        this.template.querySelectorAll(".modal textarea[data-field]").forEach((t) => {
            const v = this.editing[t.dataset.field] || "";
            if (t !== this.template.activeElement && t.value !== v) t.value = v;
        });
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
            help: (RULE_TYPES[r.Rule_Type__c] || {}).help || "",
            typeLabel: (RULE_TYPES[r.Rule_Type__c] || {}).label || r.Rule_Type__c,
            isCustom: this.defaultCodes.length > 0 && !this.defaultCodes.includes(r.Code__c),
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
        return Object.keys(RULE_TYPES).map((k) => ({ label: RULE_TYPES[k].label, value: k, hint: k }));
    }
    get categoryOptions() {
        return ["Win back", "Cross-sell", "Surgeons & site expansion", "New accounts & tenders"].map((c) => ({ label: c, value: c }));
    }
    get editHelp() {
        return this.editing ? (RULE_TYPES[this.editing.Rule_Type__c] || {}).help : "";
    }
    get isNewRule() {
        return this.editing && !this.editing.Id;
    }
    get modalEyebrow() {
        return this.isNewRule ? "New rule" : "Edit rule";
    }
    get modalTitle() {
        return (this.editing && this.editing.Name) || "Untitled rule";
    }
    get saveLabel() {
        return this.isNewRule ? "Create rule" : "Save rule";
    }
    get saveDisabled() {
        const e = this.editing;
        return this.busy || !e || !e.Name || !e.Code__c || !e.Rule_Type__c || !e.Category__c;
    }
    get canDelete() {
        return this.editing && this.editing.Id && !this.defaultCodes.includes(this.editing.Code__c);
    }
    get paramFields() {
        const t = this.editing && RULE_TYPES[this.editing.Rule_Type__c];
        if (!t) return [];
        return Object.keys(t.fields).map((field) => ({
            field,
            label: t.fields[field],
            value: this.editing[field],
            step: field === "Expected_Ratio__c" ? "0.05" : field === "Min_Value__c" ? "1000" : "1"
        }));
    }
    get lineFields() {
        const t = this.editing && RULE_TYPES[this.editing.Rule_Type__c];
        if (!t || !t.lines) return [];
        return Object.keys(t.lines).map((field) => {
            const selected = (this.editing[field] || "").split(",").map((c) => c.trim()).filter((c) => c);
            return {
                field,
                label: t.lines[field],
                chips: this.lines.map((l) => ({
                    code: l.Code__c,
                    name: l.Name,
                    pressed: selected.includes(l.Code__c) ? "true" : "false",
                    cls: selected.includes(l.Code__c) ? "chip chip_on" : "chip"
                }))
            };
        });
    }

    // ---------------------------------------------------------------- rules
    editRule(e) {
        const r = this.rules.find((x) => x.Id === e.currentTarget.dataset.id);
        this.editing = { ...r };
        this.focusModal();
    }
    newRule() {
        this.editing = {
            Name: "", Code__c: "", Rule_Type__c: "WINBACK_SOFT", Category__c: RULE_TYPES.WINBACK_SOFT.category,
            Active__c: true, Weight__c: 3, Threshold_Pct__c: 25, Min_Value__c: 10000, Lookback_Months__c: 12, Recent_Months__c: 6
        };
        this.focusModal();
    }
    focusModal() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            const input = this.template.querySelector(".modal .rule-name");
            if (input) input.focus();
        });
    }
    handleModalKey(e) {
        if (e.key === "Escape") this.cancelEdit();
    }
    toggleLine(e) {
        const { field, code } = e.currentTarget.dataset;
        const current = (this.editing[field] || "").split(",").map((c) => c.trim()).filter((c) => c);
        const next = current.includes(code) ? current.filter((c) => c !== code) : [...current, code];
        this.editing = { ...this.editing, [field]: next.join(",") };
    }
    async deleteEditing() {
        const ok = await LightningConfirm.open({ message: `Delete the rule "${this.editing.Name}"? Its pointers stay, without a rule.`, label: "Delete rule", theme: "error" });
        if (!ok) return;
        this.busy = true;
        try {
            await deleteRule({ ruleId: this.editing.Id });
            this.editing = undefined;
            this.rules = await getRules();
            this.message = "Rule deleted.";
        } catch (err) {
            this.error = reduceErrors(err);
        } finally {
            this.busy = false;
        }
    }
    async doCreateTeam() {
        this.busy = true;
        try {
            const n = await createDemoTeam();
            this.message = `Demo team ready: ${n} reps report to you. Generate the demo data to spread the accounts across the team.`;
            this.dispatchEvent(new CustomEvent("datachanged"));
        } catch (err) {
            this.error = reduceErrors(err);
        } finally {
            this.busy = false;
        }
    }
    cancelEdit() {
        this.editing = undefined;
    }
    handleRuleField(e) {
        const f = e.target.dataset.field;
        let v = e.target.type === "toggle" || e.target.type === "checkbox" ? e.target.checked : e.detail.value !== undefined ? e.detail.value : e.target.value;
        if (NUMERIC.includes(f)) {
            v = v === "" || v === null ? null : Number(v);
        }
        const next = { ...this.editing, [f]: v };
        if (f === "Rule_Type__c" && RULE_TYPES[v]) {
            next.Category__c = RULE_TYPES[v].category;
        }
        if (f === "Name" && !this.editing.Id) {
            next.Code__c = `CUSTOM_${(v || "").toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "")}`.slice(0, 60);
        }
        this.editing = next;
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
            this.error = undefined;
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
