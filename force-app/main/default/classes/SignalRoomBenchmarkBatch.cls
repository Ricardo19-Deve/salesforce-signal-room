/**
 * Step 1 of an engine run: builds segment-level peer benchmarks over all profiled
 * accounts (in scope or not), then chains SignalRoomEngineBatch.
 */
public with sharing class SignalRoomBenchmarkBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Id runId;
    private final Date asOf;
    private final SignalRoomEngine.Benchmarks bm = new SignalRoomEngine.Benchmarks();

    public SignalRoomBenchmarkBatch(Id runId) {
        this.runId = runId;
        this.asOf = SignalRoomEngine.defaultAsOf();
    }

    /** Creates a run record and starts the two-step engine. */
    public static Id launch() {
        SR_Run__c run = new SR_Run__c(Status__c = 'Running', Started__c = Datetime.now());
        insert run;
        Database.executeBatch(new SignalRoomBenchmarkBatch(run.Id), 50);
        return run.Id;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(SignalRoomEngine.profileQuery(false));
    }

    public void execute(Database.BatchableContext bc, List<SR_Account_Profile__c> scope) {
        SignalRoomEngine.addToBenchmarks(bm, scope, asOf);
    }

    public void finish(Database.BatchableContext bc) {
        if (!Test.isRunningTest()) {
            Database.executeBatch(new SignalRoomEngineBatch(runId, bm), 5);
        }
    }
}
