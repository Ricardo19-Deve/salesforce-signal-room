import { TOURS } from 'c/signalRoomTour';

const SHELL_TARGETS = ['nav', 'filters', 'run', 'guide'];
const ACTIONS = /^(open-first|back|expand-first|close-drawer|tab:\w+)$/;

describe('page tours', () => {
    it('has a tour for every page of the portal', () => {
        expect(Object.keys(TOURS).sort()).toEqual(
            ['account', 'admin', 'contracts', 'dashboard', 'market', 'pointers', 'tenders', 'signalroom'].sort()
        );
    });

    it('explains every block with its own text', () => {
        Object.values(TOURS).forEach((steps) => {
            expect(steps.length).toBeGreaterThan(4);
            const titles = steps.map((s) => s.title);
            expect(new Set(titles).size).toBe(titles.length);
            steps.forEach((s) => {
                expect(s.body.length).toBeGreaterThan(40);
                const t = s.target;
                expect(SHELL_TARGETS.includes(t) || t.startsWith('page:') || t.startsWith('drawer:')).toBe(true);
                expect(s.action === undefined || ACTIONS.test(s.action)).toBe(true);
            });
        });
    });

    it('ends every tour on the guide', () => {
        Object.values(TOURS).forEach((steps) => expect(steps[steps.length - 1].target).toBe('guide'));
    });
});
