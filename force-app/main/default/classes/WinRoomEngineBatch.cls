/**
 * Step 2 of an engine run: evaluates the rules for in-scope accounts and saves
 * pointers. Expires undecided pointers that were not detected again.
 */
public with sharing class WinRoomEngineBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Id runId;
    private final WinRoomEngine.Benchmarks bm;
    private final List<WR_Rule__c> rules;
    private Integer accounts = 0;
    private Integer created = 0;
    private Integer updated = 0;
    private List<String> errors = new List<String>();

    public WinRoomEngineBatch(Id runId, WinRoomEngine.Benchmarks bm) {
        this.runId = runId;
        this.bm = bm;
        this.rules = WinRoomRules.activeRules();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(WinRoomEngine.profileQuery(true));
    }

    public void execute(Database.BatchableContext bc, List<WR_Account_Profile__c> scope) {
        try {
            WinRoomEngine engine = new WinRoomEngine(WinRoomEngine.defaultAsOf(), rules, bm).withRun(runId);
            WinRoomEngine.SaveResult sr = engine.save(engine.evaluate(scope));
            accounts += scope.size();
            created += sr.created;
            updated += sr.updated;
            errors.addAll(sr.errors);
        } catch (Exception e) {
            errors.add(e.getTypeName() + ': ' + e.getMessage() + ' @ ' + e.getStackTraceString().left(300));
        }
    }

    public void finish(Database.BatchableContext bc) {
        WR_Run__c run = [SELECT Id, Started__c FROM WR_Run__c WHERE Id = :runId];
        run.Accounts_Processed__c = accounts;
        run.Pointers_New__c = created;
        run.Pointers_Updated__c = updated;
        run.Pointers_Expired__c = WinRoomEngine.expireStale(run.Started__c);
        run.Status__c = errors.isEmpty() ? 'Completed' : 'Failed';
        run.Finished__c = Datetime.now();
        run.Message__c = errors.isEmpty() ? null : String.join(errors, '\n').left(32000);
        update run;
    }
}
