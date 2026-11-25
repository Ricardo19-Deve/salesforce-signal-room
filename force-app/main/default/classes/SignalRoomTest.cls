@IsTest
private class SignalRoomTest {

    @TestSetup
    static void setup() {
        // The portal runs in user mode: tests run as a user holding the Signal Room admin permission set.
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Username = 'sr.test.' + suffix + '@example.com', Email = 'sr.test@example.com', LastName = 'SignalRoomTest',
            Alias = 'srtest', TimeZoneSidKey = 'Europe/Lisbon', LocaleSidKey = 'en_GB', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', ProfileId = admin.Id
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Signal_Room_Admin'].Id
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

    private static User srUser() {
        return [SELECT Id FROM User WHERE LastName = 'SignalRoomTest' AND Username LIKE 'sr.test.%' LIMIT 1];
    }

    /** Generates demo data (sales batch included) and runs the engine synchronously. */
    private static void seedAndRun() {
        Test.startTest();
        SignalRoomMockData.generate(true, false);
        Test.stopTest();
        SignalRoomEngine.runNow();
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
        System.runAs(srUser()) {
            seedAndRun();

            Assert.areEqual(4, [SELECT COUNT() FROM SR_Account_Profile__c]);
            Assert.isTrue([SELECT COUNT() FROM SR_Sales__c] > 0, 'sales generated');
            Assert.areEqual(SignalRoomRules.defaultRules().size(), [SELECT COUNT() FROM SR_Rule__c]);

            Set<String> types = new Set<String>();
            for (AggregateResult ar : [SELECT Type__c t FROM SR_Pointer__c GROUP BY Type__c]) {
                types.add((String) ar.get('t'));
            }
            // Archetypes 0-3 are planted on the 4 test accounts.
            Assert.isTrue(types.contains('Win-back soft'), 'soft churn: ' + types);
            Assert.isTrue(types.contains('Win-back hard'), 'hard churn: ' + types);
            Assert.isTrue(types.contains('Partial switch'), 'tibia switch: ' + types);
            Assert.isTrue(types.contains('Cross-sell'), 'patella gap: ' + types);

            SR_Run__c run = [SELECT Status__c, Pointers_New__c FROM SR_Run__c LIMIT 1];
            Assert.areEqual('Completed', run.Status__c);
            Assert.isTrue(run.Pointers_New__c > 0);

            for (SR_Pointer__c p : [SELECT Score__c, Priority__c, Evidence__c, Signature__c, Assigned_To__c FROM SR_Pointer__c]) {
                Assert.isNotNull(p.Priority__c);
                Assert.isNotNull(p.Signature__c);
                Assert.areEqual(UserInfo.getUserId(), p.Assigned_To__c);
                Assert.isTrue(p.Evidence__c.contains('facts'));
            }
        }
    }

    @IsTest
    static void rerunKeepsDecisionsAndDoesNotDuplicate() {
        System.runAs(srUser()) {
            seedAndRun();
            Integer before = [SELECT COUNT() FROM SR_Pointer__c];
            SR_Pointer__c rejected = [SELECT Id FROM SR_Pointer__c LIMIT 1];
            SignalRoomController.decidePointer(rejected.Id, 'Rejected', 'Data incorrect', 'test');

            SignalRoomEngine.runNow();

            Assert.areEqual(before, [SELECT COUNT() FROM SR_Pointer__c], 'no duplicates on re-run');
            Assert.areEqual('Rejected', [SELECT Status__c FROM SR_Pointer__c WHERE Id = :rejected.Id].Status__c);
        }
    }

    @IsTest
    static void controllerReadApis() {
        System.runAs(srUser()) {
            seedAndRun();
            Map<String, Object> ctx = SignalRoomController.getContext();
            Assert.isTrue((Boolean) ctx.get('isAdmin'));

            Map<String, Object> dash = SignalRoomController.getDashboard('all', null);
            Assert.isFalse(((List<Object>) dash.get('byCategory')).isEmpty());
            SignalRoomController.getDashboard('mine', 'GB');

            List<Map<String, Object>> rows = SignalRoomController.getPointers(JSON.serialize(new Map<String, Object>{
                'scope' => 'all', 'status' => 'Open', 'sortBy' => 'value'
            }));
            Assert.isFalse(rows.isEmpty());
            SignalRoomController.getPointers(JSON.serialize(new Map<String, Object>{
                'status' => 'All', 'category' => 'Win back', 'priority' => 'High', 'search' => 'Meridian', 'sortBy' => 'due'
            }));
            Map<String, Object> detail = SignalRoomController.getPointer((Id) rows[0].get('id'));
            Assert.isNotNull(detail.get('evidence'));

            Id accountId = (Id) rows[0].get('accountId');
            Assert.isFalse(SignalRoomController.searchAccounts('Test').isEmpty());
            Map<String, Object> a360 = SignalRoomController.getAccount360(accountId);
            Assert.isFalse(((List<Object>) a360.get('series')).isEmpty());

            Assert.areEqual(SignalRoomRules.defaultRules().size(), SignalRoomController.getRules().size());
            Assert.areEqual(13, SignalRoomController.getProductLines().size());
            Assert.isFalse(SignalRoomController.getProfiles().isEmpty());
            Assert.isTrue((Integer) SignalRoomController.getDataStats().get('sales') > 0);
            Assert.isFalse(SignalRoomController.getRuns().isEmpty());
            Assert.isNotNull(SignalRoomController.searchUsers(UserInfo.getLastName()));
        }
    }

    @IsTest
    static void pointerLifecycle() {
        System.runAs(srUser()) {
            seedAndRun();
            SR_Pointer__c p = [SELECT Id FROM SR_Pointer__c ORDER BY Score__c DESC LIMIT 1];

            try {
                SignalRoomController.decidePointer(p.Id, 'Rejected', null, null);
                Assert.fail('reason is required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('rejection reason'));
            }
            Map<String, Object> accepted = SignalRoomController.decidePointer(p.Id, 'Accepted', null, 'go');
            Assert.areEqual('Accepted', accepted.get('status'));

            Map<String, Object> enriched = SignalRoomController.enrichWithAI(p.Id);
            Map<String, Object> insight = (Map<String, Object>) enriched.get('aiInsight');
            Assert.isNotNull(insight.get('why'));

            try {
                Map<String, Object> converted = SignalRoomController.convertToOpportunity(p.Id, 50000, Date.today().addDays(60));
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
        System.runAs(srUser()) {
            // Pretend the Signal_Room_LLM named credential exists; the HTTP response is mocked.
            SignalRoomAIService.forceConfigured = true;
            Test.setMock(HttpCalloutMock.class, new OpenAiMock());
            Test.startTest();
            SR_Pointer__c p = new SR_Pointer__c(
                Title__c = 'Partial switch: Meridian Tibial Tray', Type__c = 'Partial switch', Category__c = 'Win back',
                Value_At_Stake__c = 50000, Rationale__c = 'Tibia trays dropped.', Next_Best_Action__c = 'Call. Visit.'
            );
            SignalRoomAIService.Result r = SignalRoomAIService.enrichPointer(p, null);
            SignalRoomAIService.Result b = SignalRoomAIService.sessionBrief('GB', 'agenda');
            Test.stopTest();
            Assert.isTrue(r.aiGenerated, 'AI error: ' + r.error);
            Assert.areEqual('Volume moved to a competitor.', r.content.get('why'));
            Assert.areEqual('Busy week', b.content.get('headline'));
            Assert.isTrue(SignalRoomAIService.isConfigured());
        }
    }

    @IsTest
    static void aiFallbackWithoutKey() {
        System.runAs(srUser()) {
            seedAndRun();
            SR_Pointer__c p = [SELECT Id FROM SR_Pointer__c LIMIT 1];
            Map<String, Object> enriched = SignalRoomController.enrichWithAI(p.Id);
            Map<String, Object> insight = (Map<String, Object>) enriched.get('aiInsight');
            Assert.areEqual(false, insight.get('aiGenerated'));
            Assert.isNotNull(insight.get('why'));
        }
    }

    @IsTest
    static void signalRoomSessionFlow() {
        System.runAs(srUser()) {
            seedAndRun();
            List<Map<String, Object>> sessions = SignalRoomController.getSessions('GB');
            Assert.areEqual(2, sessions.size());
            Id sessionId = SignalRoomController.createSession('GB', Date.today());
            SR_Pointer__c p = [SELECT Id FROM SR_Pointer__c WHERE Country__c = 'GB' LIMIT 1];
            SignalRoomController.decidePointer(p.Id, 'Accepted', null, null);

            Map<String, Object> agenda = SignalRoomController.getAgenda(sessionId);
            Assert.isFalse(((List<Object>) agenda.get('q3AcceptedNoAction')).isEmpty(), 'accepted pointer without action');

            Id commitmentId = SignalRoomController.saveCommitment(JSON.serialize(new Map<String, Object>{
                'sessionId' => sessionId, 'pointerId' => p.Id, 'action' => 'Call the head of orthopaedics',
                'dueDate' => String.valueOf(Date.today().addDays(-1))
            }));
            agenda = SignalRoomController.getAgenda(sessionId);
            Assert.areEqual(1, ((List<Object>) agenda.get('q7Commitments')).size());
            Assert.areEqual(1, ((List<Object>) agenda.get('q4Overdue')).size());

            SignalRoomController.updateCommitment(commitmentId, 'Done', 'Meeting booked');
            SignalRoomController.saveSessionNotes(sessionId, 'notes');
            Map<String, Object> brief = SignalRoomController.sessionBrief(sessionId);
            Assert.isNotNull(brief.get('headline'));
            SignalRoomController.completeSession(sessionId, 'done');
            Assert.areEqual('Completed', [SELECT Status__c FROM SR_Session__c WHERE Id = :sessionId].Status__c);
            Id allTeamsSession = SignalRoomController.createSession('All', Date.today());
            Assert.isNotNull(SignalRoomController.getAgenda(allTeamsSession).get('kpi'));
        }
    }

    @IsTest
    static void adminApis() {
        System.runAs(srUser()) {
            Test.startTest();
            SignalRoomController.resetRules();
            SR_Rule__c rule = SignalRoomController.getRules()[0];
            rule.Threshold_Pct__c = 40;
            SignalRoomController.saveRule(rule);
            Id runId = SignalRoomController.runEngine();
            Test.stopTest();
            Assert.isNotNull(runId);
            Assert.areEqual(40, [SELECT Threshold_Pct__c FROM SR_Rule__c WHERE Id = :rule.Id].Threshold_Pct__c);
        }
    }

    @IsTest
    static void profileScopeAndJobStatus() {
        System.runAs(srUser()) {
            Test.startTest();
            Id jobId = SignalRoomController.generateMockData(true, true);
            Test.stopTest();
            Assert.isNotNull(SignalRoomController.getJobStatus(jobId));
            SR_Account_Profile__c p = [SELECT Id FROM SR_Account_Profile__c LIMIT 1];
            SignalRoomController.updateProfile(p.Id, false, 'Phase 3');
            Assert.areEqual('Phase 3', [SELECT Phase__c FROM SR_Account_Profile__c WHERE Id = :p.Id].Phase__c);
        }
    }

    @IsTest
    static void batchesRunEndToEnd() {
        System.runAs(srUser()) {
            Test.startTest();
            SignalRoomMockData.generate(false, false);
            Test.stopTest();
            SR_Run__c run = new SR_Run__c(Status__c = 'Running', Started__c = Datetime.now().addSeconds(-1));
            insert run;
            SignalRoomEngine.Benchmarks bm = new SignalRoomEngine.Benchmarks();
            SignalRoomEngine.addToBenchmarks(bm, Database.query(SignalRoomEngine.profileQuery(false)), SignalRoomEngine.defaultAsOf());
            SignalRoomEngineBatch batch = new SignalRoomEngineBatch(run.Id, bm);
            batch.execute(null, Database.query(SignalRoomEngine.profileQuery(true)));
            batch.finish(null);
            Assert.areEqual('Completed', [SELECT Status__c FROM SR_Run__c WHERE Id = :run.Id].Status__c);

            SignalRoomBenchmarkBatch bb = new SignalRoomBenchmarkBatch(run.Id);
            bb.execute(null, Database.query(SignalRoomEngine.profileQuery(false)));
            bb.finish(null);
        }
    }

    @IsTest
    static void purgeRemovesDemoData() {
        System.runAs(srUser()) {
            SignalRoomMockData.Rng rng = new SignalRoomMockData.Rng(UserInfo.getUserId());
            Assert.isTrue(rng.between(1, 3) >= 1);
            SignalRoomRules.ensureDefaults(false);
            Account a = [SELECT Id FROM Account LIMIT 1];
            insert new SR_Account_Profile__c(Name = 'x', Account__c = a.Id, Account_Key__c = a.Id, Is_Demo__c = true);
            Test.startTest();
            SignalRoomController.purgeMockData();
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM SR_Account_Profile__c]);
        }
    }

    @IsTest
    static void scoringIsBounded() {
        System.runAs(srUser()) {
            Assert.isTrue(SignalRoomEngine.score(0, 1, 0) >= 0);
            Assert.isTrue(SignalRoomEngine.score(100000000, 5, 100) <= 100);
            Assert.areEqual(0.55, SignalRoomMockData.pattern(0, 'KNEE_FEM', 2));
            Assert.areEqual(1, SignalRoomMockData.pattern(7, 'KNEE_FEM', 2));
        }
    }

    // ------------------------------------------------------------------ contracts

    @IsTest
    static void contractsTrackComplianceAndRaisePointers() {
        System.runAs(srUser()) {
            seedAndRun();
            // Archetypes 0 (soft churn) and 2 (tibia switch) get demo contracts that under-deliver.
            Assert.areEqual(2, [SELECT COUNT() FROM SR_Contract__c]);
            Map<String, Object> view = SignalRoomController.getContracts(null);
            Map<String, Integer> byHealth = (Map<String, Integer>) view.get('byHealth');
            Assert.isTrue(byHealth.get('Under') >= 1, 'under-delivering contract: ' + byHealth);
            Assert.isFalse([SELECT Id FROM SR_Pointer__c WHERE Type__c = 'Contract shortfall'].isEmpty(), 'shortfall pointer');

            SR_Contract__c c = [SELECT Id FROM SR_Contract__c LIMIT 1];
            Map<String, Object> detail = SignalRoomController.getContract(c.Id);
            SignalRoomContracts.ContractResult r = (SignalRoomContracts.ContractResult) detail.get('contract');
            Assert.isFalse(r.lines.isEmpty());
            Assert.areEqual(r.lines[0].months.size(), r.lines[0].delivered.size());
            Assert.isNotNull(r.compliancePct);
            SignalRoomController.getContracts(JSON.serialize(new Map<String, Object>{ 'health' => 'Renewal', 'search' => 'agreement' }));
        }
    }

    @IsTest
    static void contractEditorAndRenewal() {
        System.runAs(srUser()) {
            seedAndRun();
            Account a = [SELECT Id FROM Account WHERE Name = 'Test Hospital Charlie'];
            SR_Product_Line__c cup = [SELECT Id FROM SR_Product_Line__c WHERE Code__c = 'HIP_CUP'];
            try {
                SignalRoomController.saveContract(JSON.serialize(new Map<String, Object>{
                    'contract' => new Map<String, Object>{ 'name' => 'x' }, 'lines' => new List<Object>()
                }));
                Assert.fail('account and dates are required');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('required'));
            }
            Id contractId = SignalRoomController.saveContract(JSON.serialize(new Map<String, Object>{
                'contract' => new Map<String, Object>{
                    'name' => 'Hip framework', 'reference' => 'TEST-1', 'accountId' => a.Id,
                    'startDate' => String.valueOf(Date.today().addMonths(-30)), 'endDate' => String.valueOf(Date.today().addMonths(3)),
                    'status' => 'Active', 'tolerance' => 10
                },
                'lines' => new List<Object>{ new Map<String, Object>{ 'productLineId' => cup.Id, 'label' => 'Primary hips', 'monthlyQty' => 10, 'unitPrice' => 900 } },
                'deletedLineIds' => new List<Object>()
            }));
            SignalRoomEngine.runNow();
            Assert.isFalse([SELECT Id FROM SR_Pointer__c WHERE Type__c = 'Contract renewal' AND Contract__c = :contractId].isEmpty(), 'renewal pointer');

            SR_Contract_Line__c line = [SELECT Id FROM SR_Contract_Line__c WHERE Contract__c = :contractId];
            SignalRoomController.saveContract(JSON.serialize(new Map<String, Object>{
                'contract' => new Map<String, Object>{
                    'id' => contractId, 'name' => 'Hip framework', 'accountId' => a.Id,
                    'startDate' => String.valueOf(Date.today().addMonths(-30)), 'endDate' => String.valueOf(Date.today().addMonths(3))
                },
                'lines' => new List<Object>(),
                'deletedLineIds' => new List<Object>{ line.Id }
            }));
            Assert.areEqual(0, [SELECT COUNT() FROM SR_Contract_Line__c WHERE Contract__c = :contractId]);
            SignalRoomController.deleteContract(contractId);
            Assert.areEqual(0, [SELECT COUNT() FROM SR_Contract__c WHERE Id = :contractId]);
        }
    }

    // ------------------------------------------------------------------ market (registry)

    private static String sitesJson() {
        List<Object> sites = new List<Object>();
        List<String> months = new List<String>{ 'Jan 26', 'Feb 26' };
        sites.add(new Map<String, Object>{
            'key' => 'NHS|R1|Test Hospital Alpha', 'name' => 'Test Hospital Alpha', 'providerType' => 'NHS', 'orgCode' => 'R1',
            'orgName' => 'Alpha NHS Foundation Trust', 'region' => 'London', 'hip12' => 400, 'knee12' => 500, 'hipPrior' => 380,
            'kneePrior' => 450, 'total12' => 950, 'months' => months, 'hip' => new List<Integer>{ 30, 35 },
            'knee' => new List<Integer>{ 40, 42 }, 'asOf' => '2026-10-01'
        });
        sites.add(new Map<String, Object>{
            'key' => 'NHS|R2|Bravo Community Site', 'name' => 'Bravo Community Site', 'providerType' => 'NHS', 'orgCode' => 'R2',
            'orgName' => 'Somewhere Else Trust', 'region' => 'London', 'hip12' => 100, 'knee12' => 80, 'hipPrior' => 90,
            'kneePrior' => 70, 'total12' => 190, 'months' => months, 'hip' => new List<Integer>{ 8, 9 },
            'knee' => new List<Integer>{ 6, 7 }, 'asOf' => '2026-10-01'
        });
        sites.add(new Map<String, Object>{
            'key' => 'Independent Sector|C1|Nowhere Clinic', 'name' => 'Nowhere Clinic', 'providerType' => 'Independent Sector',
            'orgCode' => 'C1', 'orgName' => 'Private Group', 'region' => 'North West', 'hip12' => 50, 'knee12' => 60,
            'hipPrior' => 0, 'kneePrior' => 0, 'total12' => 110, 'months' => months, 'hip' => new List<Integer>{ 4, 5 },
            'knee' => new List<Integer>{ 5, 5 }, 'asOf' => '2026-10-01'
        });
        return JSON.serialize(sites);
    }

    @IsTest
    static void marketImportMatchesAccountsAndAppliesVolumes() {
        System.runAs(srUser()) {
            Assert.areEqual(3, SignalRoomController.importMarket(sitesJson()));
            Assert.areEqual(3, SignalRoomController.importMarket(sitesJson()), 're-import upserts');
            Assert.areEqual(3, [SELECT COUNT() FROM SR_Market_Site__c]);

            Map<String, Integer> counts = SignalRoomController.autoMatchMarket();
            Assert.areEqual(1, counts.get('auto'), String.valueOf(counts));
            Account alpha = [SELECT Id FROM Account WHERE Name = 'Test Hospital Alpha'];
            SR_Account_Profile__c p = [
                SELECT Hip_Procedures__c, Knee_Procedures__c, Volume_Source__c FROM SR_Account_Profile__c WHERE Account__c = :alpha.Id
            ];
            Assert.areEqual('NJR', p.Volume_Source__c);
            Assert.areEqual(400, p.Hip_Procedures__c);

            // Link a second hospital manually: volumes add up on the account.
            SR_Market_Site__c bravo = [SELECT Id FROM SR_Market_Site__c WHERE Name = 'Bravo Community Site'];
            SignalRoomController.setMarketMapping(bravo.Id, alpha.Id, 'Confirmed');
            Assert.areEqual(500, [SELECT Hip_Procedures__c FROM SR_Account_Profile__c WHERE Account__c = :alpha.Id].Hip_Procedures__c);

            Map<String, Object> market = SignalRoomController.getMarket(JSON.serialize(new Map<String, Object>{ 'status' => 'Mapped' }));
            Assert.areEqual(2, ((List<Object>) market.get('rows')).size());
            SignalRoomController.getMarket(JSON.serialize(new Map<String, Object>{
                'search' => 'Clinic', 'region' => 'North West', 'provider' => 'Independent Sector', 'status' => 'Unmatched'
            }));
            Assert.isNotNull(SignalRoomController.getAccount360(alpha.Id).get('market'));

            SignalRoomController.setMarketMapping(bravo.Id, null, 'Ignored');
            Assert.areEqual('Ignored', [SELECT Match_Status__c FROM SR_Market_Site__c WHERE Id = :bravo.Id].Match_Status__c);
            Assert.isFalse(SignalRoomController.searchAllAccounts('Test').isEmpty());
        }
    }

    @IsTest
    static void nameMatchingIgnoresNoiseWords() {
        Set<String> a = SignalRoomMarket.tokens('Abbot\'s and St Elmo\'s NHS Foundation Trust');
        Set<String> b = SignalRoomMarket.tokens('Abbots & Saint Elmos Hospital');
        Assert.areEqual(new Set<String>{ 'abbots', 'st', 'elmos' }, a);
        Assert.areEqual(1, SignalRoomMarket.dice(a, b));
        Assert.areEqual(0, SignalRoomMarket.dice(a, new Set<String>()));
    }

    // ------------------------------------------------------------------ public tender feeds

    private class TenderFeedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String in40 = String.valueOf(Date.today().addDays(40));
            Map<String, Object> theatre = new Map<String, Object>{ 'id' => '45000000', 'scheme' => 'CPV' };
            Map<String, Object> fixation = new Map<String, Object>{ 'id' => '33141770', 'scheme' => 'CPV' };
            if (req.getEndpoint().contains('ted.europa.eu')) {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'totalNoticeCount' => 1,
                    'notices' => new List<Object>{ new Map<String, Object>{
                        'publication-number' => '123456-2026',
                        'notice-title' => new Map<String, Object>{ 'eng' => 'Germany – Orthopaedic implants – Knieendoprothesen und Hüftendoprothesen' },
                        'buyer-name' => new Map<String, Object>{ 'deu' => new List<Object>{ 'Test Hospital Charlie' } },
                        'buyer-country' => new List<Object>{ 'DEU' },
                        'publication-date' => String.valueOf(Date.today()) + '+01:00',
                        'deadline-receipt-tender-date-lot' => new List<Object>{ in40 + '+01:00', in40 + '+01:00' },
                        'classification-cpv' => new List<Object>{ '33183100', '33183100' },
                        'estimated-value-lot' => new List<Object>{ '100000.00', '50000.00' },
                        'estimated-value-cur-lot' => new List<Object>{ 'EUR' },
                        'notice-type' => 'cn-standard'
                    } }
                }));
            } else {
                String scottish = 'Trauma fixation devices';
                List<Object> releases = new List<Object>{
                    release('rls-1-NOV100', 'Alpha Test Hospital NHS Trust', scottish, fixation, in40, 1000),
                    release('rls-1-NOV101', 'Alpha Test Hospital NHS Trust', 'Office furniture', theatre, in40, 5000)
                };
                if (req.getEndpoint().contains('publiccontractsscotland')) {
                    // The same notice as on Find a Tender (skipped as a duplicate) and one only on PCS.
                    releases.add(release('rls-2-NOV200', 'Northern Isles Board', 'Hip arthroplasty implants', fixation, in40, 2000));
                }
                res.setBody(JSON.serialize(new Map<String, Object>{ 'releases' => releases }));
            }
            return res;
        }

        private Map<String, Object> release(String id, String buyer, String title, Map<String, Object> cpv, String deadline,
                Decimal amount) {
            return new Map<String, Object>{
                'id' => id, 'ocid' => 'ocds-' + id, 'date' => String.valueOf(Date.today()) + 'T09:00:00Z',
                'tag' => new List<Object>{ 'tender' },
                'buyer' => new Map<String, Object>{ 'name' => buyer },
                'tender' => new Map<String, Object>{
                    'title' => title, 'status' => 'active', 'description' => 'Supply of ' + title,
                    'classification' => cpv,
                    'value' => new Map<String, Object>{ 'amount' => amount, 'currency' => 'GBP' },
                    'tenderPeriod' => new Map<String, Object>{ 'endDate' => deadline + 'T12:00:00Z' }
                }
            };
        }
    }

    @IsTest
    static void tenderFeedsImportDeduplicateAndMatch() {
        System.runAs(srUser()) {
            List<SR_Tender_Source__c> sources = SignalRoomTenders.sources();
            for (SR_Tender_Source__c s : sources) {
                s.Active__c = true;
                s.Lookback_Days__c = 30;
            }
            update sources;
            Test.setMock(HttpCalloutMock.class, new TenderFeedMock());
            Test.startTest();
            Database.executeBatch(new SignalRoomTenderSync(), 10);
            Test.stopTest();

            Map<String, SR_Tender__c> byRef = new Map<String, SR_Tender__c>();
            for (SR_Tender__c t : [
                SELECT Reference__c, Category__c, Country__c, Estimated_Value__c, Original_Value__c, Status__c,
                       Account__r.Name, Match_Status__c, Source__c, URL__c
                FROM SR_Tender__c
            ]) {
                byRef.put(t.Reference__c, t);
            }
            Assert.areEqual(new Set<String>{ 'TED-123456-2026', 'FTS-rls-1-NOV100', 'PCS-NOV200' }, byRef.keySet(),
                'out-of-scope CPV filtered and the Scottish duplicate skipped');
            SR_Tender__c ted = byRef.get('TED-123456-2026');
            Assert.areEqual('Knee & Hip', ted.Category__c);
            Assert.areEqual('DE', ted.Country__c);
            Assert.areEqual(150000, ted.Estimated_Value__c, 'lots are summed');
            Assert.areEqual('Test Hospital Charlie', ted.Account__r.Name);
            Assert.areEqual('Auto-matched', ted.Match_Status__c);
            SR_Tender__c fts = byRef.get('FTS-rls-1-NOV100');
            Assert.areEqual('Trauma', fts.Category__c);
            Assert.isTrue(fts.Estimated_Value__c > fts.Original_Value__c, 'GBP converted to EUR');
            Assert.areEqual('Test Hospital Alpha', fts.Account__r.Name);
            Assert.areEqual('Unmatched', byRef.get('PCS-NOV200').Match_Status__c);
            Assert.areEqual('Hip', byRef.get('PCS-NOV200').Category__c);
            for (SR_Tender_Source__c s : [SELECT Last_Status__c, Last_Run__c FROM SR_Tender_Source__c]) {
                Assert.isTrue(s.Last_Status__c.startsWith('OK'), s.Last_Status__c);
            }

            Map<String, Object> view = SignalRoomController.getTenders(null);
            Assert.areEqual(3, ((List<Object>) view.get('rows')).size());
            Assert.areEqual(2, view.get('linked'));
            Map<String, Object> filtered = SignalRoomController.getTenders(JSON.serialize(new Map<String, Object>{
                'mapping' => 'Unmatched', 'source' => 'Public Contracts Scotland', 'status' => 'All', 'search' => 'Hip'
            }));
            Assert.areEqual(1, ((List<Object>) filtered.get('rows')).size());

            // Human decisions survive a re-sync.
            Id pcsId = [SELECT Id FROM SR_Tender__c WHERE Reference__c = 'PCS-NOV200'].Id;
            Id bravo = [SELECT Id FROM Account WHERE Name = 'Test Hospital Bravo'].Id;
            SignalRoomController.setTenderMapping(pcsId, bravo, 'Confirmed');
            SignalRoomController.setTenderStatus(ted.Id, 'Submitted');
            SignalRoomTenders.Notice again = new SignalRoomTenders.Notice();
            again.ref = 'TED-123456-2026';
            again.source = SignalRoomTenders.TED;
            again.title = 'Knieendoprothesen und Hüftendoprothesen';
            again.buyer = 'Test Hospital Charlie';
            again.country = 'DE';
            again.status = 'Open';
            again.deadline = Date.today().addDays(40);
            Assert.areEqual(1, SignalRoomTenders.store(new List<SignalRoomTenders.Notice>{ again }));
            Assert.areEqual('Submitted', [SELECT Status__c FROM SR_Tender__c WHERE Id = :ted.Id].Status__c);
            Assert.areEqual(bravo, [SELECT Account__c FROM SR_Tender__c WHERE Id = :pcsId].Account__c);
            Assert.areEqual(0, SignalRoomController.autoMatchTenders().get('auto'));
            SignalRoomController.setTenderMapping(pcsId, null, 'Ignored');
            Assert.areEqual('Ignored', [SELECT Match_Status__c FROM SR_Tender__c WHERE Id = :pcsId].Match_Status__c);
        }
    }

    @IsTest
    static void tenderSourcesScheduleAndHelpers() {
        System.runAs(srUser()) {
            List<SR_Tender_Source__c> sources = SignalRoomTenders.sources();
            Assert.areEqual(3, sources.size());
            SR_Tender_Source__c ted;
            for (SR_Tender_Source__c s : sources) {
                if (s.Code__c == SignalRoomTenders.TED) {
                    ted = s;
                }
            }
            ted.Countries__c = 'DE, FR';
            ted.CPV_Prefixes__c = '33183';
            SignalRoomController.saveTenderSource(ted);
            ted = [SELECT Id, Code__c, CPV_Prefixes__c, Countries__c, Lookback_Days__c, Last_Run__c FROM SR_Tender_Source__c WHERE Id = :ted.Id];
            String body = SignalRoomTenders.tedRequest(ted, Date.newInstance(2026, 11, 1), 1).getBody();
            Assert.isTrue(body.contains('33183*') && body.contains('buyer-country IN (DEU FRA)') && body.contains('20261101'), body);
            Assert.areEqual(Date.today().addDays(-30), SignalRoomTenders.fromDate(ted));

            SignalRoomController.scheduleTenderSync(true);
            Assert.isTrue(SignalRoomTenderSync.isScheduled());
            SignalRoomController.scheduleTenderSync(false);
            Assert.isFalse(SignalRoomTenderSync.isScheduled());

            Assert.areEqual('Robotics', SignalRoomTenders.category('33183100', 'Robotic-assisted knee system'));
            Assert.areEqual('Orthopaedics', SignalRoomTenders.category('33183100', 'Implants'));
            Assert.areEqual(new Set<String>{ 'lodz', 'jonschera' },
                SignalRoomTenders.tokens('Szpital Łódź im. Jonschera'));
            Assert.areEqual(SignalRoomTenders.dedupeKey('A Board', 'Hip implants'), SignalRoomTenders.dedupeKey('A Board', 'Hip  implants!'));
        }
    }

    // ------------------------------------------------------------------ demo team, team scope, custom rules

    @IsTest
    static void demoTeamDrivesTheTeamScope() {
        User me = srUser();
        System.runAs(me) {
            Assert.areEqual(6, SignalRoomController.createDemoTeam());
            Assert.areEqual(6, SignalRoomController.createDemoTeam(), 'idempotent');
        }
        System.runAs(me) {
            seedAndRun();
            Assert.areEqual(6, SignalRoomController.getContext().get('teamSize'));
            Set<Id> reps = new Set<Id>();
            for (AggregateResult ar : [SELECT Rep__c r FROM SR_Account_Profile__c GROUP BY Rep__c]) {
                reps.add((Id) ar.get('r'));
            }
            Assert.isTrue(reps.size() > 1, 'accounts are spread across the team');
            Integer all = SignalRoomController.getPointers(JSON.serialize(new Map<String, Object>{ 'scope' => 'all' })).size();
            Integer mine = SignalRoomController.getPointers(JSON.serialize(new Map<String, Object>{ 'scope' => 'mine' })).size();
            Integer team = SignalRoomController.getPointers(JSON.serialize(new Map<String, Object>{ 'scope' => 'team' })).size();
            Assert.isTrue(mine < team, 'my team includes my reports');
            Assert.areEqual(all, team, 'every demo pointer belongs to the team');
            Assert.isNotNull(SignalRoomController.getDashboard('team', null));
        }
    }

    @IsTest
    static void customRulesCanBeAddedAndDeleted() {
        System.runAs(srUser()) {
            SignalRoomRules.ensureDefaults(true);
            SR_Rule__c r = SignalRoomController.saveRule(new SR_Rule__c(
                Name = 'Deep churn', Code__c = 'CUSTOM_DEEP_CHURN', Rule_Type__c = 'WINBACK_SOFT', Category__c = 'Win back',
                Active__c = true, Weight__c = 3, Threshold_Pct__c = 50, Min_Value__c = 1000, Lookback_Months__c = 12, Recent_Months__c = 3
            ));
            SignalRoomController.deleteRule(r.Id);
            Assert.areEqual(0, [SELECT COUNT() FROM SR_Rule__c WHERE Code__c = 'CUSTOM_DEEP_CHURN']);
            Id defaultRule = [SELECT Id FROM SR_Rule__c WHERE Code__c = 'NT_TENDER'].Id;
            try {
                SignalRoomController.deleteRule(defaultRule);
                Assert.fail('default rules cannot be deleted');
            } catch (AuraHandledException e) {
                Assert.areEqual(1, [SELECT COUNT() FROM SR_Rule__c WHERE Id = :defaultRule]);
            }
        }
    }
}
