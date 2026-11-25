import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { connect, sendInit } from '../src/lib/bridge'
import { createRunner } from '../src/lib/commands'
import { useStore } from '../src/lib/store'

let listeners: Map<string, Set<EventListener>>
beforeEach(() => {
  vi.useFakeTimers()
  listeners = new Map()
  vi.stubGlobal('document', {
    addEventListener: (t: string, l: EventListener) => { (listeners.get(t) ?? listeners.set(t, new Set()).get(t)!).add(l) },
    removeEventListener: (t: string, l: EventListener) => { listeners.get(t)?.delete(l) },
    querySelector: () => null,
  })
  vi.stubGlobal('window', { location: { search: '' } })
  useStore.setState({ state: null, pending: {}, lastError: null, needResync: false, panel: null })
})
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals() })
const count = () => listeners.get('cpp:touch_sidebar')?.size ?? 0

describe('bridge lifecycle', () => {
  it('registers one listener and dispose removes it (re-run leaves exactly one)', () => {
    const a = connect(() => {}, () => {}); expect(count()).toBe(1)
    a.dispose(); expect(count()).toBe(0)
    const b = connect(() => {}, () => {}); expect(count()).toBe(1)
    b.dispose(); expect(count()).toBe(0)
  })
  it('native bridge: init is posted once per sendInit and nothing else', () => {
    const post = vi.fn()
    vi.stubGlobal('window', { location: { search: '' }, chrome: { webview: { postMessage: post } } })
    const b = connect(() => {}, () => {}); sendInit(b, 'en')
    expect(post).toHaveBeenCalledTimes(1)
    expect(JSON.parse(post.mock.calls[0][0]).body.action).toBe('init')
    b.dispose()
  })
  it('mock dispose cancels the pending init push', () => {
    const got = vi.fn(); const b = connect(got, () => {}); b.dispose()
    vi.advanceTimersByTime(1000); expect(got).not.toHaveBeenCalled()
  })
})

describe('command runner timeouts', () => {
  const bridge = { send: vi.fn(), mock: false, dispose() {} }
  it('times out an unanswered command with an error', () => {
    const r = createRunner(() => bridge, 1000); r.run('slice')
    expect(r.active).toBe(1); vi.advanceTimersByTime(1001)
    expect(useStore.getState().lastError?.message).toBe('timeout: slice'); expect(Object.keys(useStore.getState().pending)).toHaveLength(0)
    r.dispose()
  })
  it('ack clears the timer', () => {
    const r = createRunner(() => bridge, 1000); r.run('slice')
    const id = Object.keys(useStore.getState().pending)[0]
    useStore.getState().receive({ action: 'ack', payload: { id } })
    expect(r.active).toBe(0); vi.advanceTimersByTime(2000); expect(useStore.getState().lastError).toBeNull()
    r.dispose()
  })
  it('dispose clears outstanding timers', () => {
    const r = createRunner(() => bridge, 1000); r.run('slice'); r.run('print'); r.dispose()
    expect(r.active).toBe(0); vi.advanceTimersByTime(5000); expect(useStore.getState().lastError).toBeNull()
  })
})
