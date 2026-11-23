/**
 * Default product-line catalogue and opportunity-identification rules for the
 * Win Room. Rules are stored as WR_Rule__c records so admins can tune
 * thresholds from the portal; this class only (re)seeds the defaults.
 *
 * How the generic rule fields are interpreted per Rule_Type__c:
 *
 *  WINBACK_SOFT        Recent_Months__c window vs. the same window one year earlier.
 *                      Threshold_Pct__c = minimum revenue drop. Value = annualised gap.
 *  WINBACK_HARD        Zero units in the last Recent_Months__c while the previous
 *                      Lookback_Months__c had >= Min_Value__c revenue. Value = lost 12m revenue.
 *  ATTACH              Target units / anchor units over Lookback_Months__c is below
 *                      Expected_Ratio__c * (1 - Threshold_Pct__c). If the target used to be
 *                      bought at the expected ratio it is a partial switch (win back),
 *                      otherwise a cross-sell gap. Value = missing units * price.
 *  CAPITAL_PULLTHROUGH Account uses the anchor capital line (e.g. Atlas Robotic Knee) but not the
 *                      target workflow (Atlas Robotic Hip) although it has hip volume.
 *                      Expected_Ratio__c = share of hip procedures expected on the workflow.
 *  PEER_WHITESPACE     Line bought by >= Threshold_Pct__c of accounts in the same segment
 *                      but not by this account. Value = peer average scaled by account size.
 *  SURGEON_SITE        Surgeon buys Contoso at one site, operates at another site without Contoso.
 *                      Threshold_Pct__c = share of the surgeon's procedures we can win.
 *  NEW_SURGEON         Affiliation started in the last Recent_Months__c, no Contoso sales yet.
 *  TENDER_RADAR        Open tender with deadline within Lookback_Months__c months.
 *                      Threshold_Pct__c = expected win probability for the value at stake.
 *  SHARE_OF_WALLET     Contoso 12m revenue / estimated market (procedures * basket) below
 *                      Threshold_Pct__c. Expected_Ratio__c = target share. Value = gap to target.
 */
