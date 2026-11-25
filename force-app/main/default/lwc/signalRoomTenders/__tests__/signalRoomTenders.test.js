import { createElement } from 'lwc';
import SignalRoomTenders from 'c/signalRoomTenders';
import getTenders from '@salesforce/apex/SignalRoomController.getTenders';

jest.mock('@salesforce/apex/SignalRoomController.getTenders', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.syncTenders', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.saveTenderSource', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.scheduleTenderSync', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.autoMatchTenders', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.setTenderMapping', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.setTenderStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.searchAllAccounts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/SignalRoomController.getJobStatus', () => ({ default: jest.fn() }), { virtual: true });

const DATA = {
    open: 2, openValue: 1500000, closingSoon: 1, linked: 1, countries: ['DE', 'GB'],
    sources: ['TED (EU)', 'Find a Tender (UK)'], scheduled: false,
    feeds: [
        { Id: 'f2', Name: 'Find a Tender (UK)', Code__c: 'FTS', Active__c: true, CPV_Prefixes__c: '33183', Lookback_Days__c: 180 },
        { Id: 'f1', Name: 'TED (EU)', Code__c: 'TED', Active__c: true, CPV_Prefixes__c: '33183', Lookback_Days__c: 30 }
    ],
    rows: [
        {
            id: 't1', title: 'Knee and hip prostheses', buyer: 'City Hospital', country: 'DE', category: 'Knee & Hip',
            deadline: '2026-12-01', daysLeft: 0, value: 1000000, originalValue: 1000000, currencyCode: 'EUR',
            status: 'Open', source: 'TED (EU)', url: 'https://example.org/notice/1', matchStatus: 'Auto-matched',
            accountId: 'a1', accountName: 'City Hospital'
        },
        {
            id: 't2', title: 'Trauma fixation devices', buyer: 'North Board', country: 'GB', category: 'Trauma',
            deadline: '2026-12-20', daysLeft: 1, value: 575000, originalValue: 500000, currencyCode: 'GBP',
            status: 'Open', source: 'Find a Tender (UK)', matchStatus: 'Suggested', suggestedId: 'a2',
            suggestedName: 'North Hospital', score: 80
        }
    ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(isAdmin) {
    const el = createElement('c-signal-room-tenders', { is: SignalRoomTenders });
    el.isAdmin = isAdmin;
    document.body.appendChild(el);
    return el;
}

describe('c-signal-room-tenders', () => {
    beforeEach(() => getTenders.mockResolvedValue(DATA));
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('shows the indicators and one row per tender with the notice link', async () => {
        const el = mount(false);
        await flush();
        const kpis = [...el.shadowRoot.querySelectorAll('.sr-kpi-value')].map((k) => k.textContent);
        expect(kpis[0]).toBe('2');
        const titles = [...el.shadowRoot.querySelectorAll('.title-text')];
        expect(titles).toHaveLength(2);
        expect(titles[0].getAttribute('href')).toBe('https://example.org/notice/1');
        expect(el.shadowRoot.textContent).toContain('Closes today');
        expect(el.shadowRoot.textContent).toContain('1 day left');
        expect(el.shadowRoot.textContent).toContain('GBP 500,000');
    });

    it('hides the sources panel and mapping actions from users', async () => {
        const el = mount(false);
        await flush();
        expect(el.shadowRoot.querySelector('table.feeds')).toBeNull();
        expect(el.shadowRoot.textContent).not.toContain('Confirm');
    });

    it('lists the sources in portal order for admins', async () => {
        const el = mount(true);
        await flush();
        const names = [...el.shadowRoot.querySelectorAll('table.feeds .sr-strong')].map((n) => n.textContent);
        expect(names).toEqual(['TED (EU)', 'Find a Tender (UK)']);
        expect(el.shadowRoot.textContent).toContain('Confirm');
    });

    it('expands a tender to show its details', async () => {
        const el = mount(true);
        await flush();
        el.shadowRoot.querySelector('.expander').click();
        await flush();
        expect(el.shadowRoot.querySelector('.detail-row')).not.toBeNull();
        expect(el.shadowRoot.textContent).toContain('Set status');
    });
});
