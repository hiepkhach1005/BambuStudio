import type { ReactNode, SVGProps } from 'react'

// Project-specific icon set: 24px grid, 1.75 stroke, currentColor.
const P: Record<string, ReactNode> = {
  printer: <><path d="M6 9V4h12v5" /><rect x="4" y="9" width="16" height="8" rx="2" /><path d="M7 14h10v6H7z" /></>,
  filament: <><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="2.5" /><path d="M12 4v3.5M12 16.5V20M4 12h3.5M16.5 12H20" /></>,
  quality: <><path d="M4 7h9M17 7h3M4 17h3M11 17h9" /><circle cx="15" cy="7" r="2" /><circle cx="9" cy="17" r="2" /></>,
  objects: <><path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" /><path d="M4 7.5l8 4.5 8-4.5M12 12v9" /></>,
  play: <path d="M8 5.5v13l11-6.5z" />,
  stop: <rect x="6" y="6" width="12" height="12" rx="2" />,
  print: <><path d="M5 12h14M13 6l6 6-6 6" /><path d="M4 5v14" /></>,
  export: <><path d="M12 4v10M7.5 10L12 14.5 16.5 10" /><path d="M5 19h14" /></>,
  edit: <><path d="M5 19l1-4L16.5 4.5a2 2 0 013 3L9 18z" /><path d="M14.5 6.5l3 3" /></>,
  trash: <><path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13" /><path d="M10 11v6M14 11v6" /></>,
  eye: <><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" /><circle cx="12" cy="12" r="3" /></>,
  eyeOff: <><path d="M3 3l18 18" /><path d="M9.5 5.9A9 9 0 0112 5.5c6 0 9.500 6.500 9.500 6.500a15 15 0 01-3 3.700M6.300 7.500A15 15 0 002.500 12S6 18.500 12 18.500c1.300 0 2.500-.3 3.600-.8" /></>,
  more: <><circle cx="6" cy="12" r="1.200" /><circle cx="12" cy="12" r="1.200" /><circle cx="18" cy="12" r="1.200" /></>,
  plus: <path d="M12 5v14M5 12h14" />,
  minus: <path d="M5 12h14" />,
  chevDown: <path d="M6 9l6 6 6-6" />,
  chevRight: <path d="M9 6l6 6-6 6" />,
  sun: <><circle cx="12" cy="12" r="4" /><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.600 5.600l1.400 1.400M17 17l1.400 1.400M5.600 18.400L7 17M17 7l1.400-1.400" /></>,
  moon: <path d="M20 14.500A8 8 0 019.500 4a8 8 0 1010.500 10.500z" />,
  alert: <><path d="M12 4l9 16H3z" /><path d="M12 10v4.500M12 17.500v.1" /></>,
  close: <path d="M6 6l12 12M18 6L6 18" />,
  arrange: <><rect x="4" y="4" width="7" height="7" rx="1.500" /><rect x="13" y="4" width="7" height="7" rx="1.500" /><rect x="4" y="13" width="7" height="7" rx="1.500" /><rect x="13" y="13" width="7" height="7" rx="1.500" /></>,
  check: <path d="M5 12.500l4.500 4.500L19 7.500" />,
}
export type IconName = keyof typeof P

export function Icon({ name, size = 24, ...p }: { name: IconName; size?: number } & Omit<SVGProps<SVGSVGElement>, 'name'>) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" className="shrink-0" {...p}>
      {name === 'play' || name === 'stop' ? <g fill="currentColor">{P[name]}</g> : P[name]}
    </svg>
  )
}
