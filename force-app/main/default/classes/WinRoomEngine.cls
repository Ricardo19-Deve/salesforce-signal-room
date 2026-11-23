/**
 * Win Room opportunity-identification engine.
 *
 * Reads monthly sell-in (WR_Sales__c), surgeon affiliations and tenders,
 * evaluates the active WR_Rule__c records and produces customer-level
 * "improvement pointers" (WR_Pointer__c). Deterministic by design: every
 * pointer carries the numbers that triggered it (Evidence__c) and a plain
 * rationale, so reps can trust and challenge it. GenAI is only used afterwards
 * to enrich the "why and what" (WinRoomAIService).
 *
 * Runs in two batches (WinRoomBenchmarkBatch -> WinRoomEngineBatch) so it
 * scales to the full customer base; runNow() executes the same logic in one
 * transaction for tests and small data sets.
 */
public with sharing class WinRoomEngine {

    public static final Set<String> DECIDED = new Set<String>{ 'Accepted', 'Rejected', 'Converted' };
    private static final Integer HISTORY_MONTHS = 24;
    private static final Integer MIN_PEERS = 4;
    private static final Decimal MIN_ANCHOR_UNITS = 10;

    // ------------------------------------------------------------------ data holders

    /** Segment-level peer statistics over the last 12 months. */
    public class Benchmarks {
        public Map<String, Integer> segmentAccounts = new Map<String, Integer>();
        public Map<String, Decimal> segmentProcedures = new Map<String, Decimal>();
        public Map<String, Integer> buyers = new Map<String, Integer>();
        public Map<String, Decimal> buyerRevenue = new Map<String, Decimal>();
    }

    public class AccountData {
        public WR_Account_Profile__c profile;
        public Map<String, Map<Integer, Decimal>> revenue = new Map<String, Map<Integer, Decimal>>();
        public Map<String, Map<Integer, Decimal>> units = new Map<String, Map<Integer, Decimal>>();
        public Set<Id> surgeonsWithSales = new Set<Id>();
        public List<WR_Affiliation__c> affiliations = new List<WR_Affiliation__c>();
        public List<WR_Tender__c> tenders = new List<WR_Tender__c>();
        public List<WinRoomContracts.ContractResult> contracts = new List<WinRoomContracts.ContractResult>();
    }

    public class SaveResult {
        public Integer created = 0;
        public Integer updated = 0;
        public List<String> errors = new List<String>();
    }

    // ------------------------------------------------------------------ state

    private final Date asOf;
    private final List<WR_Rule__c> rules;
    private final Benchmarks bm;
    private final Map<String, WR_Product_Line__c> linesByCode = new Map<String, WR_Product_Line__c>();
    private Map<Id, Set<Id>> surgeonSites = new Map<Id, Set<Id>>();
    private Map<Id, String> accountNames = new Map<Id, String>();
    private Id runId;

    public WinRoomEngine(Date asOf, List<WR_Rule__c> rules, Benchmarks bm) {
        this.asOf = asOf.toStartOfMonth();
        this.rules = rules;
        this.bm = bm == null ? new Benchmarks() : bm;
        for (WR_Product_Line__c l : [
            SELECT Id, Code__c, Name, System__c, Category__c, Avg_Price__c, Is_Capital__c
            FROM WR_Product_Line__c WHERE Active__c = true
        ]) {
            linesByCode.put(l.Code__c, l);
        }
    }

    public WinRoomEngine withRun(Id runId) {
        this.runId = runId;
        return this;
    }

    // ------------------------------------------------------------------ public API

    public static Date defaultAsOf() {
        return Date.today().toStartOfMonth();
    }

    public static String profileQuery(Boolean inScopeOnly) {
        return 'SELECT Id, Name, Account__c, Account__r.Name, Account__r.OwnerId, Country__c, Segment__c, Size_Band__c, '
            + 'Knee_Procedures__c, Hip_Procedures__c, Phase__c, In_Scope__c, Has_Robot__c, Rep__c, Is_Demo__c '
            + 'FROM WR_Account_Profile__c WHERE Account__c != null'
            + (inScopeOnly ? ' AND In_Scope__c = true' : '');
    }

    /** Adds the 12-month purchases of the given accounts to the peer benchmarks. */
    public static void addToBenchmarks(Benchmarks bm, List<WR_Account_Profile__c> profiles, Date asOf) {
        Date monthStart = asOf.toStartOfMonth();
        Map<Id, String> segmentByAccount = new Map<Id, String>();
        for (WR_Account_Profile__c p : profiles) {
            String seg = segmentKey(p);
            segmentByAccount.put(p.Account__c, seg);
            increment(bm.segmentAccounts, seg, 1);
            addTo(bm.segmentProcedures, seg, procedures(p));
        }
        Date fromDate = monthStart.addMonths(-12);
        Set<Id> accountIds = segmentByAccount.keySet();
        for (AggregateResult ar : [
            SELECT Account__c acc, Product_Line__r.Code__c code, SUM(Revenue__c) rev
            FROM WR_Sales__c
            WHERE Account__c IN :accountIds AND Period__c >= :fromDate AND Period__c < :monthStart
            GROUP BY Account__c, Product_Line__r.Code__c
        ]) {
            Decimal rev = (Decimal) ar.get('rev');
            if (rev == null || rev <= 0) {
                continue;
            }
            String key = segmentByAccount.get((Id) ar.get('acc')) + '|' + (String) ar.get('code');
            increment(bm.buyers, key, 1);
            addTo(bm.buyerRevenue, key, rev);
        }
    }

    /** Evaluates all active rules for a set of in-scope accounts. */
    public List<WR_Pointer__c> evaluate(List<WR_Account_Profile__c> profiles) {
        Map<Id, AccountData> data = load(profiles);
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        for (AccountData a : data.values()) {
            out.addAll(evaluateAccount(a));
        }
        return out;
    }

    /**
     * Inserts new pointers and refreshes existing ones (matched on Signature__c).
     * Decisions taken by reps (accepted / rejected / converted) are never overwritten.
     */
    public SaveResult save(List<WR_Pointer__c> candidates) {
        SaveResult result = new SaveResult();
        Map<String, WR_Pointer__c> bySig = new Map<String, WR_Pointer__c>();
        for (WR_Pointer__c p : candidates) {
            bySig.put(p.Signature__c, p);
        }
        Map<String, WR_Pointer__c> existing = new Map<String, WR_Pointer__c>();
        for (WR_Pointer__c p : [
            SELECT Id, Signature__c, Status__c FROM WR_Pointer__c WHERE Signature__c IN :bySig.keySet()
        ]) {
            existing.put(p.Signature__c, p);
        }
        List<WR_Pointer__c> toInsert = new List<WR_Pointer__c>();
        List<WR_Pointer__c> toUpdate = new List<WR_Pointer__c>();
        for (WR_Pointer__c p : bySig.values()) {
            WR_Pointer__c old = existing.get(p.Signature__c);
            if (old == null) {
                p.Status__c = 'New';
                toInsert.add(p);
            } else if (old.Status__c == 'Rejected') {
                // Keep the rep's rejection; only mark that the signal is still present.
                toUpdate.add(new WR_Pointer__c(Id = old.Id, Last_Detected__c = p.Last_Detected__c));
            } else {
                p.Id = old.Id;
                if (DECIDED.contains(old.Status__c)) {
                    p.Status__c = null;
                    p.Assigned_To__c = null;
                } else {
                    p.Status__c = 'New';
                }
                toUpdate.add(stripNulls(p));
            }
        }
        collect(Database.insert(toInsert, false), result, true);
        collect(Database.update(toUpdate, false), result, false);
        return result;
    }

    /** Marks undecided pointers that were not detected by the given run as expired. */
    public static Integer expireStale(Datetime runStarted) {
        List<WR_Pointer__c> stale = [
            SELECT Id FROM WR_Pointer__c
            WHERE Status__c = 'New' AND (Last_Detected__c = null OR Last_Detected__c < :runStarted)
            LIMIT 9000
        ];
        for (WR_Pointer__c p : stale) {
            p.Status__c = 'Expired';
        }
        update stale;
        return stale.size();
    }

    /** Full run in a single transaction (tests, small data sets). */
    @TestVisible
    static WR_Run__c runNow() {
        WR_Run__c run = new WR_Run__c(Status__c = 'Running', Started__c = Datetime.now().addSeconds(-1));
        insert run;
        Benchmarks bm = new Benchmarks();
        addToBenchmarks(bm, Database.query(profileQuery(false)), defaultAsOf());
        List<WR_Account_Profile__c> inScope = Database.query(profileQuery(true));
        WinRoomEngine engine = new WinRoomEngine(defaultAsOf(), WinRoomRules.activeRules(), bm).withRun(run.Id);
        SaveResult sr = engine.save(engine.evaluate(inScope));
        run.Accounts_Processed__c = inScope.size();
        run.Pointers_New__c = sr.created;
        run.Pointers_Updated__c = sr.updated;
        run.Pointers_Expired__c = expireStale(run.Started__c);
        run.Status__c = 'Completed';
        run.Finished__c = Datetime.now();
        run.Message__c = sr.errors.isEmpty() ? null : String.join(sr.errors, '\n').left(32000);
        update run;
        return run;
    }

    // ------------------------------------------------------------------ loading

    private Map<Id, AccountData> load(List<WR_Account_Profile__c> profiles) {
        Map<Id, AccountData> data = new Map<Id, AccountData>();
        for (WR_Account_Profile__c p : profiles) {
            AccountData a = new AccountData();
            a.profile = p;
            data.put(p.Account__c, a);
            accountNames.put(p.Account__c, p.Account__r?.Name != null ? p.Account__r.Name : p.Name);
        }
        Set<Id> accountIds = data.keySet();
        Date fromDate = asOf.addMonths(-HISTORY_MONTHS);
        for (AggregateResult ar : [
            SELECT Account__c acc, Product_Line__r.Code__c code, Period__c period, SUM(Revenue__c) rev, SUM(Units__c) u
            FROM WR_Sales__c
            WHERE Account__c IN :accountIds AND Period__c >= :fromDate AND Period__c < :asOf
            GROUP BY Account__c, Product_Line__r.Code__c, Period__c
        ]) {
            AccountData a = data.get((Id) ar.get('acc'));
            Integer m = monthsBack((Date) ar.get('period'));
            String code = (String) ar.get('code');
            put(a.revenue, code, m, (Decimal) ar.get('rev'));
            put(a.units, code, m, (Decimal) ar.get('u'));
        }
        Date yearAgo = asOf.addMonths(-12);
        for (AggregateResult ar : [
            SELECT Account__c acc, Surgeon__c surgeon
            FROM WR_Sales__c
            WHERE Account__c IN :accountIds AND Surgeon__c != null AND Period__c >= :yearAgo AND Period__c < :asOf
            GROUP BY Account__c, Surgeon__c
        ]) {
            data.get((Id) ar.get('acc')).surgeonsWithSales.add((Id) ar.get('surgeon'));
        }
        Set<Id> surgeonIds = new Set<Id>();
        for (WR_Affiliation__c af : [
            SELECT Id, Surgeon__c, Surgeon__r.Name, Surgeon__r.Specialty__c, Account__c, Annual_Procedures__c,
                   Start_Date__c, Primary__c, Source__c
            FROM WR_Affiliation__c
            WHERE Account__c IN :accountIds AND Surgeon__c != null
        ]) {
            data.get(af.Account__c).affiliations.add(af);
            surgeonIds.add(af.Surgeon__c);
        }
        // Where else do these surgeons generate Contoso sales?
        for (AggregateResult ar : [
            SELECT Surgeon__c surgeon, Account__c acc, Account__r.Name accName
            FROM WR_Sales__c
            WHERE Surgeon__c IN :surgeonIds AND Period__c >= :yearAgo AND Period__c < :asOf
            GROUP BY Surgeon__c, Account__c, Account__r.Name
        ]) {
            Id s = (Id) ar.get('surgeon');
            if (!surgeonSites.containsKey(s)) {
                surgeonSites.put(s, new Set<Id>());
            }
            surgeonSites.get(s).add((Id) ar.get('acc'));
            accountNames.put((Id) ar.get('acc'), (String) ar.get('accName'));
        }
        Date today = Date.today();
        for (WR_Tender__c t : [
            SELECT Id, Name, Account__c, Category__c, Deadline__c, Estimated_Value__c, Reference__c, Source__c, Country__c
            FROM WR_Tender__c
            WHERE Account__c IN :accountIds AND Status__c = 'Open' AND Deadline__c >= :today
        ]) {
            data.get(t.Account__c).tenders.add(t);
        }
        if (hasContractRules()) {
            List<WR_Contract__c> contracts = Database.query(WinRoomContracts.contractQuery()
                + ' WHERE Account__c IN :accountIds AND Status__c = \'Active\'');
            for (WinRoomContracts.ContractResult c : WinRoomContracts.evaluate(contracts, asOf)) {
                data.get(c.accountId).contracts.add(c);
            }
        }
        return data;
    }

    // ------------------------------------------------------------------ evaluation

    @TestVisible
    private List<WR_Pointer__c> evaluateAccount(AccountData a) {
        List<WR_Pointer__c> all = new List<WR_Pointer__c>();
        for (WR_Rule__c r : rules) {
            switch on r.Rule_Type__c {
                when 'WINBACK_SOFT' { all.addAll(winbackSoft(r, a)); }
                when 'WINBACK_HARD' { all.addAll(winbackHard(r, a)); }
                when 'ATTACH' { all.addAll(attach(r, a)); }
                when 'CAPITAL_PULLTHROUGH' { all.addAll(capitalPullThrough(r, a)); }
                when 'PEER_WHITESPACE' { all.addAll(peerWhitespace(r, a)); }
                when 'SURGEON_SITE' { all.addAll(surgeonSite(r, a)); }
                when 'NEW_SURGEON' { all.addAll(newSurgeon(r, a)); }
                when 'TENDER_RADAR' { all.addAll(tenderRadar(r, a)); }
                when 'SHARE_OF_WALLET' { all.addAll(shareOfWallet(r, a)); }
                when 'CONTRACT_COMPLIANCE' { all.addAll(contractCompliance(r, a)); }
                when 'CONTRACT_RENEWAL' { all.addAll(contractRenewal(r, a)); }
            }
        }
        // Contract pointers are kept apart: a shortfall against a commitment is a different conversation.
        // One pointer per customer x product. A specific signal (churn, switch, attach gap) always beats the generic
        // peer comparison; between specific signals the highest score wins.
        Map<String, WR_Pointer__c> best = new Map<String, WR_Pointer__c>();
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        for (WR_Pointer__c p : all) {
            if (p.Product_Line__c == null || p.Contract__c != null) {
                out.add(p);
                continue;
            }
            String key = String.valueOf(p.Product_Line__c);
            WR_Pointer__c cur = best.get(key);
            Boolean pGeneric = p.Type__c == 'Peer white space';
            Boolean curGeneric = cur != null && cur.Type__c == 'Peer white space';
            if (cur == null || (curGeneric && !pGeneric) || (pGeneric == curGeneric && p.Score__c > cur.Score__c)) {
                best.put(key, p);
            }
        }
        out.addAll(best.values());
        return out;
    }

    private List<WR_Pointer__c> winbackSoft(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Integer recent = intOr(r.Recent_Months__c, 6);
        Decimal threshold = pctOr(r.Threshold_Pct__c, 25);
        for (String code : candidateLines(r.Anchor_Lines__c, a)) {
            if (isCapital(code) || sum(a.units, code, 1, 3) == 0) {
                continue; // zero recent volume is hard churn
            }
            Decimal now = sum(a.revenue, code, 1, recent);
            Decimal before = sum(a.revenue, code, 13, 12 + recent);
            if (before <= 0) {
                continue;
            }
            Decimal drop = (before - now) / before;
            Decimal value = (before - now) * 12 / recent;
            if (drop < threshold || value < nz(r.Min_Value__c)) {
                continue;
            }
            WR_Product_Line__c line = linesByCode.get(code);
            String rationale = line.Name + ' revenue fell ' + pctText(drop) + ' in the last ' + recent
                + ' months (' + money(now) + ') versus the same period last year (' + money(before) + '). '
                + 'Annualised gap: ' + money(value) + '.';
            Map<String, Object> facts = new Map<String, Object>{
                'Last ' + recent + ' months' => money(now),
                'Same period last year' => money(before),
                'Decline' => pctText(drop)
            };
            out.add(build(r, a, 'Win-back soft', r.Category__c, 'Volume decline: ' + line.Name, value,
                rationale, facts, new List<String>{ code }, line.Id, null, null, 40, Date.today().addDays(14)));
        }
        return out;
    }

    private List<WR_Pointer__c> winbackHard(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Integer recent = intOr(r.Recent_Months__c, 3);
        Integer lookback = intOr(r.Lookback_Months__c, 12);
        for (String code : candidateLines(r.Anchor_Lines__c, a)) {
            if (isCapital(code) || sum(a.units, code, 1, recent) > 0) {
                continue;
            }
            Decimal before = sum(a.revenue, code, recent + 1, recent + lookback);
            if (before < nz(r.Min_Value__c)) {
                continue;
            }
            Decimal value = before * 12 / lookback;
            WR_Product_Line__c line = linesByCode.get(code);
            Integer lastMonth = lastActiveMonth(a.units, code);
            String rationale = 'No ' + line.Name + ' orders in the last ' + recent + ' months, after '
                + money(before) + ' in the previous ' + lookback + ' months'
                + (lastMonth != null ? ' (last order ' + monthLabel(lastMonth) + ')' : '') + '. '
                + 'Hard churn: switched competitor or stopped using the line.';
            Map<String, Object> facts = new Map<String, Object>{
                'Revenue previous ' + lookback + ' months' => money(before),
                'Months without orders' => recent,
                'Last order' => lastMonth != null ? monthLabel(lastMonth) : '-'
            };
            out.add(build(r, a, 'Win-back hard', r.Category__c, 'Line stopped: ' + line.Name, value,
                rationale, facts, new List<String>{ code }, line.Id, null, null, 80, Date.today().addDays(7)));
        }
        return out;
    }

    private List<WR_Pointer__c> attach(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        List<String> anchors = codes(r.Anchor_Lines__c);
        List<String> targets = codes(r.Target_Lines__c);
        if (anchors.isEmpty() || targets.isEmpty() || !linesByCode.containsKey(targets[0])) {
            return out;
        }
        Integer lookback = intOr(r.Lookback_Months__c, 12);
        Decimal ratio = r.Expected_Ratio__c == null ? 1 : r.Expected_Ratio__c;
        Decimal tolerance = pctOr(r.Threshold_Pct__c, 20);
        Decimal anchorUnits = sumAll(a.units, anchors, 1, lookback);
        Decimal targetUnits = sumAll(a.units, targets, 1, lookback);
        if (anchorUnits < MIN_ANCHOR_UNITS) {
            return out;
        }
        Decimal actual = targetUnits / anchorUnits;
        if (actual >= ratio * (1 - tolerance)) {
            return out;
        }
        WR_Product_Line__c target = linesByCode.get(targets[0]);
        Decimal gapUnits = anchorUnits * ratio - targetUnits;
        Decimal value = gapUnits * nz(target.Avg_Price__c) * 12 / lookback;
        if (value < nz(r.Min_Value__c)) {
            return out;
        }
        Decimal priorAnchor = sumAll(a.units, anchors, 13, 12 + lookback);
        Decimal priorTarget = sumAll(a.units, targets, 13, 12 + lookback);
        Boolean switched = priorAnchor > 0 && priorTarget / priorAnchor >= ratio * (1 - tolerance);
        String type = switched ? 'Partial switch' : 'Cross-sell';
        String category = switched ? WinRoomRules.CAT_WINBACK : WinRoomRules.CAT_XSELL;
        String anchorNames = lineNames(anchors);
        String rationale = (switched
                ? target.Name + ' usage per ' + anchorNames + ' dropped from ' + ratioText(priorTarget, priorAnchor)
                    + ' to ' + ratioText(targetUnits, anchorUnits) + ' while ' + anchorNames + ' volume continues. '
                    + 'Likely partial switch to a competitor. '
                : 'The account used ' + anchorUnits.setScale(0) + ' ' + anchorNames + ' in the last ' + lookback
                    + ' months but only ' + targetUnits.setScale(0) + ' ' + target.Name + ' (ratio '
                    + ratioText(targetUnits, anchorUnits) + ' vs. expected ' + ratio.setScale(2) + '). ')
            + 'Gap: ~' + gapUnits.setScale(0) + ' units, ' + money(value) + ' per year.';
        Map<String, Object> facts = new Map<String, Object>{
            anchorNames + ' units (' + lookback + 'm)' => anchorUnits.setScale(0),
            target.Name + ' units (' + lookback + 'm)' => targetUnits.setScale(0),
            'Actual ratio' => ratioText(targetUnits, anchorUnits),
            'Expected ratio' => ratio.setScale(2),
            'Ratio same period last year' => ratioText(priorTarget, priorAnchor)
        };
        List<String> chartLines = new List<String>(anchors);
        chartLines.addAll(targets);
        out.add(build(r, a, type, category, (switched ? 'Partial switch: ' : 'Pull-through: ') + target.Name, value,
            rationale, facts, chartLines, target.Id, null, null, switched ? 70 : 40, Date.today().addDays(21)));
        return out;
    }

    private List<WR_Pointer__c> capitalPullThrough(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        List<String> anchors = codes(r.Anchor_Lines__c);
        List<String> targets = codes(r.Target_Lines__c);
        if (anchors.isEmpty() || targets.isEmpty() || !linesByCode.containsKey(targets[0])) {
            return out;
        }
        Integer lookback = intOr(r.Lookback_Months__c, 12);
        if (sumAll(a.units, anchors, 1, lookback) <= 0 || sumAll(a.units, targets, 1, lookback) > 0) {
            return out;
        }
        Decimal cups = sum(a.units, 'HIP_CUP', 1, lookback);
        Decimal stems = sumAll(a.units, new List<String>{ 'HIP_STEM_T', 'HIP_STEM_C' }, 1, lookback);
        Decimal hipCases = Math.max(cups, stems);
        Decimal share = r.Expected_Ratio__c == null ? 0.4 : r.Expected_Ratio__c;
        Decimal cases = hipCases * share * 12 / lookback;
        WR_Product_Line__c target = linesByCode.get(targets[0]);
        Decimal protectedImplants = cases * basket('Hip') * 0.2;
        Decimal value = cases * nz(target.Avg_Price__c) + protectedImplants;
        if (value < nz(r.Min_Value__c)) {
            return out;
        }
        String rationale = 'The account runs ' + lineNames(anchors) + ' and performed ~' + hipCases.setScale(0)
            + ' Contoso hip cases in the last ' + lookback + ' months, but has no ' + target.Name + ' workflow. '
            + 'At ' + pctText(share) + ' robotic adoption this is ~' + cases.setScale(0) + ' cases per year: '
            + money(cases * nz(target.Avg_Price__c)) + ' in workflow fees plus ' + money(protectedImplants)
            + ' of hip implant revenue protected (20% retention uplift).';
        Map<String, Object> facts = new Map<String, Object>{
            'Hip cases (' + lookback + 'm)' => hipCases.setScale(0),
            'Expected robotic share' => pctText(share),
            'Expected Atlas Robotic Hip cases / year' => cases.setScale(0)
        };
        List<String> chartLines = new List<String>{ 'HIP_CUP', 'HIP_STEM_T' };
        chartLines.addAll(anchors);
        out.add(build(r, a, 'Capital pull-through', r.Category__c, 'Workflow bundle: ' + target.Name, value,
            rationale, facts, chartLines, target.Id, null, null, 50, Date.today().addDays(30)));
        return out;
    }

    private List<WR_Pointer__c> peerWhitespace(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        String seg = segmentKey(a.profile);
        Integer peers = bm.segmentAccounts.get(seg);
        if (peers == null || peers < MIN_PEERS) {
            return out;
        }
        Decimal threshold = pctOr(r.Threshold_Pct__c, 60);
        Decimal avgProcedures = nz(bm.segmentProcedures.get(seg)) / peers;
        Decimal sizeFactor = avgProcedures > 0 ? procedures(a.profile) / avgProcedures : 1;
        Decimal maxFactor = 2;
        Decimal minFactor = 0.3;
        sizeFactor = Math.min(maxFactor, Math.max(minFactor, sizeFactor));
        for (WR_Product_Line__c line : linesByCode.values()) {
            if (line.Is_Capital__c == true || sum(a.units, line.Code__c, 1, 24) > 0) {
                continue; // already bought at some point -> churn rules apply instead
            }
            String key = seg + '|' + line.Code__c;
            Integer buyers = bm.buyers.get(key);
            if (buyers == null || buyers == 0) {
                continue;
            }
            Decimal penetration = Decimal.valueOf(buyers) / peers;
            if (penetration < threshold) {
                continue;
            }
            Decimal value = bm.buyerRevenue.get(key) / buyers * sizeFactor;
            if (value < nz(r.Min_Value__c)) {
                continue;
            }
            String rationale = buyers + ' of ' + peers + ' comparable hospitals (' + segmentLabel(a.profile) + ') buy '
                + line.Name + ' (' + pctText(penetration) + ' penetration), but this account never did. '
                + 'Peer average ' + money(bm.buyerRevenue.get(key) / buyers) + ' per year, scaled by account size (x'
                + sizeFactor.setScale(2) + ') = ' + money(value) + '.';
            Map<String, Object> facts = new Map<String, Object>{
                'Peer group' => segmentLabel(a.profile),
                'Peers buying' => buyers + ' / ' + peers,
                'Peer average revenue' => money(bm.buyerRevenue.get(key) / buyers),
                'Size factor' => sizeFactor.setScale(2)
            };
            out.add(build(r, a, 'Peer white space', r.Category__c, 'White space vs. peers: ' + line.Name, value,
                rationale, facts, new List<String>(), line.Id, null, null, 30, Date.today().addDays(45)));
        }
        return out;
    }

    private List<WR_Pointer__c> surgeonSite(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Decimal share = pctOr(r.Threshold_Pct__c, 50);
        for (WR_Affiliation__c af : a.affiliations) {
            Set<Id> sites = surgeonSites.get(af.Surgeon__c);
            if (sites == null || a.surgeonsWithSales.contains(af.Surgeon__c)) {
                continue;
            }
            Id otherSite = null;
            for (Id s : sites) {
                if (s != a.profile.Account__c) {
                    otherSite = s;
                    break;
                }
            }
            if (otherSite == null) {
                continue;
            }
            Decimal procs = nz(af.Annual_Procedures__c);
            Decimal value = procs * share * basket(af.Surgeon__r.Specialty__c);
            if (value < nz(r.Min_Value__c)) {
                continue;
            }
            String other = accountNames.get(otherSite);
            String rationale = af.Surgeon__r.Name + ' uses Contoso at ' + other + ' and also performs ~' + procs.setScale(0)
                + ' ' + nvl(af.Surgeon__r.Specialty__c, 'recon').toLowerCase() + ' procedures per year here, with no Contoso usage at this site. '
                + 'Winning ' + pctText(share) + ' of these cases = ' + money(value) + ' per year.';
            Map<String, Object> facts = new Map<String, Object>{
                'Surgeon' => af.Surgeon__r.Name,
                'Uses Contoso at' => other,
                'Procedures here / year' => procs.setScale(0),
                'Affiliation source' => nvl(af.Source__c, '-')
            };
            out.add(build(r, a, 'Surgeon site expansion', r.Category__c, 'Hunt plan: ' + af.Surgeon__r.Name + ' at this site',
                value, rationale, facts, new List<String>(), null, af.Surgeon__c, null, 60, Date.today().addDays(21)));
        }
        return out;
    }

    private List<WR_Pointer__c> newSurgeon(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Decimal share = pctOr(r.Threshold_Pct__c, 40);
        Date since = Date.today().addMonths(-intOr(r.Recent_Months__c, 6));
        for (WR_Affiliation__c af : a.affiliations) {
            if (af.Start_Date__c == null || af.Start_Date__c < since || a.surgeonsWithSales.contains(af.Surgeon__c)
                    || surgeonSites.containsKey(af.Surgeon__c)) {
                continue;
            }
            Decimal procs = nz(af.Annual_Procedures__c);
            Decimal value = procs * share * basket(af.Surgeon__r.Specialty__c);
            if (value < nz(r.Min_Value__c)) {
                continue;
            }
            String rationale = af.Surgeon__r.Name + ' (' + nvl(af.Surgeon__r.Specialty__c, 'recon') + ') joined on '
                + af.Start_Date__c.format() + ' with ~' + procs.setScale(0) + ' procedures per year and no Contoso cases yet. '
                + 'First-case window before preferences harden: ' + pctText(share) + ' of cases = ' + money(value) + ' per year.';
            Map<String, Object> facts = new Map<String, Object>{
                'Surgeon' => af.Surgeon__r.Name,
                'Joined' => af.Start_Date__c.format(),
                'Expected procedures / year' => procs.setScale(0)
            };
            out.add(build(r, a, 'New surgeon', r.Category__c, 'First case target: ' + af.Surgeon__r.Name, value,
                rationale, facts, new List<String>(), null, af.Surgeon__c, null, 70, firstCaseDue(af.Start_Date__c)));
        }
        return out;
    }

    private List<WR_Pointer__c> tenderRadar(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Date horizon = Date.today().addMonths(intOr(r.Lookback_Months__c, 2));
        Decimal winProbability = pctOr(r.Threshold_Pct__c, 35);
        for (WR_Tender__c t : a.tenders) {
            if (t.Deadline__c > horizon) {
                continue;
            }
            Integer days = Date.today().daysBetween(t.Deadline__c);
            Decimal value = nz(t.Estimated_Value__c) * winProbability;
            if (value < nz(r.Min_Value__c)) {
                continue;
            }
            Integer urgency = days <= 14 ? 100 : (days <= 30 ? 75 : 50);
            String rationale = 'Open tender "' + t.Name + '" (' + nvl(t.Category__c, 'recon') + ', ref. '
                + nvl(t.Reference__c, '-') + ') closes on ' + t.Deadline__c.format() + ' - ' + days + ' days left. '
                + 'Estimated value ' + money(t.Estimated_Value__c) + '; at ' + pctText(winProbability)
                + ' win probability the value at stake is ' + money(value) + '.';
            Map<String, Object> facts = new Map<String, Object>{
                'Deadline' => t.Deadline__c.format(),
                'Days left' => days,
                'Estimated value' => money(t.Estimated_Value__c),
                'Source' => nvl(t.Source__c, '-')
            };
            Date due = t.Deadline__c.addDays(-14) > Date.today() ? t.Deadline__c.addDays(-14) : Date.today();
            out.add(build(r, a, 'Tender', r.Category__c, 'Tender: ' + t.Name.left(80) + ' (' + days + ' days)', value,
                rationale, facts, new List<String>(), null, null, t.Id, urgency, due));
        }
        return out;
    }

    private List<WR_Pointer__c> shareOfWallet(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Decimal market = nz(a.profile.Knee_Procedures__c) * basket('Knee') + nz(a.profile.Hip_Procedures__c) * basket('Hip');
        if (market <= 0) {
            return out;
        }
        Decimal ours = 0;
        for (String code : a.revenue.keySet()) {
            ours += sum(a.revenue, code, 1, 12);
        }
        Decimal share = ours / market;
        Decimal threshold = pctOr(r.Threshold_Pct__c, 15);
        Decimal target = r.Expected_Ratio__c == null ? 0.3 : r.Expected_Ratio__c;
        if (share >= threshold) {
            return out;
        }
        Decimal value = target * market - ours;
        if (value < nz(r.Min_Value__c)) {
            return out;
        }
        Boolean greenfield = ours == 0;
        String rationale = 'Estimated reconstructive market ' + money(market) + ' per year ('
            + nz(a.profile.Knee_Procedures__c).setScale(0) + ' knees, ' + nz(a.profile.Hip_Procedures__c).setScale(0)
            + ' hips x basket price). Contoso revenue last 12 months ' + money(ours) + ' = ' + pctText(share)
            + ' share of wallet. Reaching the ' + pctText(target) + ' target is worth ' + money(value) + '.';
        Map<String, Object> facts = new Map<String, Object>{
            'Estimated market / year' => money(market),
            'Contoso revenue (12m)' => money(ours),
            'Share of wallet' => pctText(share),
            'Target share' => pctText(target)
        };
        out.add(build(r, a, 'Share of wallet', r.Category__c,
            greenfield ? 'Greenfield account' : 'Low share of wallet (' + pctText(share) + ')', value,
            rationale, facts, new List<String>(), null, null, null, 30, Date.today().addDays(60)));
        return out;
    }

    private Boolean hasContractRules() {
        for (WR_Rule__c r : rules) {
            if (r.Rule_Type__c == 'CONTRACT_COMPLIANCE' || r.Rule_Type__c == 'CONTRACT_RENEWAL') {
                return true;
            }
        }
        return false;
    }

    /**
     * Shortfall when delivered volume to date is below the commitment beyond the threshold and the recent run-rate
     * is too; overrun when both are above. Value = annual revenue gap at the current run-rate (or the backlog).
     */
    private List<WR_Pointer__c> contractCompliance(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Decimal threshold = pctOr(r.Threshold_Pct__c, 10);
        for (WinRoomContracts.ContractResult c : a.contracts) {
            for (WinRoomContracts.LineResult l : c.lines) {
                if (l.variancePct == null || l.runRatePct == null || l.monthlyQty == 0) {
                    continue;
                }
                Boolean shortfall = l.status == 'Under' && l.runRatePct < -threshold;
                Boolean overrun = l.status == 'Over' && l.runRatePct > threshold;
                if (!shortfall && !overrun) {
                    continue;
                }
                Decimal annualGap = (l.runRate - l.monthlyQty).abs() * 12 * l.unitPrice;
                Decimal backlog = (0 - l.varianceUnits) * l.unitPrice;
                Decimal value = shortfall ? Math.max(annualGap, backlog) : annualGap;
                if (value < nz(r.Min_Value__c)) {
                    continue;
                }
                String rationale = c.name + ' commits ' + l.monthlyQty.setScale(0) + ' ' + l.label + ' per month. Since '
                    + c.comparedFrom.format() + ' ' + l.deliveredToDate.setScale(0) + ' were delivered against '
                    + l.committedToDate.setScale(0) + ' committed (' + signedPct(l.variancePct) + '); the last '
                    + WinRoomContracts.RUN_RATE_MONTHS + ' months run at ' + l.runRate.setScale(1) + ' per month ('
                    + signedPct(l.runRatePct) + '). '
                    + (shortfall
                        ? 'At this rate the term ends ' + l.projectedVariance.abs().setScale(0) + ' units short. Value at stake ' + money(value) + ' per year.'
                        : 'The account buys ' + money(value) + ' per year above the commitment, outside the contracted terms.');
                Map<String, Object> facts = new Map<String, Object>{
                    'Contract' => c.name,
                    'Committed / month' => l.monthlyQty.setScale(0),
                    'Delivered to date' => l.deliveredToDate.setScale(0) + ' / ' + l.committedToDate.setScale(0),
                    'Variance to date' => signedPct(l.variancePct),
                    'Run-rate (' + WinRoomContracts.RUN_RATE_MONTHS + 'm)' => l.runRate.setScale(1),
                    'Projected at term end' => l.projectedTotal + ' / ' + l.totalCommitment.setScale(0)
                };
                WR_Pointer__c p = build(r, a, shortfall ? 'Contract shortfall' : 'Contract overrun',
                    shortfall ? WinRoomRules.CAT_WINBACK : WinRoomRules.CAT_XSELL,
                    (shortfall ? 'Contract shortfall: ' : 'Contract overrun: ') + l.label + ' (' + signedPct(l.variancePct) + ')',
                    value, rationale, facts, new List<String>(), l.productLineId, null, null, c.contractId,
                    shortfall ? 85 : 45, Date.today().addDays(shortfall ? 14 : 30));
                p.Evidence__c = JSON.serialize(new Map<String, Object>{
                    'facts' => facts,
                    'months' => l.months,
                    'series' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Committed', 'unit' => 'units', 'values' => l.committed },
                        new Map<String, Object>{ 'label' => 'Delivered', 'unit' => 'units', 'values' => l.delivered }
                    },
                    'rule' => r.Name
                });
                out.add(p);
            }
        }
        return out;
    }

    /** Active contract ending within Lookback months: plan the renewal. Value = annual contract value. */
    private List<WR_Pointer__c> contractRenewal(WR_Rule__c r, AccountData a) {
        List<WR_Pointer__c> out = new List<WR_Pointer__c>();
        Date horizon = Date.today().addMonths(intOr(r.Lookback_Months__c, 6));
        for (WinRoomContracts.ContractResult c : a.contracts) {
            if (c.endDate == null || c.endDate < Date.today() || c.endDate > horizon || c.annualValue < nz(r.Min_Value__c)) {
                continue;
            }
            Integer days = Date.today().daysBetween(c.endDate);
            String compliance = c.compliancePct == null ? 'no delivery data yet'
                : 'delivered ' + pctText(c.compliancePct) + ' of the committed value to date';
            String rationale = c.name + ' (' + nvl(c.reference, '-') + ') ends on ' + c.endDate.format() + ' - ' + days
                + ' days left. Annual contract value ' + money(c.annualValue) + '; ' + compliance + ' (' + c.health + ').';
            Map<String, Object> facts = new Map<String, Object>{
                'Contract' => c.name,
                'Ends' => c.endDate.format(),
                'Days left' => days,
                'Annual value' => money(c.annualValue),
                'Compliance to date' => c.compliancePct == null ? '-' : pctText(c.compliancePct)
            };
            Date due = c.endDate.addDays(-90) > Date.today() ? c.endDate.addDays(-90) : Date.today().addDays(7);
            out.add(build(r, a, 'Contract renewal', r.Category__c, 'Contract renewal: ' + c.name.left(80) + ' (' + days + ' days)',
                c.annualValue, rationale, facts, new List<String>(), null, null, null, c.contractId,
                days <= 90 ? 100 : 70, due));
        }
        return out;
    }

    private static String signedPct(Decimal ratio) {
        return (ratio >= 0 ? '+' : '') + pctText(ratio);
    }

    // ------------------------------------------------------------------ pointer factory

    private WR_Pointer__c build(WR_Rule__c r, AccountData a, String type, String category, String title,
            Decimal value, String rationale, Map<String, Object> facts, List<String> chartLines, Id lineId,
            Id surgeonId, Id tenderId, Integer urgency, Date due) {
        return build(r, a, type, category, title, value, rationale, facts, chartLines, lineId, surgeonId, tenderId,
            null, urgency, due);
    }

    private WR_Pointer__c build(WR_Rule__c r, AccountData a, String type, String category, String title,
            Decimal value, String rationale, Map<String, Object> facts, List<String> chartLines, Id lineId,
            Id surgeonId, Id tenderId, Id contractId, Integer urgency, Date due) {
        Decimal rounded = value.setScale(0, RoundingMode.HALF_UP);
        Integer score = score(rounded, r.Weight__c, urgency);
        Map<String, Object> evidence = new Map<String, Object>{
            'facts' => facts,
            'months' => monthLabels(),
            'series' => series(a, chartLines),
            'rule' => r.Name
        };
        return new WR_Pointer__c(
            Title__c = title.left(255),
            Account__c = a.profile.Account__c,
            Country__c = a.profile.Country__c,
            Product_Line__c = lineId,
            Surgeon__c = surgeonId,
            Tender__c = tenderId,
            Contract__c = contractId,
            Rule__c = r.Id,
            Run__c = runId,
            Type__c = type,
            Category__c = category,
            Value_At_Stake__c = rounded,
            Score__c = score,
            Priority__c = score >= 65 ? 'High' : (score >= 45 ? 'Medium' : 'Low'),
            Rationale__c = rationale,
            Evidence__c = JSON.serialize(evidence),
            Next_Best_Action__c = r.Next_Best_Action__c,
            Assigned_To__c = a.profile.Rep__c != null ? a.profile.Rep__c : a.profile.Account__r?.OwnerId,
            Signature__c = (r.Code__c + '|' + a.profile.Account__c + '|' + nvl(lineId, '') + '|'
                + nvl(surgeonId, '') + '|' + nvl(tenderId, '') + (contractId == null ? '' : '|' + contractId)).left(255),
            Last_Detected__c = Datetime.now(),
            Due_Date__c = due,
            Is_Demo__c = a.profile.Is_Demo__c
        );
    }

    /** Welcome visit within 45 days of joining; when that is already past, two weeks from today. */
    private static Date firstCaseDue(Date joined) {
        Date due = joined.addDays(45);
        return due < Date.today() ? Date.today().addDays(14) : due;
    }

    /** 0-100: 60% value (log scale, 1M = 100), 25% rule weight, 15% urgency. */
    @TestVisible
    static Integer score(Decimal value, Decimal weight, Integer urgency) {
        Double v = value == null || value <= 0 ? 0 : Math.log(1 + value.doubleValue() / 5000) / Math.log(201);
        Double valueScore = Math.min(100.0, 100.0 * v);
        Double weightScore = (weight == null ? 3 : weight.doubleValue()) * 20;
        return (Integer) Math.round(0.6 * valueScore + 0.25 * weightScore + 0.15 * urgency);
    }

    private List<Map<String, Object>> series(AccountData a, List<String> codes) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String code : codes) {
            WR_Product_Line__c line = linesByCode.get(code);
            if (line == null) {
                continue;
            }
            List<Decimal> values = new List<Decimal>();
            for (Integer m = HISTORY_MONTHS; m >= 1; m--) {
                values.add(get(a.units, code, m));
            }
            out.add(new Map<String, Object>{ 'label' => line.Name, 'unit' => 'units', 'values' => values });
        }
        return out;
    }

    private List<String> monthLabels() {
        List<String> out = new List<String>();
        for (Integer m = HISTORY_MONTHS; m >= 1; m--) {
            out.add(monthLabel(m));
        }
        return out;
    }

    // ------------------------------------------------------------------ helpers

    private List<String> candidateLines(String filter, AccountData a) {
        List<String> explicit = codes(filter);
        return explicit.isEmpty() ? new List<String>(a.units.keySet()) : explicit;
    }

    private Boolean isCapital(String code) {
        WR_Product_Line__c l = linesByCode.get(code);
        return l == null || l.Is_Capital__c == true;
    }

    private String lineNames(List<String> codes) {
        List<String> names = new List<String>();
        for (String c : codes) {
            names.add(linesByCode.containsKey(c) ? linesByCode.get(c).Name : c);
        }
        return String.join(names, ' / ');
    }

    /** Average implant basket per procedure for a category (Knee, Hip, Knee & Hip). */
    private Decimal basket(String specialty) {
        Decimal knee = price('KNEE_FEM') + price('KNEE_TIB') + price('KNEE_PAT');
        Decimal hip = price('HIP_CUP') + price('HIP_LINER') + price('HIP_STEM_T') + price('HIP_HEAD');
        if (specialty == 'Knee') {
            return knee;
        }
        if (specialty == 'Hip') {
            return hip;
        }
        return (knee + hip) / 2;
    }

    private Decimal price(String code) {
        WR_Product_Line__c l = linesByCode.get(code);
        return l == null ? 0 : nz(l.Avg_Price__c);
    }

    private Integer monthsBack(Date period) {
        return (asOf.year() * 12 + asOf.month()) - (period.year() * 12 + period.month());
    }

    private String monthLabel(Integer monthsBack) {
        return Datetime.newInstance(asOf.addMonths(-monthsBack), Time.newInstance(12, 0, 0, 0)).format('MMM yy');
    }

    private static Integer lastActiveMonth(Map<String, Map<Integer, Decimal>> m, String code) {
        Map<Integer, Decimal> byMonth = m.get(code);
        if (byMonth == null) {
            return null;
        }
        Integer best = null;
        for (Integer k : byMonth.keySet()) {
            if (byMonth.get(k) > 0 && (best == null || k < best)) {
                best = k;
            }
        }
        return best;
    }

    private static String segmentKey(WR_Account_Profile__c p) {
        return nvl(p.Segment__c, 'Unknown');
    }

    private static String segmentLabel(WR_Account_Profile__c p) {
        return nvl(p.Segment__c, 'same segment');
    }

    private static Decimal procedures(WR_Account_Profile__c p) {
        return nz(p.Knee_Procedures__c) + nz(p.Hip_Procedures__c);
    }

    private static List<String> codes(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) {
            return out;
        }
        for (String c : csv.split(',')) {
            if (String.isNotBlank(c)) {
                out.add(c.trim().toUpperCase());
            }
        }
        return out;
    }

    private static void put(Map<String, Map<Integer, Decimal>> m, String code, Integer month, Decimal v) {
        if (!m.containsKey(code)) {
            m.put(code, new Map<Integer, Decimal>());
        }
        Map<Integer, Decimal> byMonth = m.get(code);
        byMonth.put(month, nz(byMonth.get(month)) + nz(v));
    }

    private static Decimal get(Map<String, Map<Integer, Decimal>> m, String code, Integer month) {
        Map<Integer, Decimal> byMonth = m.get(code);
        return byMonth == null ? 0 : nz(byMonth.get(month));
    }

    private static Decimal sum(Map<String, Map<Integer, Decimal>> m, String code, Integer fromMonth, Integer toMonth) {
        Decimal total = 0;
        for (Integer i = fromMonth; i <= toMonth; i++) {
            total += get(m, code, i);
        }
        return total;
    }

    private static Decimal sumAll(Map<String, Map<Integer, Decimal>> m, List<String> codes, Integer fromMonth, Integer toMonth) {
        Decimal total = 0;
        for (String c : codes) {
            total += sum(m, c, fromMonth, toMonth);
        }
        return total;
    }

    private static void increment(Map<String, Integer> m, String key, Integer amount) {
        m.put(key, (m.containsKey(key) ? m.get(key) : 0) + amount);
    }

    private static void addTo(Map<String, Decimal> m, String key, Decimal amount) {
        m.put(key, nz(m.get(key)) + nz(amount));
    }

    private static WR_Pointer__c stripNulls(WR_Pointer__c p) {
        Map<String, Object> populated = p.getPopulatedFieldsAsMap();
        WR_Pointer__c clean = new WR_Pointer__c();
        for (String f : populated.keySet()) {
            if (populated.get(f) != null) {
                clean.put(f, populated.get(f));
            }
        }
        return clean;
    }

    private static void collect(List<Database.SaveResult> results, SaveResult acc, Boolean inserted) {
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) {
                if (inserted) {
                    acc.created++;
                } else {
                    acc.updated++;
                }
            } else {
                for (Database.Error e : r.getErrors()) {
                    acc.errors.add(e.getMessage());
                }
            }
        }
    }

    private static Integer intOr(Decimal v, Integer fallback) {
        return v == null || v <= 0 ? fallback : v.intValue();
    }

    /** Percent fields hold 25 for 25%; returns 0.25. */
    private static Decimal pctOr(Decimal v, Decimal fallback) {
        return (v == null ? fallback : v) / 100;
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }

    private static String nvl(Object v, String fallback) {
        return v == null ? fallback : String.valueOf(v);
    }

    public static String money(Decimal v) {
        Decimal x = nz(v);
        if (Math.abs(x) >= 1000000) {
            return '€' + (x / 1000000).setScale(2) + 'M';
        }
        if (Math.abs(x) >= 1000) {
            return '€' + (x / 1000).setScale(1) + 'k';
        }
        return '€' + x.setScale(0);
    }

    private static String pctText(Decimal ratio) {
        return (nz(ratio) * 100).setScale(0) + '%';
    }

    private static String ratioText(Decimal num, Decimal den) {
        return den == null || den == 0 ? '-' : (num / den).setScale(2).toPlainString();
    }
}
