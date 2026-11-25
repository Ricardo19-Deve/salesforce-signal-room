import { createElement } from 'lwc';
import SignalRoomSelect from 'c/signalRoomSelect';

const OPTIONS = [
    { value: '', label: 'All' },
    { value: 'High', label: 'High' },
    { value: 'Medium', label: 'Medium' },
    { value: 'Low', label: 'Low' }
];

function mount(props = {}) {
    const el = createElement('c-signal-room-select', { is: SignalRoomSelect });
    Object.assign(el, { label: 'Priority', options: OPTIONS, value: 'Medium' }, props);
    document.body.appendChild(el);
    return el;
}

const flush = () => Promise.resolve();
const trigger = (el) => el.shadowRoot.querySelector('button.trigger');
const items = (el) => [...el.shadowRoot.querySelectorAll('.item')];

describe('c-signal-room-select', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('shows the label and the selected option', () => {
        const el = mount();
        expect(trigger(el).textContent).toContain('Priority');
        expect(trigger(el).textContent).toContain('Medium');
    });

    it('opens, marks the selected option and emits the picked value', async () => {
        const el = mount();
        const handler = jest.fn();
        el.addEventListener('change', handler);
        trigger(el).click();
        await flush();
        expect(items(el)).toHaveLength(4);
        expect(items(el)[2].getAttribute('aria-selected')).toBe('true');
        items(el)[1].click();
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.value).toBe('High');
        expect(el.shadowRoot.querySelector('.menu')).toBeNull();
    });

    it('does not emit when the same option is picked again', async () => {
        const el = mount();
        const handler = jest.fn();
        el.addEventListener('change', handler);
        trigger(el).click();
        await flush();
        items(el)[2].click();
        await flush();
        expect(handler).not.toHaveBeenCalled();
    });

    it('closes with Escape', async () => {
        const el = mount();
        trigger(el).click();
        await flush();
        trigger(el).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        await flush();
        expect(el.shadowRoot.querySelector('.menu')).toBeNull();
    });

    it('renders the stacked field variant', () => {
        const el = mount({ variant: 'field', value: '' });
        expect(el.shadowRoot.querySelector('.field-label').textContent).toContain('Priority');
        expect(trigger(el).textContent).toContain('All');
    });
});
