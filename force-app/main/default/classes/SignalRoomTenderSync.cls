/**
 * Reads the active tender sources: one batch execute per source (scope 1), so each portal gets its own callout
 * and heap limits. All callouts of a source run before any DML. finish() closes expired notices and matches buyers
 * to accounts. Also schedulable for a daily sync.
 */
public with sharing class SignalRoomTenderSync implements Database.Batchable<String>, Database.AllowsCallouts,
        Database.Stateful, Schedulable {

    public static final String JOB_NAME = 'Signal Room tender sync';
    private static final Integer PCS_MAX_MONTHS = 3;
    /** Find a Tender has no CPV filter: it is read in windows of this many days, one batch item each. */
    private static final Integer FTS_WINDOW_DAYS = 30;

    public Map<String, Integer> totals = new Map<String, Integer>{ 'fetched' => 0, 'stored' => 0 };
    private Map<String, Map<String, Integer>> perSource = new Map<String, Map<String, Integer>>();
    private Set<String> failed = new Set<String>();

    public static Id launch() {
        Integer running = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'SignalRoomTenderSync' AND JobType = 'BatchApex'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        if (running > 0) {
            throw new AuraHandledException('A tender sync is already running.');
        }
        return Database.executeBatch(new SignalRoomTenderSync(), 1);
    }

    public static Boolean isScheduled() {
        return ![SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME LIMIT 1].isEmpty();
    }

    /** Daily at 06:00 (org time zone). */
    public static void schedule(Boolean enabled) {
        for (CronTrigger c : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME]) {
            System.abortJob(c.Id);
        }
        if (enabled) {
            System.schedule(JOB_NAME, '0 0 6 * * ?', new SignalRoomTenderSync());
        }
    }

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new SignalRoomTenderSync(), 1);
    }

    public Iterable<String> start(Database.BatchableContext ctx) {
        Set<String> active = new Set<String>();
        for (SR_Tender_Source__c s : SignalRoomTenders.sources()) {
            if (s.Active__c) {
                active.add(s.Code__c);
            }
        }
        // Work items: "TED", "FTS|<window start>" (oldest first), "PCS". Find a Tender runs before Public Contracts
        // Scotland, so a notice published on both keeps the Find a Tender record.
        List<String> units = new List<String>();
        if (active.contains(SignalRoomTenders.TED)) {
            units.add(SignalRoomTenders.TED);
        }
        if (active.contains(SignalRoomTenders.FTS)) {
            SR_Tender_Source__c fts = [
                SELECT Lookback_Days__c, Last_Run__c FROM SR_Tender_Source__c WHERE Code__c = :SignalRoomTenders.FTS LIMIT 1
            ];
            for (Date d = SignalRoomTenders.fromDate(fts); d <= Date.today(); d = d.addDays(FTS_WINDOW_DAYS)) {
                units.add(SignalRoomTenders.FTS + '|' + String.valueOf(d));
            }
        }
        if (active.contains(SignalRoomTenders.PCS)) {
            units.add(SignalRoomTenders.PCS);
        }
        return units;
    }

    public void execute(Database.BatchableContext ctx, List<String> scope) {
        // Salesforce allows no callout after DML in a transaction: read every portal first, then store.
        List<Fetch> fetches = new List<Fetch>();
        for (String unit : scope) {
            fetches.add(fetchSource(unit));
        }
        for (Fetch f : fetches) {
            save(f);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        SignalRoomTenders.closeExpired();
        SignalRoomTenders.autoMatch();
    }

    /** What one portal returned. */
    public class Fetch {
        public SR_Tender_Source__c source;
        public List<SignalRoomTenders.Notice> notices = new List<SignalRoomTenders.Notice>();
        public Integer fetched = 0;
        public String error;
        /** False for the earlier windows of a source read in several items. */
        public Boolean isLast = true;
    }

    /** Reads one work item of a portal (callouts only, no DML). Errors are kept on the result, never thrown. */
    public Fetch fetchSource(String unit) {
        String code = unit.substringBefore('|');
        Fetch f = new Fetch();
        f.isLast = !unit.contains('|') || Date.valueOf(unit.substringAfter('|')).addDays(FTS_WINDOW_DAYS) > Date.today();
        f.source = [
            SELECT Id, Code__c, CPV_Prefixes__c, Countries__c, Lookback_Days__c, Max_Pages__c, Last_Run__c
            FROM SR_Tender_Source__c WHERE Code__c = :code LIMIT 1
        ];
        SR_Tender_Source__c s = f.source;
        Integer maxPages = s.Max_Pages__c == null || s.Max_Pages__c < 1 ? 5 : Integer.valueOf(s.Max_Pages__c);
        Date since = SignalRoomTenders.fromDate(s);
        List<String> prefixes = SignalRoomTenders.cpvPrefixes(s);
        try {
            Http http = new Http();
            if (code == SignalRoomTenders.TED) {
                for (Integer page = 1; page <= maxPages; page++) {
                    List<Integer> total = new List<Integer>();
                    List<SignalRoomTenders.Notice> batch = SignalRoomTenders.parseTed(
                        send(http, SignalRoomTenders.tedRequest(s, since, page)), total);
                    f.notices.addAll(batch);
                    f.fetched += batch.size();
                    if (batch.isEmpty() || f.fetched >= total[0]) {
                        break;
                    }
                }
            } else if (code == SignalRoomTenders.FTS) {
                Date windowStart = Date.valueOf(unit.substringAfter('|'));
                Date windowEnd = windowStart.addDays(FTS_WINDOW_DAYS);
                String nextUrl;
                for (Integer page = 1; page <= maxPages; page++) {
                    SignalRoomTenders.OcdsPage p = SignalRoomTenders.parseOcds(
                        send(http, SignalRoomTenders.ftsRequest(windowStart, windowEnd, nextUrl)), code, prefixes);
                    f.fetched += p.releases;
                    f.notices.addAll(p.notices);
                    nextUrl = p.nextUrl;
                    if (nextUrl == null) {
                        break;
                    }
                }
            } else if (code == SignalRoomTenders.PCS) {
                Date firstMonth = Date.today().toStartOfMonth().addMonths(1 - PCS_MAX_MONTHS);
                Date month = since.toStartOfMonth() < firstMonth ? firstMonth : since.toStartOfMonth();
                for (Date m = month; m <= Date.today(); m = m.addMonths(1)) {
                    SignalRoomTenders.OcdsPage p = SignalRoomTenders.parseOcds(
                        send(http, SignalRoomTenders.pcsRequest(m)), code, prefixes);
                    f.fetched += p.releases;
                    f.notices.addAll(p.notices);
                }
            }
        } catch (Exception e) {
            f.error = e.getMessage().contains('PKIX')
                ? 'the portal sends an incomplete TLS certificate chain, so Salesforce refuses the connection. '
                  + 'Keep this source inactive; Scottish notices above the threshold also arrive through Find a Tender.'
                : e.getMessage();
        }
        return f;
    }

    /** Stores the notices of one portal and records the outcome on the source. */
    public void save(Fetch f) {
        String code = f.source.Code__c;
        Map<String, Integer> run = perSource.containsKey(code)
            ? perSource.get(code) : new Map<String, Integer>{ 'read' => 0, 'scope' => 0, 'stored' => 0 };
        perSource.put(code, run);
        SR_Tender_Source__c s = new SR_Tender_Source__c(Id = f.source.Id);
        if (f.error != null) {
            failed.add(code);
            s.Last_Status__c = ('Error: ' + f.error).abbreviate(255);
        } else {
            Integer stored = SignalRoomTenders.store(f.notices);
            run.put('read', run.get('read') + f.fetched);
            run.put('scope', run.get('scope') + f.notices.size());
            run.put('stored', run.get('stored') + stored);
            totals.put('fetched', totals.get('fetched') + f.fetched);
            totals.put('stored', totals.get('stored') + stored);
            if (failed.contains(code)) {
                return;
            }
            // The run date only moves forward once every window of the source has been read.
            if (f.isLast) {
                s.Last_Run__c = Datetime.now();
            }
            s.Last_Status__c = ('OK: ' + run.get('read') + ' notices read, ' + run.get('scope') + ' in scope, '
                + run.get('stored') + ' stored').abbreviate(255);
        }
        s.Last_Fetched__c = run.get('read');
        s.Last_Imported__c = run.get('stored');
        update as user s;
    }

    private static String send(Http http, HttpRequest req) {
        HttpResponse res = http.send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException('HTTP ' + res.getStatusCode() + ' from ' + req.getEndpoint().substringBefore('?'));
        }
        return res.getBody();
    }
}
