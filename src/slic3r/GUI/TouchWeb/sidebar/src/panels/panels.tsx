import { useTranslation } from 'react-i18next'
import { useStore, isBusy } from '../lib/store'
import type { CommandName, ObjectNode, OptValue } from '../lib/protocol'
import { Btn, Card, Row, Stepper, Toggle, Picker, cn } from '../ui/kit'
import { Icon } from '../ui/icons'

export type Run = (cmd: CommandName, args?: Record<string, unknown>) => void
const useBusy = () => useStore((s) => s.pending)

export function PrinterPanel({ run }: { run: Run }) {
  const { t } = useTranslation(); const st = useStore((s) => s.state)!; useBusy(); const g = useStore.getState()
  const p = st.printer
  return (
    <Card title={t('sec_printer')}>
      <Row label={t('preset')} busy={isBusy(g, 'select_printer_preset')}><Picker title={t('preset')} value={p.preset} options={p.presets} disabled={isBusy(g, 'select_printer_preset')} onPick={(id) => run('select_printer_preset', { id })} /></Row>
      <Row label={t('nozzle')}><span>{p.nozzle} mm</span></Row>
      <Row label={t('plate')} busy={isBusy(g, 'select_plate_type')}><Picker title={t('plate')} value={p.plate} options={p.plateTypes} disabled={isBusy(g, 'select_plate_type')} onPick={(id) => run('select_plate_type', { id })} /></Row>
    </Card>
  )
}

export function FilamentPanel({ run }: { run: Run }) {
  const { t } = useTranslation(); const st = useStore((s) => s.state)!; useBusy(); const g = useStore.getState()
  const f = st.filament
  return (
    <div className="flex flex-col gap-2">
      {f.items.map((it) => (
        <Card key={it.id}>
          <div className="flex items-center gap-2 min-h-12">
            <span className="w-10 h-10 rounded-xl shrink-0 border border-line shadow-[inset_0_0_0_2px_rgba(255,255,255,.25)]" style={{ background: it.color }} role="img" aria-label={it.color} />
            <span className="flex-1 min-w-0 flex flex-col leading-tight"><span className="truncate font-medium">{t('filament_n', { n: it.id + 1 })}</span><span className="text-xs text-mute">{it.type ?? ''}</span></span>
            <Btn aria-label={t('edit')} onClick={() => run('filament_edit', { index: it.id })}><Icon name="edit" /></Btn>
            <Btn variant="ghost" className="text-danger" aria-label={t('remove')} disabled={f.items.length <= 1 || isBusy(g, 'filament_remove')} onClick={() => run('filament_remove', { index: it.id })}><Icon name="trash" /></Btn>
          </div>
          <Picker title={t('preset')} value={it.preset} options={f.presets} onPick={(id) => run('filament_set_preset', { index: it.id, id })} />
        </Card>
      ))}
      <Btn variant="primary" disabled={f.items.length >= f.max || isBusy(g, 'filament_add')} onClick={() => run('filament_add')}><Icon name="plus" />{t('add')}</Btn>
    </div>
  )
}

const BRIM = ['auto_brim', 'no_brim', 'outer_only', 'inner_only', 'outer_and_inner']
const BRIM_KEY: Record<string, string> = { auto_brim: 'brim_auto', no_brim: 'brim_none', outer_only: 'brim_outer', inner_only: 'brim_inner', outer_and_inner: 'brim_both' }
const PATTERNS = ['grid', 'gyroid', 'cubic', 'triangles', 'honeycomb', 'zig-zag', 'line', 'concentric', 'lightning', 'adaptive-cubic'].map((x) => ({ id: x, name: x }))

