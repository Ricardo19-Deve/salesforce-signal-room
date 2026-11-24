import { LightningElement, api } from "lwc";
import getRules from "@salesforce/apex/WinRoomController.getRules";
import { money } from "c/winRoomUtils";
import { SECTIONS } from "./guideContent";
import { TOURS } from "c/winRoomTour";

/**
 * In-portal guide: what every page shows, where the data comes from and how each number is calculated.
 * Doubles as the demo script. Opens on the section of the page the user came from.
 */
export default class WinRoomGuide extends LightningElement {
    @api
    get section() {
        return this.current;
    }
    set section(value) {
        if (value && SECTIONS.some((s) => s.id === value)) {
            this.current = value;
        }
    }

    current = "overview";
    rules = [];

    async connectedCallback() {
        try {
            this.rules = await getRules();
        } catch (e) {
            this.rules = [];
        }
    }

    get toc() {
        return SECTIONS.map((s, i) => ({
            id: s.id,
            label: s.title,
            num: String(i + 1).padStart(2, "0"),
            cls: s.id === this.current ? "toc-item toc-item_active" : "toc-item",
            ariaCurrent: s.id === this.current ? "page" : "false"
        }));
    }
    get sectionData() {
        const index = SECTIONS.findIndex((s) => s.id === this.current);
        const base = SECTIONS[index];
        const tour = base.view ? (TOURS[base.view] || []).filter((t) => t.target !== "guide") : [];
        // Pages also get the tour steps as a "block by block" reference, so the guide and the tour say the same.
        const s = tour.length
            ? {
                  ...base,
                  blocks: [
                      ...base.blocks,
                      { h: "Block by block" },
                      { table: { head: ["Block", "What it shows and how it is calculated", "Data"], rows: tour.map((t) => [t.title, t.body, t.data || "–"]) } }
                  ]
              }
            : base;
        return {
            ...s,
            num: String(index + 1).padStart(2, "0"),
            blocks: s.blocks.map((b, i) => ({
                ...b,
                key: `${s.id}-${i}`,
                isH: !!b.h,
                isP: !!b.p,
                isNote: !!b.note,
                isFormula: !!b.formula,
                isList: !!b.list,
                isSteps: !!b.steps,
                isTable: !!b.table,
                items: (b.list || b.steps || []).map((text, j) => ({ key: `${s.id}-${i}-${j}`, text, num: j + 1 })),
                head: b.table ? b.table.head.map((h, j) => ({ key: `h${j}`, text: h })) : [],
                rows: b.table
                    ? b.table.rows.map((r, j) => ({
                          key: `r${j}`,
                          cells: r.map((c, k) => ({ key: `c${k}`, text: c, cls: k === 0 ? "cell-first" : "" }))
                      }))
                    : []
            })),
            hasView: !!s.view,
            prev: index > 0 ? SECTIONS[index - 1] : null,
            next: index < SECTIONS.length - 1 ? SECTIONS[index + 1] : null
        };
    }
    get showRules() {
        return !!this.sectionData.rules && this.rules.length > 0;
    }
    get ruleRows() {
        const pctText = (v) => (v === null || v === undefined ? "–" : `${v}%`);
        const months = (v) => (v === null || v === undefined ? "–" : `${v} m`);
        return this.rules.map((r) => ({
            id: r.Id,
            name: r.Name,
            type: r.Rule_Type__c,
            category: r.Category__c,
            threshold: pctText(r.Threshold_Pct__c),
            minValue: r.Min_Value__c ? money(r.Min_Value__c) : "–",
            lookback: months(r.Lookback_Months__c),
            recent: months(r.Recent_Months__c),
            weight: r.Weight__c ?? "–",
            active: r.Active__c ? "Yes" : "No",
            description: r.Description__c
        }));
    }

    select(e) {
        this.current = e.currentTarget.dataset.id;
        this.scrollTop();
    }
    goPrev() {
        this.current = this.sectionData.prev.id;
        this.scrollTop();
    }
    goNext() {
        this.current = this.sectionData.next.id;
        this.scrollTop();
    }
    openPage() {
        this.dispatchEvent(new CustomEvent("navigate", { detail: { view: this.sectionData.view } }));
    }
    scrollTop() {
        // Only scroll back when the top of the section is out of view.
        const el = this.template.querySelector(".content");
        if (el && el.getBoundingClientRect().top < 0) el.scrollIntoView({ block: "start", behavior: "smooth" });
    }
}
