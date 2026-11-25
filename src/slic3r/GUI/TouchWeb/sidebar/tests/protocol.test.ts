import { describe, it, expect } from 'vitest'
import { parseNative, applyOps, makeCommand, PROTOCOL_VERSION } from '../src/lib/protocol'
import { MOCK_STATE } from '../src/lib/mock'

const env = (action: string, payload: unknown, version = PROTOCOL_VERSION) =>
  ({ head: { version, type: 'report', seq: 1, ts: 1 }, body: { module: 'touch_sidebar', action, payload } })

describe('parseNative', () => {
  it('accepts init and snapshot', () => {
    expect(parseNative(env('init', { protocol: '1.0', state: MOCK_STATE() }))?.action).toBe('init')
    expect(parseNative(JSON.stringify(env('snapshot', { state: MOCK_STATE() })))?.action).toBe('snapshot')
  })
  it('rejects bad version, module, json and state', () => {
    expect(parseNative(env('snapshot', { state: MOCK_STATE() }, '2.0'))).toBeNull()
    expect(parseNative({ ...env('ack', { id: 'a' }), body: { module: 'x', action: 'ack', payload: { id: 'a' } } })).toBeNull()
    expect(parseNative('{nope')).toBeNull()
    expect(parseNative(env('snapshot', { state: { revision: 1 } }))).toBeNull()
    expect(parseNative(env('unknown', {}))).toBeNull()
  })
  it('validates patch, ack, error', () => {
    expect(parseNative(env('patch', { base: 1, revision: 2, ops: [{ op: 'set', path: ['slice', 'progress'], value: 5 }] }))).not.toBeNull()
    expect(parseNative(env('patch', { base: 1, revision: 2, ops: [{ op: 'bad', path: ['a'] }] }))).toBeNull()
    expect(parseNative(env('patch', { base: 1, revision: 2, ops: [{ op: 'set', path: [], value: 1 }] }))).toBeNull()
    expect(parseNative(env('ack', { id: 'c1' }))).not.toBeNull()
    expect(parseNative(env('ack', {}))).toBeNull()
    expect(parseNative(env('error', { code: 3, message: 'm' }))).not.toBeNull()
    expect(parseNative(env('error', { message: 'm' }))).toBeNull()
  })
})

describe('applyOps', () => {
  it('sets, removes, is immutable', () => {
    const s = MOCK_STATE()
    const n = applyOps(s, [{ op: 'set', path: ['quality', 'values', 'wall_loops'], value: 4 }, { op: 'remove', path: ['filament', 'items', 0] }])
    expect(n.quality.values.wall_loops).toBe(4)
    expect(n.filament.items).toHaveLength(1)
    expect(s.quality.values.wall_loops).toBe(2)
  })
  it('throws on bad path and prototype keys', () => {
    expect(() => applyOps(MOCK_STATE(), [{ op: 'set', path: ['nope', 'x'], value: 1 }])).toThrow()
    expect(() => applyOps(MOCK_STATE(), [{ op: 'set', path: ['__proto__', 'x'], value: 1 }])).toThrow()
  })
})

it('makeCommand carries id', () => {
  const c = makeCommand('c9', 'slice')
  expect(c.body).toMatchObject({ module: 'touch_sidebar', action: 'command', payload: { id: 'c9', cmd: 'slice' } })
})
