import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { Dialog, Switch as RSwitch } from 'radix-ui'
import { useTranslation } from 'react-i18next'
import { Icon } from './icons'

export const cn = (...c: (string | false | undefined)[]) => c.filter(Boolean).join(' ')

export function Btn({ variant = 'default', className, ...p }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'default' | 'primary' | 'danger' | 'ghost' }) {
  const v = { default: 'bg-row', primary: 'bg-accent text-white font-semibold', danger: 'bg-danger text-white', ghost: 'bg-transparent border border-line' }[variant]
  return <button type="button" {...p} className={cn('min-h-12 min-w-12 rounded-xl px-4 border-0 flex items-center justify-center gap-2', v, className)} />
}

export function Card({ title, children }: { title?: ReactNode; children: ReactNode }) {
  return (
    <section className="rounded-2xl bg-card border border-line p-2 flex flex-col gap-2 shadow-sm">
      {title && <h3 className="m-0 px-1 pt-1 text-xs font-semibold uppercase tracking-wide text-mute">{title}</h3>}
      {children}
    </section>
  )
}

export function Row({ label, children, busy, stack }: { label: ReactNode; children?: ReactNode; busy?: boolean; stack?: boolean }) {
  return (
    <div className={cn('rounded-xl bg-row px-3 py-1 flex gap-2', stack ? 'flex-col py-2' : 'min-h-14 items-center justify-between')}>
      <span className="text-[15px] truncate min-w-0">{label}{busy && <span className="ml-2 text-mute">…</span>}</span>
      {children}
    </div>
  )
}

export function Stepper({ value, step, min, max, decimals = 0, unit, disabled, onChange, label }: { value: number; step: number; min: number; max: number; decimals?: number; unit?: string; disabled?: boolean; label: string; onChange(v: number): void }) {
  const clamp = (v: number) => Math.min(max, Math.max(min, Number(v.toFixed(decimals + 2))))
  return (
    <div className="flex items-center gap-2">
      <Btn aria-label={label + ' -'} disabled={disabled || value <= min} onClick={() => onChange(clamp(value - step))} className="w-14 bg-card border border-line"><Icon name="minus" /></Btn>
      <span className="flex-1 text-center tabular-nums text-lg font-semibold">{value.toFixed(decimals)}<span className="text-sm text-mute font-normal">{unit}</span></span>
      <Btn aria-label={label + ' +'} disabled={disabled || value >= max} onClick={() => onChange(clamp(value + step))} className="w-14 bg-card border border-line"><Icon name="plus" /></Btn>
    </div>
  )
}

export function Toggle({ checked, disabled, onChange, label }: { checked: boolean; disabled?: boolean; label: string; onChange(v: boolean): void }) {
  return (
    <RSwitch.Root aria-label={label} checked={checked} disabled={disabled} onCheckedChange={onChange}
      className={cn('w-16 h-12 rounded-full relative border-0 shrink-0 transition-colors', checked ? 'bg-accent' : 'bg-line')}>
      <RSwitch.Thumb data-thumb className={cn('block w-9 h-9 rounded-full bg-white shadow transition-transform', checked ? 'translate-x-[26px]' : 'translate-x-[3px]')} />
    </RSwitch.Root>
  )
}

export function Picker({ title, value, options, disabled, onPick }: { title: string; value: string; options: { id: string; name: string }[]; disabled?: boolean; onPick(id: string): void }) {
  const { t } = useTranslation()
  const cur = options.find((o) => o.id === value)
  return (
    <Dialog.Root>
      <Dialog.Trigger asChild>
        <button type="button" data-picker disabled={disabled} className="min-h-12 max-w-[170px] rounded-xl bg-card border border-line pl-3 pr-2 flex items-center gap-1"><span className="truncate text-sm">{cur?.name ?? '—'}</span><Icon name="chevDown" size={20} /></button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/55" />
        <Dialog.Content className="fixed left-2 right-2 top-2 bottom-2 rounded-2xl bg-panel border border-line p-3 flex flex-col gap-2">
          <Dialog.Title className="text-lg font-semibold">{title}</Dialog.Title>
          <Dialog.Description className="sr-only">{title}</Dialog.Description>
          <div className="scroll flex-1 flex flex-col gap-2">
            {options.map((o) => (
              <Dialog.Close asChild key={o.id}>
                <button type="button" onClick={() => onPick(o.id)} className={cn('min-h-14 w-full rounded-xl px-3 text-left border-0', o.id === value ? 'bg-accent text-white font-semibold' : 'bg-row')}><span className="flex items-center justify-between gap-2"><span>{o.name}</span>{o.id === value && <Icon name="check" />}</span></button>
              </Dialog.Close>
            ))}
          </div>
          <Dialog.Close asChild><Btn>{t('close')}</Btn></Dialog.Close>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
