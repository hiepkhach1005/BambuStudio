import { create } from 'zustand'
import { applyOps, makeCommand, validateState, type CommandName, type NativeMsg, type SidebarState, type PanelId } from './protocol'

export interface Pending { id: string; cmd: CommandName; key?: string }
export interface Store {
  state: SidebarState | null
  theme: 'dark' | 'light'
  lang: string | null
  panel: PanelId | null
  pending: Record<string, Pending>
  lastError: { id?: string; code: number; message: string } | null
  needResync: boolean
  receive(m: NativeMsg): void
  /** Registers a pending command, returns the envelope to send. UI state is NOT changed. */
  begin(cmd: CommandName, args?: Record<string, unknown>): ReturnType<typeof makeCommand>
  togglePanel(p: PanelId): void
  clearError(): void
}

let n = 0
export const useStore = create<Store>((set, get) => ({
  state: null, theme: 'dark', lang: null, panel: null, pending: {}, lastError: null, needResync: false,
  receive(m) {
    switch (m.action) {
      case 'init': set({ state: m.payload.state, theme: m.payload.theme ?? get().theme, lang: m.payload.lang ?? get().lang, needResync: false }); break
      case 'snapshot': {
        const cur = get().state
        if (!validateState(m.payload.state)) break
        if (cur && m.payload.state.revision < cur.revision) break // stale
        set({ state: m.payload.state, needResync: false }); break
      }
      case 'patch': {
        const cur = get().state
        if (!cur || m.payload.base !== cur.revision) { set({ needResync: true }); break }
        try { set({ state: { ...applyOps(cur, m.payload.ops), revision: m.payload.revision } }) } catch { set({ needResync: true }) }
        break
      }
      case 'ack': { const { [m.payload.id]: _d, ...rest } = get().pending; void _d; set({ pending: rest }); break }
      case 'error': {
        const p = get().pending
        const id = m.payload.id
        if (id && id in p) { const { [id]: _d, ...rest } = p; void _d; set({ pending: rest, lastError: m.payload }) } else set({ lastError: m.payload })
        break
      }
      case 'theme': set({ theme: m.payload.theme, lang: m.payload.lang ?? get().lang }); break
    }
  },
  begin(cmd, args = {}) {
    const id = 'c' + ++n
    set({ pending: { ...get().pending, [id]: { id, cmd, key: typeof args.key === 'string' ? args.key : undefined } } })
    return makeCommand(id, cmd, args)
  },
  togglePanel(p) { set({ panel: get().panel === p ? null : p }) },
  clearError() { set({ lastError: null }) },
}))

export const isBusy = (s: Store, cmd: CommandName, key?: string) =>
  Object.values(s.pending).some((p) => p.cmd === cmd && (key === undefined || p.key === key))
