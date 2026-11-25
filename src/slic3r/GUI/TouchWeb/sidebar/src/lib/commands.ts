import { useStore } from './store'
import type { CommandName } from './protocol'
import type { Bridge } from './bridge'

export const CMD_TIMEOUT = 15000

/** Sends commands and fails them locally if native never answers. Timers are cleared on ack/error and on dispose. */
export function createRunner(getBridge: () => Bridge | null, timeoutMs = CMD_TIMEOUT) {
  const timers = new Map<string, ReturnType<typeof setTimeout>>()
  const unsub = useStore.subscribe((s) => {
    for (const [id, t] of timers) if (!(id in s.pending)) { clearTimeout(t); timers.delete(id) }
  })
  return {
    run(cmd: CommandName, args?: Record<string, unknown>) {
      const env = useStore.getState().begin(cmd, args)
      const id = (env.body as { payload: { id: string } }).payload.id
      timers.set(id, setTimeout(() => {
        timers.delete(id)
        if (id in useStore.getState().pending) useStore.getState().receive({ action: 'error', payload: { id, code: -1, message: 'timeout: ' + cmd } })
      }, timeoutMs))
      getBridge()?.send(env)
    },
    dispose() { unsub(); timers.forEach(clearTimeout); timers.clear() },
    get active() { return timers.size },
  }
}
