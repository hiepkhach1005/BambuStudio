import { useCallback, useEffect, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { useStore } from './lib/store'
import { connect, sendInit, sendLayout, sendResync, type Bridge } from './lib/bridge'
import { createRunner } from './lib/commands'
import type { PanelId } from './lib/protocol'
import { pickLang } from './i18n'
import { Btn, cn } from './ui/kit'
import { Icon, type IconName } from './ui/icons'
import { FilamentPanel, ObjectsPanel, PrinterPanel, QualityPanel, type Run } from './panels/panels'

export const RAIL_W = 60
export const PANEL_W = 300
const TABS: { id: PanelId; icon: IconName }[] = [
  { id: 'printer', icon: 'printer' }, { id: 'filament', icon: 'filament' }, { id: 'quality', icon: 'quality' }, { id: 'objects', icon: 'objects' },
]

/** Slice / Print / Export. Compact = stacked icon+label buttons that fit the 60px rail. */
function Actions({ run, compact }: { run: Run; compact: boolean }) {
  const { t } = useTranslation()
  const state = useStore((s) => s.state)
  const anyPending = useStore((s) => Object.keys(s.pending).length > 0)
  const slice = state?.slice
  const slicing = slice?.status === 'slicing'
  const ready = slice?.status === 'ready'
  const btn = compact ? 'h-14 w-full flex-col gap-0 px-0 text-xs leading-tight' : 'min-h-14 flex-1'
  const lab = (k: string) => <span className={compact ? 'text-xs' : 'text-sm'}>{t(k)}</span>
  return (
    <div className={cn('flex gap-2', compact ? 'flex-col' : 'flex-col')}>
      {slicing && (
        <div className="h-2 rounded-full bg-row overflow-hidden" role="progressbar" aria-valuenow={slice!.progress} aria-valuemin={0} aria-valuemax={100}>
          <div className="h-full bg-accent transition-[width]" style={{ width: slice!.progress + '%' }} />
        </div>
      )}
      {slicing ? (
        <Btn variant="danger" className={cn(btn, 'flex-none')} aria-label={t('cancel')} onClick={() => run('cancel')}>
          <Icon name="stop" />
          <span className={compact ? 'text-xs' : 'text-base'}>{compact ? `${slice!.progress}%` : `${t('cancel')} ${slice!.progress}%`}</span>
        </Btn>
      ) : (
        <>
          <Btn variant="primary" className={cn(btn, 'flex-none')} aria-label={t('slice')} disabled={!state || anyPending} onClick={() => run('slice')}>
            <Icon name="play" />{lab('slice')}
          </Btn>
          <div className={cn('flex gap-2', compact && 'flex-col')}>
            <Btn className={cn(btn, 'bg-card border border-line')} aria-label={t('print')} disabled={!ready || !slice?.canPrint} onClick={() => run('print')}><Icon name="print" />{lab('print')}</Btn>
            <Btn className={cn(btn, 'bg-card border border-line')} aria-label={t('export')} disabled={!ready} onClick={() => run('export')}><Icon name="export" />{lab('export')}</Btn>
          </div>
        </>
      )}
    </div>
  )
}

export default function App() {
  const { t, i18n } = useTranslation()
  const bridge = useRef<Bridge | null>(null)
  const runner = useRef<ReturnType<typeof createRunner> | null>(null)
  const state = useStore((s) => s.state)
  const panel = useStore((s) => s.panel)
  const theme = useStore((s) => s.theme)
  const lang = useStore((s) => s.lang)
  const error = useStore((s) => s.lastError)
  const needResync = useStore((s) => s.needResync)

  // Connect once. Language changes do NOT reconnect or re-send init.
  useEffect(() => {
    const b = connect((m) => useStore.getState().receive(m), () => console.warn('[touch_sidebar] dropped invalid native message'))
    bridge.current = b
    runner.current = createRunner(() => bridge.current)
    sendInit(b, i18n.language)
    return () => { runner.current?.dispose(); runner.current = null; b.dispose(); bridge.current = null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useEffect(() => { document.documentElement.dataset.theme = theme }, [theme])
  useEffect(() => { if (lang) void i18n.changeLanguage(pickLang(lang)) }, [lang, i18n])
  useEffect(() => { if (needResync && bridge.current) sendResync(bridge.current, useStore.getState().state?.revision ?? 0) }, [needResync])
  useEffect(() => { if (bridge.current) sendLayout(bridge.current, panel !== null, panel, RAIL_W + (panel ? PANEL_W : 0)) }, [panel])
  useEffect(() => {
    const stop = (e: Event) => { const el = e.target as HTMLElement | null; if (!el?.closest('input, textarea, [contenteditable="true"]')) e.preventDefault() }
    document.addEventListener('contextmenu', stop)
    return () => document.removeEventListener('contextmenu', stop)
  }, [])

  const run: Run = useCallback((cmd, args) => runner.current?.run(cmd, args), [])

  return (
    <div className="h-full w-full flex bg-bg text-fg overflow-hidden">
      <nav className="w-[60px] shrink-0 h-full bg-panel border-r border-line flex flex-col gap-2 p-1 pt-2" aria-label="rail">
        {TABS.map((x) => (
          <button key={x.id} type="button" aria-label={t(x.id)} aria-pressed={panel === x.id} onClick={() => useStore.getState().togglePanel(x.id)}
            className={cn('h-14 w-full rounded-xl border-0 flex flex-col items-center justify-center gap-0.5 text-xs leading-none', panel === x.id ? 'bg-accent text-white' : 'bg-transparent text-mute hover:text-fg')}>
            <Icon name={x.icon} /><span className="max-w-full truncate">{t(x.id)}</span>
          </button>
        ))}
        <div className="flex-1 min-h-0" />
        {bridge.current?.mock && <span className="text-xs text-center text-danger font-semibold">{t('mock')}</span>}
        {error && !panel && (
          <button type="button" aria-label={error.message} title={error.message} onClick={() => useStore.getState().togglePanel('printer')}
            className="h-12 w-full rounded-xl border border-danger bg-danger/15 text-danger flex items-center justify-center"><Icon name="alert" /></button>
        )}
        {!panel && <Actions run={run} compact />}
        <button type="button" aria-label={theme === 'dark' ? t('light') : t('dark')} className="h-12 w-full rounded-xl border-0 bg-transparent text-mute hover:text-fg flex items-center justify-center"
          onClick={() => useStore.setState({ theme: theme === 'dark' ? 'light' : 'dark' })}><Icon name={theme === 'dark' ? 'sun' : 'moon'} /></button>
      </nav>
      {panel && (
        <section key={panel} className="panel-in h-full bg-bg flex flex-col min-w-0" style={{ width: PANEL_W }}>
          <h2 className="m-0 px-4 pt-3 pb-2 text-lg font-semibold flex items-center gap-2"><span className="w-1 h-5 rounded-full bg-accent" />{t(panel)}</h2>
          <div className="scroll flex-1 min-h-0 px-2 pb-2">
            {!state && <p className="text-mute text-sm text-center py-6">{t('waiting')}</p>}
            {state && panel === 'printer' && <PrinterPanel run={run} />}
            {state && panel === 'filament' && <FilamentPanel run={run} />}
            {state && panel === 'quality' && <QualityPanel run={run} advanced={() => run('open_advanced', { tab: 'process' })} />}
            {state && panel === 'objects' && <ObjectsPanel run={run} />}
          </div>
          <footer className="shrink-0 bg-panel border-t border-line p-2 flex flex-col gap-2">
            {error && (
              <div role="alert" className="rounded-xl bg-danger/15 border border-danger p-2 flex items-start gap-2 text-sm">
                <Icon name="alert" size={20} className="text-danger mt-0.5" />
                <span className="flex-1 min-w-0 break-words">{error.message}</span>
                <button type="button" aria-label={t('retry')} onClick={() => useStore.getState().clearError()} className="w-12 h-12 -m-2 rounded-xl border-0 bg-transparent flex items-center justify-center"><Icon name="close" size={20} /></button>
              </div>
            )}
            {needResync && <span className="text-xs text-mute">{t('resync')}</span>}
            <Actions run={run} compact={false} />
          </footer>
        </section>
      )}
    </div>
  )
}
