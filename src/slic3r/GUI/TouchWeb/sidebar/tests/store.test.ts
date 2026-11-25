import { describe, it, expect, beforeEach } from 'vitest'
import { useStore, isBusy } from '../src/lib/store'
import { MOCK_STATE } from '../src/lib/mock'

beforeEach(() => useStore.setState({ state: null, pending: {}, lastError: null, needResync: false, panel: null }))
const init = () => useStore.getState().receive({ action: 'init', payload: { protocol: '1.0', state: MOCK_STATE(), theme: 'light', lang: 'vi' } })

describe('store', () => {
  it('init sets state, theme, lang', () => {
    init(); const s = useStore.getState()
    expect(s.state?.revision).toBe(1); expect(s.theme).toBe('light'); expect(s.lang).toBe('vi')
  })
  it('does not change state optimistically; ack clears pending', () => {
    init()
    const env = useStore.getState().begin('set_option', { key: 'wall_loops', value: 3 })
    expect(useStore.getState().state!.quality.values.wall_loops).toBe(2)
    expect(isBusy(useStore.getState(), 'set_option', 'wall_loops')).toBe(true)
    const id = (env.body as any).payload.id
    useStore.getState().receive({ action: 'ack', payload: { id } })
    expect(isBusy(useStore.getState(), 'set_option', 'wall_loops')).toBe(false)
    expect(useStore.getState().state!.quality.values.wall_loops).toBe(2)
  })
  it('error clears pending and records message', () => {
    init()
    const id = (useStore.getState().begin('slice').body as any).payload.id
    useStore.getState().receive({ action: 'error', payload: { id, code: 5, message: 'boom' } })
    expect(useStore.getState().lastError?.message).toBe('boom')
    expect(Object.keys(useStore.getState().pending)).toHaveLength(0)
  })
  it('patch applies when base matches, else requests resync', () => {
    init()
    useStore.getState().receive({ action: 'patch', payload: { base: 1, revision: 2, ops: [{ op: 'set', path: ['slice', 'progress'], value: 40 }] } })
    expect(useStore.getState().state!.slice.progress).toBe(40); expect(useStore.getState().state!.revision).toBe(2)
    useStore.getState().receive({ action: 'patch', payload: { base: 7, revision: 8, ops: [] } })
    expect(useStore.getState().needResync).toBe(true); expect(useStore.getState().state!.revision).toBe(2)
  })
  it('bad patch path triggers resync, stale snapshot ignored', () => {
    init()
    useStore.getState().receive({ action: 'patch', payload: { base: 1, revision: 2, ops: [{ op: 'set', path: ['zzz', 'a'], value: 1 }] } })
    expect(useStore.getState().needResync).toBe(true)
    const old = MOCK_STATE(); old.revision = 0
    useStore.getState().receive({ action: 'snapshot', payload: { state: old } })
    expect(useStore.getState().state!.revision).toBe(1)
  })
  it('togglePanel opens and closes', () => {
    useStore.getState().togglePanel('quality'); expect(useStore.getState().panel).toBe('quality')
    useStore.getState().togglePanel('quality'); expect(useStore.getState().panel).toBeNull()
  })
})
