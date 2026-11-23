/**
 * Public tender feeds for the tender radar.
 *
 *  TED  Tenders Electronic Daily (EU / EEA), Search API v3, anonymous. CPV prefixes are filtered by the API.
 *  FTS  Find a Tender (UK, above threshold), OCDS release packages, paginated with a cursor.
 *  PCS  Public Contracts Scotland, OCDS releases per month (also below threshold).
 *
 * Notices are parsed into one shape, deduplicated across portals (same buyer + title), converted to EUR, given a
 * category from CPV codes and title keywords, and matched to accounts by buyer name within the same country.
 * Matched open tenders are read by the TENDER_RADAR rule like any other tender.
 */
public with sharing class WinRoomTenders {

    public static final String TED = 'TED';
    public static final String FTS = 'FTS';
    public static final String PCS = 'PCS';
    public static final Map<String, String> SOURCE_NAMES = new Map<String, String>{
        TED => 'TED (EU)', FTS => 'Find a Tender (UK)', PCS => 'Public Contracts Scotland'
    };
    /** Orthopaedic implants, prostheses and bone fixation (33183*) and fracture fixation devices (33141770). */
    public static final String DEFAULT_CPV = '33183, 33141770';
    public static final Set<String> MAPPED = new Set<String>{ 'Auto-matched', 'Confirmed' };
    /** Statuses set by people: a sync never overwrites them. */
    private static final Set<String> DECIDED = new Set<String>{ 'Submitted', 'Won', 'Lost' };
    private static final Decimal AUTO_MATCH = 0.95;
    private static final Decimal SUGGEST = 0.6;
    private static final Integer DISTINCTIVE_MAX_ACCOUNTS = 3;
    /** A match on one part of the buyer name scores slightly below a match on the whole name. */
    private static final Decimal SEGMENT_WEIGHT = 0.95;

    public static final Map<String, String> ISO3 = new Map<String, String>{
        'AUT' => 'AT', 'BEL' => 'BE', 'BGR' => 'BG', 'CHE' => 'CH', 'CYP' => 'CY', 'CZE' => 'CZ', 'DEU' => 'DE',
        'DNK' => 'DK', 'ESP' => 'ES', 'EST' => 'EE', 'FIN' => 'FI', 'FRA' => 'FR', 'GBR' => 'GB', 'GRC' => 'GR',
        'HRV' => 'HR', 'HUN' => 'HU', 'IRL' => 'IE', 'ISL' => 'IS', 'ITA' => 'IT', 'LIE' => 'LI', 'LTU' => 'LT',
        'LUX' => 'LU', 'LVA' => 'LV', 'MLT' => 'MT', 'NLD' => 'NL', 'NOR' => 'NO', 'POL' => 'PL', 'PRT' => 'PT',
        'ROU' => 'RO', 'SVK' => 'SK', 'SVN' => 'SI', 'SWE' => 'SE'
    };
    public static final Map<String, String> COUNTRY_NAMES = new Map<String, String>{
        'AT' => 'Austria', 'BE' => 'Belgium', 'BG' => 'Bulgaria', 'CH' => 'Switzerland', 'CY' => 'Cyprus',
        'CZ' => 'Czech Republic', 'DE' => 'Germany', 'DK' => 'Denmark', 'ES' => 'Spain', 'EE' => 'Estonia',
        'FI' => 'Finland', 'FR' => 'France', 'GB' => 'United Kingdom', 'GR' => 'Greece', 'HR' => 'Croatia',
        'HU' => 'Hungary', 'IE' => 'Ireland', 'IS' => 'Iceland', 'IT' => 'Italy', 'LI' => 'Liechtenstein',
        'LT' => 'Lithuania', 'LU' => 'Luxembourg', 'LV' => 'Latvia', 'MT' => 'Malta', 'NL' => 'Netherlands',
        'NO' => 'Norway', 'PL' => 'Poland', 'PT' => 'Portugal', 'RO' => 'Romania', 'SK' => 'Slovakia',
        'SI' => 'Slovenia', 'SE' => 'Sweden'
    };
    /** Indicative EUR rates, used only when the org has no multi-currency rates. */
    private static final Map<String, Decimal> FALLBACK_EUR = new Map<String, Decimal>{
        'EUR' => 1, 'GBP' => 1.15, 'CHF' => 1.06, 'PLN' => 0.23, 'CZK' => 0.04, 'HUF' => 0.0025, 'RON' => 0.2,
        'BGN' => 0.511, 'SEK' => 0.087, 'DKK' => 0.134, 'NOK' => 0.085, 'ISK' => 0.0066
    };
    private static final List<String> KNEE_WORDS = new List<String>{
        'knee', 'genou', 'knie', 'rodilla', 'ginocchio', 'kolan', 'joelho', 'kolen', 'knä', 'knæ', 'genunch', 'térd'
    };
    private static final List<String> HIP_WORDS = new List<String>{
        'hip', 'hanche', 'hüft', 'huft', 'cadera', 'anca', 'biodr', 'heup', 'quadril', 'höft', 'hofte', 'kycl', 'csípő'
    };
    private static final List<String> TRAUMA_WORDS = new List<String>{
        'trauma', 'fractur', 'osteosynth', 'złam', 'zlam', 'nail', 'clou', 'chiodo', 'clavo', 'gwoźdź', 'plate'
    };
    private static final Set<String> STOPWORDS = new Set<String>{
        'the', 'of', 'and', 'for', 'at', 'in', 'on', 'de', 'du', 'des', 'la', 'le', 'les', 'el', 'los', 'las', 'di',
        'del', 'della', 'degli', 'da', 'do', 'dos', 'das', 'der', 'die', 'und', 'et', 'y', 'e', 'i', 'w', 'z', 'im',
        'am', 'van', 'het', 'en', 'och', 'og', 'a', 'o', 'u', 'na', 'nhs', 'trust', 'foundation', 'board', 'health',
        'healthcare', 'service', 'services', 'medical', 'hospital', 'hospitals', 'hopital', 'hospitalier',
        'hospitaliere', 'hospitalario', 'hospitaliero', 'ospedale', 'ospedaliera', 'ospedaliero', 'spital', 'szpital',
        'szpitala', 'ziekenhuis', 'krankenhaus', 'klinikum', 'kliniken', 'klinik', 'klinika', 'clinic', 'clinica',
        'clinique', 'centre', 'center', 'centro', 'centrum', 'universitaire', 'universitario', 'universitaria',
        'university', 'universitat', 'universitatsklinikum', 'uniwersytecki', 'general', 'regional', 'region',
        'azienda', 'sanitaria', 'servicio', 'salud', 'publique', 'public', 'sp', 'zoo', 'spa', 'gmbh', 'ag', 'sa',
        'ltd', 'limited', 'plc', 'nv', 'bv', 'ab', 'as', 'oy', 'srl', 'spzoz', 'zoz', 'samodzielny', 'publiczny',
        'zaklad', 'opieki', 'zdrowotnej', 'wojewodzki', 'specjalistyczny', 'chu', 'ch', 'aphp', 'gh', 'groupe'
    };

    /** One notice from any portal, before it is stored. */
    public class Notice {
        public String ref;
        public String source;
        public String title;
        public String buyer;
        public String country;
        public String url;
        public String cpv;
        public String noticeType;
        public String curr;
        public String description;
        public String status;
        public Date published;
        public Date deadline;
        public Decimal value;
    }

    // ================================================================== sources

    /** Feed configuration, with the three portals created on first use. */
    public static List<WR_Tender_Source__c> sources() {
        List<WR_Tender_Source__c> rows = [
            SELECT Id, Name, Code__c, Active__c, CPV_Prefixes__c, Countries__c, Lookback_Days__c, Max_Pages__c,
                   Last_Run__c, Last_Status__c, Last_Fetched__c, Last_Imported__c
            FROM WR_Tender_Source__c ORDER BY Code__c DESC
        ];
        Set<String> have = new Set<String>();
        for (WR_Tender_Source__c s : rows) {
            have.add(s.Code__c);
        }
        List<WR_Tender_Source__c> missing = new List<WR_Tender_Source__c>();
        for (String code : new List<String>{ TED, FTS, PCS }) {
            if (!have.contains(code)) {
                // Public Contracts Scotland starts inactive: its API currently fails TLS validation from Salesforce.
                missing.add(new WR_Tender_Source__c(
                    Name = SOURCE_NAMES.get(code), Code__c = code, Active__c = code != PCS, CPV_Prefixes__c = DEFAULT_CPV,
                    Lookback_Days__c = code == FTS ? 180 : 30, Max_Pages__c = code == FTS ? 10 : 5
                ));
            }
        }
        if (!missing.isEmpty()) {
            insert as user missing;
            rows.addAll(missing);
        }
        return rows;
    }

    public static List<String> cpvPrefixes(WR_Tender_Source__c s) {
        List<String> out = new List<String>();
        for (String p : String.isBlank(s.CPV_Prefixes__c) ? DEFAULT_CPV.split(',') : s.CPV_Prefixes__c.split('[,; ]+')) {
            if (String.isNotBlank(p) && p.trim().isNumeric()) {
                out.add(p.trim());
            }
        }
        return out;
    }

    /** First day to read: the last run (minus a day of overlap) or the lookback window. */
    public static Date fromDate(WR_Tender_Source__c s) {
        Date lookback = Date.today().addDays(-Integer.valueOf(s.Lookback_Days__c == null ? 30 : s.Lookback_Days__c));
        if (s.Last_Run__c == null) {
            return lookback;
        }
        Date last = s.Last_Run__c.date().addDays(-1);
        return last > lookback ? last : lookback;
    }

    // ================================================================== TED

    public static HttpRequest tedRequest(WR_Tender_Source__c s, Date since, Integer page) {
        List<String> cpv = new List<String>();
        for (String p : cpvPrefixes(s)) {
            cpv.add(p + '*');
        }
        String q = 'classification-cpv IN (' + String.join(cpv, ' ') + ') AND notice-type IN (cn-standard cn-social cn-desg)'
            + ' AND publication-date>=' + String.valueOf(since).remove('-');
        List<String> countries = new List<String>();
        if (String.isNotBlank(s.Countries__c)) {
            Map<String, String> toIso3 = new Map<String, String>();
            for (String k : ISO3.keySet()) {
                toIso3.put(ISO3.get(k), k);
            }
            for (String c : s.Countries__c.toUpperCase().split('[,; ]+')) {
                if (toIso3.containsKey(c.trim())) {
                    countries.add(toIso3.get(c.trim()));
                }
            }
        }
        if (!countries.isEmpty()) {
            q += ' AND buyer-country IN (' + String.join(countries, ' ') + ')';
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.ted.europa.eu/v3/notices/search');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'query' => q,
            'fields' => new List<String>{
                'publication-number', 'notice-title', 'buyer-name', 'buyer-country', 'publication-date',
                'deadline-receipt-tender-date-lot', 'classification-cpv', 'estimated-value-lot',
                'estimated-value-cur-lot', 'estimated-value-proc', 'estimated-value-cur-proc', 'notice-type',
                'description-proc'
            },
            'limit' => 100,
            'page' => page,
            'paginationMode' => 'PAGE_NUMBER'
        }));
        return req;
    }

    /** Returns the notices of one TED page and the total count (in out[0] of totals). */
    public static List<Notice> parseTed(String body, List<Integer> totals) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        if (totals != null) {
            totals.add(root.get('totalNoticeCount') == null ? 0 : Integer.valueOf(root.get('totalNoticeCount')));
        }
        List<Notice> out = new List<Notice>();
        for (Object o : (List<Object>) nvlList(root.get('notices'))) {
            Map<String, Object> n = (Map<String, Object>) o;
            String pn = (String) n.get('publication-number');
            if (String.isBlank(pn)) {
                continue;
            }
            Notice t = new Notice();
            t.source = TED;
            t.ref = 'TED-' + pn;
            t.url = 'https://ted.europa.eu/en/notice/-/detail/' + pn;
            t.title = stripCountry(pickLanguage(n.get('notice-title')));
            t.buyer = pickLanguage(n.get('buyer-name'));
            List<Object> countries = nvlList(n.get('buyer-country'));
            t.country = countries.isEmpty() ? null : ISO3.get((String) countries[0]);
            t.published = toDate(n.get('publication-date'));
            t.deadline = nextDeadline(nvlList(n.get('deadline-receipt-tender-date-lot')));
            t.cpv = joinDistinct(nvlList(n.get('classification-cpv')));
            t.noticeType = (String) n.get('notice-type');
            t.description = pickLanguage(n.get('description-proc'));
            Decimal proc = sum(nvlList(n.get('estimated-value-proc')));
            t.value = proc != null ? proc : sum(nvlList(n.get('estimated-value-lot')));
            List<Object> cur = nvlList(n.get(proc != null ? 'estimated-value-cur-proc' : 'estimated-value-cur-lot'));
            t.curr = cur.isEmpty() ? 'EUR' : (String) cur[0];
            t.status = 'Open';
            out.add(t);
        }
        return out;
    }

    // ================================================================== OCDS (Find a Tender, Public Contracts Scotland)

    public static HttpRequest ftsRequest(Date since, Date until, String nextUrl) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(nextUrl != null ? nextUrl
            : 'https://www.find-tender.service.gov.uk/api/1.0/ocdsReleasePackages?stages=tender&limit=100&updatedFrom='
              + String.valueOf(since) + 'T00:00:00&updatedTo=' + String.valueOf(until) + 'T00:00:00');
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        return req;
    }

    public static HttpRequest pcsRequest(Date month) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.publiccontractsscotland.gov.uk/v1/Notices?dateFrom='
            + String.valueOf(month.month()).leftPad(2, '0') + '-' + month.year() + '&noticeType=2&outputType=0');
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(60000);
        return req;
    }

    /** One OCDS release package: the notices in scope, how many releases it held and the next page link. */
    public class OcdsPage {
        public List<Notice> notices = new List<Notice>();
        public Integer releases = 0;
        public String nextUrl;
    }

    /** Tender-stage releases whose CPV codes start with one of the prefixes. */
    public static OcdsPage parseOcds(String body, String source, List<String> prefixes) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        OcdsPage page = new OcdsPage();
        Map<String, Object> links = (Map<String, Object>) root.get('links');
        page.nextUrl = links == null ? null : (String) links.get('next');
        Map<String, Notice> byRef = new Map<String, Notice>();
        List<Object> releases = nvlList(root.get('releases'));
        page.releases = releases.size();
        for (Object o : releases) {
            Map<String, Object> r = (Map<String, Object>) o;
            Map<String, Object> td = (Map<String, Object>) r.get('tender');
            if (td == null) {
                continue;
            }
            List<String> cpvs = new List<String>();
            addCpv(cpvs, td.get('classification'));
            for (Object i : nvlList(td.get('items'))) {
                Map<String, Object> item = (Map<String, Object>) i;
                addCpv(cpvs, item.get('classification'));
                for (Object c : nvlList(item.get('additionalClassifications'))) {
                    addCpv(cpvs, c);
                }
            }
            if (!matchesPrefix(cpvs, prefixes)) {
                continue;
            }
            Notice t = new Notice();
            t.source = source;
            String id = (String) r.get('id');
            Map<String, Object> buyer = (Map<String, Object>) r.get('buyer');
            t.buyer = buyer == null ? null : (String) buyer.get('name');
            t.country = 'GB';
            t.title = (String) td.get('title');
            t.description = (String) td.get('description');
            t.cpv = joinDistinct(cpvs);
            t.noticeType = 'tender';
            t.published = toDate(r.get('date'));
            Map<String, Object> period = (Map<String, Object>) td.get('tenderPeriod');
            t.deadline = period == null ? null : toDate(period.get('endDate'));
            Map<String, Object> v = (Map<String, Object>) td.get('value');
            if (v != null && v.get('amount') != null) {
                t.value = Decimal.valueOf(String.valueOf(v.get('amount')));
                t.curr = v.get('currency') == null ? 'GBP' : (String) v.get('currency');
            }
            String st = (String) td.get('status');
            t.status = st == 'cancelled' ? 'Cancelled' : (st == 'complete' || st == 'unsuccessful' ? 'Closed' : 'Open');
            if (source == FTS) {
                t.ref = 'FTS-' + id;
                t.url = 'https://www.find-tender.service.gov.uk/Notice/' + id;
            } else {
                // PCS release ids look like rls-2-NOV569337: the notice id is the last part.
                String noticeId = id == null ? (String) r.get('ocid') : id.substringAfterLast('-');
                t.ref = 'PCS-' + noticeId;
                t.url = 'https://www.publiccontractsscotland.gov.uk/search/show/search_view.aspx?ID=' + noticeId;
                for (Object d : nvlList(td.get('documents'))) {
                    Map<String, Object> doc = (Map<String, Object>) d;
                    if (doc.get('documentType') == 'contractNotice' && doc.get('url') != null) {
                        t.url = (String) doc.get('url');
                    }
                }
            }
            // A package can hold several versions of one notice: the last one wins.
            byRef.put(t.ref, t);
        }
        page.notices = byRef.values();
        return page;
    }

    // ================================================================== store

    /**
     * Inserts new notices and refreshes known ones. Keeps account links and human statuses; skips a notice already
     * stored from another portal (same buyer + title). Returns the number of notices inserted or updated.
     */
    public static Integer store(List<Notice> notices) {
        Map<String, Notice> byRef = new Map<String, Notice>();
        Map<String, String> keyOf = new Map<String, String>();
        for (Notice n : notices) {
            if (String.isBlank(n.title)) {
                continue;
            }
            byRef.put(n.ref, n);
            keyOf.put(n.ref, dedupeKey(n.buyer, n.title));
        }
        if (byRef.isEmpty()) {
            return 0;
        }
        Map<String, WR_Tender__c> existing = new Map<String, WR_Tender__c>();
        Map<String, String> refByKey = new Map<String, String>();
        Set<String> keys = new Set<String>(keyOf.values());
        for (WR_Tender__c t : [
            SELECT Id, Reference__c, Status__c, Dedupe_Key__c FROM WR_Tender__c
            WHERE Reference__c IN :byRef.keySet() OR Dedupe_Key__c IN :keys
        ]) {
            if (byRef.containsKey(t.Reference__c)) {
                existing.put(t.Reference__c, t);
            }
            refByKey.put(t.Dedupe_Key__c, t.Reference__c);
        }
        Map<String, Decimal> rates = eurRates();
        Datetime now = Datetime.now();
        List<WR_Tender__c> inserts = new List<WR_Tender__c>();
        List<WR_Tender__c> updates = new List<WR_Tender__c>();
        for (Notice n : byRef.values()) {
            String key = keyOf.get(n.ref);
            WR_Tender__c old = existing.get(n.ref);
            if (old == null && refByKey.containsKey(key)) {
                continue;
            }
            refByKey.put(key, n.ref);
            String status = n.status;
            if (status == 'Open' && n.deadline != null && n.deadline < Date.today()) {
                status = 'Closed';
            }
            WR_Tender__c t = new WR_Tender__c(
                Name = n.title.abbreviate(80),
                Title__c = n.title.abbreviate(255),
                Buyer_Name__c = n.buyer == null ? null : n.buyer.abbreviate(255),
                Country__c = COUNTRY_NAMES.containsKey(n.country) ? n.country : null,
                Category__c = category(n.cpv, n.title + ' ' + nvl(n.description)),
                Publication_Date__c = n.published,
                Deadline__c = n.deadline,
                Original_Value__c = n.value,
                Currency__c = n.curr,
                Estimated_Value__c = toEur(n.value, n.curr, rates),
                Source__c = SOURCE_NAMES.get(n.source),
                URL__c = n.url,
                CPV_Codes__c = n.cpv == null ? null : n.cpv.abbreviate(255),
                Notice_Type__c = n.noticeType,
                Description__c = n.description == null ? null : n.description.abbreviate(32000),
                Dedupe_Key__c = key,
                Last_Synced__c = now
            );
            if (old == null) {
                t.Reference__c = n.ref;
                t.Status__c = status;
                t.Match_Status__c = 'Unmatched';
                inserts.add(t);
            } else {
                t.Id = old.Id;
                if (!DECIDED.contains(old.Status__c)) {
                    t.Status__c = status;
                }
                updates.add(t);
            }
        }
        insert as user inserts;
        update as user updates;
        return inserts.size() + updates.size();
    }

    /** Imported tenders whose deadline has passed are closed (demo tenders and human statuses are left alone). */
    public static Integer closeExpired() {
        List<WR_Tender__c> rows = [
            SELECT Id FROM WR_Tender__c
            WHERE Status__c = 'Open' AND Deadline__c < TODAY AND Is_Demo__c = false AND Last_Synced__c != null
            LIMIT 5000
        ];
        for (WR_Tender__c t : rows) {
            t.Status__c = 'Closed';
        }
        update as user rows;
        return rows.size();
    }

    // ================================================================== matching

    /** Links unmatched tenders to accounts of the same country by buyer name. Returns counts per outcome. */
    public static Map<String, Integer> autoMatch() {
        Map<String, Integer> counts = new Map<String, Integer>{ 'auto' => 0, 'suggested' => 0, 'unmatched' => 0 };
        List<WR_Tender__c> tenders = [
            SELECT Id, Buyer_Name__c, Country__c FROM WR_Tender__c
            WHERE Account__c = null AND (Match_Status__c IN ('Unmatched', 'Suggested') OR Match_Status__c = null) AND Is_Demo__c = false
            AND Buyer_Name__c != null LIMIT 5000
        ];
        if (tenders.isEmpty()) {
            return counts;
        }
        Set<String> countryValues = new Set<String>();
        for (WR_Tender__c t : tenders) {
            if (t.Country__c != null) {
                countryValues.addAll(countryVariants(t.Country__c));
            }
        }
        // Per country: account tokens, an inverted index and how many accounts use each word.
        Map<String, List<Account>> accByCountry = new Map<String, List<Account>>();
        Map<String, List<Set<String>>> tokByCountry = new Map<String, List<Set<String>>>();
        Map<String, Map<String, Set<Integer>>> indexByCountry = new Map<String, Map<String, Set<Integer>>>();
        for (Account a : [
            SELECT Id, Name, BillingCountry FROM Account WHERE BillingCountry IN :countryValues ORDER BY Name LIMIT 20000
        ]) {
            String c = isoOf(a.BillingCountry);
            if (!accByCountry.containsKey(c)) {
                accByCountry.put(c, new List<Account>());
                tokByCountry.put(c, new List<Set<String>>());
                indexByCountry.put(c, new Map<String, Set<Integer>>());
            }
            Integer i = accByCountry.get(c).size();
            Set<String> tok = tokens(a.Name);
            accByCountry.get(c).add(a);
            tokByCountry.get(c).add(tok);
            Map<String, Set<Integer>> index = indexByCountry.get(c);
            for (String w : tok) {
                if (!index.containsKey(w)) {
                    index.put(w, new Set<Integer>());
                }
                index.get(w).add(i);
            }
        }
        List<WR_Tender__c> updates = new List<WR_Tender__c>();
        for (WR_Tender__c t : tenders) {
            WR_Tender__c u = new WR_Tender__c(Id = t.Id, Match_Status__c = 'Unmatched', Suggested_Account__c = null);
            Map<String, Set<Integer>> index = indexByCountry.get(t.Country__c);
            Set<String> buyerTok = tokens(t.Buyer_Name__c);
            // "Servicio Andaluz de Salud. Hospital Virgen del Rocio": each part of the name is also scored on its own.
            List<Set<String>> segments = new List<Set<String>>();
            for (String part : t.Buyer_Name__c.split('\\s+[-–/|]\\s+|[.;,:(]\\s+')) {
                Set<String> segTok = tokens(part);
                if (!segTok.isEmpty() && segTok.size() < buyerTok.size()) {
                    segments.add(segTok);
                }
            }
            Decimal best = 0;
            Integer bestIdx;
            if (index != null) {
                Set<Integer> candidates = new Set<Integer>();
                for (String w : buyerTok) {
                    if (index.containsKey(w)) {
                        candidates.addAll(index.get(w));
                    }
                }
                List<Set<String>> accTok = tokByCountry.get(t.Country__c);
                for (Integer i : candidates) {
                    Decimal score = WinRoomMarket.dice(buyerTok, accTok[i]);
                    for (Set<String> segTok : segments) {
                        score = Math.max(score, WinRoomMarket.dice(segTok, accTok[i]) * SEGMENT_WEIGHT);
                    }
                    if (score > best && sharesDistinctive(buyerTok, accTok[i], index)) {
                        best = score;
                        bestIdx = i;
                    }
                }
            }
            u.Match_Score__c = (best * 100).setScale(0);
            // A link is only automatic when at least two words agree: "La Paz" alone stays a suggestion.
            if (bestIdx != null && best >= AUTO_MATCH && commonWords(buyerTok, tokByCountry.get(t.Country__c)[bestIdx]) >= 2) {
                u.Account__c = accByCountry.get(t.Country__c)[bestIdx].Id;
                u.Match_Status__c = 'Auto-matched';
                counts.put('auto', counts.get('auto') + 1);
            } else if (bestIdx != null && best >= SUGGEST) {
                u.Suggested_Account__c = accByCountry.get(t.Country__c)[bestIdx].Id;
                u.Match_Status__c = 'Suggested';
                counts.put('suggested', counts.get('suggested') + 1);
            } else {
                counts.put('unmatched', counts.get('unmatched') + 1);
            }
            updates.add(u);
        }
        update as user updates;
        return counts;
    }

    /** Confirms, changes, ignores or clears the account of a tender. */
    public static void setMapping(Id tenderId, Id accountId, String status) {
        WR_Tender__c t = new WR_Tender__c(Id = tenderId, Suggested_Account__c = null);
        if (status == 'Confirmed' && accountId != null) {
            t.Account__c = accountId;
            t.Match_Status__c = 'Confirmed';
        } else {
            t.Account__c = null;
            t.Match_Status__c = status == 'Ignored' ? 'Ignored' : 'Unmatched';
        }
        update as user t;
    }

    // ================================================================== helpers

    @TestVisible
    static String category(String cpv, String text) {
        // Keywords match the start of a word ("hip" in "hip stems", not in "shipping").
        String s = ' ' + (text == null ? '' : text).toLowerCase().replaceAll('[^\\p{L}0-9]+', ' ');
        if (s.contains('robot')) {
            return 'Robotics';
        }
        Boolean knee = containsAny(s, KNEE_WORDS);
        Boolean hip = containsAny(s, HIP_WORDS);
        if (knee && hip) {
            return 'Knee & Hip';
        }
        if (knee) {
            return 'Knee';
        }
        if (hip) {
            return 'Hip';
        }
        if ((cpv != null && cpv.contains('33141770')) || containsAny(s, TRAUMA_WORDS)) {
            return 'Trauma';
        }
        return 'Orthopaedics';
    }

    @TestVisible
    static Set<String> tokens(String name) {
        Set<String> out = new Set<String>();
        if (String.isBlank(name)) {
            return out;
        }
        String n = fold(name.toLowerCase()).replace('&', ' and ').replaceAll('[\'’`.]', '').replaceAll('[^a-z0-9 ]', ' ');
        for (String t : n.split('\\s+')) {
            if (t == 'saint' || t == 'sankt' || t == 'santa' || t == 'santo' || t == 'san' || t == 'sao') {
                t = 'st';
            }
            if (t.length() > 1 && !STOPWORDS.contains(t)) {
                out.add(t);
            }
        }
        return out;
    }

    /** Removes accents so that buyer names in any language tokenise the same way as account names. */
    @TestVisible
    static String fold(String s) {
        Map<String, String> m = new Map<String, String>{
            'á' => 'a', 'à' => 'a', 'â' => 'a', 'ä' => 'a', 'ã' => 'a', 'å' => 'a', 'ą' => 'a', 'ă' => 'a',
            'é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e', 'ę' => 'e', 'ě' => 'e', 'í' => 'i', 'ì' => 'i',
            'î' => 'i', 'ï' => 'i', 'ó' => 'o', 'ò' => 'o', 'ô' => 'o', 'ö' => 'o', 'õ' => 'o', 'ø' => 'o',
            'ő' => 'o', 'ú' => 'u', 'ù' => 'u', 'û' => 'u', 'ü' => 'u', 'ű' => 'u', 'ů' => 'u', 'ç' => 'c',
            'ć' => 'c', 'č' => 'c', 'ł' => 'l', 'ń' => 'n', 'ñ' => 'n', 'ň' => 'n', 'ś' => 's', 'š' => 's',
            'ș' => 's', 'ş' => 's', 'ź' => 'z', 'ż' => 'z', 'ž' => 'z', 'ř' => 'r', 'ý' => 'y', 'ț' => 't',
            'ţ' => 't', 'ď' => 'd', 'đ' => 'd', 'ß' => 'ss', 'æ' => 'ae', 'œ' => 'oe'
        };
        String out = '';
        for (Integer i = 0; i < s.length(); i++) {
            String ch = s.substring(i, i + 1);
            out += m.containsKey(ch) ? m.get(ch) : ch;
        }
        return out;
    }

    private static Integer commonWords(Set<String> a, Set<String> b) {
        Integer n = 0;
        for (String w : a) {
            if (b.contains(w)) {
                n++;
            }
        }
        return n;
    }

    private static Boolean sharesDistinctive(Set<String> buyerTok, Set<String> accTok, Map<String, Set<Integer>> index) {
        for (String w : buyerTok) {
            if (accTok.contains(w) && index.containsKey(w) && index.get(w).size() <= DISTINCTIVE_MAX_ACCOUNTS) {
                return true;
            }
        }
        return false;
    }

    public static String dedupeKey(String buyer, String title) {
        String s = String.join(new List<String>(tokens(buyer)), ' ') + '|' + fold(nvl(title).toLowerCase()).replaceAll('[^a-z0-9]', '');
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(s)));
    }

    /** EUR per unit of each currency: org rates when multi-currency is on, else indicative rates. */
    private static Map<String, Decimal> eurRates() {
        Map<String, Decimal> out = new Map<String, Decimal>(FALLBACK_EUR);
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return out;
        }
        Map<String, Decimal> perCorporate = new Map<String, Decimal>();
        for (SObject c : Database.query('SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = true')) {
            perCorporate.put((String) c.get('IsoCode'), (Decimal) c.get('ConversionRate'));
        }
        if (!perCorporate.containsKey('EUR')) {
            return out;
        }
        for (String iso : perCorporate.keySet()) {
            out.put(iso, perCorporate.get('EUR') / perCorporate.get(iso));
        }
        return out;
    }

    private static Decimal toEur(Decimal value, String curr, Map<String, Decimal> rates) {
        if (value == null) {
            return null;
        }
        String c = String.isBlank(curr) ? 'EUR' : curr.toUpperCase();
        return rates.containsKey(c) ? (value * rates.get(c)).setScale(2) : null;
    }

    private static Set<String> countryVariants(String iso) {
        Set<String> out = new Set<String>{ iso };
        if (COUNTRY_NAMES.containsKey(iso)) {
            out.add(COUNTRY_NAMES.get(iso));
        }
        if (iso == 'GB') {
            out.addAll(new Set<String>{ 'UK', 'England', 'Scotland', 'Wales', 'Northern Ireland', 'Great Britain' });
        }
        return out;
    }

    private static String isoOf(String billingCountry) {
        String c = billingCountry == null ? '' : billingCountry.trim();
        if (COUNTRY_NAMES.containsKey(c.toUpperCase())) {
            return c.toUpperCase();
        }
        for (String iso : COUNTRY_NAMES.keySet()) {
            if (COUNTRY_NAMES.get(iso).equalsIgnoreCase(c)) {
                return iso;
            }
        }
        return countryVariants('GB').contains(c) ? 'GB' : c;
    }

    private static String pickLanguage(Object value) {
        if (value instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) value;
            Object v = m.containsKey('eng') ? m.get('eng') : (m.isEmpty() ? null : m.values()[0]);
            if (v instanceof List<Object>) {
                List<Object> l = (List<Object>) v;
                return l.isEmpty() ? null : String.valueOf(l[0]);
            }
            return v == null ? null : String.valueOf(v);
        }
        return value == null ? null : String.valueOf(value);
    }

    /** TED titles read "Country – Subject – Original title": the country is already a field. */
    private static String stripCountry(String title) {
        if (title == null) {
            return null;
        }
        Integer i = title.indexOf(' – ');
        return i > 0 && i < 40 ? title.substring(i + 3) : title;
    }

    /** The earliest deadline still ahead, or the latest one when all have passed. */
    private static Date nextDeadline(List<Object> values) {
        Date next;
        Date latest;
        for (Object o : values) {
            Date d = toDate(o);
            if (d == null) {
                continue;
            }
            if (d >= Date.today() && (next == null || d < next)) {
                next = d;
            }
            if (latest == null || d > latest) {
                latest = d;
            }
        }
        return next != null ? next : latest;
    }

    private static Date toDate(Object value) {
        String s = value == null ? null : String.valueOf(value);
        if (s == null || s.length() < 10) {
            return null;
        }
        try {
            return Date.valueOf(s.left(10));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal sum(List<Object> values) {
        Decimal total;
        for (Object o : values) {
            if (o == null) {
                continue;
            }
            try {
                total = (total == null ? 0 : total) + Decimal.valueOf(String.valueOf(o));
            } catch (Exception e) {
                continue;
            }
        }
        return total;
    }

    private static void addCpv(List<String> out, Object classification) {
        if (classification instanceof Map<String, Object>) {
            Map<String, Object> c = (Map<String, Object>) classification;
            if (c.get('id') != null && (c.get('scheme') == null || String.valueOf(c.get('scheme')).equalsIgnoreCase('CPV'))) {
                out.add(String.valueOf(c.get('id')));
            }
        }
    }

    private static Boolean matchesPrefix(List<String> cpvs, List<String> prefixes) {
        for (String c : cpvs) {
            for (String p : prefixes) {
                if (c.startsWith(p)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static String joinDistinct(List<Object> values) {
        Set<String> seen = new Set<String>();
        List<String> out = new List<String>();
        for (Object o : values) {
            String s = String.valueOf(o);
            if (o != null && seen.add(s)) {
                out.add(s);
            }
        }
        return out.isEmpty() ? null : String.join(out, ', ');
    }

    private static Boolean containsAny(String s, List<String> words) {
        for (String w : words) {
            if (s.contains(' ' + w)) {
                return true;
            }
        }
        return false;
    }

    private static List<Object> nvlList(Object o) {
        return o instanceof List<Object> ? (List<Object>) o : new List<Object>();
    }

    private static String nvl(String s) {
        return s == null ? '' : s;
    }
}
