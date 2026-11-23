/**
 * Generates (per account profile) or purges (per sales row) Win Room demo sell-in.
 * Generation optionally chains an engine run so pointers appear right away.
 */
public with sharing class WinRoomMockDataBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Boolean purgeMode;
    private final Map<Id, Integer> archetypeByProfile;
    private final Boolean runEngine;
    private final Boolean compact;

    /** Generate mode. */
    public WinRoomMockDataBatch(Map<Id, Integer> archetypeByProfile, Boolean runEngine, Boolean compact) {
        this.compact = compact == true;
        this.purgeMode = false;
        this.archetypeByProfile = archetypeByProfile;
        this.runEngine = runEngine == true;
    }

    /** Purge mode. */
    public WinRoomMockDataBatch() {
        this.purgeMode = true;
        this.compact = false;
        this.archetypeByProfile = new Map<Id, Integer>();
        this.runEngine = false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (purgeMode) {
            return Database.getQueryLocator([SELECT Id FROM WR_Sales__c WHERE Is_Demo__c = true]);
        }
        Set<Id> ids = archetypeByProfile.keySet();
        return Database.getQueryLocator([
            SELECT Id, Name, Account__c, Country__c, Knee_Procedures__c, Hip_Procedures__c, Has_Robot__c
            FROM WR_Account_Profile__c WHERE Id IN :ids
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (purgeMode) {
            delete scope;
            return;
        }
        Map<String, WR_Product_Line__c> lines = new Map<String, WR_Product_Line__c>();
        for (WR_Product_Line__c l : [SELECT Id, Code__c, Category__c, Avg_Price__c FROM WR_Product_Line__c]) {
            lines.put(l.Code__c, l);
        }
        Set<Id> accountIds = new Set<Id>();
        for (SObject s : scope) {
            accountIds.add((Id) s.get('Account__c'));
        }
        // Only established primary surgeons carry sales; new and secondary affiliations stay empty on purpose.
        Date established = Date.today().addMonths(-WinRoomMockData.HISTORY_MONTHS);
        Map<Id, List<WR_Affiliation__c>> surgeons = new Map<Id, List<WR_Affiliation__c>>();
        for (WR_Affiliation__c af : [
            SELECT Account__c, Surgeon__c, Surgeon__r.Specialty__c
            FROM WR_Affiliation__c
            WHERE Account__c IN :accountIds AND Primary__c = true AND Start_Date__c < :established AND Surgeon__c != null
            ORDER BY External_Key__c
        ]) {
            if (!surgeons.containsKey(af.Account__c)) {
                surgeons.put(af.Account__c, new List<WR_Affiliation__c>());
            }
            surgeons.get(af.Account__c).add(af);
        }
        Date asOf = WinRoomEngine.defaultAsOf();
        List<WR_Sales__c> rows = new List<WR_Sales__c>();
        for (SObject s : scope) {
            WR_Account_Profile__c p = (WR_Account_Profile__c) s;
            List<WR_Affiliation__c> split = surgeons.containsKey(p.Account__c)
                ? surgeons.get(p.Account__c) : new List<WR_Affiliation__c>();
            rows.addAll(WinRoomMockData.salesFor(p, archetypeByProfile.get(p.Id), lines, split, asOf, compact));
        }
        upsert rows External_Key__c;
    }

    public void finish(Database.BatchableContext bc) {
        if (purgeMode) {
            WinRoomMockData.purgeSmallObjects();
        } else if (runEngine && !Test.isRunningTest()) {
            WinRoomBenchmarkBatch.launch();
        }
    }
}
