import { parseNjr } from 'c/signalRoomMarket';

// Fictitious rows in the layout of the registry export (NHS file uses Trust columns, independent file Company columns).
const HEADER_NHS =
    'Provider Type,Year,Month#,Month,Region Code,Region Name,Trust Code,Trust Name,Hospital,' +
    'Completed Procedures (by Submission Date),Completed Procedures (by Operation Date),' +
    'Hip Procedures (by Submission Date),Hip Procedures (by Operation Date),' +
    'Knee Procedures (by Submission Date),Knee Procedures (by Operation Date)';
const HEADER_IND = HEADER_NHS.replace('Trust Code,Trust Name', 'Company Code,Company Name');

function monthsAgo(n) {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - n);
    return { year: d.getFullYear(), month: d.getMonth() + 1 };
}

function row(provider, orgCode, orgName, hospital, ago, hip, knee) {
    const { year, month } = monthsAgo(ago);
    return `${provider},${year},${month},M,X,Test Region,${orgCode},"${orgName}",${hospital},0,${hip + knee},0,${hip},0,${knee}`;
}

describe('parseNjr', () => {
    it('aggregates the last 12 and prior 12 complete months per hospital', () => {
        const nhs = ['Data as at - ', HEADER_NHS];
        for (let m = 1; m <= 24; m++) nhs.push(row('NHS', 'T01', 'Example Trust, North', 'Example General Hospital', m, 10, 5));
        nhs.push(row('NHS', 'T01', 'Example Trust, North', 'Example General Hospital', 0, 99, 99)); // current month: ignored
        const ind = ['Data as at - ', HEADER_IND, row('Independent Sector', 'C01', 'Sample Group', 'Sample Clinic', 3, 4, 6)];

        const sites = parseNjr([nhs.join('\n'), ind.join('\r\n')]);
        const general = sites.find((s) => s.name === 'Example General Hospital');
        expect(sites).toHaveLength(2);
        expect(general.orgName).toBe('Example Trust, North');
        expect(general.hip12).toBe(120);
        expect(general.knee12).toBe(60);
        expect(general.hipPrior).toBe(120);
        expect(general.months).toHaveLength(24);
        expect(general.hip.reduce((a, b) => a + b, 0)).toBe(240);

        const clinic = sites.find((s) => s.name === 'Sample Clinic');
        expect(clinic.providerType).toBe('Independent Sector');
        expect(clinic.orgCode).toBe('C01');
        expect(clinic.knee12).toBe(6);
    });

    it('rejects files that are not a registry export', () => {
        expect(() => parseNjr(['a,b,c\n1,2,3'])).toThrow(/Provider Type/);
    });
});
