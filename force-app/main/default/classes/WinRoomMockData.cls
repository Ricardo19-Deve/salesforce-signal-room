/**
 * Mock data for the Win Room in sandboxes.
 *
 * Builds account profiles on the existing hospital accounts (Account itself is
 * never modified), surgeons, affiliations, tenders, win room sessions and 24
 * months of sell-in with planted patterns so every rule has something to find:
 *
 *   archetype 0  soft churn on Meridian knee (-45% in the last 6 months)
 *   archetype 1  hard churn: Unity partial knee stopped 4 months ago
 *   archetype 2  partial switch: Meridian tibia trays halved, femoral stable
 *   archetype 3  Meridian patella never ordered
 *   archetype 4  Orbit cups stopped 5 months ago while Summit stems continue
 *   archetype 5  Atlas Robotic Knee robot, hip volume, no Atlas Robotic Hip workflow
 *   archetype 6  low share of wallet (~6%)
 *   archetype 7  healthy account (control)
 *
 * Compact mode (automatic in Developer Edition orgs, which only have 5 MB of data storage): 18 months of
 * history - the minimum the rules need - and one sales row per product line and month instead of one per surgeon.
 *
 * Every record carries Is_Demo__c = true and is removed by purge().
 * Opportunities created from demo pointers are not deleted.
 */