public with sharing class WinRoomRules {

    public static final String CAT_WINBACK = 'Win back';
    public static final String CAT_XSELL = 'Cross-sell';
    public static final String CAT_SURGEON = 'Surgeons & site expansion';
    public static final String CAT_NEW = 'New accounts & tenders';

    /** Default product lines: code, name, system, category, component, price, capital, sort. */
    public static List<WR_Product_Line__c> defaultProductLines() {
        return new List<WR_Product_Line__c>{
            line('KNEE_FEM', 'Meridian Femoral', 'Meridian Knee', 'Knee', 'Femoral', 1450, false, 10),
            line('KNEE_TIB', 'Meridian Tibial Tray', 'Meridian Knee', 'Knee', 'Tibia', 1150, false, 20),
            line('KNEE_PAT', 'Meridian Patella', 'Meridian Knee', 'Knee', 'Patella', 320, false, 30),
            line('KNEE_CL', 'Meridian Porous Cementless', 'Meridian Knee', 'Knee', 'Cementless', 1900, false, 40),
            line('BONE_CEMENT', 'Antibiotic Bone Cement', 'Bone Cement', 'Knee', 'Cement', 95, false, 50),
            line('PARTIAL_KNEE', 'Unity Partial Knee', 'Unity', 'Partial Knee', 'Unicompartmental', 1600, false, 60),
            line('HIP_CUP', 'Orbit Acetabular Cup', 'Orbit', 'Hip', 'Cup', 980, false, 70),
            line('HIP_LINER', 'Orbit Crosslinked Liner', 'Orbit', 'Hip', 'Liner', 420, false, 80),
            line('HIP_STEM_T', 'Summit Tapered Stem', 'Summit', 'Hip', 'Stem', 1100, false, 90),
            line('HIP_STEM_C', 'Vista Collared Stem', 'Vista', 'Hip', 'Stem', 950, false, 100),
            line('HIP_HEAD', 'Ceramic Femoral Head', 'Hip Heads', 'Hip', 'Head', 380, false, 110),
            line('ROBOT_KNEE', 'Atlas Robotic Knee (per procedure)', 'Atlas', 'Robotics', 'Knee workflow', 250, true, 120),
            line('ROBOT_HIP', 'Atlas Robotic Hip (per procedure)', 'Atlas', 'Robotics', 'Hip workflow', 250, true, 130)
        };
    }

    public static List<WR_Rule__c> defaultRules() {
        return new List<WR_Rule__c>{
            rule('WB_SOFT_CHURN', 'Soft churn - volume decline', 'WINBACK_SOFT', CAT_WINBACK, 4,
                25, 15000, 12, 6, null, null, null,
                'Revenue of a product line in the last 6 months dropped at least 25% versus the same 6 months last year.',
                'Review the account volume trend with the surgeon lead. Confirm whether volume moved to a competitor (partial switch) or the procedure mix changed. Agree a recovery plan: trial, in-service or contract review.'),
            rule('WB_HARD_CHURN', 'Hard churn - product line stopped', 'WINBACK_HARD', CAT_WINBACK, 5,
                null, 20000, 12, 3, null, null, null,
                'No orders in the last 3 months for a line that generated at least 20k in the 12 months before.',
                'Call the account within one week. Identify the root cause (competitor switch, stock-out, clinical issue, contract). Escalate to the commercial director if a tender or contract lock-in is involved.'),
            rule('WB_PARTIAL_TIBIA', 'Partial switch - tibia trays vs femoral', 'ATTACH', CAT_WINBACK, 5,
                20, 10000, 6, null, 'KNEE_FEM', 'KNEE_TIB', 1.0,
                'Meridian tibial trays per femoral component are below the expected 1:1 ratio. Femoral volume is stable, so tibia volume is being sourced elsewhere.',
                'Bring femoral/tibia usage data to the surgeon. Check whether a competitor tibia or cementless line is being mixed in. Offer a Meridian cementless or tibia trial.'),
            rule('WB_HIP_CUP', 'Cup share loss - Summit stems without Orbit cups', 'ATTACH', CAT_WINBACK, 5,
                30, 10000, 6, null, 'HIP_STEM_T,HIP_STEM_C', 'HIP_CUP', 0.9,
                'Stems keep being ordered but Orbit cups are missing, which signals cup share loss before a full hip conversion.',
                'Act before the full hip converts. Meet the hip surgeons, demonstrate Orbit cup and liner outcomes and propose a full-construct bundle price.'),
            rule('XS_PATELLA', 'Pull-through - Meridian patella', 'ATTACH', CAT_XSELL, 3,
                30, 5000, 12, null, 'KNEE_FEM', 'KNEE_PAT', 0.6,
                'High Meridian femoral volume with low or no Contoso patella pull-through. The same tender leaves the bag incomplete.',
                'Check the contract scope: patella is usually already on contract. Run an in-service with the scrub team and add the patella to the standard tray.'),
            rule('XS_LINER', 'Attach - Orbit liner per cup', 'ATTACH', CAT_XSELL, 3,
                20, 5000, 12, null, 'HIP_CUP', 'HIP_LINER', 1.0,
                'Orbit cups are used with non-Contoso liners.',
                'Present crosslinked liner clinical data and pricing within the existing Orbit agreement.'),
            rule('XS_HEADS', 'Attach - femoral heads per stem', 'ATTACH', CAT_XSELL, 2,
                25, 5000, 12, null, 'HIP_STEM_T,HIP_STEM_C', 'HIP_HEAD', 1.0,
                'Stems are used with non-Contoso femoral heads.',
                'Offer the ceramic femoral head as part of a complete hip construct.'),
            rule('XS_ROBOT_HIP', 'Capital pull-through - Atlas Robotic Hip workflow', 'CAPITAL_PULLTHROUGH', CAT_XSELL, 4,
                null, 10000, 12, null, 'ROBOT_KNEE', 'ROBOT_HIP', 0.4,
                'The account runs Atlas Robotic Knee and has relevant hip volume (Orbit/Summit), but no Atlas Robotic Hip workflow.',
                'Propose a Atlas Robotic Hip workflow bundle within the existing capital agreement, with a surgeon training day and case support for the first 10 cases.'),
            rule('XS_PEER_GAP', 'Peer white space - line used by similar hospitals', 'PEER_WHITESPACE', CAT_XSELL, 3,
                60, 15000, 12, null, null, null, null,
                'At least 60% of hospitals in the same segment buy this line; this account does not.',
                'Use the peer evidence (anonymised) in the next business review. Identify the surgeon champion and propose an evaluation.'),
            rule('SX_SURGEON_SITE', 'Surgeon uses Contoso elsewhere - site expansion', 'SURGEON_SITE', CAT_SURGEON, 4,
                50, 10000, 12, null, null, null, null,
                'A surgeon who uses Contoso at another hospital also operates here, but there is no Contoso usage at this site.',
                'Build a hunt plan for this site with the surgeon as champion. Map procurement and the value committee, and use the experience from the primary site.'),
            rule('SX_NEW_SURGEON', 'New surgeon - first case target', 'NEW_SURGEON', CAT_SURGEON, 4,
                40, 5000, 12, 6, null, null, null,
                'A surgeon joined this hospital recently and has no Contoso cases yet. Preferences are not yet locked in.',
                'Welcome visit within 30 days. Offer a Meridian, Unity or Orbit product demo and a first-case support plan before preferences harden.'),
            rule('NT_TENDER', 'Tender radar - open RFP closing soon', 'TENDER_RADAR', CAT_NEW, 5,
                35, 0, 2, null, null, null, null,
                'An open tender in our categories closes within 2 months. An owner must be assigned so no tender is skipped.',
                'Assign a bid owner today. Check the eligibility criteria, the comparable win/loss history and the pricing guardrails. Prepare the clinical dossier.'),
            rule('NT_SHARE_OF_WALLET', 'Low share of wallet / greenfield', 'SHARE_OF_WALLET', CAT_NEW, 3,
                15, 25000, 12, null, null, null, 0.30,
                'Contoso revenue covers less than 15% of the estimated reconstructive market of the account (procedures x basket price).',
                'Run stakeholder mapping (surgeons, procurement, value committee). Build the clinical and economic case and target the next tender or framework renewal.')
        };
    }

    /** Upserts the default product lines and rules. With reset=false existing rules keep their tuned values. */
    public static void ensureDefaults(Boolean reset) {
        upsert defaultProductLines() Code__c;
        List<WR_Rule__c> defaults = defaultRules();
        if (reset) {
            upsert defaults Code__c;
            return;
        }
        Set<String> existing = new Set<String>();
        for (WR_Rule__c r : [SELECT Code__c FROM WR_Rule__c]) {
            existing.add(r.Code__c);
        }
        List<WR_Rule__c> missing = new List<WR_Rule__c>();
        for (WR_Rule__c r : defaults) {
            if (!existing.contains(r.Code__c)) {
                missing.add(r);
            }
        }
        if (!missing.isEmpty()) {
            insert missing;
        }
    }

    public static List<WR_Rule__c> activeRules() {
        return [
            SELECT Id, Name, Code__c, Rule_Type__c, Category__c, Weight__c, Threshold_Pct__c, Min_Value__c,
                   Lookback_Months__c, Recent_Months__c, Anchor_Lines__c, Target_Lines__c, Expected_Ratio__c,
                   Description__c, Next_Best_Action__c
            FROM WR_Rule__c
            WHERE Active__c = true
            ORDER BY Code__c
        ];
    }

    private static WR_Product_Line__c line(String code, String name, String systemName, String category,
            String component, Decimal price, Boolean capital, Integer sortOrder) {
        return new WR_Product_Line__c(
            Code__c = code, Name = name, System__c = systemName, Category__c = category, Component__c = component,
            Avg_Price__c = price, Is_Capital__c = capital, Active__c = true, Sort_Order__c = sortOrder
        );
    }

    private static WR_Rule__c rule(String code, String name, String ruleType, String category, Integer weight,
            Decimal thresholdPct, Decimal minValue, Integer lookback, Integer recent, String anchor, String target,
            Decimal ratio, String description, String playbook) {
        return new WR_Rule__c(
            Code__c = code, Name = name, Rule_Type__c = ruleType, Category__c = category, Active__c = true,
            Weight__c = weight, Threshold_Pct__c = thresholdPct, Min_Value__c = minValue,
            Lookback_Months__c = lookback, Recent_Months__c = recent, Anchor_Lines__c = anchor,
            Target_Lines__c = target, Expected_Ratio__c = ratio, Description__c = description,
            Next_Best_Action__c = playbook
        );
    }
}
