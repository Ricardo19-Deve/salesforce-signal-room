import { LightningElement, api } from "lwc";

/** Segmented toggle (e.g. All / Mine). Fires `change` with detail { value }. */
export default class SignalRoomSegmented extends LightningElement {
    @api options = [];
    @api value;
    @api label;

    get items() {
        return (this.options || []).map((o) => ({
            ...o,
            cls: `seg${o.value === this.value ? " seg_on" : ""}`,
            pressed: o.value === this.value ? "true" : "false"
        }));
    }
    pick(event) {
        const value = event.currentTarget.dataset.value;
        if (value !== this.value) {
            this.dispatchEvent(new CustomEvent("change", { detail: { value } }));
        }
    }
}
