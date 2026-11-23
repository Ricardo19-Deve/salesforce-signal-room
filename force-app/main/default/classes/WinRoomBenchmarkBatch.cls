/**
 * Step 1 of an engine run: builds segment-level peer benchmarks over all profiled
 * accounts (in scope or not), then chains WinRoomEngineBatch.
 */
public with sharing class WinRoomBenchmarkBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Id runId;
    private final Date asOf;
    private final WinRoomEngine.Benchmarks bm = new WinRoomEngine.Benchmarks();

    public WinRoomBenchmarkBatch(Id runId) {
        this.runId = runId;
        this.asOf = WinRoomEngine.defaultAsOf();
    }

    /** Creates a run record and starts the two-step engine. */
    public static Id launch() {
        WR_Run__c run = new WR_Run__c(Status__c = 'Running', Started__c = Datetime.now());
        insert run;
        Database.executeBatch(new WinRoomBenchmarkBatch(run.Id), 50);
        return run.Id;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(WinRoomEngine.profileQuery(false));
    }

    public void execute(Database.BatchableContext bc, List<WR_Account_Profile__c> scope) {
        WinRoomEngine.addToBenchmarks(bm, scope, asOf);
    }

    public void finish(Database.BatchableContext bc) {
        if (!Test.isRunningTest()) {
            Database.executeBatch(new WinRoomEngineBatch(runId, bm), 5);
        }
    }
}
