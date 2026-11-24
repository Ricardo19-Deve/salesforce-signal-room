import { TOURS } from '../tourContent';

const SHELL_TARGETS = ['nav', 'filters', 'run', 'guide'];

describe('page tours', () => {
    it('has a tour for every page of the portal', () => {
        expect(Object.keys(TOURS).sort()).toEqual(
            ['account', 'admin', 'contracts', 'dashboard', 'market', 'pointers', 'tenders', 'winroom'].sort()
        );
    });

    it('explains every step and targets the shell or a page selector', () => {
        Object.values(TOURS).forEach((steps) => {
            expect(steps.length).toBeGreaterThan(2);
            steps.forEach((s) => {
                expect(s.title).toBeTruthy();
                expect(s.body.length).toBeGreaterThan(30);
                expect(SHELL_TARGETS.includes(s.target) || s.target.startsWith('page:')).toBe(true);
            });
        });
    });

    it('ends every tour with the guide', () => {
        Object.values(TOURS).forEach((steps) => expect(steps[steps.length - 1].target).toBe('guide'));
    });
});
