// v1.1 operations kit (v1.2 plan, Slice 3): drop-in versions of the small shared pieces the operations screens use, drawn with ui-* classes only.
// A screen moved into src/ui-v1/ imports these in place of src/ui-kit.jsx; props are the same so the screen's own code does not change.
import './tokens.css'
import './ui-kit.css'
import { RefreshCw } from 'lucide-react'
import { fmtNumber } from '../lib/format.js'
export { fmtDate, fmtDateTime, fmtDayMonth, fmtNumber, fmtRelative } from '../lib/format.js'

const TONE = { success: 'success', ok: 'success', danger: 'danger', critical: 'danger', error: 'danger', warning: 'warning', warn: 'warning', info: 'neutral', neutral: 'neutral', violet: 'neutral', unknown: 'neutral' }
const toneOf = t => TONE[t] || 'neutral'
const STATUS = { ok: 'success', success: 'success', active: 'success', on: 'success', done: 'success', ready: 'success', healthy: 'success', failed: 'danger', error: 'danger', critical: 'danger', warning: 'warning', paused: 'warning', pending: 'warning', stale: 'warning' }
const human = v => String(v ?? 'unknown').replace(/[_-]+/g, ' ').replace(/^./, c => c.toUpperCase())

export function Button({ children, variant, compact = false, className = '', type = 'button', ...rest }) {
  return <button type={type} className={`ui-btn${variant === 'primary' ? ' ui-btn-primary' : variant === 'danger' ? ' ui-btn-danger' : ''}${compact ? ' ui-btn-sm' : ''}${className ? ' ' + className : ''}`} {...rest}>{children}</button>
}
export function StatusChip({ value, tone, label, title, className = '' }) {
  const t = tone || STATUS[String(value ?? '').toLowerCase()] || 'neutral'
  return <span className={`ui-badge${className ? ' ' + className : ''}`} data-tone={toneOf(t)} title={title} data-state={String(value ?? '').toLowerCase() || undefined}>{label ?? human(value || 'unknown')}</span>
}
export function Badge({ children, tone, title, className = '' }) { return <span className={`ui-badge${className ? ' ' + className : ''}`} data-tone={tone ? toneOf(tone) : 'neutral'} title={title}>{children}</span> }
export function StatusDot({ tone = 'unknown', label }) { return <span className="ui-dot" data-tone={toneOf(tone)} role="img" aria-label={label || tone} title={label} /> }
export function Metric({ label, value, detail, icon: Icon, tone = 'neutral', className = '' }) {
  const shown = typeof value === 'number' ? fmtNumber(value) : (value ?? '—')
  return <div className={`ui-metric${className ? ' ' + className : ''}`} data-tone={toneOf(tone)}>{Icon && <span className="ui-metric-icon"><Icon size={16} /></span>}<div><small>{label}</small><strong>{shown}</strong>{detail && <span className="ui-metric-detail">{detail}</span>}</div></div>
}
export function SectionTitle({ icon: Icon, title, subtitle, action, level = 3 }) {
  const H = level === 2 ? 'h2' : 'h3'
  return <div className="ui-st"><div className="ui-st-head">{Icon && <span className="ui-st-icon"><Icon size={16} /></span>}<div><H>{title}</H>{subtitle && <p>{subtitle}</p>}</div></div>{action}</div>
}
export function Empty({ children, text, icon: Icon }) { return <div className="ui-emptyline">{Icon && <Icon size={17} />}<span>{children ?? text}</span></div> }
export function Loading({ label = 'Loading…', compact = false }) { return <div className={`ui-loading${compact ? ' is-compact' : ''}`}><RefreshCw size={16} /><span>{label}</span></div> }
