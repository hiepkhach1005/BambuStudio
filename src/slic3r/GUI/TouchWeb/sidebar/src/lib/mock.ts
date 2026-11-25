// Dev-only fake native side. Never instantiated when a native bridge exists.
import type { Envelope, SidebarState } from './protocol'

export const MOCK_STATE = (): SidebarState => ({
  revision: 1,
  printer: { presets: [{ id: 'p1', name: 'Bambu Lab X1 Carbon 0.4 nozzle' }, { id: 'p2', name: 'Bambu Lab P1S 0.4 nozzle' }], preset: 'p1',
    nozzles: ['0.2', '0.4', '0.6', '0.8'], nozzle: '0.4',
    plateTypes: [{ id: 'btPC', name: 'Cool Plate' }, { id: 'btEP', name: 'Engineering Plate' }, { id: 'btPEI', name: 'Textured PEI Plate' }], plate: 'btPEI' },
  filament: { max: 16, presets: [{ id: 'f1', name: 'Bambu PLA Basic' }, { id: 'f2', name: 'Bambu PETG HF' }],
    items: [{ id: 0, color: '#00AE42', type: 'PLA', preset: 'f1' }, { id: 1, color: '#FFFFFF', type: 'PETG', preset: 'f2' }] },
  quality: { presets: [{ id: 'q1', name: '0.20mm Standard @BBL X1C' }, { id: 'q2', name: '0.12mm Fine @BBL X1C' }], preset: 'q1',
    values: { layer_height: 0.2, wall_loops: 2, top_shell_layers: 5, bottom_shell_layers: 3, sparse_infill_density: 15, sparse_infill_pattern: 'grid', enable_support: false, brim_type: 'auto_brim', brim_width: 5 } },
  objects: [{ id: 'plate:0', kind: 'plate', name: 'Plate 1', children: [{ id: 'obj:0', kind: 'object', name: 'cube.stl', visible: true, selected: false, children: [] }] }],
  slice: { status: 'idle', progress: 0 },
})

export function mockHandle(push: (body: unknown) => void) {
  let st = MOCK_STATE()
  let timer: ReturnType<typeof setInterval> | undefined
  const timeouts = new Set<ReturnType<typeof setTimeout>>()
  const bump = (fn: () => void) => { fn(); st = { ...st, revision: st.revision + 1 }; push({ module: 'touch_sidebar', action: 'snapshot', payload: { state: st } }) }
  const handle = (env: Envelope) => {
    const b = env.body as { action: string; payload: Record<string, any> }
    if (b.action !== 'command') return
    const { id, cmd, args } = b.payload
    const th = setTimeout(() => {
      timeouts.delete(th)
      if (cmd === 'set_option') bump(() => { st = { ...st, quality: { ...st.quality, values: { ...st.quality.values, [args.key]: args.value } } } })
      else if (cmd === 'slice') {
        bump(() => { st = { ...st, slice: { status: 'slicing', progress: 0 } } })
        timer = setInterval(() => {
          const p = Math.min(100, st.slice.progress + 20)
          bump(() => { st = { ...st, slice: p >= 100 ? { status: 'ready', progress: 100, canPrint: true } : { status: 'slicing', progress: p } } })
          if (p >= 100) clearInterval(timer)
        }, 400)
      } else if (cmd === 'cancel') { clearInterval(timer); bump(() => { st = { ...st, slice: { status: 'idle', progress: 0 } } }) }
      push({ module: 'touch_sidebar', action: 'ack', payload: { id, revision: st.revision } })
    }, 80)
    timeouts.add(th)
  }
  return { handle, dispose() { clearInterval(timer); timeouts.forEach(clearTimeout); timeouts.clear() } }
}
