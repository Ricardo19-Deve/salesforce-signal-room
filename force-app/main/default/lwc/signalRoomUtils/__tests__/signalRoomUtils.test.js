import { money, pct, daysUntil, decoratePointer, reduceErrors, CATEGORIES, SERIES_COLORS } from 'c/signalRoomUtils';

describe('c/signalRoomUtils', () => {
    it('formats money compactly', () => {
        expect(money(0)).toBe('€0');
        expect(money(950)).toBe('€950');
        expect(money(12345)).toBe('€12.3k');
        expect(money(250000)).toBe('€250k');
        expect(money(1234567)).toBe('€1.23M');
        expect(money(null)).toBe('€0');
    });

    it('formats ratios as percentages', () => {
        expect(pct(0.256)).toBe('26%');
        expect(pct(0.256, 1)).toBe('25.6%');
        expect(pct(null)).toBe('–');
    });

    it('counts days until a date', () => {
        const d = new Date();
        d.setDate(d.getDate() + 10);
        expect(daysUntil(d.toISOString().substring(0, 10))).toBe(10);
        expect(daysUntil(null)).toBeNull();
    });

    it('decorates a pointer row for the tables', () => {
        const past = new Date();
        past.setDate(past.getDate() - 3);
        const row = decoratePointer({ value: 50000, priority: 'High', status: 'New', score: 140, dueDate: past.toISOString().substring(0, 10) });
        expect(row.valueText).toBe('€50.0k');
        expect(row.priorityClass).toBe('sr-pill sr-pill_high');
        expect(row.statusClass).toBe('sr-status sr-status_new');
        expect(row.dueCellClass).toContain('sr-overdue');
        expect(row.scoreStyle).toBe('width:100%');
    });

    it('does not flag decided pointers as overdue', () => {
        const row = decoratePointer({ status: 'Rejected', dueDate: '2020-01-01' });
        expect(row.dueCellClass).not.toContain('sr-overdue');
    });

    it('reads Apex and JavaScript errors', () => {
        expect(reduceErrors({ body: { message: 'Only admins' } })).toBe('Only admins');
        expect(reduceErrors({ body: { pageErrors: [{ message: 'Validation' }] } })).toBe('Validation');
        expect(reduceErrors(new Error('boom'))).toBe('boom');
    });

    it('keeps four categories and a fixed colour order', () => {
        expect(CATEGORIES).toHaveLength(4);
        expect(SERIES_COLORS).toHaveLength(4);
    });
});
