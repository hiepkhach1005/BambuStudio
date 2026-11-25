import { parseNative, makeRequest, type Envelope, type NativeMsg, type SidebarState } from './protocol'
import { MOCK_STATE, mockHandle } from './mock'
import { useStore } from './store'
import type { PanelId } from './protocol'

// Mock-only URL switches (?panel=quality&theme=light&slicing=45&picker=1&error=1). Ignored with a native bridge.
function mockQuery(): URLSearchParams { try { return new URLSearchParams(window.location.search) } catch { return new URLSearchParams() } }

type W = Window & { chrome?: { webview?: { postMessage?: (s: string) => void } }; webkit?: { messageHandlers?: { wx?: { postMessage?: (s: string) => void } } }; __cppPush?: (pkt: unknown) => void }

export function hasNativeBridge(w: W = window as W): boolean {
  return typeof w.chrome?.webview?.postMessage === 'function' || typeof w.webkit?.messageHandlers?.wx?.postMessage === 'function'
}

function nativeSend(env: Envelope) {
  const w = window as W
  const s = JSON.stringify(env)
  if (typeof w.chrome?.webview?.postMessage === 'function') w.chrome.webview.postMessage(s)
  else w.webkit!.messageHandlers!.wx!.postMessage!(s)
}

export interface Bridge { send(env: Envelope): void; mock: boolean; dispose(): void }

/** Connect. Mock is used ONLY when no native bridge exists. */
export function connect(onMsg: (m: NativeMsg) => void, onBad: (raw: unknown) => void): Bridge {
  const handle = (raw: unknown) => { const m = parseNative(raw); if (m) onMsg(m); else onBad(raw) }
  // DeviceWeb convention: native calls window.__cppPush(pkt) -> 'cpp:<event>' CustomEvent
  const listener = (e: Event) => handle((e as CustomEvent).detail)
  document.addEventListener('cpp:touch_sidebar', listener)
  const off = () => document.removeEventListener('cpp:touch_sidebar', listener)
  const native = hasNativeBridge()
  if (native) {
    const b: Bridge = { send: nativeSend, mock: false, dispose: off }
    return b
  }
  const push = (body: unknown) => handle({ head: { version: '1.0', type: 'report', seq: 0, ts: Date.now() }, body })
  const mock = mockHandle(push)
  const q = mockQuery()
  const st = MOCK_STATE() as SidebarState
  if (q.get('slicing')) st.slice = { status: 'slicing', progress: Number(q.get('slicing')) || 45 }
  const t0 = setTimeout(() => {
    push({ module: 'touch_sidebar', action: 'init', payload: { protocol: '1.0', state: st, theme: q.get('theme') === 'light' ? 'light' : 'dark', lang: q.get('lang') ?? 'en' } })
    const panel = q.get('panel')
    if (panel) useStore.getState().togglePanel(panel as PanelId)
    if (q.get('picker')) setTimeout(() => document.querySelector<HTMLElement>('[data-picker]')?.click(), 150)
    if (q.get('error')) push({ module: 'touch_sidebar', action: 'error', payload: { code: 7, message: 'Mock error: slicing failed' } })
  }, 50)
  return { mock: true, send: (env) => mock.handle(env), dispose() { clearTimeout(t0); mock.dispose(); off() } }
}

export function sendInit(b: Bridge, lang: string) { b.send(makeRequest('init', { protocol: '1.0', lang })) }
export function sendResync(b: Bridge, have: number) { b.send(makeRequest('resync', { have })) }
export function sendLayout(b: Bridge, open: boolean, panel: string | null, width: number) {
  b.send(makeRequest('layout', { open, panel, width }))
}
