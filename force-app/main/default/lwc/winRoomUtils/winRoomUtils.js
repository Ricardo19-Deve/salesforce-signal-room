/** Shared helpers for the Win Room portal. */

export const CATEGORIES = ["Win back", "Cross-sell", "Surgeons & site expansion", "New accounts & tenders"];

export const CATEGORY_META = {
    "Win back": { icon: "utility:undo", hint: "Soft / hard churn and partial switches" },
    "Cross-sell": { icon: "utility:add", hint: "Pull-through, attach and peer white space" },
    "Surgeons & site expansion": { icon: "utility:user", hint: "Surgeons using Contoso elsewhere, new surgeons" },
    "New accounts & tenders": { icon: "utility:new_window", hint: "Tender radar, greenfield, share of wallet" }
};

/** Categorical series colours (validated palette, fixed order - never cycled). */
export const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"];

export const REJECTION_REASONS = [
    "Already in progress",
    "Customer not interested",
    "Contract or tender lock-in",
    "Clinical preference",
    "Data incorrect",
    "Other"
];

export function money(value) {
    const v = Number(value || 0);
    if (v < 0) return `-${money(-v)}`;
    const abs = Math.abs(v);
    if (abs >= 1000000) return `€${(v / 1000000).toFixed(2)}M`;
    if (abs >= 1000) return `€${(v / 1000).toFixed(abs >= 100000 ? 0 : 1)}k`;
    return `€${Math.round(v)}`;
}

export function pct(ratio, digits = 0) {
    if (ratio === null || ratio === undefined || isNaN(ratio)) return "–";
    return `${(Number(ratio) * 100).toFixed(digits)}%`;
}

export function formatDate(value) {
    if (!value) return "";
    const d = new Date(value.length === 10 ? `${value}T12:00:00` : value);
    return d.toLocaleDateString(undefined, { day: "2-digit", month: "short", year: "numeric" });
}

export function daysUntil(value) {
    if (!value) return null;
    const d = new Date(`${String(value).substring(0, 10)}T12:00:00`);
    const today = new Date();
    today.setHours(12, 0, 0, 0);
    return Math.round((d - today) / 86400000);
}

export function todayIso(offsetDays = 0) {
    const d = new Date();
    d.setDate(d.getDate() + offsetDays);
    return d.toISOString().substring(0, 10);
}

export function priorityClass(priority) {
    return `wr-pill wr-pill_${(priority || "none").toLowerCase()}`;
}

export function statusClass(status) {
    return `wr-status wr-status_${(status || "none").toLowerCase()}`;
}

export function reduceErrors(error) {
    if (!error) return "Unknown error";
    if (Array.isArray(error)) return error.map(reduceErrors).join(", ");
    if (error.body) {
        if (Array.isArray(error.body)) return error.body.map((e) => e.message).join(", ");
        if (error.body.pageErrors && error.body.pageErrors.length) return error.body.pageErrors.map((e) => e.message).join(", ");
        if (error.body.fieldErrors) {
            const msgs = Object.values(error.body.fieldErrors).flat().map((e) => e.message);
            if (msgs.length) return msgs.join(", ");
        }
        if (error.body.message) return error.body.message;
    }
    return error.message || String(error);
}

/** Adds display fields to a pointer row coming from WinRoomController. */
export function decoratePointer(p) {
    const due = daysUntil(p.dueDate);
    return {
        ...p,
        valueText: money(p.value),
        priorityClass: priorityClass(p.priority),
        statusClass: statusClass(p.status),
        dueText: p.dueDate ? formatDate(p.dueDate) : "",
        dueClass: due !== null && due < 0 && (p.status === "New" || p.status === "Accepted") ? "wr-overdue" : "",
        dueCellClass: `nowrap${due !== null && due < 0 && (p.status === "New" || p.status === "Accepted") ? " wr-overdue" : ""}`,
        subject: p.productLine || p.surgeon || p.tender || "",
        scoreStyle: `width:${Math.max(4, Math.min(100, p.score || 0))}%`
    };
}
