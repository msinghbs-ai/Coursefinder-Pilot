import React from 'react'
import { orderMarkets } from '../lib/markets.js'
import { usePortal } from '../lib/portal.jsx'

export const Pill = ({ tone = 'grey', children, dashed }) => <span className={`tag tag-${tone}${dashed ? ' dashed' : ''}`}>{children}</span>

export function PageHead({ title, sub }) {
  return <div className="page-head"><h1>{title}</h1>{sub && <p className="muted">{sub}</p>}</div>
}

// "Study in": All plus every destination that has published providers (read live). Kept across screens.
export function StudyInBar() {
  const { destinations, studyIn, setStudyIn, loading } = usePortal()
  return (
    <div className="studyin" role="group" aria-label="Study in">
      <strong>Study in</strong>
      <div className="studyin-pills">
        <button type="button" className="spill" aria-pressed={studyIn === ''} onClick={() => setStudyIn('')}>All</button>
        {destinations.map(d => <button key={d.code} type="button" className="spill" aria-pressed={studyIn === d.code} onClick={() => setStudyIn(d.code)}>{d.name}</button>)}
        {loading && <span className="studyin-note">Loading destinations…</span>}
      </div>
      <span className="studyin-note">Kept across Courses, Entry Requirements, Providers, Scholarships and Saved courses</span>
    </div>
  )
}

export function PillGroup({ label, value, options, onChange }) {
  return (
    <div className="field" role="group" aria-label={label}>
      <span className="field-label">{label}</span>
      <div className="pillrow">
        {options.map(o => (
          <button key={o.value} type="button" className="fpill" aria-pressed={value === o.value} onClick={() => onChange(o.value)}>
            {o.label}{o.count !== undefined && <span className="fpill-n">{o.count.toLocaleString('en-AU')}</span>}
          </button>
        ))}
      </div>
    </div>
  )
}

export const Select = ({ label, value, onChange, children }) => (
  <label className="field"><span className="field-label">{label}</span><select value={value} onChange={e => onChange(e.target.value)}>{children}</select></label>
)

export function LoadState({ loading, error, unavailable, onRetry, what }) {
  if (loading) return <p className="muted" role="status">Loading {what}…</p>
  if (unavailable) return <div className="notice">This part of the platform is not switched on yet. Nothing is shown until it is.</div>
  if (error) return <div className="notice bad" role="alert">{error} {onRetry && <button type="button" className="link-inline" onClick={onRetry}>Try again</button>}</div>
  return null
}

export function ShowMore({ shown, total, loading, onClick, noun }) {
  if (shown >= total) return total > 0 ? <p className="muted center">All {total.toLocaleString('en-AU')} {noun} shown.</p> : null
  return (
    <div className="more">
      <p className="muted">{shown.toLocaleString('en-AU')} of {total.toLocaleString('en-AU')} {noun} shown</p>
      <button type="button" className="btn" disabled={loading} onClick={onClick}>{loading ? 'Loading…' : 'Show more'}</button>
    </div>
  )
}

export const Count = ({ n, children }) => <p className="count"><strong>{Number(n).toLocaleString('en-AU')}</strong> {children}</p>

// s1222: a student-country list with the priority countries first (portal.priority_source_countries), a divider, then the rest A to Z.
export function MarketOptions({ markets, priority }) {
  const { pinned, rest } = orderMarkets(markets, priority)
  return (
    <>
      {pinned.map(m => <option key={`p-${m.code}`} value={m.code}>{m.name}</option>)}
      {pinned.length > 0 && rest.length > 0 && <option disabled value="__divider">──────────</option>}
      {rest.map(m => <option key={m.code} value={m.code}>{m.name}</option>)}
    </>
  )
}

// s1222: Cards or List, kept for the person across screens.
export function ViewToggle({ value, onChange }) {
  return (
    <div className="view-toggle" role="group" aria-label="Show results as">
      <button type="button" className="vt-btn" aria-pressed={value !== 'list'} onClick={() => onChange('cards')}>Cards</button>
      <button type="button" className="vt-btn" aria-pressed={value === 'list'} onClick={() => onChange('list')}>List</button>
    </div>
  )
}

// s1275: the platform holds no answer on whether a course takes international students (open_to_international is null). A course known to be
// closed to them is not searched. The badge shows only when the function sent the field and it is null, never for a course that did not send it.
// s1279: the provider under a course title is clamped to two lines (a long list of trading names would push the card's facts down); the full text is the tooltip
// and is read in full in Course details. The short description is shown only when the platform holds one (never "Not recorded" on a concise card).
export const ProviderLine = ({ name, as: Tag = 'p', className = 'muted' }) => (name ? <Tag className={`${className} clamp-2`} title={name}>{name}</Tag> : null)
export const DescSnippet = ({ c }) => (c && typeof c.description_snippet === 'string' && c.description_snippet.trim() ? <p className="desc-snippet clamp-2">{c.description_snippet}</p> : null)
export const IntlBadge = ({ c }) => (c && c.open_to_international === null ? <Pill tone="amber">Check international availability</Pill> : null)

// s1222: the national course register code (CRICOS, NZQA, MTCU) as a badge beside the course title.
export const RegBadge = ({ r }) => (r && r.code ? <span className="reg-badge" title={`${r.label} course code`}>{r.label} {r.code}</span> : null)
