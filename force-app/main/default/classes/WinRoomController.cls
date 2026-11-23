/**
 * Apex API of the Win Room portal (LWC winRoomApp and children).
 *
 *  Dashboard      getDashboard
 *  Pointers       getPointers, getPointer, decidePointer, convertToOpportunity, enrichWithAI
 *  Account 360    searchAccounts, getAccount360
 *  Win Room       getSessions, createSession, getAgenda, saveCommitment, updateCommitment,
 *                 completeSession, sessionBrief, searchUsers
 *  Admin          getRules, saveRule, resetRules, runEngine, getRuns, getProfiles,
 *                 updateProfile, generateMockData, purgeMockData, getJobStatus
 */
public with sharing class WinRoomController {

    private static final Set<String> OPEN = new Set<String>{ 'New', 'Accepted' };
    private static final String POINTER_FIELDS = 'Id, Name, Title__c, Account__c, Account__r.Name, Country__c, '
        + 'Product_Line__c, Product_Line__r.Name, Surgeon__c, Surgeon__r.Name, Tender__c, Tender__r.Name, '
        + 'Rule__c, Rule__r.Name, Type__c, Category__c, Status__c, Priority__c, Value_At_Stake__c, Score__c, '
        + 'Due_Date__c, Assigned_To__c, Assigned_To__r.Name, Opportunity__c, Opportunity__r.Name, '
        + 'Opportunity__r.StageName, Rejection_Reason__c, Last_Detected__c, CreatedDate';

    // ================================================================== context

    @AuraEnabled
    public static Map<String, Object> getContext() {
        List<WR_Run__c> runs = [
            SELECT Id, Name, Status__c, Started__c, Finished__c, Pointers_New__c, Pointers_Updated__c,
                   Pointers_Expired__c, Accounts_Processed__c
            FROM WR_Run__c ORDER BY CreatedDate DESC LIMIT 1
        ];
        List<String> countries = new List<String>();
        for (AggregateResult ar : [
            SELECT Country__c c FROM WR_Account_Profile__c WHERE Country__c != null GROUP BY Country__c ORDER BY Country__c
        ]) {
            countries.add((String) ar.get('c'));
        }
        return new Map<String, Object>{
            'userId' => UserInfo.getUserId(),
            'userName' => UserInfo.getName(),
            'isAdmin' => isAdmin(),
            'aiConfigured' => WinRoomAIService.isConfigured(),
            'countries' => countries,
            'profiles' => [SELECT COUNT() FROM WR_Account_Profile__c],
            'pointers' => [SELECT COUNT() FROM WR_Pointer__c],
            'rules' => [SELECT COUNT() FROM WR_Rule__c],
            'lastRun' => runs.isEmpty() ? null : runs[0]
        };
    }

    // ================================================================== dashboard

    @AuraEnabled
    public static Map<String, Object> getDashboard(String scope, String country) {
        Map<String, Object> binds = baseBinds(scope, country);
        String cond = baseWhere(scope, country);

        Map<String, Object> byStatus = new Map<String, Object>();
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Status__c s, COUNT(Id) n, SUM(Value_At_Stake__c) v FROM WR_Pointer__c ' + cond
                + ' GROUP BY Status__c', binds, AccessLevel.USER_MODE)) {
            byStatus.put((String) ar.get('s'), bucket(ar));
        }
        binds.put('openStatuses', OPEN);
        String openWhere = cond + ' AND Status__c IN :openStatuses';
        List<Object> byCategory = groupBy('Category__c', openWhere, binds);
        List<Object> byType = groupBy('Type__c', openWhere, binds);
        List<Object> byCountry = groupBy('Country__c', openWhere, binds);
        List<Object> byPriority = groupBy('Priority__c', openWhere, binds);

        List<Object> byRule = new List<Object>();
        Map<String, Map<String, Object>> rules = new Map<String, Map<String, Object>>();
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Rule__r.Name r, Status__c s, COUNT(Id) n FROM WR_Pointer__c ' + cond
                + ' AND Rule__c != null GROUP BY Rule__r.Name, Status__c', binds, AccessLevel.USER_MODE)) {
            String name = (String) ar.get('r');
            if (!rules.containsKey(name)) {
                rules.put(name, new Map<String, Object>{ 'label' => name, 'total' => 0, 'accepted' => 0, 'rejected' => 0 });
            }
            Map<String, Object> row = rules.get(name);
            Integer n = (Integer) ar.get('n');
            row.put('total', (Integer) row.get('total') + n);
            String s = (String) ar.get('s');
            if (s == 'Accepted' || s == 'Converted') {
                row.put('accepted', (Integer) row.get('accepted') + n);
            } else if (s == 'Rejected') {
                row.put('rejected', (Integer) row.get('rejected') + n);
            }
        }
        byRule.addAll(rules.values());

        List<WR_Pointer__c> top = Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ' FROM WR_Pointer__c ' + openWhere + ' ORDER BY Score__c DESC NULLS LAST LIMIT 10',
            binds, AccessLevel.USER_MODE);

        Decimal pipeline = 0;
        Decimal won = 0;
        Integer converted = 0;
        for (WR_Pointer__c p : (List<WR_Pointer__c>) Database.queryWithBinds(
                'SELECT Opportunity__r.Amount, Opportunity__r.IsWon, Opportunity__r.IsClosed FROM WR_Pointer__c '
                + cond + ' AND Opportunity__c != null LIMIT 5000', binds, AccessLevel.USER_MODE)) {
            converted++;
            Decimal amount = p.Opportunity__r.Amount == null ? 0 : p.Opportunity__r.Amount;
            if (p.Opportunity__r.IsWon) {
                won += amount;
            } else if (!p.Opportunity__r.IsClosed) {
                pipeline += amount;
            }
        }
        Date today = Date.today();
        Integer overdue = [
            SELECT COUNT() FROM WR_Commitment__c
            WHERE Status__c = 'Blocked' OR (Status__c = 'Open' AND Due_Date__c < :today)
        ];
        Integer openCommitments = [SELECT COUNT() FROM WR_Commitment__c WHERE Status__c = 'Open'];
        return new Map<String, Object>{
            'byStatus' => byStatus,
            'byCategory' => byCategory,
            'byType' => byType,
            'byCountry' => byCountry,
            'byPriority' => byPriority,
            'byRule' => byRule,
            'top' => rows(top),
            'pipeline' => pipeline,
            'won' => won,
            'converted' => converted,
            'openCommitments' => openCommitments,
            'overdueCommitments' => overdue
        };
    }

    // ================================================================== pointers

    @AuraEnabled
    public static List<Map<String, Object>> getPointers(String filterJson) {
        Map<String, Object> f = String.isBlank(filterJson)
            ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(filterJson);
        String scope = (String) f.get('scope');
        String country = (String) f.get('country');
        Map<String, Object> binds = baseBinds(scope, country);
        String cond = baseWhere(scope, country);
        String status = (String) f.get('status');
        if (String.isBlank(status) || status == 'Open') {
            binds.put('openStatuses', OPEN);
            cond += ' AND Status__c IN :openStatuses';
        } else if (status != 'All') {
            binds.put('status', status);
            cond += ' AND Status__c = :status';
        }
        for (String key : new List<String>{ 'category', 'priority', 'type' }) {
            String v = (String) f.get(key);
            if (String.isNotBlank(v)) {
                String field = key == 'category' ? 'Category__c' : (key == 'priority' ? 'Priority__c' : 'Type__c');
                binds.put(key, v);
                cond += ' AND ' + field + ' = :' + key;
            }
        }
        String accountId = (String) f.get('accountId');
        if (String.isNotBlank(accountId)) {
            binds.put('accountId', Id.valueOf(accountId));
            cond += ' AND Account__c = :accountId';
        }
        String search = (String) f.get('search');
        if (String.isNotBlank(search)) {
            binds.put('search', '%' + search.trim() + '%');
            cond += ' AND (Title__c LIKE :search OR Account__r.Name LIKE :search OR Name LIKE :search)';
        }
        String sortBy = (String) f.get('sortBy');
        String order = sortBy == 'value' ? 'Value_At_Stake__c DESC NULLS LAST'
            : (sortBy == 'due' ? 'Due_Date__c ASC NULLS LAST' : 'Score__c DESC NULLS LAST');
        return rows(Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ' FROM WR_Pointer__c ' + cond + ' ORDER BY ' + order + ' LIMIT 500',
            binds, AccessLevel.USER_MODE));
    }

    @AuraEnabled
    public static Map<String, Object> getPointer(Id pointerId) {
        WR_Pointer__c p = loadPointer(pointerId);
        List<WR_Account_Profile__c> profiles = [
            SELECT Id, Country__c, Segment__c, Size_Band__c, Knee_Procedures__c, Hip_Procedures__c, Has_Robot__c, Phase__c
            FROM WR_Account_Profile__c WHERE Account__c = :p.Account__c LIMIT 1
        ];
        List<WR_Commitment__c> commitments = [
            SELECT Id, Name, Action__c, Due_Date__c, Status__c, Outcome__c, Owner_User__r.Name, Session__r.Name
            FROM WR_Commitment__c WHERE Pointer__c = :pointerId ORDER BY Due_Date__c
        ];
        Map<String, Object> out = row(p);
        out.put('rationale', p.Rationale__c);
        out.put('evidence', String.isBlank(p.Evidence__c) ? null : JSON.deserializeUntyped(p.Evidence__c));
        out.put('nextBestAction', p.Next_Best_Action__c);
        out.put('aiInsight', String.isBlank(p.AI_Insight__c) ? null : JSON.deserializeUntyped(p.AI_Insight__c));
        out.put('aiGeneratedOn', p.AI_Generated_On__c);
        out.put('decisionComment', p.Decision_Comment__c);
        out.put('decidedBy', p.Decided_By__r?.Name);
        out.put('decidedOn', p.Decided_On__c);
        out.put('ruleDescription', p.Rule__r?.Description__c);
        out.put('opportunityAmount', p.Opportunity__r?.Amount);
        out.put('profile', profiles.isEmpty() ? null : profiles[0]);
        out.put('commitments', commitments);
        out.put('aiConfigured', WinRoomAIService.isConfigured());
        return out;
    }

    @AuraEnabled
    public static Map<String, Object> decidePointer(Id pointerId, String decision, String reason, String comment) {
        if (!new Set<String>{ 'Accepted', 'Rejected', 'New' }.contains(decision)) {
            throw error('Unknown decision: ' + decision);
        }
        if (decision == 'Rejected' && String.isBlank(reason)) {
            throw error('Please select a rejection reason - it is used to improve the rules.');
        }
        WR_Pointer__c p = new WR_Pointer__c(
            Id = pointerId,
            Status__c = decision,
            Rejection_Reason__c = decision == 'Rejected' ? reason : null,
            Decision_Comment__c = comment,
            Decided_By__c = decision == 'New' ? null : UserInfo.getUserId(),
            Decided_On__c = decision == 'New' ? null : Datetime.now()
        );
        update as user p;
        return getPointer(pointerId);
    }

    @AuraEnabled
    public static Map<String, Object> convertToOpportunity(Id pointerId, Decimal amount, Date closeDate) {
        WR_Pointer__c p = loadPointer(pointerId);
        if (p.Opportunity__c != null) {
            throw error('This pointer is already linked to opportunity ' + p.Opportunity__r.Name + '.');
        }
        if (p.Status__c == 'Rejected' || p.Status__c == 'Expired') {
            throw error('Re-open the pointer before creating an opportunity.');
        }
        String name = (Date.today().year() + '-WR-' + p.Account__r.Name + '-' + p.Title__c).left(120);
        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = p.Account__c,
            StageName = firstOpenStage(),
            CloseDate = closeDate != null ? closeDate : Date.today().addDays(90),
            Amount = amount != null ? amount : p.Value_At_Stake__c,
            Description = ('Created from Win Room pointer ' + p.Name + ' (' + p.Type__c + ').\n' + p.Rationale__c).left(32000)
        );
        try {
            insert as user opp;
        } catch (DmlException e) {
            throw error('Opportunity could not be created: ' + e.getDmlMessage(0));
        }
        update as user new WR_Pointer__c(
            Id = pointerId,
            Status__c = 'Converted',
            Opportunity__c = opp.Id,
            Decided_By__c = p.Decided_By__c != null ? p.Decided_By__c : UserInfo.getUserId(),
            Decided_On__c = p.Decided_On__c != null ? p.Decided_On__c : Datetime.now()
        );
        return getPointer(pointerId);
    }

    @AuraEnabled
    public static Map<String, Object> enrichWithAI(Id pointerId) {
        WR_Pointer__c p = loadPointer(pointerId);
        List<WR_Account_Profile__c> profiles = [
            SELECT Country__c, Segment__c, Size_Band__c, Knee_Procedures__c, Hip_Procedures__c, Has_Robot__c
            FROM WR_Account_Profile__c WHERE Account__c = :p.Account__c LIMIT 1
        ];
        WinRoomAIService.Result r = WinRoomAIService.enrichPointer(p, profiles.isEmpty() ? null : profiles[0]);
        Map<String, Object> content = r.content;
        content.put('aiGenerated', r.aiGenerated);
        if (r.error != null) {
            content.put('error', r.error);
        }
        update as user new WR_Pointer__c(
            Id = pointerId, AI_Insight__c = JSON.serialize(content).left(32000), AI_Generated_On__c = Datetime.now()
        );
        return getPointer(pointerId);
    }

    // ================================================================== account 360

    @AuraEnabled
    public static List<Map<String, Object>> searchAccounts(String term) {
        String likeTerm = '%' + (term == null ? '' : term.trim()) + '%';
        Map<Id, Map<String, Object>> out = new Map<Id, Map<String, Object>>();
        for (WR_Account_Profile__c p : [
            SELECT Account__c, Account__r.Name, Country__c, Segment__c, Phase__c, In_Scope__c
            FROM WR_Account_Profile__c
            WHERE Account__c != null AND Account__r.Name LIKE :likeTerm
            ORDER BY In_Scope__c DESC, Account__r.Name
            LIMIT 60
        ]) {
            out.put(p.Account__c, new Map<String, Object>{
                'accountId' => p.Account__c, 'name' => p.Account__r.Name, 'country' => p.Country__c,
                'segment' => p.Segment__c, 'phase' => p.Phase__c, 'inScope' => p.In_Scope__c,
                'openPointers' => 0, 'openValue' => 0
            });
        }
        Set<Id> ids = out.keySet();
        for (AggregateResult ar : [
            SELECT Account__c a, COUNT(Id) n, SUM(Value_At_Stake__c) v FROM WR_Pointer__c
            WHERE Account__c IN :ids AND Status__c IN :OPEN GROUP BY Account__c
        ]) {
            Map<String, Object> row = out.get((Id) ar.get('a'));
            row.put('openPointers', ar.get('n'));
            row.put('openValue', ar.get('v'));
        }
        return out.values();
    }

    @AuraEnabled
    public static Map<String, Object> getAccount360(Id accountId) {
        Account acc = [SELECT Id, Name, BillingCity, BillingCountry, Owner.Name FROM Account WHERE Id = :accountId];
        List<WR_Account_Profile__c> profiles = [
            SELECT Id, Country__c, Segment__c, Size_Band__c, Knee_Procedures__c, Hip_Procedures__c, Phase__c,
                   In_Scope__c, Has_Robot__c, Rep__r.Name
            FROM WR_Account_Profile__c WHERE Account__c = :accountId LIMIT 1
        ];
        Date asOf = WinRoomEngine.defaultAsOf();
        Date fromDate = asOf.addMonths(-24);
        Date yearAgo = asOf.addMonths(-12);

        // Monthly revenue per category for the trend chart.
        List<String> months = new List<String>();
        Map<String, Integer> monthIndex = new Map<String, Integer>();
        for (Integer i = 0; i < 24; i++) {
            Date d = fromDate.addMonths(i);
            monthIndex.put(String.valueOf(d), i);
            months.add(Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('MMM yy'));
        }
        Map<String, List<Decimal>> trend = new Map<String, List<Decimal>>();
        Map<String, Map<String, Object>> lines = new Map<String, Map<String, Object>>();
        // Growth = last 6 months vs the same 6 months a year earlier (works with 18 or 24 months of history).
        Date recentFrom = asOf.addMonths(-6);
        Date lyFrom = asOf.addMonths(-18);
        Decimal last12 = 0;
        Decimal recent6 = 0;
        Decimal ly6 = 0;
        for (AggregateResult ar : [
            SELECT Product_Line__r.Category__c cat, Product_Line__r.Name line, Period__c period,
                   SUM(Revenue__c) rev, SUM(Units__c) u
            FROM WR_Sales__c
            WHERE Account__c = :accountId AND Period__c >= :fromDate AND Period__c < :asOf
            GROUP BY Product_Line__r.Category__c, Product_Line__r.Name, Period__c
        ]) {
            String cat = (String) ar.get('cat');
            String line = (String) ar.get('line');
            Date period = (Date) ar.get('period');
            Decimal rev = (Decimal) ar.get('rev');
            if (!trend.containsKey(cat)) {
                List<Decimal> zeros = new List<Decimal>();
                for (Integer i = 0; i < 24; i++) {
                    zeros.add(0);
                }
                trend.put(cat, zeros);
            }
            Integer idx = monthIndex.get(String.valueOf(period));
            if (idx != null) {
                trend.get(cat)[idx] += rev;
            }
            if (!lines.containsKey(line)) {
                Decimal zero = 0;
                lines.put(line, new Map<String, Object>{ 'line' => line, 'category' => cat, 'last12' => zero, 'units12' => zero,
                    'recent6' => zero, 'ly6' => zero });
            }
            Map<String, Object> l = lines.get(line);
            if (period >= yearAgo) {
                l.put('last12', (Decimal) l.get('last12') + rev);
                l.put('units12', (Decimal) l.get('units12') + (Decimal) ar.get('u'));
                last12 += rev;
            }
            if (period >= recentFrom) {
                l.put('recent6', (Decimal) l.get('recent6') + rev);
                recent6 += rev;
            } else if (period >= lyFrom && period < yearAgo) {
                l.put('ly6', (Decimal) l.get('ly6') + rev);
                ly6 += rev;
            }
        }
        List<Map<String, Object>> series = new List<Map<String, Object>>();
        for (String cat : trend.keySet()) {
            series.add(new Map<String, Object>{ 'label' => cat, 'values' => trend.get(cat) });
        }
        for (Map<String, Object> l : lines.values()) {
            Decimal before = (Decimal) l.get('ly6');
            l.put('growth', before > 0 ? (((Decimal) l.get('recent6') - before) / before) : null);
        }

        List<Map<String, Object>> affiliations = new List<Map<String, Object>>();
        Set<Id> withSales = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Surgeon__c s FROM WR_Sales__c
            WHERE Account__c = :accountId AND Surgeon__c != null AND Period__c >= :yearAgo GROUP BY Surgeon__c
        ]) {
            withSales.add((Id) ar.get('s'));
        }
        for (WR_Affiliation__c af : [
            SELECT Surgeon__c, Surgeon__r.Name, Surgeon__r.Specialty__c, Annual_Procedures__c, Start_Date__c, Primary__c, Source__c
            FROM WR_Affiliation__c WHERE Account__c = :accountId ORDER BY Annual_Procedures__c DESC NULLS LAST
        ]) {
            affiliations.add(new Map<String, Object>{
                'surgeonId' => af.Surgeon__c, 'name' => af.Surgeon__r.Name, 'specialty' => af.Surgeon__r.Specialty__c,
                'procedures' => af.Annual_Procedures__c, 'since' => af.Start_Date__c, 'primary' => af.Primary__c,
                'source' => af.Source__c, 'usesZb' => withSales.contains(af.Surgeon__c)
            });
        }

        List<WR_Pointer__c> pointers = [
            SELECT Id, Name, Title__c, Account__c, Account__r.Name, Country__c, Product_Line__c, Product_Line__r.Name,
                   Surgeon__c, Surgeon__r.Name, Tender__c, Tender__r.Name, Rule__c, Rule__r.Name, Type__c, Category__c,
                   Status__c, Priority__c, Value_At_Stake__c, Score__c, Due_Date__c, Assigned_To__c, Assigned_To__r.Name,
                   Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName, Rejection_Reason__c, Last_Detected__c, CreatedDate
            FROM WR_Pointer__c
            WHERE Account__c = :accountId AND Status__c != 'Expired'
            ORDER BY Score__c DESC NULLS LAST
        ];
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, Amount, CloseDate, Owner.Name
            FROM Opportunity WHERE AccountId = :accountId AND IsClosed = false
            ORDER BY CloseDate LIMIT 20
        ];
        List<WR_Tender__c> tenders = [
            SELECT Id, Name, Reference__c, Category__c, Deadline__c, Estimated_Value__c, Status__c, Source__c
            FROM WR_Tender__c WHERE Account__c = :accountId ORDER BY Deadline__c DESC
        ];
        return new Map<String, Object>{
            'account' => acc,
            'profile' => profiles.isEmpty() ? null : profiles[0],
            'months' => months,
            'series' => series,
            'lines' => lines.values(),
            'last12' => last12,
            'growth6' => ly6 > 0 ? (recent6 - ly6) / ly6 : null,
            'affiliations' => affiliations,
            'pointers' => rows(pointers),
            'opportunities' => opps,
            'tenders' => tenders
        };
    }

    // ================================================================== win room

    @AuraEnabled
    public static List<Map<String, Object>> getSessions(String team) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Session__c s, COUNT(Id) n FROM WR_Commitment__c WHERE Session__c != null GROUP BY Session__c
        ]) {
            counts.put((Id) ar.get('s'), (Integer) ar.get('n'));
        }
        List<WR_Session__c> sessions = String.isBlank(team)
            ? [SELECT Id, Name, Session_Date__c, Team__c, Status__c, Facilitator__r.Name FROM WR_Session__c
               ORDER BY Session_Date__c DESC LIMIT 40]
            : [SELECT Id, Name, Session_Date__c, Team__c, Status__c, Facilitator__r.Name FROM WR_Session__c
               WHERE Team__c = :team ORDER BY Session_Date__c DESC LIMIT 40];
        for (WR_Session__c s : sessions) {
            out.add(new Map<String, Object>{
                'id' => s.Id, 'name' => s.Name, 'date' => s.Session_Date__c, 'team' => s.Team__c,
                'status' => s.Status__c, 'facilitator' => s.Facilitator__r?.Name,
                'commitments' => counts.containsKey(s.Id) ? counts.get(s.Id) : 0
            });
        }
        return out;
    }

    @AuraEnabled
    public static Id createSession(String team, Date sessionDate) {
        if (String.isBlank(team) || sessionDate == null) {
            throw error('Team and date are required.');
        }
        WR_Session__c s = new WR_Session__c(
            Name = 'Win Room ' + team + ' - ' + String.valueOf(sessionDate), Team__c = team,
            Session_Date__c = sessionDate, Facilitator__c = UserInfo.getUserId(), Status__c = 'Planned'
        );
        insert as user s;
        return s.Id;
    }

    /** The "same 7 questions every 7 days" agenda for one session. */
    @AuraEnabled
    public static Map<String, Object> getAgenda(Id sessionId) {
        WR_Session__c s = [
            SELECT Id, Name, Session_Date__c, Team__c, Status__c, Notes__c, Facilitator__r.Name
            FROM WR_Session__c WHERE Id = :sessionId
        ];
        List<WR_Session__c> previous = [
            SELECT Session_Date__c FROM WR_Session__c
            WHERE Team__c = :s.Team__c AND Session_Date__c < :s.Session_Date__c
            ORDER BY Session_Date__c DESC LIMIT 1
        ];
        Date since = previous.isEmpty() ? s.Session_Date__c.addDays(-7) : previous[0].Session_Date__c;
        Datetime sinceDt = Datetime.newInstance(since, Time.newInstance(0, 0, 0, 0));
        Boolean all = s.Team__c == 'All';
        Map<String, Object> binds = new Map<String, Object>{
            'team' => s.Team__c, 'since' => sinceDt, 'today' => Date.today(), 'stuck' => Datetime.now().addDays(-21),
            'openStatuses' => OPEN
        };
        String teamFilter = all ? '' : ' AND Country__c = :team';

        List<WR_Pointer__c> results = Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ', Opportunity__r.IsWon, Opportunity__r.Amount FROM WR_Pointer__c '
            + 'WHERE Opportunity__r.IsClosed = true AND Opportunity__r.LastModifiedDate >= :since' + teamFilter
            + ' ORDER BY Opportunity__r.Amount DESC NULLS LAST LIMIT 20', binds, AccessLevel.USER_MODE);
        List<WR_Pointer__c> fresh = Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ' FROM WR_Pointer__c WHERE Status__c = \'New\' AND CreatedDate >= :since'
            + teamFilter + ' ORDER BY Score__c DESC NULLS LAST LIMIT 15', binds, AccessLevel.USER_MODE);
        if (fresh.isEmpty()) {
            fresh = Database.queryWithBinds(
                'SELECT ' + POINTER_FIELDS + ' FROM WR_Pointer__c WHERE Status__c = \'New\' AND Priority__c = \'High\''
                + teamFilter + ' ORDER BY Score__c DESC NULLS LAST LIMIT 15', binds, AccessLevel.USER_MODE);
        }
        List<WR_Pointer__c> acceptedNoAction = new List<WR_Pointer__c>();
        List<WR_Pointer__c> accepted = Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ' FROM WR_Pointer__c WHERE Status__c = \'Accepted\' AND Opportunity__c = null'
            + teamFilter + ' ORDER BY Score__c DESC NULLS LAST LIMIT 200', binds, AccessLevel.USER_MODE);
        Set<Id> withAction = new Set<Id>();
        for (WR_Commitment__c c : [
            SELECT Pointer__c FROM WR_Commitment__c WHERE Pointer__c IN :accepted AND Status__c = 'Open'
        ]) {
            withAction.add(c.Pointer__c);
        }
        for (WR_Pointer__c p : accepted) {
            if (!withAction.contains(p.Id) && acceptedNoAction.size() < 15) {
                acceptedNoAction.add(p);
            }
        }
        String cTeam = all ? '' : ' AND (Session__r.Team__c = :team OR Pointer__r.Country__c = :team)';
        List<WR_Commitment__c> overdue = Database.queryWithBinds(
            'SELECT Id, Name, Action__c, Due_Date__c, Status__c, Outcome__c, Owner_User__c, Owner_User__r.Name, '
            + 'Account__r.Name, Pointer__c, Pointer__r.Title__c FROM WR_Commitment__c '
            + 'WHERE (Status__c = \'Blocked\' OR (Status__c = \'Open\' AND Due_Date__c < :today))' + cTeam
            + ' ORDER BY Due_Date__c LIMIT 30', binds, AccessLevel.USER_MODE);
        List<WR_Pointer__c> stuck = Database.queryWithBinds(
            'SELECT ' + POINTER_FIELDS + ', Opportunity__r.Amount, Opportunity__r.LastStageChangeDate FROM WR_Pointer__c '
            + 'WHERE Opportunity__c != null AND Opportunity__r.IsClosed = false '
            + 'AND (Opportunity__r.LastStageChangeDate < :stuck OR (Opportunity__r.LastStageChangeDate = null AND Opportunity__r.CreatedDate < :stuck))'
            + teamFilter + ' ORDER BY Opportunity__r.Amount DESC NULLS LAST LIMIT 15', binds, AccessLevel.USER_MODE);
        Date in30 = Date.today().addDays(30);
        binds.put('in30', in30);
        List<WR_Tender__c> tenders = Database.queryWithBinds(
            'SELECT Id, Name, Account__c, Account__r.Name, Category__c, Deadline__c, Estimated_Value__c, Reference__c '
            + 'FROM WR_Tender__c WHERE Status__c = \'Open\' AND Deadline__c >= :today AND Deadline__c <= :in30'
            + teamFilter + ' ORDER BY Deadline__c', binds, AccessLevel.USER_MODE);
        List<WR_Commitment__c> commitments = [
            SELECT Id, Name, Action__c, Due_Date__c, Status__c, Outcome__c, Owner_User__c, Owner_User__r.Name,
                   Account__r.Name, Pointer__c, Pointer__r.Title__c, Opportunity__r.Name
            FROM WR_Commitment__c WHERE Session__c = :sessionId ORDER BY CreatedDate
        ];

        Map<String, Object> kpi = new Map<String, Object>();
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Status__c st, COUNT(Id) n, SUM(Value_At_Stake__c) v FROM WR_Pointer__c WHERE Id != null'
                + teamFilter + ' GROUP BY Status__c', binds, AccessLevel.USER_MODE)) {
            kpi.put((String) ar.get('st'), bucket(ar));
        }
        Decimal wonValue = 0;
        Integer wonCount = 0;
        Integer lostCount = 0;
        for (WR_Pointer__c p : results) {
            if (p.Opportunity__r.IsWon) {
                wonCount++;
                wonValue += p.Opportunity__r.Amount == null ? 0 : p.Opportunity__r.Amount;
            } else {
                lostCount++;
            }
        }
        return new Map<String, Object>{
            'session' => s,
            'since' => since,
            'kpi' => kpi,
            'q1Results' => rows(results),
            'q1Won' => wonCount,
            'q1Lost' => lostCount,
            'q1WonValue' => wonValue,
            'q2New' => rows(fresh),
            'q3AcceptedNoAction' => rows(acceptedNoAction),
            'q4Overdue' => overdue,
            'q5Stuck' => rows(stuck),
            'q6Tenders' => tenders,
            'q7Commitments' => commitments
        };
    }

    @AuraEnabled
    public static Id saveCommitment(String commitmentJson) {
        Map<String, Object> c = (Map<String, Object>) JSON.deserializeUntyped(commitmentJson);
        String action = (String) c.get('action');
        if (String.isBlank(action)) {
            throw error('Describe the action.');
        }
        WR_Commitment__c rec = new WR_Commitment__c(
            Action__c = action.left(255),
            Session__c = idOrNull(c.get('sessionId')),
            Pointer__c = idOrNull(c.get('pointerId')),
            Account__c = idOrNull(c.get('accountId')),
            Owner_User__c = idOrNull(c.get('ownerId')) != null ? idOrNull(c.get('ownerId')) : UserInfo.getUserId(),
            Due_Date__c = c.get('dueDate') == null || String.isBlank((String) c.get('dueDate'))
                ? Date.today().addDays(7) : Date.valueOf((String) c.get('dueDate')),
            Status__c = 'Open'
        );
        if (rec.Pointer__c != null) {
            WR_Pointer__c p = [SELECT Account__c, Opportunity__c, Is_Demo__c FROM WR_Pointer__c WHERE Id = :rec.Pointer__c];
            rec.Account__c = p.Account__c;
            rec.Opportunity__c = p.Opportunity__c;
        }
        insert as user rec;
        return rec.Id;
    }

    @AuraEnabled
    public static void updateCommitment(Id commitmentId, String status, String outcome) {
        update as user new WR_Commitment__c(Id = commitmentId, Status__c = status, Outcome__c = outcome);
    }

    @AuraEnabled
    public static void completeSession(Id sessionId, String notes) {
        update as user new WR_Session__c(Id = sessionId, Status__c = 'Completed', Notes__c = notes);
    }

    @AuraEnabled
    public static void saveSessionNotes(Id sessionId, String notes) {
        update as user new WR_Session__c(Id = sessionId, Notes__c = notes);
    }

    @AuraEnabled
    public static Map<String, Object> sessionBrief(Id sessionId) {
        Map<String, Object> agenda = getAgenda(sessionId);
        WR_Session__c s = (WR_Session__c) agenda.get('session');
        List<String> lines = new List<String>();
        lines.add('Since ' + String.valueOf(agenda.get('since')) + ': won ' + agenda.get('q1Won') + ' ('
            + WinRoomEngine.money((Decimal) agenda.get('q1WonValue')) + '), lost ' + agenda.get('q1Lost'));
        lines.add('Q2 new pointers: ' + summarise((List<Map<String, Object>>) agenda.get('q2New')));
        lines.add('Q3 accepted without action: ' + summarise((List<Map<String, Object>>) agenda.get('q3AcceptedNoAction')));
        List<String> overdue = new List<String>();
        for (WR_Commitment__c c : (List<WR_Commitment__c>) agenda.get('q4Overdue')) {
            overdue.add(c.Action__c + ' (' + c.Owner_User__r?.Name + ', due ' + c.Due_Date__c + ', ' + c.Status__c + ')');
        }
        lines.add('Q4 overdue/blocked commitments: ' + String.join(overdue, '; '));
        lines.add('Q5 stuck opportunities: ' + summarise((List<Map<String, Object>>) agenda.get('q5Stuck')));
        List<String> tenders = new List<String>();
        for (WR_Tender__c t : (List<WR_Tender__c>) agenda.get('q6Tenders')) {
            tenders.add(t.Name + ' at ' + t.Account__r?.Name + ' closes ' + t.Deadline__c + ' (' + WinRoomEngine.money(t.Estimated_Value__c) + ')');
        }
        lines.add('Q6 tenders closing in 30 days: ' + String.join(tenders, '; '));
        WinRoomAIService.Result r = WinRoomAIService.sessionBrief(s.Team__c, String.join(lines, '\n'));
        Map<String, Object> out = r.content;
        out.put('aiGenerated', r.aiGenerated);
        if (r.error != null) {
            out.put('error', r.error);
        }
        return out;
    }

    @AuraEnabled
    public static List<Map<String, Object>> searchUsers(String term) {
        String likeTerm = '%' + (term == null ? '' : term.trim()) + '%';
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (User u : [
            SELECT Id, Name, Title FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Name LIKE :likeTerm ORDER BY Name LIMIT 10
        ]) {
            out.add(new Map<String, Object>{ 'id' => u.Id, 'name' => u.Name, 'title' => u.Title });
        }
        return out;
    }

    // ================================================================== admin

    @AuraEnabled
    public static List<WR_Rule__c> getRules() {
        return [
            SELECT Id, Name, Code__c, Rule_Type__c, Category__c, Active__c, Weight__c, Threshold_Pct__c, Min_Value__c,
                   Lookback_Months__c, Recent_Months__c, Anchor_Lines__c, Target_Lines__c, Expected_Ratio__c,
                   Description__c, Next_Best_Action__c
            FROM WR_Rule__c ORDER BY Category__c, Name
        ];
    }

    @AuraEnabled
    public static List<WR_Product_Line__c> getProductLines() {
        return [
            SELECT Id, Name, Code__c, System__c, Category__c, Component__c, Avg_Price__c, Is_Capital__c, Active__c
            FROM WR_Product_Line__c ORDER BY Sort_Order__c, Name
        ];
    }

    @AuraEnabled
    public static WR_Rule__c saveRule(WR_Rule__c rule) {
        requireAdmin();
        upsert as user rule;
        return rule;
    }

    @AuraEnabled
    public static void resetRules() {
        requireAdmin();
        WinRoomRules.ensureDefaults(true);
    }

    @AuraEnabled
    public static Id runEngine() {
        requireAdmin();
        WinRoomRules.ensureDefaults(false);
        Integer running = [SELECT COUNT() FROM WR_Run__c WHERE Status__c = 'Running' AND CreatedDate = TODAY];
        Integer activeJobs = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name IN ('WinRoomBenchmarkBatch', 'WinRoomEngineBatch', 'WinRoomMockDataBatch')
              AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        if (running > 0 && activeJobs > 0) {
            throw error('An engine run is already in progress.');
        }
        return WinRoomBenchmarkBatch.launch();
    }

    @AuraEnabled
    public static List<WR_Run__c> getRuns() {
        return [
            SELECT Id, Name, Status__c, Started__c, Finished__c, Accounts_Processed__c, Pointers_New__c,
                   Pointers_Updated__c, Pointers_Expired__c, Message__c, CreatedBy.Name
            FROM WR_Run__c ORDER BY CreatedDate DESC LIMIT 15
        ];
    }

    @AuraEnabled
    public static Map<String, Object> getDataStats() {
        return new Map<String, Object>{
            'profiles' => [SELECT COUNT() FROM WR_Account_Profile__c],
            'inScope' => [SELECT COUNT() FROM WR_Account_Profile__c WHERE In_Scope__c = true],
            'sales' => [SELECT COUNT() FROM WR_Sales__c],
            'surgeons' => [SELECT COUNT() FROM WR_Surgeon__c],
            'affiliations' => [SELECT COUNT() FROM WR_Affiliation__c],
            'tenders' => [SELECT COUNT() FROM WR_Tender__c],
            'pointers' => [SELECT COUNT() FROM WR_Pointer__c],
            'sessions' => [SELECT COUNT() FROM WR_Session__c],
            'commitments' => [SELECT COUNT() FROM WR_Commitment__c],
            'productLines' => [SELECT COUNT() FROM WR_Product_Line__c],
            'rules' => [SELECT COUNT() FROM WR_Rule__c],
            'convertedOpportunities' => [SELECT COUNT() FROM WR_Pointer__c WHERE Opportunity__c != null]
        };
    }

    @AuraEnabled
    public static List<WR_Account_Profile__c> getProfiles() {
        return [
            SELECT Id, Name, Account__c, Country__c, Segment__c, Size_Band__c, Knee_Procedures__c, Hip_Procedures__c,
                   Phase__c, In_Scope__c, Has_Robot__c, Rep__c, Rep__r.Name, Is_Demo__c
            FROM WR_Account_Profile__c ORDER BY In_Scope__c DESC, Country__c, Name LIMIT 1000
        ];
    }

    @AuraEnabled
    public static void updateProfile(Id profileId, Boolean inScope, String phase) {
        requireAdmin();
        WR_Account_Profile__c p = new WR_Account_Profile__c(Id = profileId, In_Scope__c = inScope == true);
        if (String.isNotBlank(phase)) {
            p.Phase__c = phase;
        }
        update as user p;
    }

    @AuraEnabled
    public static Id generateMockData(Boolean assignToMe, Boolean runEngine) {
        requireAdmin();
        try {
            return WinRoomMockData.generate(assignToMe == true, runEngine == true);
        } catch (Exception e) {
            throw error('Demo data generation failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id purgeMockData() {
        requireAdmin();
        return WinRoomMockData.purge();
    }

    @AuraEnabled
    public static Map<String, Object> getJobStatus(Id jobId) {
        if (jobId == null) {
            return null;
        }
        AsyncApexJob j = [
            SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus
            FROM AsyncApexJob WHERE Id = :jobId
        ];
        return new Map<String, Object>{
            'status' => j.Status, 'processed' => j.JobItemsProcessed, 'total' => j.TotalJobItems,
            'errors' => j.NumberOfErrors, 'message' => j.ExtendedStatus
        };
    }

    // ================================================================== helpers

    @TestVisible
    static Boolean isAdmin() {
        return FeatureManagement.checkPermission('Win_Room_Admin')
            || [SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId()].PermissionsModifyAllData;
    }

    private static void requireAdmin() {
        if (!isAdmin()) {
            throw error('Only Win Room admins can do this (permission set Win Room Admin).');
        }
    }

    private static WR_Pointer__c loadPointer(Id pointerId) {
        return [
            SELECT Id, Name, Title__c, Account__c, Account__r.Name, Country__c, Product_Line__c, Product_Line__r.Name,
                   Surgeon__c, Surgeon__r.Name, Tender__c, Tender__r.Name, Rule__c, Rule__r.Name, Rule__r.Description__c,
                   Type__c, Category__c, Status__c, Priority__c, Value_At_Stake__c, Score__c, Due_Date__c,
                   Assigned_To__c, Assigned_To__r.Name, Opportunity__c, Opportunity__r.Name, Opportunity__r.StageName,
                   Opportunity__r.Amount, Rejection_Reason__c, Decision_Comment__c, Decided_By__c, Decided_By__r.Name,
                   Decided_On__c, Rationale__c, Evidence__c, Next_Best_Action__c, AI_Insight__c, AI_Generated_On__c,
                   Last_Detected__c, CreatedDate
            FROM WR_Pointer__c WHERE Id = :pointerId
        ];
    }

    /** First open stage of the org's sales process, so the module works with any stage names. */
    @TestVisible
    static String firstOpenStage() {
        List<OpportunityStage> stages = [
            SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
        ];
        return stages.isEmpty() ? 'Prospecting' : stages[0].ApiName;
    }

    private static String baseWhere(String scope, String country) {
        String cond = 'WHERE Id != null';
        if (scope == 'mine') {
            cond += ' AND Assigned_To__c = :userId';
        }
        if (String.isNotBlank(country)) {
            cond += ' AND Country__c = :country';
        }
        return cond;
    }

    private static Map<String, Object> baseBinds(String scope, String country) {
        return new Map<String, Object>{ 'userId' => UserInfo.getUserId(), 'country' => country };
    }

    private static List<Object> groupBy(String field, String cond, Map<String, Object> binds) {
        List<Object> out = new List<Object>();
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT ' + field + ' k, COUNT(Id) n, SUM(Value_At_Stake__c) v FROM WR_Pointer__c ' + cond
                + ' GROUP BY ' + field + ' ORDER BY SUM(Value_At_Stake__c) DESC NULLS LAST', binds, AccessLevel.USER_MODE)) {
            Map<String, Object> b = bucket(ar);
            b.put('label', ar.get('k') == null ? '(none)' : ar.get('k'));
            out.add(b);
        }
        return out;
    }

    private static Map<String, Object> bucket(AggregateResult ar) {
        Decimal v = (Decimal) ar.get('v');
        return new Map<String, Object>{ 'count' => ar.get('n'), 'value' => v == null ? 0 : v };
    }

    private static List<Map<String, Object>> rows(List<WR_Pointer__c> pointers) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (WR_Pointer__c p : pointers) {
            out.add(row(p));
        }
        return out;
    }

    private static Map<String, Object> row(WR_Pointer__c p) {
        return new Map<String, Object>{
            'id' => p.Id,
            'name' => p.Name,
            'title' => p.Title__c,
            'accountId' => p.Account__c,
            'accountName' => p.Account__r?.Name,
            'country' => p.Country__c,
            'productLine' => p.Product_Line__r?.Name,
            'surgeon' => p.Surgeon__r?.Name,
            'tender' => p.Tender__r?.Name,
            'rule' => p.Rule__r?.Name,
            'type' => p.Type__c,
            'category' => p.Category__c,
            'status' => p.Status__c,
            'priority' => p.Priority__c,
            'value' => p.Value_At_Stake__c,
            'score' => p.Score__c,
            'dueDate' => p.Due_Date__c,
            'assignedTo' => p.Assigned_To__r?.Name,
            'assignedToId' => p.Assigned_To__c,
            'opportunityId' => p.Opportunity__c,
            'opportunityName' => p.Opportunity__r?.Name,
            'opportunityStage' => p.Opportunity__r?.StageName,
            'rejectionReason' => p.Rejection_Reason__c,
            'lastDetected' => p.Last_Detected__c,
            'createdDate' => p.CreatedDate
        };
    }

    private static String summarise(List<Map<String, Object>> pointers) {
        List<String> parts = new List<String>();
        for (Map<String, Object> p : pointers) {
            if (parts.size() >= 8) {
                break;
            }
            parts.add(p.get('accountName') + ': ' + p.get('title') + ' (' + WinRoomEngine.money((Decimal) p.get('value')) + ')');
        }
        return parts.isEmpty() ? 'none' : String.join(parts, '; ');
    }

    private static Id idOrNull(Object v) {
        return v == null || String.isBlank(String.valueOf(v)) ? null : Id.valueOf(String.valueOf(v));
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
