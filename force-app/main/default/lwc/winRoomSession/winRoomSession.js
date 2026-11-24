import { LightningElement, api } from "lwc";
import getSessions from "@salesforce/apex/WinRoomController.getSessions";
import createSession from "@salesforce/apex/WinRoomController.createSession";
import getAgenda from "@salesforce/apex/WinRoomController.getAgenda";
import saveCommitment from "@salesforce/apex/WinRoomController.saveCommitment";
import updateCommitment from "@salesforce/apex/WinRoomController.updateCommitment";
import completeSession from "@salesforce/apex/WinRoomController.completeSession";
import saveSessionNotes from "@salesforce/apex/WinRoomController.saveSessionNotes";
import sessionBrief from "@salesforce/apex/WinRoomController.sessionBrief";
import searchUsers from "@salesforce/apex/WinRoomController.searchUsers";
import { decoratePointer, money, formatDate, daysUntil, statusClass, todayIso, reduceErrors, tourRect } from "c/winRoomUtils";

const TEAMS = ["GB", "DE", "FR", "ES", "IT", "All"];

export default class WinRoomSession extends LightningElement {
    /** Tour support: scrolls to and measures one block of this page (selector inside the template). */
    @api
    tourRect(selector, scroll) {
        return tourRect(this.template, selector, scroll);
    }

    _country;
    _refreshKey;
    team = "GB";
    sessions = [];
    sessionId;
    agenda;
    brief;
    error;
    loading = false;
    busy = false;
    newDate = todayIso(0);
    notes = "";
    cmtAction = "";
    cmtDue = todayIso(7);
    cmtPointerId = "";
    cmtOwnerId = "";
    ownerResults = [];
    ownerLabel = "";

    @api
    get country() {
        return this._country;
    }
    set country(v) {
        this._country = v;
        if (v && TEAMS.includes(v) && v !== this.team) {
            this.team = v;
            this.sessionId = undefined;
            this.agenda = undefined;
            this.loadSessions();
        }
    }
    @api
    get refreshKey() {
        return this._refreshKey;
    }
    set refreshKey(v) {
        const changed = this._refreshKey !== undefined && v !== this._refreshKey;
        this._refreshKey = v;
        if (changed && this.sessionId) this.loadAgenda();
    }

    connectedCallback() {
        this.loadSessions();
    }

