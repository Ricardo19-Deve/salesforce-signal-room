import { LightningElement, api } from "lwc";

/**
 * Compact dropdown used across the Win Room portal instead of lightning-combobox.
 *
 *   <c-win-room-select label="Status" value={status} options={statusOptions} onchange={handle}></c-win-room-select>
 *
 * variant="filter" (default) renders a pill-shaped trigger "Label: Value";
 * variant="field" renders a stacked form field (label above, full width).
 * Fires `change` with detail { value }.
 */
export default class WinRoomSelect extends LightningElement {
    @api label;
    @api options = [];
    @api value = "";
    @api placeholder = "Select…";
    @api variant = "filter";
    @api searchable = false;
    @api required = false;
    @api disabled = false;

    open = false;
    term = "";
    activeIndex = -1;
    _outside;

    get isField() {
        return this.variant === "field";
    }
    get wrapperClass() {
        return `sel sel_${this.variant}${this.open ? " sel_open" : ""}`;
    }
    get selected() {
        return (this.options || []).find((o) => o.value === this.value);
    }
    get displayValue() {
        const s = this.selected;
        return s ? s.label : this.placeholder;
    }
    get triggerClass() {
        const empty = !this.selected || this.selected.value === "";
        return `trigger${empty ? " trigger_empty" : ""}`;
    }
    get showSearch() {
        return this.searchable || (this.options || []).length > 8;
    }
    get items() {
        const t = this.term.trim().toLowerCase();
        return (this.options || [])
            .filter((o) => !t || String(o.label).toLowerCase().includes(t))
            .map((o, i) => ({
                ...o,
                key: `${o.value}-${i}`,
                selected: o.value === this.value,
                cls: `item${o.value === this.value ? " item_selected" : ""}${i === this.activeIndex ? " item_active" : ""}`
            }));
    }
    get noResults() {
        return this.items.length === 0;
    }

    toggle() {
        if (this.disabled) return;
        if (this.open) {
            this.close();
        } else {
            this.open = true;
            this.term = "";
            this.activeIndex = (this.options || []).findIndex((o) => o.value === this.value);
            this._outside = (e) => {
                if (!e.composedPath().includes(this.template.host)) this.close();
            };
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => window.addEventListener("click", this._outside), 0);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => {
                const search = this.template.querySelector(".search");
                if (search) search.focus();
            }, 30);
        }
    }
    close() {
        this.open = false;
        if (this._outside) window.removeEventListener("click", this._outside);
        this._outside = null;
    }
    disconnectedCallback() {
        this.close();
    }
    pick(event) {
        this.choose(event.currentTarget.dataset.value);
    }
    choose(value) {
        this.close();
        if (value !== this.value) {
            this.dispatchEvent(new CustomEvent("change", { detail: { value } }));
        }
    }
    handleSearch(event) {
        this.term = event.target.value;
        this.activeIndex = 0;
    }
    handleKey(event) {
        const items = this.items;
        if (event.key === "Escape") {
            this.close();
        } else if (event.key === "ArrowDown") {
            event.preventDefault();
            if (!this.open) this.toggle();
            this.activeIndex = Math.min(items.length - 1, this.activeIndex + 1);
        } else if (event.key === "ArrowUp") {
            event.preventDefault();
            this.activeIndex = Math.max(0, this.activeIndex - 1);
        } else if (event.key === "Enter" && this.open && items[this.activeIndex]) {
            event.preventDefault();
            this.choose(items[this.activeIndex].value);
        }
    }
}
