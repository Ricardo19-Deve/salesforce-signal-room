import { LightningElement, api } from "lwc";
import { SERIES_COLORS, money } from "c/winRoomUtils";

const PAD = { left: 56, right: 14, top: 12, bottom: 26 };

/** Axis maximum = 4 round ticks (1, 2 or 5 x a power of ten) that cover the data. */
function niceMax(v) {
    if (v <= 0) return 4;
    const raw = v / 4;
    const p = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / p;
    const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return Math.max(4, step * p * 4);
}

/**
 * Small multi-series line chart (max 4 series, fixed colour order), with legend,
 * crosshair tooltip and a table view for accessibility.
 */
export default class WinRoomLineChart extends LightningElement {
    @api months = [];
    @api series = [];
    @api unit = "money"; // money | units
    @api heading;
    @api wide = false; // wider aspect ratio for full-width cards (keeps the text size constant)
    hoverIndex = null;
    showTable = false;

    /** Index of the first month with data: leading empty months (shorter history) are not drawn. */
    get first() {
        const n = (this.months || []).length;
        for (let i = 0; i < n; i++) {
            if ((this.series || []).some((x) => Number((x.values || [])[i]) > 0)) return i;
        }
        return 0;
    }
    get m() {
        return (this.months || []).slice(this.first);
    }
    get s() {
        const f = this.first;
        return (this.series || []).map((x) => ({ ...x, values: (x.values || []).slice(f) }));
    }

    get w() {
        return this.wide ? 1100 : 680;
    }
    get h() {
        return this.wide ? 260 : 220;
    }
    get viewBox() {
        return `0 0 ${this.w} ${this.h}`;
    }
    get hasData() {
        return (this.s || []).length > 0 && (this.m || []).length > 0;
    }
    get plotWidth() {
        return this.w - PAD.left - PAD.right;
    }
    get plotHeight() {
        return this.h - PAD.top - PAD.bottom;
    }
    get maxValue() {
        let m = 0;
        (this.s || []).forEach((s) => (s.values || []).forEach((v) => (m = Math.max(m, Number(v) || 0))));
        return niceMax(m);
    }
    x(i) {
        const n = Math.max(1, this.m.length - 1);
        return PAD.left + (this.plotWidth * i) / n;
    }
    y(v) {
        return PAD.top + this.plotHeight - (this.plotHeight * (Number(v) || 0)) / this.maxValue;
    }
    fmt(v) {
        return this.unit === "money" ? money(v) : `${Math.round(Number(v) || 0)}`;
    }
    get lines() {
        return (this.s || []).slice(0, 4).map((s, idx) => {
            const pts = (s.values || []).map((v, i) => `${i === 0 ? "M" : "L"}${this.x(i).toFixed(1)},${this.y(v).toFixed(1)}`);
            const color = SERIES_COLORS[idx];
            const hv = this.hoverIndex !== null ? (s.values || [])[this.hoverIndex] : null;
            return {
                key: `${idx}-${s.label}`,
                label: s.label,
                path: pts.join(" "),
                color,
                swatch: `background:${color}`,
                dotX: this.hoverIndex !== null ? this.x(this.hoverIndex) : 0,
                dotY: this.hoverIndex !== null ? this.y(hv) : 0,
                hoverValue: hv !== null && hv !== undefined ? this.fmt(hv) : ""
            };
        });
    }
    get gridLines() {
        const out = [];
        for (let i = 0; i <= 4; i++) {
            const v = (this.maxValue * i) / 4;
            const yy = this.y(v);
            out.push({ key: `g${i}`, y: yy, x1: PAD.left, x2: this.w - PAD.right, label: this.fmt(v), ly: yy + 3, lx: PAD.left - 6 });
        }
        return out;
    }
    get xLabels() {
        const out = [];
        (this.m || []).forEach((m, i) => {
            if (i % 3 === 0 || i === this.m.length - 1) {
                out.push({ key: `x${i}`, label: m, x: this.x(i), y: this.h - 8 });
            }
        });
        return out;
    }
    get hitAreas() {
        const n = this.m.length;
        const w = this.plotWidth / Math.max(1, n - 1);
        return (this.m || []).map((m, i) => ({
            key: `h${i}`,
            index: i,
            x: this.x(i) - w / 2,
            w,
            y: PAD.top,
            h: this.plotHeight
        }));
    }
    get hovering() {
        return this.hoverIndex !== null;
    }
    get crossX() {
        return this.hovering ? this.x(this.hoverIndex) : 0;
    }
    get crossY1() {
        return PAD.top;
    }
    get crossY2() {
        return PAD.top + this.plotHeight;
    }
    get tooltipMonth() {
        return this.hovering ? this.m[this.hoverIndex] : "";
    }
    get tooltipStyle() {
        if (!this.hovering) return "display:none";
        const leftPct = (this.x(this.hoverIndex) / this.w) * 100;
        return leftPct > 60 ? `right:${100 - leftPct + 2}%` : `left:${leftPct + 2}%`;
    }
    get tableRows() {
        return (this.m || []).map((m, i) => ({
            key: `r${i}`,
            month: m,
            cells: (this.s || []).slice(0, 4).map((s, j) => ({ key: `c${i}-${j}`, value: this.fmt((s.values || [])[i]) }))
        }));
    }
    get toggleLabel() {
        return this.showTable ? "Chart" : "Table";
    }

    handleEnter(event) {
        this.hoverIndex = Number(event.currentTarget.dataset.index);
    }
    handleLeave() {
        this.hoverIndex = null;
    }
    toggleTable() {
        this.showTable = !this.showTable;
    }
}
