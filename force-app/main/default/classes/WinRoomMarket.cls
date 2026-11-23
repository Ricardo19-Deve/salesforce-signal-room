/**
 * Market volumes from an external procedure registry. UK: National Joint Registry (NJR) StatsOnline, whose official
 * CSV export ("Download all NJR statistics") gives hip / knee procedures per hospital and month.
 *
 * Flow: an admin downloads the CSV from the NJR site and uploads it in the portal (Market view). The browser keeps
 * the last 24 months and sends one aggregate per hospital (importSites). autoMatch() links hospitals to Accounts by
 * hospital or trust name; admins confirm or correct the suggestions (setMapping). applyVolumes() copies the 12-month
 * volumes of the mapped hospitals into the account profile (Volume_Source__c = NJR), which feeds share of wallet,
 * peer sizing and greenfield rules.
 *
 * Several registry hospitals can map to one account (e.g. a trust with two sites). No callout is made.
 */
public with sharing class WinRoomMarket {

    public static final String SOURCE_NJR = 'NJR';
    public static final Set<String> MAPPED = new Set<String>{ 'Auto-matched', 'Confirmed' };
    private static final Set<String> GB = new Set<String>{ 'GB', 'UK', 'United Kingdom', 'England', 'Wales', 'Northern Ireland', 'Scotland' };
    private static final Set<String> STOPWORDS = new Set<String>{
        'the', 'hospital', 'hospitals', 'nhs', 'foundation', 'trust', 'ft', 'university', 'universities', 'teaching',
        'of', 'and', 'general', 'healthcare', 'health', 'services', 'limited', 'ltd', 'group', 'care', 'district',
        'county', 'community', 'centre', 'center', 'site', 'sites', 'plc', 'uk'
    };
    private static final Decimal AUTO_MATCH = 0.95;
    private static final Decimal SUGGEST = 0.6;
    // A word used by more registry hospitals than this ("royal", "infirmary", "london") cannot carry a suggestion alone.
    private static final Integer DISTINCTIVE_MAX_SITES = 4;

    public class SiteInput {
        public String key;
        public String name;
        public String providerType;
        public String orgCode;
        public String orgName;
        public String region;
        public Decimal hip12;
        public Decimal knee12;
        public Decimal hipPrior;
        public Decimal kneePrior;
        public Decimal total12;
        public List<String> months;
        public List<Decimal> hip;
        public List<Decimal> knee;
        public String asOf;
    }

    /** Upserts registry hospitals; mapping fields are never overwritten by an import. */
    public static Integer importSites(String sitesJson) {
        List<SiteInput> input = (List<SiteInput>) JSON.deserialize(sitesJson, List<SiteInput>.class);
        List<WR_Market_Site__c> rows = new List<WR_Market_Site__c>();
        for (SiteInput s : input) {
            rows.add(new WR_Market_Site__c(
                Site_Key__c = (SOURCE_NJR + '|' + s.key).left(200),
                Name = s.name.left(80),
                Source__c = SOURCE_NJR,
                Provider_Type__c = s.providerType == 'NHS' ? 'NHS' : 'Independent Sector',
                Org_Code__c = s.orgCode == null ? null : s.orgCode.left(20),
                Org_Name__c = s.orgName == null ? null : s.orgName.left(255),
                Region__c = s.region == null ? null : s.region.left(80),
                Country__c = 'GB',
                Hip_12m__c = s.hip12,
                Knee_12m__c = s.knee12,
                Hip_Prior_12m__c = s.hipPrior,
                Knee_Prior_12m__c = s.kneePrior,
                Total_12m__c = s.total12,
                Monthly_JSON__c = JSON.serialize(new Map<String, Object>{ 'months' => s.months, 'hip' => s.hip, 'knee' => s.knee }),
                Data_As_Of__c = String.isBlank(s.asOf) ? Date.today() : Date.valueOf(s.asOf)
            ));
        }
        upsert as user rows Site_Key__c;
        return rows.size();
    }

    /** Links unmapped hospitals to UK accounts by name. Returns counts per outcome. */
    public static Map<String, Integer> autoMatch() {
        List<Account> accounts = [
            SELECT Id, Name FROM Account WHERE BillingCountry IN :GB ORDER BY Name LIMIT 20000
        ];
        List<Set<String>> accTokens = new List<Set<String>>();
        Map<String, Set<Integer>> index = new Map<String, Set<Integer>>();
        for (Integer i = 0; i < accounts.size(); i++) {
            Set<String> t = tokens(accounts[i].Name);
            accTokens.add(t);
            for (String tok : t) {
                if (!index.containsKey(tok)) {
                    index.put(tok, new Set<Integer>());
                }
                index.get(tok).add(i);
            }
        }
        Map<String, Integer> counts = new Map<String, Integer>{ 'auto' => 0, 'suggested' => 0, 'unmatched' => 0 };
        Map<String, Integer> siteFrequency = new Map<String, Integer>();
        for (WR_Market_Site__c s : [SELECT Name, Org_Name__c FROM WR_Market_Site__c]) {
            Set<String> words = tokens(s.Name);
            words.addAll(tokens(s.Org_Name__c));
            for (String w : words) {
                siteFrequency.put(w, (siteFrequency.containsKey(w) ? siteFrequency.get(w) : 0) + 1);
            }
        }
        List<WR_Market_Site__c> updates = new List<WR_Market_Site__c>();
        Set<Id> mappedAccounts = new Set<Id>();
        for (WR_Market_Site__c s : [
            SELECT Id, Name, Org_Name__c FROM WR_Market_Site__c
            WHERE Account__c = null AND Match_Status__c != 'Ignored'
        ]) {
            Set<String> siteTok = tokens(s.Name);
            Set<String> orgTok = tokens(s.Org_Name__c);
            Set<Integer> candidates = new Set<Integer>();
            for (String tok : siteTok) {
                if (index.containsKey(tok)) {
                    candidates.addAll(index.get(tok));
                }
            }
            for (String tok : orgTok) {
                if (index.containsKey(tok)) {
                    candidates.addAll(index.get(tok));
                }
            }
            Decimal best = 0;
            Integer bestIdx = null;
            for (Integer i : candidates) {
                // A trust-level account matches all its hospitals, slightly below an exact hospital match.
                Decimal score = Math.max(dice(siteTok, accTokens[i]), dice(orgTok, accTokens[i]) * 0.95);
                if (score > best) {
                    best = score;
                    bestIdx = i;
                }
            }
            WR_Market_Site__c u = new WR_Market_Site__c(Id = s.Id, Match_Score__c = (best * 100).setScale(0));
            if (bestIdx != null && best >= AUTO_MATCH) {
                u.Account__c = accounts[bestIdx].Id;
                u.Suggested_Account__c = null;
                u.Match_Status__c = 'Auto-matched';
                mappedAccounts.add(u.Account__c);
                counts.put('auto', counts.get('auto') + 1);
            } else if (bestIdx != null && best >= SUGGEST
                    && sharesDistinctive(siteTok, orgTok, accTokens[bestIdx], siteFrequency)) {
                u.Suggested_Account__c = accounts[bestIdx].Id;
                u.Match_Status__c = 'Suggested';
                counts.put('suggested', counts.get('suggested') + 1);
            } else {
                u.Suggested_Account__c = null;
                u.Match_Status__c = 'Unmatched';
                counts.put('unmatched', counts.get('unmatched') + 1);
            }
            updates.add(u);
        }
        update as user updates;
        // Refresh every mapped account, not only the new matches: a re-import changes the volumes of existing links.
        for (AggregateResult ar : [
            SELECT Account__c a FROM WR_Market_Site__c WHERE Account__c != null AND Match_Status__c IN :MAPPED GROUP BY Account__c
        ]) {
            mappedAccounts.add((Id) ar.get('a'));
        }
        applyVolumes(mappedAccounts);
        return counts;
    }

    /** Confirms, changes, ignores or clears the account of a registry hospital. */
    public static void setMapping(Id siteId, Id accountId, String status) {
        WR_Market_Site__c s = [SELECT Id, Account__c FROM WR_Market_Site__c WHERE Id = :siteId];
        Set<Id> affected = new Set<Id>();
        if (s.Account__c != null) {
            affected.add(s.Account__c);
        }
        WR_Market_Site__c u = new WR_Market_Site__c(Id = siteId);
        if (status == 'Ignored' || accountId == null) {
            u.Account__c = null;
            u.Match_Status__c = status == 'Ignored' ? 'Ignored' : 'Unmatched';
        } else {
            u.Account__c = accountId;
            u.Suggested_Account__c = null;
            u.Match_Status__c = 'Confirmed';
            affected.add(accountId);
        }
        update as user u;
        applyVolumes(affected);
    }

    /**
     * Copies the 12-month hip / knee volumes of mapped hospitals into the account profiles (creating a profile when
     * the account has none). Accounts that lost all their hospitals go back to Volume_Source__c = Estimate.
     */
    public static void applyVolumes(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return;
        }
        Map<Id, Decimal[]> volumes = new Map<Id, Decimal[]>();
        Map<Id, String> providerByAccount = new Map<Id, String>();
        Map<Id, Date> asOfByAccount = new Map<Id, Date>();
        for (WR_Market_Site__c s : [
            SELECT Account__c, Hip_12m__c, Knee_12m__c, Provider_Type__c, Data_As_Of__c
            FROM WR_Market_Site__c WHERE Account__c IN :accountIds AND Match_Status__c IN :MAPPED
        ]) {
            if (!volumes.containsKey(s.Account__c)) {
                volumes.put(s.Account__c, new Decimal[]{ 0, 0 });
            }
            Decimal[] v = volumes.get(s.Account__c);
            v[0] += s.Hip_12m__c == null ? 0 : s.Hip_12m__c;
            v[1] += s.Knee_12m__c == null ? 0 : s.Knee_12m__c;
            providerByAccount.put(s.Account__c, s.Provider_Type__c);
            asOfByAccount.put(s.Account__c, s.Data_As_Of__c);
        }
        Map<Id, WR_Account_Profile__c> profiles = new Map<Id, WR_Account_Profile__c>();
        for (WR_Account_Profile__c p : [
            SELECT Id, Account__c, Volume_Source__c FROM WR_Account_Profile__c WHERE Account__c IN :accountIds
        ]) {
            profiles.put(p.Account__c, p);
        }
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Name, OwnerId FROM Account WHERE Id IN :accountIds]);
        List<WR_Account_Profile__c> upserts = new List<WR_Account_Profile__c>();
        for (Id accId : accountIds) {
            WR_Account_Profile__c existing = profiles.get(accId);
            if (!volumes.containsKey(accId)) {
                if (existing != null && existing.Volume_Source__c == SOURCE_NJR) {
                    upserts.add(new WR_Account_Profile__c(Id = existing.Id, Volume_Source__c = 'Estimate'));
                }
                continue;
            }
            Decimal[] v = volumes.get(accId);
            WR_Account_Profile__c p = existing != null
                ? new WR_Account_Profile__c(Id = existing.Id)
                : newProfile(accounts.get(accId), providerByAccount.get(accId), v[0] + v[1]);
            p.Hip_Procedures__c = v[0];
            p.Knee_Procedures__c = v[1];
            p.Volume_Source__c = SOURCE_NJR;
            p.Volume_As_Of__c = asOfByAccount.get(accId);
            upserts.add(p);
        }
        upsert as user upserts;
    }

    private static WR_Account_Profile__c newProfile(Account a, String providerType, Decimal total) {
        return new WR_Account_Profile__c(
            Name = a.Name.left(80),
            Account__c = a.Id,
            Account_Key__c = a.Id,
            Country__c = 'GB',
            Segment__c = providerType == 'NHS' ? 'Public Hospital' : 'Private Clinic',
            Size_Band__c = total >= 1200 ? 'Large' : (total >= 500 ? 'Medium' : 'Small'),
            Phase__c = 'Peer only',
            In_Scope__c = false,
            Rep__c = a.OwnerId
        );
    }

    /** Average implant basket per procedure (from the product line prices). */
    public static Decimal basket(String category) {
        Map<String, Decimal> price = new Map<String, Decimal>();
        for (WR_Product_Line__c l : [SELECT Code__c, Avg_Price__c FROM WR_Product_Line__c]) {
            price.put(l.Code__c, l.Avg_Price__c == null ? 0 : l.Avg_Price__c);
        }
        if (category == 'Knee') {
            return nz(price.get('KNEE_FEM')) + nz(price.get('KNEE_TIB')) + nz(price.get('KNEE_PAT'));
        }
        return nz(price.get('HIP_CUP')) + nz(price.get('HIP_LINER')) + nz(price.get('HIP_STEM_T')) + nz(price.get('HIP_HEAD'));
    }

    private static Boolean sharesDistinctive(Set<String> siteTok, Set<String> orgTok, Set<String> accTok,
            Map<String, Integer> siteFrequency) {
        Set<String> words = new Set<String>(siteTok);
        words.addAll(orgTok);
        for (String w : words) {
            if (accTok.contains(w) && (!siteFrequency.containsKey(w) || siteFrequency.get(w) <= DISTINCTIVE_MAX_SITES)) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    static Set<String> tokens(String name) {
        Set<String> out = new Set<String>();
        if (String.isBlank(name)) {
            return out;
        }
        String n = name.toLowerCase().replace('&', ' and ').replaceAll('[\'’`]', '').replaceAll('[^a-z0-9 ]', ' ');
        for (String t : n.split('\\s+')) {
            if (t == 'saint') {
                t = 'st';
            }
            if (String.isNotBlank(t) && !STOPWORDS.contains(t)) {
                out.add(t);
            }
        }
        return out;
    }

    @TestVisible
    static Decimal dice(Set<String> a, Set<String> b) {
        if (a.isEmpty() || b.isEmpty()) {
            return 0;
        }
        Integer common = 0;
        for (String t : a) {
            if (b.contains(t)) {
                common++;
            }
        }
        return Decimal.valueOf(2 * common) / (a.size() + b.size());
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
