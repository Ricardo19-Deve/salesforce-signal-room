import { createElement } from 'lwc';
import SignalRoomGuide from 'c/signalRoomGuide';
import getRules from '@salesforce/apex/SignalRoomController.getRules';
import { SECTIONS } from '../guideContent';

jest.mock('@salesforce/apex/SignalRoomController.getRules', () => ({ default: jest.fn() }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(section) {
    const el = createElement('c-signal-room-guide', { is: SignalRoomGuide });
    if (section) el.section = section;
    document.body.appendChild(el);
    return el;
}

describe('c-signal-room-guide', () => {
    beforeEach(() =>
        getRules.mockResolvedValue([
            { Id: 'r1', Name: 'Tender radar', Rule_Type__c: 'TENDER_RADAR', Threshold_Pct__c: 35, Lookback_Months__c: 2, Weight__c: 5, Active__c: true }
        ])
    );
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('lists every section in the table of contents', async () => {
        const el = mount();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.toc-item')).toHaveLength(SECTIONS.length);
        expect(el.shadowRoot.querySelector('h2').textContent).toBe(SECTIONS[0].title);
    });

    it('opens on the section of the page the user came from and links to it', async () => {
        const el = mount('tenders');
        await flush();
        expect(el.shadowRoot.querySelector('h2').textContent).toBe('Tenders');
        const handler = jest.fn();
        el.addEventListener('navigate', handler);
        el.shadowRoot.querySelector('.head .sr-btn').click();
        expect(handler.mock.calls[0][0].detail.view).toBe('tenders');
    });

    it('shows the live rule settings next to the calculations', async () => {
        const el = mount('calc');
        await flush();
        expect(el.shadowRoot.textContent).toContain('score = 0.60 x value score');
        expect(el.shadowRoot.textContent).toContain('TENDER_RADAR');
    });

    it('moves to the next section', async () => {
        const el = mount();
        await flush();
        el.shadowRoot.querySelector('.pager-btn_next').click();
        await flush();
        expect(el.shadowRoot.querySelector('h2').textContent).toBe(SECTIONS[1].title);
    });
});
