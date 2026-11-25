/**
 * Contract compliance: committed monthly volume vs. what was actually delivered (SR_Sales__c units).
 *
 * For every contract line the month-by-month committed and delivered units, the cumulative variance, the
 * run-rate of the last RUN_RATE_MONTHS and the projection to the end of the term are computed. A line is
 * "Under" or "Over" when the delivered volume to date deviates from the commitment by more than the
 * contract tolerance (default 10%), otherwise "On track".
 *
 * The comparison starts at the later of the contract start and the first month with sales data for the
 * account, so a contract older than the loaded history is not reported as under-delivered.
 * Used by the portal (SignalRoomController) and by the CONTRACT_* engine rules.
 */
public with sharing class SignalRoomContracts {

    public static final Decimal DEFAULT_TOLERANCE = 10;
    public static final Integer RUN_RATE_MONTHS = 6;

    public class LineResult {
        @AuraEnabled public Id lineId;
        @AuraEnabled public String label;
        @AuraEnabled public Id productLineId;
        @AuraEnabled public String productLine;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal monthlyQty;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public List<String> months = new List<String>();
        @AuraEnabled public List<Decimal> committed = new List<Decimal>();
        @AuraEnabled public List<Decimal> delivered = new List<Decimal>();
        @AuraEnabled public List<Decimal> cumulativeVariance = new List<Decimal>();
        @AuraEnabled public Decimal committedToDate = 0;
        @AuraEnabled public Decimal deliveredToDate = 0;
        @AuraEnabled public Decimal varianceUnits = 0;
        @AuraEnabled public Decimal variancePct;
        @AuraEnabled public Decimal varianceValue = 0;
        @AuraEnabled public Decimal runRate = 0;
        @AuraEnabled public Decimal runRatePct;
        @AuraEnabled public Decimal totalCommitment = 0;
        @AuraEnabled public Decimal projectedTotal = 0;
        @AuraEnabled public Decimal projectedVariance = 0;
        @AuraEnabled public String status;
    }

    public class ContractResult {
        @AuraEnabled public Id contractId;
        @AuraEnabled public String name;
        @AuraEnabled public String reference;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String recordStatus;
        @AuraEnabled public Decimal tolerance;
        @AuraEnabled public String notes;
        @AuraEnabled public String health;
        @AuraEnabled public Integer monthsElapsed = 0;
        @AuraEnabled public Integer monthsTotal = 0;
        @AuraEnabled public Integer daysToEnd;
        @AuraEnabled public Decimal committedValue = 0;
        @AuraEnabled public Decimal deliveredValue = 0;
        @AuraEnabled public Decimal varianceValue = 0;
        @AuraEnabled public Decimal compliancePct;
        @AuraEnabled public Decimal annualValue = 0;
        @AuraEnabled public Date comparedFrom;
        @AuraEnabled public List<LineResult> lines = new List<LineResult>();
    }

    public static String contractQuery() {
        return 'SELECT Id, Name, Reference__c, Account__c, Account__r.Name, Start_Date__c, End_Date__c, Status__c, '
            + 'Tolerance_Pct__c, Notes__c, Is_Demo__c, '
            + '(SELECT Id, Label__c, Product_Line__c, Product_Line__r.Name, Product_Line__r.Code__c, Monthly_Qty__c, '
            + 'Unit_Price__c FROM Lines__r ORDER BY Name) FROM SR_Contract__c';
    }

    /** Evaluates contracts against delivered units up to the month before asOf. */
    public static List<ContractResult> evaluate(List<SR_Contract__c> contracts, Date asOf) {
        Date monthStart = asOf.toStartOfMonth();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> lineIds = new Set<Id>();
        Date earliest = monthStart;
        for (SR_Contract__c c : contracts) {
            accountIds.add(c.Account__c);
            if (c.Start_Date__c != null && c.Start_Date__c < earliest) {
                earliest = c.Start_Date__c.toStartOfMonth();
            }
            for (SR_Contract_Line__c l : c.Lines__r) {
                if (l.Product_Line__c != null) {
                    lineIds.add(l.Product_Line__c);
                }
            }
        }
        // First month with any sales per account: the comparison cannot start before the data does.
        Map<Id, Date> firstData = new Map<Id, Date>();
        for (AggregateResult ar : [
            SELECT Account__c acc, MIN(Period__c) firstPeriod FROM SR_Sales__c
            WHERE Account__c IN :accountIds GROUP BY Account__c
        ]) {
            firstData.put((Id) ar.get('acc'), (Date) ar.get('firstPeriod'));
        }
        Map<String, Decimal> units = new Map<String, Decimal>();
        for (AggregateResult ar : [
            SELECT Account__c acc, Product_Line__c pl, Period__c period, SUM(Units__c) u
            FROM SR_Sales__c
            WHERE Account__c IN :accountIds AND Product_Line__c IN :lineIds
              AND Period__c >= :earliest AND Period__c < :monthStart
            GROUP BY Account__c, Product_Line__c, Period__c
        ]) {
            units.put(key((Id) ar.get('acc'), (Id) ar.get('pl'), (Date) ar.get('period')), nz((Decimal) ar.get('u')));
        }

        List<ContractResult> out = new List<ContractResult>();
        for (SR_Contract__c c : contracts) {
            out.add(evaluateOne(c, monthStart, firstData.get(c.Account__c), units));
        }
        return out;
    }

    private static ContractResult evaluateOne(SR_Contract__c c, Date monthStart, Date firstData, Map<String, Decimal> units) {
        ContractResult r = new ContractResult();
        r.contractId = c.Id;
        r.name = c.Name;
        r.reference = c.Reference__c;
        r.accountId = c.Account__c;
        r.accountName = c.Account__r?.Name;
        r.startDate = c.Start_Date__c;
        r.endDate = c.End_Date__c;
        r.recordStatus = c.Status__c;
        r.notes = c.Notes__c;
        r.tolerance = c.Tolerance_Pct__c == null ? DEFAULT_TOLERANCE : c.Tolerance_Pct__c;
        if (c.Start_Date__c == null || c.End_Date__c == null) {
            r.health = 'Not started';
            return r;
        }
        Date start = c.Start_Date__c.toStartOfMonth();
        Date endMonth = c.End_Date__c.toStartOfMonth();
        r.monthsTotal = monthsBetween(start, endMonth) + 1;
        r.daysToEnd = Date.today().daysBetween(c.End_Date__c);
        Date compareFrom = firstData != null && firstData > start ? firstData.toStartOfMonth() : start;
        Date lastMonth = monthStart.addMonths(-1) < endMonth ? monthStart.addMonths(-1) : endMonth;
        Integer elapsed = compareFrom > lastMonth ? 0 : monthsBetween(compareFrom, lastMonth) + 1;
        r.monthsElapsed = start > lastMonth ? 0 : monthsBetween(start, lastMonth) + 1;
        r.comparedFrom = compareFrom;
        Integer remaining = Math.max(0, monthsBetween(lastMonth, endMonth));
        Decimal tol = r.tolerance / 100;

        Boolean anyUnder = false;
        Boolean anyOver = false;
        for (SR_Contract_Line__c l : c.Lines__r) {
            LineResult lr = new LineResult();
            lr.lineId = l.Id;
            lr.label = String.isNotBlank(l.Label__c) ? l.Label__c : l.Product_Line__r?.Name;
            lr.productLineId = l.Product_Line__c;
            lr.productLine = l.Product_Line__r?.Name;
            lr.productCode = l.Product_Line__r?.Code__c;
            lr.monthlyQty = nz(l.Monthly_Qty__c);
            lr.unitPrice = nz(l.Unit_Price__c);
            Decimal cumulative = 0;
            for (Integer i = 0; i < elapsed; i++) {
                Date m = compareFrom.addMonths(i);
                Decimal d = nz(units.get(key(c.Account__c, l.Product_Line__c, m)));
                lr.months.add(Datetime.newInstance(m, Time.newInstance(12, 0, 0, 0)).format('MMM yy'));
                lr.committed.add(lr.monthlyQty);
                lr.delivered.add(d);
                cumulative += d - lr.monthlyQty;
                lr.cumulativeVariance.add(cumulative);
                lr.committedToDate += lr.monthlyQty;
                lr.deliveredToDate += d;
            }
            Integer n = Math.min(RUN_RATE_MONTHS, lr.delivered.size());
            Decimal recent = 0;
            for (Integer i = lr.delivered.size() - n; i < lr.delivered.size(); i++) {
                recent += lr.delivered[i];
            }
            lr.runRate = n == 0 ? 0 : (recent / n).setScale(1);
            lr.runRatePct = lr.monthlyQty > 0 && n > 0 ? (lr.runRate - lr.monthlyQty) / lr.monthlyQty : null;
            lr.varianceUnits = lr.deliveredToDate - lr.committedToDate;
            lr.variancePct = lr.committedToDate > 0 ? lr.varianceUnits / lr.committedToDate : null;
            lr.varianceValue = lr.varianceUnits * lr.unitPrice;
            lr.totalCommitment = lr.monthlyQty * (elapsed + remaining);
            lr.projectedTotal = (lr.deliveredToDate + lr.runRate * remaining).setScale(0);
            lr.projectedVariance = lr.projectedTotal - lr.totalCommitment;
            if (lr.variancePct == null) {
                lr.status = 'Not started';
            } else if (lr.variancePct < -tol) {
                lr.status = 'Under';
                anyUnder = true;
            } else if (lr.variancePct > tol) {
                lr.status = 'Over';
                anyOver = true;
            } else {
                lr.status = 'On track';
            }
            r.committedValue += lr.committedToDate * lr.unitPrice;
            r.deliveredValue += lr.deliveredToDate * lr.unitPrice;
            r.annualValue += lr.monthlyQty * lr.unitPrice * 12;
            r.lines.add(lr);
        }
        r.varianceValue = r.deliveredValue - r.committedValue;
        r.compliancePct = r.committedValue > 0 ? r.deliveredValue / r.committedValue : null;
        r.health = elapsed == 0 || r.lines.isEmpty() ? 'Not started' : (anyUnder ? 'Under' : (anyOver ? 'Over' : 'On track'));
        return r;
    }

    private static String key(Id accountId, Id productLineId, Date month) {
        return accountId + '|' + productLineId + '|' + String.valueOf(month);
    }

    private static Integer monthsBetween(Date a, Date b) {
        return (b.year() * 12 + b.month()) - (a.year() * 12 + a.month());
    }

    private static Decimal nz(Decimal v) {
        return v == null ? 0 : v;
    }
}