    async loadSessions() {
        try {
            this.sessions = await getSessions({ team: this.team });
            if (!this.sessionId && this.sessions.length) {
                const planned = this.sessions.filter((s) => s.status === "Planned");
                this.sessionId = (planned.length ? planned[planned.length - 1] : this.sessions[0]).id;
                this.loadAgenda();
            }
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }

    async loadAgenda() {
        if (!this.sessionId) return;
        this.loading = true;
        try {
            this.agenda = await getAgenda({ sessionId: this.sessionId });
            this.notes = this.agenda.session.Notes__c || "";
            this.error = undefined;
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------------------------------------------------------------- view model
    get teamOptions() {
        return TEAMS.map((t) => ({ label: t === "All" ? "All teams" : t, value: t }));
    }
    get sessionRows() {
        return this.sessions.map((s) => ({
            ...s,
            cls: s.id === this.sessionId ? "sess sess_active" : "sess",
            dateText: formatDate(s.date),
            statusCls: statusClass(s.status)
        }));
    }
    get hasAgenda() {
        return !!this.agenda;
    }
    get session() {
        return this.agenda.session;
    }
    get isPlanned() {
        return this.agenda && this.agenda.session.Status__c === "Planned";
    }
    get sinceText() {
        return formatDate(this.agenda.since);
    }
    get kpis() {
        const k = this.agenda.kpi || {};
        const g = (s) => k[s] || { count: 0, value: 0 };
        return [
            { key: "new", label: "New pointers", value: `${g("New").count}`, hint: money(g("New").value) },
            { key: "acc", label: "Accepted", value: `${g("Accepted").count}`, hint: money(g("Accepted").value) },
            { key: "conv", label: "Converted", value: `${g("Converted").count}`, hint: money(g("Converted").value) },
            { key: "won", label: "Won since last win room", value: money(this.agenda.q1WonValue), hint: `${this.agenda.q1Won} won · ${this.agenda.q1Lost} lost` }
        ];
    }
    decorate(list) {
        return (list || []).map(decoratePointer);
    }
    get q1() {
        return this.decorate(this.agenda.q1Results);
    }
    get q2() {
        return this.decorate(this.agenda.q2New);
    }
    get q3() {
        return this.decorate(this.agenda.q3AcceptedNoAction);
    }
    get q5() {
        return this.decorate(this.agenda.q5Stuck);
    }
    commitmentRows(list) {
        return (list || []).map((c) => {
            const d = daysUntil(c.Due_Date__c);
            return {
                ...c,
                due: formatDate(c.Due_Date__c),
                dueCls: d !== null && d < 0 && c.Status__c === "Open" ? "nowrap wr-overdue" : "nowrap",
                cls: statusClass(c.Status__c),
                ownerName: c.Owner_User__r ? c.Owner_User__r.Name : "",
                accountName: c.Account__r ? c.Account__r.Name : "",
                pointerTitle: c.Pointer__r ? c.Pointer__r.Title__c : "",
                isOpen: c.Status__c !== "Done"
            };
        });
    }
    get q4() {
        return this.commitmentRows(this.agenda.q4Overdue);
    }
    get q6() {
        return (this.agenda.q6Tenders || []).map((t) => ({
            ...t,
            accountName: t.Account__r ? t.Account__r.Name : "",
            deadline: formatDate(t.Deadline__c),
            left: `${daysUntil(t.Deadline__c)} days`,
            value: money(t.Estimated_Value__c)
        }));
    }
    get q7() {
        return this.commitmentRows(this.agenda.q7Commitments);
    }
    get noQ1() {
        return this.q1.length === 0;
    }
    get noQ2() {
        return this.q2.length === 0;
    }
    get noQ3() {
        return this.q3.length === 0;
    }
    get noQ4() {
        return this.q4.length === 0;
    }
    get noQ5() {
        return this.q5.length === 0;
    }
    get noQ6() {
        return this.q6.length === 0;
    }
    get noQ7() {
        return this.q7.length === 0;
    }
    get questions() {
        if (!this.agenda) return [];
        return [
            { n: 1, title: "What did we win or lose since the last win room?", count: this.q1.length },
            { n: 2, title: "Which new pointers landed - who owns them?", count: this.q2.length },
            { n: 3, title: "Which accepted pointers have no opportunity or action yet?", count: this.q3.length },
            { n: 4, title: "Which commitments are overdue or blocked?", count: this.q4.length },
            { n: 5, title: "Where are opportunities stuck (no stage change in 21 days)?", count: this.q5.length },
            { n: 6, title: "Which tenders close in the next 30 days?", count: this.q6.length },
            { n: 7, title: "What do we commit to for next week?", count: this.q7.length }
        ];
    }
    get pointerOptions() {
        const all = [...this.q3, ...this.q2, ...this.q5];
        const seen = new Set();
        return [{ label: "(no pointer)", value: "" }].concat(
            all
                .filter((p) => !seen.has(p.id) && seen.add(p.id))
                .map((p) => ({ label: `${p.accountName} - ${p.title}`, value: p.id }))
        );
    }
    get hasOwnerResults() {
        return this.ownerResults.length > 0;
    }
    get briefLists() {
        if (!this.brief) return [];
        return [
            ["highlights", "Highlights"],
            ["focusAccounts", "Focus accounts"],
            ["decisionsNeeded", "Decisions needed"],
            ["challengeQuestions", "Challenger questions"]
        ]
            .filter(([k]) => Array.isArray(this.brief[k]) && this.brief[k].length)
            .map(([k, label]) => ({ key: k, label, items: this.brief[k].map((t, i) => ({ key: `${k}${i}`, text: t })) }));
    }
    get briefNote() {
        return this.brief && this.brief.aiGenerated ? "AI generated briefing" : "Rule-based briefing (AI not configured or unavailable)";
    }

    // ---------------------------------------------------------------- actions
    handleTeam(e) {
        this.team = e.detail.value;
        this.sessionId = undefined;
        this.agenda = undefined;
        this.brief = undefined;
        this.loadSessions();
    }
    selectSession(e) {
        this.sessionId = e.currentTarget.dataset.id;
        this.brief = undefined;
        this.loadAgenda();
    }
    handleNewDate(e) {
        this.newDate = e.target.value;
    }
    async newSession() {
        try {
            this.sessionId = await createSession({ team: this.team, sessionDate: this.newDate });
            await this.loadSessions();
            await this.loadAgenda();
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }
    openPointer(e) {
        this.dispatchEvent(new CustomEvent("openpointer", { detail: { pointerId: e.currentTarget.dataset.id } }));
    }
    openAccount(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent("openaccount", { detail: { accountId: e.currentTarget.dataset.id } }));
    }
    handleCmt(e) {
        this[e.target.dataset.field] = e.detail.value !== undefined ? e.detail.value : e.target.value;
    }
    async handleOwnerSearch(e) {
        const term = e.target.value;
        this.ownerLabel = term;
        if (!term || term.length < 2) {
            this.ownerResults = [];
            return;
        }
        try {
            this.ownerResults = await searchUsers({ term });
        } catch (err) {
            this.ownerResults = [];
        }
    }
    pickOwner(e) {
        this.cmtOwnerId = e.currentTarget.dataset.id;
        this.ownerLabel = e.currentTarget.dataset.name;
        this.ownerResults = [];
    }
    async addCommitment() {
        if (!this.cmtAction.trim()) return;
        this.busy = true;
        try {
            await saveCommitment({
                commitmentJson: JSON.stringify({
                    sessionId: this.sessionId,
                    pointerId: this.cmtPointerId,
                    ownerId: this.cmtOwnerId,
                    action: this.cmtAction,
                    dueDate: this.cmtDue
                })
            });
            this.cmtAction = "";
            this.cmtPointerId = "";
            this.cmtOwnerId = "";
            this.ownerLabel = "";
            await this.loadAgenda();
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
    async setCommitment(e) {
        const { id, status } = e.currentTarget.dataset;
        try {
            await updateCommitment({ commitmentId: id, status, outcome: null });
            await this.loadAgenda();
        } catch (err) {
            this.error = reduceErrors(err);
        }
    }
    handleNotes(e) {
        this.notes = e.target.value;
    }
    async saveNotes() {
        try {
            await saveSessionNotes({ sessionId: this.sessionId, notes: this.notes });
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }
    async complete() {
        try {
            await completeSession({ sessionId: this.sessionId, notes: this.notes });
            await this.loadSessions();
            await this.loadAgenda();
        } catch (e) {
            this.error = reduceErrors(e);
        }
    }
    async generateBrief() {
        this.busy = true;
        try {
            this.brief = await sessionBrief({ sessionId: this.sessionId });
        } catch (e) {
            this.error = reduceErrors(e);
        } finally {
            this.busy = false;
        }
    }
}