export function QualityPanel({ run, advanced }: { run: Run; advanced: () => void }) {
  const { t } = useTranslation(); const st = useStore((s) => s.state)!; useBusy(); const g = useStore.getState()
  const q = st.quality; const v = q.values
  const num = (k: string, def = 0) => (typeof v[k] === 'number' ? (v[k] as number) : def)
  const set = (key: string, value: OptValue) => run('set_option', { key, value })
  const step = (key: string, step: number, min: number, max: number, decimals = 0, unit?: string) => (
    <Row stack label={t(key)} busy={isBusy(g, 'set_option', key)}>
      <Stepper label={t(key)} value={num(key)} step={step} min={min} max={max} decimals={decimals} unit={unit} disabled={isBusy(g, 'set_option', key)} onChange={(x) => set(key, x)} />
    </Row>
  )
  const brim = String(v.brim_type ?? 'auto_brim')
  return (
    <div className="flex flex-col gap-2">
      <Card>
        <Row label={t('preset')} busy={isBusy(g, 'select_process_preset')}>
          <Picker title={t('preset')} value={q.preset} options={q.presets} disabled={isBusy(g, 'select_process_preset')} onPick={(id) => run('select_process_preset', { id })} />
        </Row>
      </Card>
      <Card title={t('sec_layers')}>
        {step('layer_height', 0.04, 0.04, 0.6, 2, 'mm')}
        {step('wall_loops', 1, 1, 20)}
        {step('top_shell_layers', 1, 0, 30)}
        {step('bottom_shell_layers', 1, 0, 30)}
      </Card>
      <Card title={t('sec_infill')}>
        {step('sparse_infill_density', 5, 0, 100, 0, '%')}
        <Row label={t('sparse_infill_pattern')} busy={isBusy(g, 'set_option', 'sparse_infill_pattern')}>
          <Picker title={t('sparse_infill_pattern')} value={String(v.sparse_infill_pattern ?? 'grid')} options={PATTERNS} disabled={isBusy(g, 'set_option', 'sparse_infill_pattern')} onPick={(id) => set('sparse_infill_pattern', id)} />
        </Row>
      </Card>
      <Card title={t('sec_support')}>
        <Row label={t('enable_support')} busy={isBusy(g, 'set_option', 'enable_support')}>
          <Toggle label={t('enable_support')} checked={v.enable_support === true} disabled={isBusy(g, 'set_option', 'enable_support')} onChange={(x) => set('enable_support', x)} />
        </Row>
        <Row label={t('brim_type')} busy={isBusy(g, 'set_option', 'brim_type')}>
          <Picker title={t('brim_type')} value={brim} options={BRIM.map((b) => ({ id: b, name: t(BRIM_KEY[b]) }))} disabled={isBusy(g, 'set_option', 'brim_type')} onPick={(id) => set('brim_type', id)} />
        </Row>
        {brim !== 'no_brim' && step('brim_width', 1, 0, 50, 0, 'mm')}
      </Card>
      <Btn variant="ghost" onClick={advanced}>{t('advanced')}<Icon name="chevRight" size={20} /></Btn>
    </div>
  )
}

function Node({ n, depth, run }: { n: ObjectNode; depth: number; run: Run }) {
  const { t } = useTranslation()
  return (
    <>
      <div className={cn('min-h-14 flex items-center gap-2 rounded-xl px-2', n.selected ? 'bg-accent/20 border border-accent' : 'bg-row border border-transparent')} style={{ marginLeft: depth * 12 }}>
        <button type="button" className="flex-1 min-w-0 min-h-12 text-left truncate border-0 bg-transparent" disabled={n.kind === 'plate'} onClick={() => run('object_select', { id: n.id })}>{n.name}</button>
        {n.kind === 'object' && <>
          <Btn aria-label={n.visible === false ? t('show') : t('hide')} onClick={() => run('object_set_visible', { id: n.id, visible: n.visible === false })}><Icon name={n.visible === false ? 'eyeOff' : 'eye'} /></Btn>
          <Btn variant="ghost" className="text-danger" aria-label={t('delete')} onClick={() => run('object_delete', { id: n.id })}><Icon name="trash" /></Btn>
        </>}
      </div>
      {n.children?.map((c) => <Node key={c.id} n={c} depth={depth + 1} run={run} />)}
    </>
  )
}

export function ObjectsPanel({ run }: { run: Run }) {
  const { t } = useTranslation(); const st = useStore((s) => s.state)!
  const empty = st.objects.every((p) => !p.children?.length)
  return (
    <div className="flex flex-col gap-2">
      <div className="flex gap-2">
        <Btn className="flex-1 bg-card border border-line" onClick={() => run('object_action', { id: '', action: 'arrange' })}><Icon name="arrange" />{t('arrange')}</Btn>
      </div>
      {st.objects.map((n) => <Node key={n.id} n={n} depth={0} run={run} />)}
      {empty && <p className="text-mute text-center py-4">{t('no_objects')}</p>}
    </div>
  )
}
