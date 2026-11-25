/**
 * Generates (per account profile) or purges (per sales row) Signal Room demo sell-in.
 * Generation optionally chains an engine run so pointers appear right away.
 */
public with sharing class SignalRoomMockDataBatch implements Database.Batchable<SObject>, Database.Stateful {

    private final Boolean purgeMode;
    private final Map<Id, Integer> archetypeByProfile;
    private final Boolean runEngine;
    private final Boolean compact;

    /** Generate mode. */
    public SignalRoomMockDataBatch(Map<Id, Integer> archetypeByProfile, Boolean runEngine, Boolean compact) {
        this.compact = compact == true;
        this.purgeMode = false;
        this.archetypeByProfile = archetypeByProfile;
        this.runEngine = runEngine == true;
    }

    /** Purge mode. */
    public SignalRoomMockDataBatch() {
        this.purgeMode = true;
        this.compact = false;
        this.archetypeByProfile = new Map<Id, Integer>();
        this.runEngine = false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (purgeMode) {
            return Database.getQueryLocator([SELECT Id FROM SR_Sales__c WHERE Is_Demo__c = true]);
        }
        Set<Id> ids = archetypeByProfile.keySet();
        return Database.getQueryLocator([
            SELECT Id, Name, Account__c, Country__c, Knee_Procedures__c, Hip_Procedures__c, Has_Robot__c
            FROM SR_Account_Profile__c WHERE Id IN :ids
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (purgeMode) {
            delete scope;
            return;
        }
        Map<String, SR_Product_Line__c> lines = new Map<String, SR_Product_Line__c>();
        for (SR_Product_Line__c l : [SELECT Id, Code__c, Category__c, Avg_Price__c FROM SR_Product_Line__c]) {
            lines.put(l.Code__c, l);
        }
        Set<Id> accountIds = new Set<Id>();
        for (SObject s : scope) {
            accountIds.add((Id) s.get('Account__c'));
        }
        // Only established primary surgeons carry sales; new and secondary affiliations stay empty on purpose.
        Date established = Date.today().addMonths(-SignalRoomMockData.HISTORY_MONTHS);
        Map<Id, List<SR_Affiliation__c>> surgeons = new Map<Id, List<SR_Affiliation__c>>();
        for (SR_Affiliation__c af : [
            SELECT Account__c, Surgeon__c, Surgeon__r.Specialty__c
            FROM SR_Affiliation__c
            WHERE Account__c IN :accountIds AND Primary__c = true AND Start_Date__c < :established AND Surgeon__c != null
            ORDER BY External_Key__c
        ]) {
            if (!surgeons.containsKey(af.Account__c)) {
                surgeons.put(af.Account__c, new List<SR_Affiliation__c>());
            }
            surgeons.get(af.Account__c).add(af);
        }
        Date asOf = SignalRoomEngine.defaultAsOf();
        List<SR_Sales__c> rows = new List<SR_Sales__c>();
        for (SObject s : scope) {
            SR_Account_Profile__c p = (SR_Account_Profile__c) s;
            List<SR_Affiliation__c> split = surgeons.containsKey(p.Account__c)
                ? surgeons.get(p.Account__c) : new List<SR_Affiliation__c>();
            rows.addAll(SignalRoomMockData.salesFor(p, archetypeByProfile.get(p.Id), lines, split, asOf, compact));
        }
        // Replace, not upsert: months that now have no units (e.g. after real registry volumes shrank the account)
        // must not keep the rows of a previous generation.
        delete [SELECT Id FROM SR_Sales__c WHERE Account__c IN :accountIds AND Is_Demo__c = true];
        insert rows;
    }

    public void finish(Database.BatchableContext bc) {
        if (purgeMode) {
            SignalRoomMockData.purgeSmallObjects();
        } else if (runEngine && !Test.isRunningTest()) {
            SignalRoomBenchmarkBatch.launch();
        }
    }
}
