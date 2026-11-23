@IsTest
private class WinRoomTest {

    @TestSetup
    static void setup() {
        // The portal runs in user mode: tests run as a user holding the Win Room admin permission set.
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Username = 'wr.test.' + suffix + '@example.com', Email = 'wr.test@example.com', LastName = 'WinRoomTest',
            Alias = 'wrtest', TimeZoneSidKey = 'Europe/Lisbon', LocaleSidKey = 'en_GB', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', ProfileId = admin.Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Win_Room_Admin'].Id
            );
        }
        System.runAs(u) {
            insert new List<Account>{
                new Account(Name = 'Test Hospital Alpha', BillingCountry = 'GB'),
                new Account(Name = 'Test Hospital Bravo', BillingCountry = 'GB'),
                new Account(Name = 'Test Hospital Charlie', BillingCountry = 'DE'),
                new Account(Name = 'Test Hospital Delta', BillingCountry = 'FR')
            };
        }
    }

    private static User wrUser() {
        return [SELECT Id FROM User WHERE LastName = 'WinRoomTest' AND Username LIKE 'wr.test.%' LIMIT 1];
    }

    /** Generates demo data (sales batch included) and runs the engine synchronously. */
    private static void seedAndRun() {
        Test.startTest();
        WinRoomMockData.generate(true, false);
        Test.stopTest();
        WinRoomEngine.runNow();
    }

    private class OpenAiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String content = JSON.serialize(new Map<String, Object>{
                'why' => 'Volume moved to a competitor.', 'what' => 'Offer a trial.',
                'nextBestActions' => new List<String>{ 'Call the surgeon' },
                'headline' => 'Busy week', 'highlights' => new List<String>{ 'Two tenders' }
            });
            res.setBody(JSON.serialize(new Map<String, Object>{
                'choices' => new List<Object>{ new Map<String, Object>{
                    'message' => new Map<String, Object>{ 'role' => 'assistant', 'content' => content } } }
            }));
            return res;
        }
    }

    @IsTest
    static void mockDataPlantsEveryPatternAndEngineFindsThem() {
        System.runAs(wrUser()) {
            seedAndRun();

            Assert.areEqual(4, [SELECT COUNT() FROM WR_Account_Profile__c]);
            Assert.isTrue([SELECT COUNT() FROM WR_Sales__c] > 0, 'sales generated');
            Assert.areEqual(13, [SELECT COUNT() FROM WR_Rule__c]);

            Set<String> types = new Set<String>();
            for (AggregateResult ar : [SELECT Type__c t FROM WR_Pointer__c GROUP BY Type__c]) {
                types.add((String) ar.get('t'));
            }
            // Archetypes 0-3 are planted on the 4 test accounts.
            Assert.isTrue(types.contains('Win-back soft'), 'soft churn: ' + types);
            Assert.isTrue(types.contains('Win-back hard'), 'hard churn: ' + types);
            Assert.isTrue(types.contains('Partial switch'), 'tibia switch: ' + types);
            Assert.isTrue(types.contains('Cross-sell'), 'patella gap: ' + types);

            WR_Run__c run = [SELECT Status__c, Pointers_New__c FROM WR_Run__c LIMIT 1];
            Assert.areEqual('Completed', run.Status__c);
            Assert.isTrue(run.Pointers_New__c > 0);

            for (WR_Pointer__c p : [SELECT Score__c, Priority__c, Evidence__c, Signature__c, Assigned_To__c FROM WR_Pointer__c]) {
                Assert.isNotNull(p.Priority__c);
                Assert.isNotNull(p.Signature__c);
                Assert.areEqual(UserInfo.getUserId(), p.Assigned_To__c);
                Assert.isTrue(p.Evidence__c.contains('facts'));
            }
        }
    }

    @IsTest
    static void rerunKeepsDecisionsAndDoesNotDuplicate() {
        System.runAs(wrUser()) {
            seedAndRun();
            Integer before = [SELECT COUNT() FROM WR_Pointer__c];
            WR_Pointer__c rejected = [SELECT Id FROM WR_Pointer__c LIMIT 1];
            WinRoomController.decidePointer(rejected.Id, 'Rejected', 'Data incorrect', 'test');

            WinRoomEngine.runNow();

            Assert.areEqual(before, [SELECT COUNT() FROM WR_Pointer__c], 'no duplicates on re-run');
            Assert.areEqual('Rejected', [SELECT Status__c FROM WR_Pointer__c WHERE Id = :rejected.Id].Status__c);
        }
    }

    @IsTest
    static void controllerReadApis() {
        System.runAs(wrUser()) {
            seedAndRun();
            Map<String, Object> ctx = WinRoomController.getContext();
            Assert.isTrue((Boolean) ctx.get('isAdmin'));

            Map<String, Object> dash = WinRoomController.getDashboard('all', null);
            Assert.isFalse(((List<Object>) dash.get('byCategory')).isEmpty());
            WinRoomController.getDashboard('mine', 'GB');

            List<Map<String, Object>> rows = WinRoomController.getPointers(JSON.serialize(new Map<String, Object>{
                'scope' => 'all', 'status' => 'Open', 'sortBy' => 'value'
            }));
            Assert.isFalse(rows.isEmpty());
            WinRoomController.getPointers(JSON.serialize(new Map<String, Object>{
                'status' => 'All', 'category' => 'Win back', 'priority' => 'High', 'search' => 'Meridian', 'sortBy' => 'due'
            }));
            Map<String, Object> detail = WinRoomController.getPointer((Id) rows[0].get('id'));
            Assert.isNotNull(detail.get('evidence'));

            Id accountId = (Id) rows[0].get('accountId');
            Assert.isFalse(WinRoomController.searchAccounts('Test').isEmpty());
            Map<String, Object> a360 = WinRoomController.getAccount360(accountId);
            Assert.isFalse(((List<Object>) a360.get('series')).isEmpty());

            Assert.areEqual(13, WinRoomController.getRules().size());
            Assert.areEqual(13, WinRoomController.getProductLines().size());
            Assert.isFalse(WinRoomController.getProfiles().isEmpty());
            Assert.isTrue((Integer) WinRoomController.getDataStats().get('sales') > 0);
            Assert.isFalse(WinRoomController.getRuns().isEmpty());
            Assert.isNotNull(WinRoomController.searchUsers(UserInfo.getLastName()));
        }
    }

    @IsTest
    static void pointerLifecycle() {
        System.runAs(wrUser()) {
            seedAndRun();
            WR_Pointer__c p = [SELECT Id FROM WR_Pointer__c ORDER BY Score__c DESC LIMIT 1];

            try {
                WinRoomController.decidePointer(p.Id, 'Rejected', null, null);
                Assert.fail('reason is required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('rejection reason'));
            }
            Map<String, Object> accepted = WinRoomController.decidePointer(p.Id, 'Accepted', null, 'go');
            Assert.areEqual('Accepted', accepted.get('status'));

            Map<String, Object> enriched = WinRoomController.enrichWithAI(p.Id);
            Map<String, Object> insight = (Map<String, Object>) enriched.get('aiInsight');
            Assert.isNotNull(insight.get('why'));

            try {
                Map<String, Object> converted = WinRoomController.convertToOpportunity(p.Id, 50000, Date.today().addDays(60));
                Assert.areEqual('Converted', converted.get('status'));
                Assert.isNotNull(converted.get('opportunityId'));
            } catch (AuraHandledException e) {
                // Org opportunity automation (validation rules, flows) may reject the insert; the message must explain why.
                Assert.isTrue(e.getMessage().contains('Opportunity could not be created'));
            }
        }
    }

    @IsTest
    static void aiServiceParsesModelResponse() {
        System.runAs(wrUser()) {
            // Pretend the Win_Room_LLM named credential exists; the HTTP response is mocked.
            WinRoomAIService.forceConfigured = true;
            Test.setMock(HttpCalloutMock.class, new OpenAiMock());
            Test.startTest();
            WR_Pointer__c p = new WR_Pointer__c(
                Title__c = 'Partial switch: Meridian Tibial Tray', Type__c = 'Partial switch', Category__c = 'Win back',
                Value_At_Stake__c = 50000, Rationale__c = 'Tibia trays dropped.', Next_Best_Action__c = 'Call. Visit.'
            );
            WinRoomAIService.Result r = WinRoomAIService.enrichPointer(p, null);
            WinRoomAIService.Result b = WinRoomAIService.sessionBrief('GB', 'agenda');
            Test.stopTest();
            Assert.isTrue(r.aiGenerated, 'AI error: ' + r.error);
            Assert.areEqual('Volume moved to a competitor.', r.content.get('why'));
            Assert.areEqual('Busy week', b.content.get('headline'));
            Assert.isTrue(WinRoomAIService.isConfigured());
        }
    }

    @IsTest
    static void aiFallbackWithoutKey() {
        System.runAs(wrUser()) {
            seedAndRun();
            WR_Pointer__c p = [SELECT Id FROM WR_Pointer__c LIMIT 1];
            Map<String, Object> enriched = WinRoomController.enrichWithAI(p.Id);
            Map<String, Object> insight = (Map<String, Object>) enriched.get('aiInsight');
            Assert.areEqual(false, insight.get('aiGenerated'));
            Assert.isNotNull(insight.get('why'));
        }
    }

    @IsTest
    static void winRoomSessionFlow() {
        System.runAs(wrUser()) {
            seedAndRun();
            List<Map<String, Object>> sessions = WinRoomController.getSessions('GB');
            Assert.areEqual(2, sessions.size());
            Id sessionId = WinRoomController.createSession('GB', Date.today());
            WR_Pointer__c p = [SELECT Id FROM WR_Pointer__c WHERE Country__c = 'GB' LIMIT 1];
            WinRoomController.decidePointer(p.Id, 'Accepted', null, null);

            Map<String, Object> agenda = WinRoomController.getAgenda(sessionId);
            Assert.isFalse(((List<Object>) agenda.get('q3AcceptedNoAction')).isEmpty(), 'accepted pointer without action');

            Id commitmentId = WinRoomController.saveCommitment(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId, 'pointerId' => p.Id, 'action' => 'Call the head of orthopaedics',
                'dueDate' => String.valueOf(Date.today().addDays(-1))
            }));
            agenda = WinRoomController.getAgenda(sessionId);
            Assert.areEqual(1, ((List<Object>) agenda.get('q7Commitments')).size());
            Assert.areEqual(1, ((List<Object>) agenda.get('q4Overdue')).size());

            WinRoomController.updateCommitment(commitmentId, 'Done', 'Meeting booked');
            WinRoomController.saveSessionNotes(sessionId, 'notes');
            Map<String, Object> brief = WinRoomController.sessionBrief(sessionId);
            Assert.isNotNull(brief.get('headline'));
            WinRoomController.completeSession(sessionId, 'done');
            Assert.areEqual('Completed', [SELECT Status__c FROM WR_Session__c WHERE Id = :sessionId].Status__c);
            Id allTeamsSession = WinRoomController.createSession('All', Date.today());
            Assert.isNotNull(WinRoomController.getAgenda(allTeamsSession).get('kpi'));
        }
    }

    @IsTest
    static void adminApis() {
        System.runAs(wrUser()) {
            Test.startTest();
            WinRoomController.resetRules();
            WR_Rule__c rule = WinRoomController.getRules()[0];
            rule.Threshold_Pct__c = 40;
            WinRoomController.saveRule(rule);
            Id runId = WinRoomController.runEngine();
            Test.stopTest();
            Assert.isNotNull(runId);
            Assert.areEqual(40, [SELECT Threshold_Pct__c FROM WR_Rule__c WHERE Id = :rule.Id].Threshold_Pct__c);
        }
    }

    @IsTest
    static void profileScopeAndJobStatus() {
        System.runAs(wrUser()) {
            Test.startTest();
            Id jobId = WinRoomController.generateMockData(true, true);
            Test.stopTest();
            Assert.isNotNull(WinRoomController.getJobStatus(jobId));
            WR_Account_Profile__c p = [SELECT Id FROM WR_Account_Profile__c LIMIT 1];
            WinRoomController.updateProfile(p.Id, false, 'Phase 3');
            Assert.areEqual('Phase 3', [SELECT Phase__c FROM WR_Account_Profile__c WHERE Id = :p.Id].Phase__c);
        }
    }

    @IsTest
    static void batchesRunEndToEnd() {
        System.runAs(wrUser()) {
            Test.startTest();
            WinRoomMockData.generate(false, false);
            Test.stopTest();
            WR_Run__c run = new WR_Run__c(Status__c = 'Running', Started__c = Datetime.now().addSeconds(-1));
            insert run;
            WinRoomEngine.Benchmarks bm = new WinRoomEngine.Benchmarks();
            WinRoomEngine.addToBenchmarks(bm, Database.query(WinRoomEngine.profileQuery(false)), WinRoomEngine.defaultAsOf());
            WinRoomEngineBatch batch = new WinRoomEngineBatch(run.Id, bm);
            batch.execute(null, Database.query(WinRoomEngine.profileQuery(true)));
            batch.finish(null);
            Assert.areEqual('Completed', [SELECT Status__c FROM WR_Run__c WHERE Id = :run.Id].Status__c);

            WinRoomBenchmarkBatch bb = new WinRoomBenchmarkBatch(run.Id);
            bb.execute(null, Database.query(WinRoomEngine.profileQuery(false)));
            bb.finish(null);
        }
    }

    @IsTest
    static void purgeRemovesDemoData() {
        System.runAs(wrUser()) {
            WinRoomMockData.Rng rng = new WinRoomMockData.Rng(UserInfo.getUserId());
            Assert.isTrue(rng.between(1, 3) >= 1);
            WinRoomRules.ensureDefaults(false);
            Account a = [SELECT Id FROM Account LIMIT 1];
            insert new WR_Account_Profile__c(Name = 'x', Account__c = a.Id, Account_Key__c = a.Id, Is_Demo__c = true);
            Test.startTest();
            WinRoomController.purgeMockData();
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM WR_Account_Profile__c]);
        }
    }

    @IsTest
    static void scoringIsBounded() {
        System.runAs(wrUser()) {
            Assert.isTrue(WinRoomEngine.score(0, 1, 0) >= 0);
            Assert.isTrue(WinRoomEngine.score(100000000, 5, 100) <= 100);
            Assert.areEqual(0.55, WinRoomMockData.pattern(0, 'KNEE_FEM', 2));
            Assert.areEqual(1, WinRoomMockData.pattern(7, 'KNEE_FEM', 2));
        }
    }
}
