// Wire protocol, see PROTOCOL.md. Pure functions only (unit tested).
export const PROTOCOL_VERSION = '1.0'
export const MODULE = 'touch_sidebar'

export type PanelId = 'printer' | 'filament' | 'quality' | 'objects'
export type OptValue = string | number | boolean

export interface PresetRef { id: string; name: string; dirty?: boolean }
export interface FilamentItem { id: number; color: string; type?: string; preset: string }
export interface ObjectNode { id: string; kind: 'plate' | 'object' | 'part'; name: string; visible?: boolean; selected?: boolean; children?: ObjectNode[] }
export interface SliceState { status: 'idle' | 'slicing' | 'ready' | 'error'; progress: number; message?: string; canPrint?: boolean }

export interface SidebarState {
  revision: number
  printer: { presets: PresetRef[]; preset: string; nozzles: string[]; nozzle: string; plateTypes: PresetRef[]; plate: string }
  filament: { items: FilamentItem[]; presets: PresetRef[]; max: number }
  quality: { presets: PresetRef[]; preset: string; values: Record<string, OptValue> }
  objects: ObjectNode[]
  slice: SliceState
}

export interface Head { version: string; type: 'request' | 'response' | 'report'; seq: number; ts: number }
export interface Envelope<B = unknown> { head: Head; body: B }

export type PatchOp = { op: 'set'; path: (string | number)[]; value: unknown } | { op: 'remove'; path: (string | number)[] }
export type NativeMsg =
  | { action: 'init'; payload: { protocol: string; state: SidebarState; theme?: 'dark' | 'light'; lang?: string } }
  | { action: 'snapshot'; payload: { state: SidebarState } }
  | { action: 'patch'; payload: { base: number; revision: number; ops: PatchOp[] } }
  | { action: 'ack'; payload: { id: string; revision?: number } }
  | { action: 'error'; payload: { id?: string; code: number; message: string } }
  | { action: 'theme'; payload: { theme: 'dark' | 'light'; lang?: string } }

export const COMMANDS = [
  'select_printer_preset', 'select_nozzle', 'select_plate_type',
  'filament_add', 'filament_remove', 'filament_edit', 'filament_set_preset', 'filament_set_color',
  'select_process_preset', 'set_option', 'open_advanced',
  'object_select', 'object_set_visible', 'object_delete', 'object_action',
  'slice', 'print', 'export', 'cancel',
] as const
export type CommandName = (typeof COMMANDS)[number]

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

export function validateState(s: unknown): s is SidebarState {
  if (!isObj(s) || typeof s.revision !== 'number') return false
  const { printer, filament, quality, slice } = s as Record<string, unknown>
  if (!isObj(printer) || !Array.isArray(printer.presets) || !Array.isArray(printer.plateTypes)) return false
  if (!isObj(filament) || !Array.isArray(filament.items) || !Array.isArray(filament.presets)) return false
  if (!isObj(quality) || !Array.isArray(quality.presets) || !isObj(quality.values)) return false
  if (!Array.isArray(s.objects)) return false
  if (!isObj(slice) || typeof slice.progress !== 'number' || typeof slice.status !== 'string') return false
  return true
}

/** Validate a native->web envelope. Returns the typed body or null. */
export function parseNative(raw: unknown): NativeMsg | null {
  let pkt = raw
  if (typeof raw === 'string') { try { pkt = JSON.parse(raw) } catch { return null } }
  if (!isObj(pkt) || !isObj(pkt.head) || !isObj(pkt.body)) return null
  if (pkt.head.version !== PROTOCOL_VERSION) return null
  const b = pkt.body
  if (b.module !== MODULE || typeof b.action !== 'string' || !isObj(b.payload)) return null
  const p = b.payload
  switch (b.action) {
    case 'init': return p.protocol === PROTOCOL_VERSION && validateState(p.state) ? (b as unknown as NativeMsg) : null
    case 'snapshot': return validateState(p.state) ? (b as unknown as NativeMsg) : null
    case 'patch':
      if (typeof p.base !== 'number' || typeof p.revision !== 'number' || !Array.isArray(p.ops)) return null
      for (const o of p.ops) {
        if (!isObj(o) || (o.op !== 'set' && o.op !== 'remove') || !Array.isArray(o.path) || o.path.length === 0) return null
        if (o.path.some((k) => typeof k !== 'string' && typeof k !== 'number')) return null
      }
      return b as unknown as NativeMsg
    case 'ack': return typeof p.id === 'string' ? (b as unknown as NativeMsg) : null
    case 'error': return typeof p.code === 'number' && typeof p.message === 'string' ? (b as unknown as NativeMsg) : null
    case 'theme': return p.theme === 'dark' || p.theme === 'light' ? (b as unknown as NativeMsg) : null
    default: return null
  }
}

let seq = 0
export function makeRequest(action: string, payload: Record<string, unknown>): Envelope {
  return { head: { version: PROTOCOL_VERSION, type: 'request', seq: seq++, ts: Date.now() }, body: { module: MODULE, action, payload } }
}
export function makeCommand(id: string, cmd: CommandName, args: Record<string, unknown> = {}): Envelope {
  return makeRequest('command', { id, cmd, args })
}

/** Apply patch ops immutably. Throws on a bad path. */
export function applyOps<T>(state: T, ops: PatchOp[]): T {
  let cur: unknown = state
  for (const op of ops) cur = applyOne(cur, op.path, 0, op)
  return cur as T
}
function applyOne(node: unknown, path: (string | number)[], i: number, op: PatchOp): unknown {
  const key = path[i]
  const last = i === path.length - 1
  if (Array.isArray(node)) {
    const idx = Number(key)
    if (!Number.isInteger(idx) || idx < 0 || idx > node.length) throw new Error('bad index ' + key)
    const copy = node.slice()
    if (last) { if (op.op === 'remove') copy.splice(idx, 1); else copy[idx] = (op as { value: unknown }).value }
    else { if (idx >= node.length) throw new Error('bad path'); copy[idx] = applyOne(node[idx], path, i + 1, op) }
    return copy
  }
  if (isObj(node)) {
    const k = String(key)
    if (k === '__proto__' || k === 'constructor' || k === 'prototype') throw new Error('bad key')
    const copy = { ...node }
    if (last) { if (op.op === 'remove') delete copy[k]; else copy[k] = (op as { value: unknown }).value }
    else { if (!(k in node)) throw new Error('bad path'); copy[k] = applyOne(node[k], path, i + 1, op) }
    return copy
  }
  throw new Error('bad path')
}