public with sharing class WinRoomMockData {

    public static final Integer HISTORY_MONTHS = 24;
    public static final Integer COMPACT_HISTORY_MONTHS = 18;
    private static final Set<String> SUPPORTED_COUNTRIES = new Set<String>{
        'GB', 'DE', 'FR', 'ES', 'IT', 'PT', 'NL', 'BE', 'CH', 'SE', 'DK', 'PL'
    };
    private static final List<String> PHASE_ORDER = new List<String>{ 'GB', 'DE', 'FR', 'ES', 'IT' };

    // ------------------------------------------------------------------ entry points

    /** Seeds rules, profiles, surgeons, tenders and sessions, then starts the sales batch. */
    public static final String DEMO_TEAM_DEPARTMENT = 'Win Room demo team';
    private static final List<String[]> DEMO_TEAM = new List<String[]>{
        new String[]{ 'Anna', 'Weber' }, new String[]{ 'James', 'Carter' }, new String[]{ 'Lucas', 'Martin' },
        new String[]{ 'Sofia', 'Ricci' }, new String[]{ 'Elena', 'Navarro' }, new String[]{ 'Daniel', 'Costa' }
    };

    /**
     * Creates (or re-activates) six fictitious reps reporting to the current user, with a Chatter Free licence and
     * no welcome e-mail. They only own demo pointers so the All / Mine / My team filters can be shown.
     * Runs in its own transaction: users are setup objects and cannot be inserted with the demo records.
     */
    public static Integer createDemoTeam() {
        List<Profile> chatterFree = [SELECT Id FROM Profile WHERE UserLicense.Name = 'Chatter Free' LIMIT 1];
        if (chatterFree.isEmpty()) {
            throw new IllegalArgumentException('No Chatter Free profile in this org.');
        }
        String org = UserInfo.getOrganizationId().left(15).toLowerCase();
        Map<String, User> existing = new Map<String, User>();
        for (User u : [SELECT Id, Username, IsActive, ManagerId FROM User WHERE Department = :DEMO_TEAM_DEPARTMENT]) {
            existing.put(u.Username, u);
        }
        List<User> upserts = new List<User>();
        Integer i = 0;
        for (String[] n : DEMO_TEAM) {
            i++;
            String key = (n[0] + '.' + n[1]).toLowerCase();
            String username = 'wr.demo.' + key + '.' + org + '@example.com';
            User u = existing.get(username);
            if (u != null) {
                upserts.add(new User(Id = u.Id, IsActive = true, ManagerId = UserInfo.getUserId()));
                continue;
            }
            upserts.add(new User(
                FirstName = n[0], LastName = n[1], Username = username, Email = 'wr.demo.' + key + '@example.com',
                Alias = ('wrd' + n[0]).left(8), CommunityNickname = ('wrdemo.' + key + '.' + org).left(40),
                ProfileId = chatterFree[0].Id, ManagerId = UserInfo.getUserId(), Department = DEMO_TEAM_DEPARTMENT,
                Title = 'Sales Rep (demo)', TimeZoneSidKey = UserInfo.getTimeZone().getID(), LocaleSidKey = 'en_GB',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            ));
        }
        Database.DMLOptions noMail = new Database.DMLOptions();
        noMail.EmailHeader.triggerUserEmail = false;
        noMail.EmailHeader.triggerAutoResponseEmail = false;
        noMail.EmailHeader.triggerOtherEmail = false;
        List<User> inserts = new List<User>();
        List<User> updates = new List<User>();
        for (User u : upserts) {
            (u.Id == null ? inserts : updates).add(u);
        }
        Database.insert(inserts, noMail);
        Database.update(updates, noMail);
        return upserts.size();
    }

    /** Reps for the demo accounts: the current user and, when it exists, the demo team. */
    private static List<Id> demoReps() {
        List<Id> reps = new List<Id>{ UserInfo.getUserId() };
        for (User u : [
            SELECT Id FROM User WHERE ManagerId = :UserInfo.getUserId() AND Department = :DEMO_TEAM_DEPARTMENT
            AND IsActive = true ORDER BY LastName
        ]) {
            reps.add(u.Id);
        }
        return reps;
    }

    public static Id generate(Boolean assignToMe, Boolean runEngine) {
        return generate(assignToMe, runEngine, isDeveloperEdition());
    }

    public static Boolean isDeveloperEdition() {
        return [SELECT OrganizationType FROM Organization LIMIT 1].OrganizationType == 'Developer Edition';
    }

    public static Id generate(Boolean assignToMe, Boolean runEngine, Boolean compact) {
        WinRoomRules.ensureDefaults(false);
        List<Account> accounts = pickAccounts();
        if (accounts.isEmpty()) {
            throw new MockException('No hospital accounts found to attach demo data to.');
        }
        Map<Id, Integer> archetypes = new Map<Id, Integer>();
        List<WR_Account_Profile__c> profiles = buildProfiles(accounts, assignToMe, archetypes);
        upsert profiles Account_Key__c;

        Map<Id, Integer> archetypeByProfile = new Map<Id, Integer>();
        for (WR_Account_Profile__c p : profiles) {
            archetypeByProfile.put(p.Id, archetypes.get(p.Account__c));
        }
        // Real registry volumes (e.g. NJR for UK hospitals) replace the estimates before sales are generated.
        Set<Id> accountIds = new Set<Id>();
        for (WR_Account_Profile__c p : profiles) {
            accountIds.add(p.Account__c);
        }
        WinRoomMarket.applyVolumes(accountIds);
        buildSurgeons(profiles);
        buildTenders(profiles);
        buildSessions();
        buildContracts(archetypes);
        return Database.executeBatch(new WinRoomMockDataBatch(archetypeByProfile, runEngine, compact), 4);
    }

    /** Deletes all demo data. Sales are removed in a batch, then the rest in its finish(). */
    public static Id purge() {
        return Database.executeBatch(new WinRoomMockDataBatch(), 2000);
    }

    /** Removes the demo records that are small in volume. Called at the end of the purge batch. */
    public static void purgeSmallObjects() {
        delete [SELECT Id FROM WR_Commitment__c WHERE Is_Demo__c = true OR Pointer__r.Is_Demo__c = true];
        delete [SELECT Id FROM WR_Contract_Line__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Contract__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Pointer__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Session__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Tender__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Affiliation__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Surgeon__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Account_Profile__c WHERE Is_Demo__c = true];
        delete [SELECT Id FROM WR_Run__c];
    }

    // ------------------------------------------------------------------ accounts & profiles

    @TestVisible
    static List<Account> pickAccounts() {
        List<Account> hospitals = new List<Account>();
        for (Account a : [
            SELECT Id, Name, BillingCountry, OwnerId, Industry
            FROM Account
            WHERE BillingCountry IN :SUPPORTED_COUNTRIES
            ORDER BY Name
            LIMIT 500
        ]) {
            if (a.Industry == 'Healthcare' || looksLikeHospital(a.Name)) {
                hospitals.add(a);
            }
        }
        return hospitals;
    }

    private static Boolean looksLikeHospital(String name) {
        String n = name == null ? '' : name.toLowerCase();
        for (String k : new List<String>{ 'hosp', 'hôp', 'klinik', 'clinic', 'clíni', 'univers', 'nhs', 'infirmary',
                'szpital', 'ospedale', 'chu ', 'umc', 'charité', 'policlinico', 'istituto', 'rigshospital', 'spital' }) {
            if (n.contains(k)) {
                return true;
            }
        }
        return false;
    }

    private static List<WR_Account_Profile__c> buildProfiles(List<Account> accounts, Boolean assignToMe,
            Map<Id, Integer> archetypes) {
        List<Id> reps = assignToMe ? demoReps() : new List<Id>();
        // Phase 1 countries first so the planted patterns are spread across GB, DE and FR.
        List<Account> ordered = new List<Account>();
        for (String c : PHASE_ORDER) {
            for (Account a : accounts) {
                if (a.BillingCountry == c) {
                    ordered.add(a);
                }
            }
        }
        for (Account a : accounts) {
            if (!PHASE_ORDER.contains(a.BillingCountry)) {
                ordered.add(a);
            }
        }
        List<WR_Account_Profile__c> out = new List<WR_Account_Profile__c>();
        Integer idx = 0;
        for (Account a : ordered) {
            Rng rng = new Rng(a.Id);
            Integer archetype = Math.mod(idx, 8);
            archetypes.put(a.Id, archetype);
            String segment = segmentFor(a.Name);
            String c = a.BillingCountry;
            String phase = (c == 'GB' || c == 'DE' || c == 'FR') ? 'Phase 1' : ((c == 'ES' || c == 'IT') ? 'Phase 2' : 'Peer only');
            String size = segment == 'University Hospital'
                ? (rng.next() < 0.7 ? 'Large' : 'Medium')
                : (rng.next() < 0.3 ? 'Large' : (rng.next() < 0.6 ? 'Medium' : 'Small'));
            if (phase == 'Phase 1' && size == 'Small') {
                size = 'Medium'; // pilot accounts are the larger ones
            }
            Integer knees = size == 'Large' ? rng.between(650, 1100) : (size == 'Medium' ? rng.between(320, 620) : rng.between(140, 300));
            Integer hips = (knees * (0.7 + rng.next() * 0.3)).intValue();
            out.add(new WR_Account_Profile__c(
                Name = a.Name.left(80),
                Account__c = a.Id,
                Account_Key__c = a.Id,
                Country__c = c,
                Segment__c = segment,
                Size_Band__c = size,
                Knee_Procedures__c = knees,
                Hip_Procedures__c = hips,
                Phase__c = phase,
                In_Scope__c = phase == 'Phase 1',
                Has_Robot__c = archetype == 5 || (archetype != 6 && rng.next() < 0.3),
                // With a demo team, every third account stays with the current user and the rest are spread.
                Rep__c = !assignToMe ? a.OwnerId : (reps.size() == 1 || Math.mod(idx, 3) == 0
                    ? reps[0] : reps[1 + Math.mod(idx, reps.size() - 1)]),
                Is_Demo__c = true
            ));
            idx++;
        }
        return out;
    }

    private static String segmentFor(String name) {
        String n = name.toLowerCase();
        if (n.contains('ortop') || n.contains('orthop')) {
            return 'Orthopaedic Centre';
        }
        if (n.contains('clinique') || n.contains('clínica') || n.contains('private')) {
            return 'Private Clinic';
        }
        if (n.contains('univers') || n.contains('uni') || n.contains('umc') || n.contains('chu') || n.contains('charité')
                || n.contains('klinikum') || n.contains('policlinico') || n.contains('karolinska') || n.contains('rigshospital')
                || n.contains('clínic') || n.contains('cliniques') || n.contains('pitié') || n.contains('raffaele')) {
            return 'University Hospital';
        }
        return 'Public Hospital';
    }

    // ------------------------------------------------------------------ surgeons

    private static void buildSurgeons(List<WR_Account_Profile__c> profiles) {
        List<WR_Surgeon__c> surgeons = new List<WR_Surgeon__c>();
        List<WR_Affiliation__c> affiliations = new List<WR_Affiliation__c>();
        Date established = Date.today().addYears(-6);
        Map<String, List<String>> byCountry = new Map<String, List<String>>();
        Integer idx = 0;
        for (WR_Account_Profile__c p : profiles) {
            Rng rng = new Rng(p.Account__c);
            List<String> specialties = new List<String>{ 'Knee', 'Knee & Hip', 'Hip' };
            for (Integer i = 0; i < 3; i++) {
                String key = p.Account__c + '|S' + i;
                surgeons.add(new WR_Surgeon__c(
                    Name = surgeonName(p.Country__c, rng), External_Key__c = key,
                    Specialty__c = specialties[i], Country__c = p.Country__c, Is_Demo__c = true
                ));
                affiliations.add(affiliation(key, p.Account__c, rng.between(90, 220), established, true, 'Hospital website'));
                if (!byCountry.containsKey(p.Country__c)) {
                    byCountry.put(p.Country__c, new List<String>());
                }
                byCountry.get(p.Country__c).add(key);
            }
            if (p.In_Scope__c && Math.mod(idx, 4) == 1) {
                // Recently appointed surgeon with no Contoso cases yet -> NEW_SURGEON.
                String key = p.Account__c + '|NEW';
                surgeons.add(new WR_Surgeon__c(
                    Name = surgeonName(p.Country__c, rng), External_Key__c = key,
                    Specialty__c = Math.mod(idx, 2) == 0 ? 'Hip' : 'Knee', Country__c = p.Country__c, Is_Demo__c = true
                ));
                affiliations.add(affiliation(key, p.Account__c, rng.between(110, 180), Date.today().addDays(-rng.between(20, 100)),
                    true, 'Hospital press release'));
            }
            idx++;
        }
        // Surgeons who use Contoso at their primary site and also operate elsewhere -> SURGEON_SITE.
        idx = 0;
        for (WR_Account_Profile__c p : profiles) {
            List<String> peers = byCountry.get(p.Country__c);
            if (p.In_Scope__c && Math.mod(idx, 3) == 0 && peers != null) {
                for (String key : peers) {
                    if (!key.startsWith(String.valueOf(p.Account__c))) {
                        affiliations.add(affiliation(key, p.Account__c, 60 + Math.mod(idx * 13, 60),
                            Date.today().addYears(-2), false, 'National society member list'));
                        break;
                    }
                }
            }
            idx++;
        }
        upsert surgeons External_Key__c;
        Map<String, Id> surgeonIds = new Map<String, Id>();
        for (WR_Surgeon__c s : surgeons) {
            surgeonIds.put(s.External_Key__c, s.Id);
        }
        for (WR_Affiliation__c af : affiliations) {
            af.Surgeon__c = surgeonIds.get(af.External_Key__c.substringBefore('@'));
        }
        upsert affiliations External_Key__c;
    }

    private static WR_Affiliation__c affiliation(String surgeonKey, Id accountId, Integer procedures, Date since,
            Boolean primary, String source) {
        return new WR_Affiliation__c(
            External_Key__c = surgeonKey + '@' + accountId,
            Account__c = accountId,
            Annual_Procedures__c = procedures,
            Start_Date__c = since,
            Primary__c = primary,
            Source__c = source,
            Is_Demo__c = true
        );
    }

    private static String surgeonName(String country, Rng rng) {
        Map<String, List<List<String>>> names = new Map<String, List<List<String>>>{
            'GB' => new List<List<String>>{
                new List<String>{ 'James', 'Sarah', 'David', 'Emma', 'Richard', 'Helen', 'Andrew', 'Claire', 'Mark', 'Rachel' },
                new List<String>{ 'Thompson', 'Patel', 'Hughes', 'Clarke', 'Walker', 'Evans', 'Khan', 'Wright', 'Turner', 'Bennett' } },
            'DE' => new List<List<String>>{
                new List<String>{ 'Thomas', 'Anna', 'Michael', 'Julia', 'Stefan', 'Katrin', 'Andreas', 'Sabine', 'Markus', 'Laura' },
                new List<String>{ 'Müller', 'Schmidt', 'Weber', 'Becker', 'Hoffmann', 'Wagner', 'Koch', 'Richter', 'Klein', 'Wolf' } },
            'FR' => new List<List<String>>{
                new List<String>{ 'Pierre', 'Camille', 'Nicolas', 'Claire', 'Julien', 'Sophie', 'Antoine', 'Isabelle', 'Laurent', 'Marie' },
                new List<String>{ 'Martin', 'Bernard', 'Dubois', 'Moreau', 'Lambert', 'Lefebvre', 'Girard', 'Roux', 'Fournier', 'Mercier' } },
            'ES' => new List<List<String>>{
                new List<String>{ 'Javier', 'Lucía', 'Carlos', 'María', 'Alejandro', 'Carmen', 'Pablo', 'Elena', 'Miguel', 'Laura' },
                new List<String>{ 'García', 'Martínez', 'López', 'Sánchez', 'Romero', 'Navarro', 'Torres', 'Ruiz', 'Ortega', 'Gil' } },
            'IT' => new List<List<String>>{
                new List<String>{ 'Marco', 'Giulia', 'Luca', 'Francesca', 'Alessandro', 'Chiara', 'Matteo', 'Sara', 'Davide', 'Elena' },
                new List<String>{ 'Rossi', 'Russo', 'Ferrari', 'Esposito', 'Bianchi', 'Romano', 'Colombo', 'Ricci', 'Marino', 'Greco' } },
            'PT' => new List<List<String>>{
                new List<String>{ 'João', 'Ana', 'Miguel', 'Inês', 'Pedro', 'Marta', 'Rui', 'Sofia', 'Tiago', 'Catarina' },
                new List<String>{ 'Silva', 'Santos', 'Ferreira', 'Pereira', 'Oliveira', 'Costa', 'Rodrigues', 'Martins', 'Sousa', 'Fernandes' } }
        };
        List<List<String>> pool = names.containsKey(country) ? names.get(country) : new List<List<String>>{
            new List<String>{ 'Jan', 'Eva', 'Lars', 'Nina', 'Piotr', 'Anna', 'Erik', 'Sofie', 'Tomasz', 'Lea' },
            new List<String>{ 'Jansen', 'Nielsen', 'Andersson', 'Kowalski', 'Peeters', 'Meier', 'de Vries', 'Larsen', 'Nowak', 'Berg' } };
        return 'Dr. ' + pool[0][rng.between(0, 9)] + ' ' + pool[1][rng.between(0, 9)];
    }

    // ------------------------------------------------------------------ tenders & sessions

    private static void buildTenders(List<WR_Account_Profile__c> profiles) {
        Map<String, String> sources = new Map<String, String>{
            'GB' => 'Find a Tender (UK)', 'DE' => 'DTVP / TED', 'FR' => 'BOAMP / TED', 'ES' => 'PLACSP', 'IT' => 'ANAC / TED'
        };
        List<WR_Tender__c> tenders = new List<WR_Tender__c>();
        Integer idx = 0;
        for (WR_Account_Profile__c p : profiles) {
            if (p.Phase__c != 'Phase 1' && p.Phase__c != 'Phase 2') {
                idx++;
                continue;
            }
            Rng rng = new Rng(p.Account__c);
            Integer kind = Math.mod(idx, 3);
            String category = Math.mod(idx, 2) == 0 ? 'Knee' : 'Hip';
            if (kind == 2 || Math.mod(idx, 5) == 0) {
                Integer days = 8 + Math.mod(idx * 11, 50);
                tenders.add(tender(p, rng, category, Date.today().addDays(days), 'Open', sources, idx));
            }
            if (kind == 0) {
                tenders.add(tender(p, rng, category == 'Knee' ? 'Hip' : 'Knee', Date.today().addMonths(5), 'Open', sources, idx + 1000));
            }
            if (kind == 1) {
                tenders.add(tender(p, rng, 'Knee & Hip', Date.today().addDays(-20), 'Submitted', sources, idx + 2000));
            }
            idx++;
        }
        upsert tenders Reference__c;
    }

    private static WR_Tender__c tender(WR_Account_Profile__c p, Rng rng, String category, Date deadline,
            String status, Map<String, String> sources, Integer n) {
        String label = category == 'Knee' ? 'Primary total knee arthroplasty implants'
            : (category == 'Hip' ? 'Primary total hip arthroplasty implants' : 'Hip and knee reconstruction framework');
        return new WR_Tender__c(
            Name = label,
            Reference__c = 'WR-' + p.Country__c + '-' + Date.today().year() + '-' + String.valueOf(1000 + n),
            Account__c = p.Account__c,
            Country__c = p.Country__c,
            Category__c = category,
            Publication_Date__c = deadline.addDays(-45),
            Deadline__c = deadline,
            Estimated_Value__c = rng.between(25, 90) * 10000,
            Status__c = status,
            Source__c = sources.containsKey(p.Country__c) ? sources.get(p.Country__c) : 'TED Europa',
            Is_Demo__c = true
        );
    }

    private static void buildSessions() {
        Date monday = Date.today().toStartOfWeek();
        List<WR_Session__c> sessions = new List<WR_Session__c>();
        for (String team : new List<String>{ 'GB', 'DE', 'FR' }) {
            sessions.add(session(team, monday.addDays(-7), 'Completed'));
            sessions.add(session(team, monday.addDays(Date.today() > monday ? 7 : 0), 'Planned'));
        }
        insert sessions;
    }

    private static WR_Session__c session(String team, Date d, String status) {
        return new WR_Session__c(
            Name = 'Win Room ' + team + ' - ' + String.valueOf(d),
            Session_Date__c = d,
            Team__c = team,
            Facilitator__c = UserInfo.getUserId(),
            Status__c = status,
            Notes__c = status == 'Completed' ? 'Kick-off win room. Pipeline baseline reviewed; first pointers allocated to account owners.' : null,
            Is_Demo__c = true
        );
    }

    private static final String PRICE_FACTOR = '_priceFactor';

    /**
     * Base monthly units per product line before seasonality, patterns and noise. Consumes the account's random
     * sequence in a fixed order, so salesFor() and the demo contracts see the same numbers.
     */
    public static Map<String, Decimal> baseUnits(WR_Account_Profile__c p, Integer archetype, Rng rng) {
        Decimal share = archetype == 6 ? 0.06 : 0.25 + rng.next() * 0.3;
        Decimal kneeCases = (p.Knee_Procedures__c == null ? 0 : p.Knee_Procedures__c) / 12 * share;
        Decimal hipCases = (p.Hip_Procedures__c == null ? 0 : p.Hip_Procedures__c) / 12 * share;
        Boolean cementless = rng.next() < 0.75;
        Boolean collaredStem = rng.next() < 0.5;
        Boolean robotHip = p.Has_Robot__c && archetype != 5 && rng.next() < 0.5;
        Decimal priceFactor = 0.95 + rng.next() * 0.1;

        Map<String, Decimal> base = new Map<String, Decimal>();
        base.put(PRICE_FACTOR, priceFactor);
        base.put('KNEE_FEM', kneeCases * 0.85);
        base.put('KNEE_TIB', kneeCases * 0.85);
        base.put('KNEE_PAT', archetype == 3 ? 0 : kneeCases * 0.85 * 0.65);
        base.put('KNEE_CL', cementless ? kneeCases * 0.2 : 0);
        base.put('BONE_CEMENT', kneeCases * 0.85 * 1.6);
        base.put('PARTIAL_KNEE', kneeCases * (archetype == 1 ? 0.3 : 0.1));
        base.put('HIP_STEM_T', hipCases * (collaredStem ? 0.6 : 1.0));
        base.put('HIP_STEM_C', collaredStem ? hipCases * 0.4 : 0);
        base.put('HIP_CUP', hipCases * 0.95);
        base.put('HIP_LINER', hipCases * 0.95);
        base.put('HIP_HEAD', hipCases * 0.9);
        base.put('ROBOT_KNEE', p.Has_Robot__c ? kneeCases * 0.85 * 0.5 : 0);
        base.put('ROBOT_HIP', robotHip ? hipCases * 0.3 : 0);
        return base;
    }

    // ------------------------------------------------------------------ contracts

    /**
     * Demo volume contracts on in-scope accounts, sized from the same base units as the sales so each one has a
     * known outcome: archetype 0 / 2 / 4 under-deliver (churn, tibia switch, cups stopped), 5 over-delivers
     * (commitment set at 75% of the run-rate), 7 is on track and ends in 4 months (renewal).
     */
    private static void buildContracts(Map<Id, Integer> archetypes) {
        Map<String, WR_Product_Line__c> lines = new Map<String, WR_Product_Line__c>();
        for (WR_Product_Line__c l : [SELECT Id, Code__c, Name, Avg_Price__c FROM WR_Product_Line__c]) {
            lines.put(l.Code__c, l);
        }
        Date monthStart = WinRoomEngine.defaultAsOf();
        List<WR_Contract__c> contracts = new List<WR_Contract__c>();
        Map<String, List<WR_Contract_Line__c>> linesByRef = new Map<String, List<WR_Contract_Line__c>>();
        for (WR_Account_Profile__c p : [
            SELECT Id, Name, Account__c, Country__c, Knee_Procedures__c, Hip_Procedures__c, Has_Robot__c, In_Scope__c
            FROM WR_Account_Profile__c WHERE Account__c IN :archetypes.keySet() AND In_Scope__c = true AND Is_Demo__c = true
        ]) {
            Integer archetype = archetypes.get(p.Account__c);
            Map<String, Decimal> base = baseUnits(p, archetype, new Rng(p.Account__c));
            String ref = 'CT-' + p.Country__c + '-' + String.valueOf(p.Account__c).right(6);
            Date start = monthStart.addMonths(-14);
            Date endDate = start.addMonths(36).addDays(-1);
            String name;
            List<WR_Contract_Line__c> cl = new List<WR_Contract_Line__c>();
            switch on archetype {
                when 0 {
                    name = 'Knee system agreement';
                    cl.add(contractLine(lines.get('KNEE_FEM'), 'Primary knees (femoral components)', base.get('KNEE_FEM')));
                }
                when 2 {
                    name = 'Knee system agreement';
                    cl.add(contractLine(lines.get('KNEE_FEM'), 'Primary knees (femoral components)', base.get('KNEE_FEM')));
                    cl.add(contractLine(lines.get('KNEE_TIB'), 'Tibial trays', base.get('KNEE_TIB')));
                }
                when 4 {
                    name = 'Hip framework agreement';
                    cl.add(contractLine(lines.get('HIP_CUP'), 'Primary hips (cups)', base.get('HIP_CUP')));
                }
                when 5 {
                    name = 'Hip framework agreement';
                    cl.add(contractLine(lines.get('HIP_STEM_T'), 'Hip stems', base.get('HIP_STEM_T') * 0.75));
                }
                when 7 {
                    name = 'Knee and hip agreement';
                    start = monthStart.addMonths(-32);
                    endDate = monthStart.addMonths(4).addDays(-1);
                    cl.add(contractLine(lines.get('KNEE_FEM'), 'Primary knees (femoral components)', base.get('KNEE_FEM')));
                    cl.add(contractLine(lines.get('HIP_CUP'), 'Primary hips (cups)', base.get('HIP_CUP')));
                }
            }
            // Very small hospitals (a handful of cases a month) get no volume contract in the demo.
            for (Integer i = cl.size() - 1; i >= 0; i--) {
                if (cl[i].Monthly_Qty__c < 2) {
                    cl.remove(i);
                }
            }
            if (name == null || cl.isEmpty()) {
                continue;
            }
            contracts.add(new WR_Contract__c(
                Name = (name + ' - ' + p.Name).left(80), Reference__c = ref, Account__c = p.Account__c,
                Start_Date__c = start, End_Date__c = endDate, Status__c = 'Active', Tolerance_Pct__c = 10,
                Notes__c = 'Demo contract. Committed volumes are monthly units per product line.', Is_Demo__c = true
            ));
            linesByRef.put(ref, cl);
        }
        // Demo contracts are rebuilt from scratch so they always match the regenerated sales.
        Set<Id> accountIds = archetypes.keySet();
        delete [SELECT Id FROM WR_Contract_Line__c WHERE Is_Demo__c = true AND Contract__r.Account__c IN :accountIds];
        delete [SELECT Id FROM WR_Contract__c WHERE Is_Demo__c = true AND Account__c IN :accountIds];
        insert contracts;
        List<WR_Contract_Line__c> allLines = new List<WR_Contract_Line__c>();
        for (WR_Contract__c c : contracts) {
            for (WR_Contract_Line__c l : linesByRef.get(c.Reference__c)) {
                l.Contract__c = c.Id;
                allLines.add(l);
            }
        }
        insert allLines;
    }

    private static WR_Contract_Line__c contractLine(WR_Product_Line__c line, String label, Decimal monthly) {
        Decimal qty = (monthly == null ? 0 : monthly).round(System.RoundingMode.HALF_UP);
        return new WR_Contract_Line__c(
            Product_Line__c = line.Id, Label__c = label, Monthly_Qty__c = qty,
            Unit_Price__c = ((line.Avg_Price__c == null ? 0 : line.Avg_Price__c) * 0.92).setScale(2), Is_Demo__c = true
        );
    }

    // ------------------------------------------------------------------ sales

    /** Builds 24 months of sell-in for one account. Used by WinRoomMockDataBatch. */
    public static List<WR_Sales__c> salesFor(WR_Account_Profile__c p, Integer archetype,
            Map<String, WR_Product_Line__c> lines, List<WR_Affiliation__c> surgeons, Date asOf, Boolean compact) {
        Integer history = compact == true ? COMPACT_HISTORY_MONTHS : HISTORY_MONTHS;
        Rng rng = new Rng(p.Account__c);
        Map<String, Decimal> base = baseUnits(p, archetype, rng);
        Decimal priceFactor = base.remove(PRICE_FACTOR);



        List<WR_Affiliation__c> knee = new List<WR_Affiliation__c>();
        List<WR_Affiliation__c> hip = new List<WR_Affiliation__c>();
        for (WR_Affiliation__c af : surgeons) {
            String s = af.Surgeon__r.Specialty__c;
            if (s == 'Knee' || s == 'Knee & Hip') {
                knee.add(af);
            }
            if (s == 'Hip' || s == 'Knee & Hip') {
                hip.add(af);
            }
        }

        List<WR_Sales__c> out = new List<WR_Sales__c>();
        for (String code : base.keySet()) {
            WR_Product_Line__c line = lines.get(code);
            if (line == null || base.get(code) <= 0) {
                continue;
            }
            List<WR_Affiliation__c> split = line.Category__c == 'Hip' || code == 'ROBOT_HIP' ? hip : knee;
            if (compact == true && split.size() > 1) {
                split = new List<WR_Affiliation__c>{ split[0] }; // one row per line and month
            }
            for (Integer m = history; m >= 1; m--) {
                Date period = asOf.addMonths(-m);
                Decimal noise = 0.88 + rng.next() * 0.24;
                Decimal units = base.get(code) * seasonality(period) * pattern(archetype, code, m) * noise;
                Integer total = units.round(System.RoundingMode.HALF_UP).intValue();
                if (total <= 0) {
                    continue;
                }
                Decimal price = (line.Avg_Price__c == null ? 0 : line.Avg_Price__c) * priceFactor;
                if (split.isEmpty()) {
                    out.add(row(p, line, null, period, total, price));
                    continue;
                }
                Integer remaining = total;
                for (Integer i = 0; i < split.size(); i++) {
                    Integer u = i == split.size() - 1 ? remaining : (total * (i == 0 ? 0.6 : 0.4 / (split.size() - 1))).intValue();
                    u = Math.min(u, remaining);
                    remaining -= u;
                    if (u > 0) {
                        out.add(row(p, line, split[i].Surgeon__c, period, u, price));
                    }
                }
            }
        }
        return out;
    }

    private static WR_Sales__c row(WR_Account_Profile__c p, WR_Product_Line__c line, Id surgeonId,
            Date period, Integer units, Decimal price) {
        return new WR_Sales__c(
            Account__c = p.Account__c,
            Product_Line__c = line.Id,
            Surgeon__c = surgeonId,
            Period__c = period,
            Units__c = units,
            Revenue__c = (units * price).setScale(2),
            External_Key__c = p.Account__c + '|' + line.Code__c + '|' + String.valueOf(period) + '|' + (surgeonId == null ? '-' : String.valueOf(surgeonId)),
            Is_Demo__c = true
        );
    }

    private static Decimal seasonality(Date period) {
        if (period.month() == 8) {
            return 0.6;
        }
        if (period.month() == 12) {
            return 0.8;
        }
        return 1;
    }

    /** Multiplier that plants the archetype pattern; m = months back from the as-of month. */
    @TestVisible
    static Decimal pattern(Integer archetype, String code, Integer m) {
        switch on archetype {
            when 0 {
                if (m <= 6 && (code == 'KNEE_FEM' || code == 'KNEE_TIB' || code == 'KNEE_PAT' || code == 'BONE_CEMENT')) {
                    return 0.55;
                }
            }
            when 1 {
                if (m <= 4 && code == 'PARTIAL_KNEE') {
                    return 0;
                }
            }
            when 2 {
                if (m <= 8 && code == 'KNEE_TIB') {
                    return 0.5;
                }
            }
            when 4 {
                if (m <= 5 && (code == 'HIP_CUP' || code == 'HIP_LINER')) {
                    return 0;
                }
            }
        }
        return 1;
    }

    // ------------------------------------------------------------------ deterministic random

    /** Small LCG seeded per account so re-generating produces the same data. */
    public class Rng {
        private Long state;

        public Rng(Id seed) {
            state = Math.abs(String.valueOf(seed).hashCode()) + 7;
        }

        public Double next() {
            state = Math.mod(state * 1103515245L + 12345L, 2147483648L);
            return state / 2147483648.0;
        }

        public Integer between(Integer lo, Integer hi) {
            return lo + Math.floor(next() * (hi - lo + 1)).intValue();
        }
    }

    public class MockException extends Exception {}
}
