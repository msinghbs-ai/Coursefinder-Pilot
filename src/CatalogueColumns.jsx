// CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31; decision 19:14 §3): the Columns control, the person's saved layout
// and the cells of the new columns. The layout (visible columns, order, widths, sort, direction) is kept on the server per person
// (public.admin_table_layout), so it follows them to another device or browser. This browser keeps a copy as the fallback when the server cannot be
// reached; the older browser-only preferences (screen state, cf-colw:course widths) are read, never removed.
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { ArrowDown, ArrowUp, Columns3, RotateCcw, Search, Undo2, X } from 'lucide-react'
import { supabase } from './lib/supabase'
import { StatusChip, fmtDate, fmtDateTime, fmtNumber } from './ui-kit'
import { ADAPTER_STATES, COURSE_COLUMNS, COURSE_SCREEN, DEFAULT_LIMITS, FIELD_STATES, GROUPS, citySummary, clampWidth, columnOf, defaultLayout, intakeName, intakeSummary, minWidthOf, monthName, moveColumn, normaliseLayout, toggleColumn } from './catalogue-columns'
import './catalogue-columns.css'

const LOCAL = 'coursefinder:pim:catalogue-layout:v1:'
const readLocal = user => { try { return JSON.parse(localStorage.getItem(LOCAL + user + ':' + COURSE_SCREEN) || 'null') } catch { return null } }
const writeLocal = (user, layout) => { try { localStorage.setItem(LOCAL + user + ':' + COURSE_SCREEN, JSON.stringify(layout)) } catch { /* private window */ } }
const readOldWidths = () => { try { return JSON.parse(localStorage.getItem('cf-colw:course') || '{}') || {} } catch { return {} } }
const SAVE_AFTER_MS = 700 // UI debounce while a person drags or ticks: one save for a burst of changes
const timeOf = v => { try { return new Date(v).toLocaleTimeString('en-AU', { hour: '2-digit', minute: '2-digit' }) } catch { return '' } }

/** The person's Course catalogue layout: server first, then this browser's copy, then the default. */
export function useCourseLayout(userId) {
  const [layout, setLayout] = useState(defaultLayout)
  const [limits, setLimits] = useState(DEFAULT_LIMITS)
  const [source, setSource] = useState('default') // default | local | server
  const [ack, setAck] = useState(null) // { tone, text }
  const [hasPrevious, setHasPrevious] = useState(false)
  const [loaded, setLoaded] = useState(false)
  const timer = useRef(0), latest = useRef(layout)
  useEffect(() => { latest.current = layout }, [layout])
  useEffect(() => {
    if (!userId) return
    let live = true
    const local = readLocal(userId)
    const start = local ? normaliseLayout(local) : { ...defaultLayout(), widths: normaliseLayout({ ...defaultLayout(), widths: readOldWidths() }).widths }
    setLayout(start); setSource(local ? 'local' : 'default')
    supabase.rpc('admin_table_layout', { p_action: 'read', p_args: { screen: COURSE_SCREEN } }).then(({ data, error }) => {
      if (!live) return
      if (error || !data || typeof data !== 'object' || Array.isArray(data)) { setLoaded(true); return }
      const lim = { ...DEFAULT_LIMITS, ...(data.limits || {}) }
      setLimits(lim); setHasPrevious(Boolean(data.has_previous))
      if (data.layout) { setLayout(normaliseLayout(data.layout, lim)); setSource('server') }
      setLoaded(true)
    }).catch(() => live && setLoaded(true))
    return () => { live = false; clearTimeout(timer.current) }
  }, [userId])
  const persist = next => {
    clearTimeout(timer.current)
    timer.current = setTimeout(async () => {
      try {
        const { data, error } = await supabase.rpc('admin_table_layout', { p_action: 'save', p_args: { screen: COURSE_SCREEN, layout: next } })
        if (error || !data?.saved) throw error || new Error('not saved')
        setSource('server'); setHasPrevious(Boolean(data.has_previous))
        setAck({ tone: 'success', text: `Layout saved to your account at ${timeOf(data.saved_at)}` })
      } catch (e) { setAck({ tone: 'warning', text: `Saved in this browser only: ${e?.message || 'the server did not answer'}` }) }
    }, SAVE_AFTER_MS)
  }
  const update = patch => {
    const next = normaliseLayout({ ...latest.current, ...(typeof patch === 'function' ? patch(latest.current) : patch) }, limits)
    setLayout(next); latest.current = next
    if (userId) writeLocal(userId, next)
    setAck({ tone: 'info', text: 'Saving…' }); persist(next)
  }
  const reset = async () => {
    clearTimeout(timer.current)
    const next = defaultLayout(); setLayout(next); latest.current = next
    if (userId) writeLocal(userId, next)
    try {
      const { data, error } = await supabase.rpc('admin_table_layout', { p_action: 'reset', p_args: { screen: COURSE_SCREEN } })
      if (error || !data?.reset) throw error || new Error('not reset')
      setHasPrevious(Boolean(data.has_previous)); setSource('default'); setAck({ tone: 'success', text: 'Default layout restored. Your last saved layout can be brought back.' })
    } catch (e) { setAck({ tone: 'warning', text: `Default layout shown in this browser only: ${e?.message || 'the server did not answer'}` }) }
  }
  const restore = async () => {
    try {
      const { data, error } = await supabase.rpc('admin_table_layout', { p_action: 'restore', p_args: { screen: COURSE_SCREEN } })
      if (error || !data?.restored) throw error || new Error('nothing to restore')
      const next = normaliseLayout(data.layout, limits); setLayout(next); latest.current = next
      if (userId) writeLocal(userId, next)
      setHasPrevious(Boolean(data.has_previous)); setSource('server'); setAck({ tone: 'success', text: `Last saved layout restored at ${timeOf(data.saved_at)}` })
    } catch (e) { setAck({ tone: 'warning', text: `Could not restore: ${e?.message || 'the server did not answer'}` }) }
  }
  return { layout, limits, source, ack, hasPrevious, loaded, update, reset, restore }
}

/** Columns control: search, four groups, a count, show and hide, move up and down, Reset to default, Restore last saved. */
export function ColumnsControl({ layout, limits, hasPrevious, onChange, onReset, onRestore }) {
  const [open, setOpen] = useState(false), [q, setQ] = useState('')
  const ref = useRef(null), searchRef = useRef(null)
  useEffect(() => { if (!open) return; const close = e => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }; const esc = e => { if (e.key === 'Escape') setOpen(false) }; addEventListener('mousedown', close); addEventListener('keydown', esc); setTimeout(() => searchRef.current?.focus(), 0); return () => { removeEventListener('mousedown', close); removeEventListener('keydown', esc) } }, [open])
  const shown = layout.columns, full = shown.length >= (limits.max_columns || DEFAULT_LIMITS.max_columns)
  const match = c => !q || `${c.label} ${c.group}`.toLowerCase().includes(q.toLowerCase())
  const move = (key, by) => { onChange({ columns: moveColumn(shown, key, by) }); requestAnimationFrame(() => document.querySelector(`[data-col-move="${key}:${by}"]`)?.focus()) }
  return <div className="cc-columns" ref={ref}>
    <button type="button" className="m-secondary compact" aria-expanded={open} aria-haspopup="dialog" data-columns-toggle onClick={() => setOpen(x => !x)}><Columns3 size={14} />Columns <span className="cc-count" data-columns-count>{shown.length} of {COURSE_COLUMNS.length}</span></button>
    {open && <div className="cc-panel" role="dialog" aria-label="Choose columns" data-columns-panel>
      <div className="cc-panel-head"><strong>Columns</strong><span>{shown.length} of {COURSE_COLUMNS.length} shown{full ? ' (the most a layout can show)' : ''}</span><button type="button" className="cc-icon" aria-label="Close columns" onClick={() => setOpen(false)}><X size={14} /></button></div>
      <label className="cc-search"><Search size={14} /><input ref={searchRef} value={q} onChange={e => setQ(e.target.value)} placeholder="Search columns…" aria-label="Search columns" /></label>
      <div className="cc-order" aria-label="Shown columns, in order">
        <small>Shown, in order</small>
        <ol>{shown.filter(k => match(columnOf(k))).map(k => { const c = columnOf(k), i = shown.indexOf(k); return <li key={k} data-col-order={k}><span>{c.label}</span>
          <button type="button" className="cc-icon" data-col-move={`${k}:-1`} aria-label={`Move ${c.label} left`} disabled={i === 0} onClick={() => move(k, -1)}><ArrowUp size={13} /></button>
          <button type="button" className="cc-icon" data-col-move={`${k}:1`} aria-label={`Move ${c.label} right`} disabled={i === shown.length - 1} onClick={() => move(k, 1)}><ArrowDown size={13} /></button></li> })}</ol>
      </div>
      {GROUPS.map(g => { const cols = COURSE_COLUMNS.filter(c => c.group === g && match(c)); if (!cols.length) return null; return <fieldset key={g} className="cc-group" data-columns-group={g}>
        <legend>{g} <small>{cols.filter(c => shown.includes(c.key)).length} of {COURSE_COLUMNS.filter(c => c.group === g).length}</small></legend>
        {cols.map(c => <label key={c.key} className="cc-option"><input type="checkbox" checked={shown.includes(c.key)} disabled={c.alwaysVisible || (!shown.includes(c.key) && full)} onChange={e => onChange({ columns: toggleColumn(shown, c.key, e.target.checked, limits) })} data-col-toggle={c.key} />{c.label}{c.alwaysVisible && <small> (always shown)</small>}{c.sortKey && <small> · sorts</small>}</label>)}
      </fieldset> })}
      {!COURSE_COLUMNS.some(match) && <p className="cc-empty">No column matches “{q}”.</p>}
      <div className="cc-actions"><button type="button" className="m-secondary compact" onClick={onReset} data-columns-reset><RotateCcw size={13} />Reset to default</button><button type="button" className="m-secondary compact" onClick={onRestore} disabled={!hasPrevious} data-columns-restore><Undo2 size={13} />Restore last saved</button></div>
    </div>}
  </div>
}

export function FieldState({ fs }) {
  if (!fs) return <span className="cc-unknown" data-field-state="unknown" title="No field state is held for this course">Unknown</span>
  const [label, tone] = FIELD_STATES[fs.state] || ['Unknown', 'neutral']
  return <span data-field-state={fs.state}><StatusChip tone={tone} label={label} title={[fs.reason && `Reason: ${fs.reason}`, fs.flag && `Flag: ${fs.flag}`].filter(Boolean).join(' · ') || undefined} /></span>
}
const Unknown = ({ title }) => <span className="cc-unknown" title={title || 'No trustworthy record of this'}>Unknown</span>

function Cities({ row }) {
  const [open, setOpen] = useState(false)
  const s = citySummary(row.cities)
  if (!s.names.length) return row.city_names ? <span>{row.city_names}</span> : <span className="cc-unknown" title="No campus city held for this course">No campus city</span>
  if (s.names.length === 1) return <span data-cities="1">{s.names[0]}</span>
  return <span className="cc-cities" data-cities={s.names.length}><button type="button" className="cc-link" aria-expanded={open} onClick={e => { e.stopPropagation(); setOpen(x => !x) }}>{s.short}</button>{open && <ul onClick={e => e.stopPropagation()}>{s.names.map(n => <li key={n}>{n}</li>)}</ul>}</span>
}
// Intakes as the website builds them (active intakes; month from the label by the website's rule). Nothing is filled in: an intake with no
// month, year or date says so; a course with no intake shows its field state.
function Expand({ short, items, attr }) {
  const [open, setOpen] = useState(false)
  if (items.length <= 1) return <span {...attr}>{short}</span>
  return <span className="cc-cities" {...attr}><button type="button" className="cc-link" aria-expanded={open} onClick={e => { e.stopPropagation(); setOpen(x => !x) }}>{short}</button>{open && <ul onClick={e => e.stopPropagation()}>{items.map((n, i) => <li key={i}>{n}</li>)}</ul>}</span>
}
const intakeLine = i => [intakeName(i), i.start_date ? `starts ${fmtDate(i.start_date)}` : null, i.application_deadline ? `apply by ${fmtDate(i.application_deadline)}` : i.deadline_kind === 'rolling' ? 'rolling applications' : null].filter(Boolean).join(' · ')
function intakeCell(key, row) {
  const list = Array.isArray(row.intakes) ? row.intakes : []
  const fs = row.field_states || {}
  if (!list.length) return key === 'deadline' ? <FieldState fs={fs.deadline} /> : <FieldState fs={fs.intakes} />
  const many = (vals, attr) => { const u = [...new Set(vals)]; return u.length ? <Expand short={u.length > 1 ? `${u[0]} +${u.length - 1}` : u[0]} items={u} attr={attr} /> : null }
  if (key === 'intakes') { const s = intakeSummary(list); return <Expand short={s.short} items={list.map(intakeLine)} attr={{ 'data-intakes': list.length }} /> }
  if (key === 'intake_month') return many(list.map(i => monthName(i.month)).filter(Boolean), { 'data-intake-month': '' }) || <span className="cc-unknown" title="The intakes held name no month">Not held</span>
  if (key === 'intake_year') return many(list.map(i => i.year).filter(Boolean).map(String), { 'data-intake-year': '' }) || <span className="cc-unknown" title="The intakes held name no year">Not held</span>
  if (key === 'commencement_date') return many(list.filter(i => i.start_date).sort((a, b) => String(a.start_date).localeCompare(String(b.start_date))).map(i => fmtDate(i.start_date)), { 'data-commencement': '' }) || <span className="cc-unknown" title="No exact start date is held: only the intake month or label">Not held</span>
  if (key === 'deadline') {
    const dated = list.filter(i => i.application_deadline).sort((a, b) => String(a.application_deadline).localeCompare(String(b.application_deadline))).map(i => fmtDate(i.application_deadline))
    if (dated.length) return many(dated, { 'data-deadline': '' })
    if (list.some(i => i.deadline_kind === 'rolling')) return <span title={list.find(i => i.deadline_text)?.deadline_text || 'Applications are rolling'}>Rolling</span>
    return <FieldState fs={fs.deadline} />
  }
  return undefined
}
function Published({ row }) {
  const p = row.published
  if (!p || !p.website_at) return <span className="cc-unknown" title="This course has no item in the website feed">Not in the website feed</span>
  const z = p.zoho_at ? `Zoho feed: ${p.zoho_removed ? 'withdrawn' : 'last changed'} ${fmtDateTime(p.zoho_at)}` : 'Zoho feed: no item'
  return <span title={`Website feed: the course's item was ${p.website_removed ? 'withdrawn' : 'last added or changed'} at ${fmtDateTime(p.website_at)} (an unchanged re-check is not counted).\n${z}`} data-published={p.website_removed ? 'withdrawn' : 'published'}>{p.website_removed ? 'Withdrawn ' : ''}{fmtDateTime(p.website_at)}</span>
}
function Campuses({ row }) {
  const [open, setOpen] = useState(false)
  const list = Array.isArray(row.cities) ? row.cities : []
  const n = Number(row.campus_count ?? list.length) || 0
  if (!n) return <span className="cc-unknown">No campus linked</span>
  return <span className="cc-cities"><button type="button" className="cc-link" aria-expanded={open} onClick={e => { e.stopPropagation(); setOpen(x => !x) }}>{n === 1 ? (list[0]?.campus || '1 campus') : `${n} campuses`}</button>{open && <ul onClick={e => e.stopPropagation()}>{list.map((c, i) => <li key={i}>{c.campus}{c.city ? ` · ${c.city}` : ''}{c.subdivision_code ? ` (${c.subdivision_code})` : ''}</li>)}</ul>}</span>
}
function Adapter({ row, navigate }) {
  const a = row.adapter
  if (!a) return <Unknown title="Adapter status not loaded" />
  const [label, tone] = ADAPTER_STATES[a.state] || ['Unknown', 'neutral']
  return <span className="cc-adapter" data-adapter-state={a.state}><StatusChip tone={tone} label={label} title={a.reason} />{a.state !== 'not_configured' && navigate && <button type="button" className="cc-link" onClick={e => { e.stopPropagation(); navigate('layer2', { tab: 'builder', provider: row.provider_id }) }}>Open adapter</button>}</span>
}
const SOURCE_WORDS = { ai_stored: 'AI reader (stored page)', ai_title: 'AI reader (title)', adapter: 'Adapter', institution_rule: 'Institution rule', provider_facts: 'Provider facts', scraper: 'Page reader',
  adapter_overwrite: 'Adapter overwrite', layer2_admission: 'Layer 2 admission', layer4_approval: 'Layer 4 approval', intake_dates: 'Intake dates', manual: 'Set by hand', enrich_fields: 'Enrich fields' }
function admissionTitle(la) {
  if (!la) return 'No admission record: shown as Unknown'
  const s = v => v == null ? '—' : (typeof v === 'string' ? v : JSON.stringify(v)).slice(0, 160)
  return [`Field: ${la.field}`, `Admitted: ${fmtDateTime(la.at)}`, `Source: ${SOURCE_WORDS[la.source] || la.source}`, la.rule && `Rule: ${la.rule}`, `Previous value: ${s(la.before)}`, `New value: ${s(la.after)}`, la.evidence_id && `Evidence: ${la.evidence_id}`].filter(Boolean).join('\n')
}
const FS = { duration: 'duration', delivery_mode: 'delivery', english: 'english', academic_entry: 'academic_entry', description: 'description', official_url: 'official_url', intl_fee_year: 'provider_tuition' }

/** Cells of the columns this change adds. Existing columns keep their own cells. */
export function renderCourseCell(key, row, { navigate } = {}) {
  const fs = row.field_states || {}
  switch (key) {
    case 'country_name': return row.country_name || '—'
    case 'city_names': return <Cities row={row} />
    case 'campus_count': return <Campuses row={row} />
    case 'duration': return row.duration_value != null ? `${Number(row.duration_value)} ${row.duration_unit || ''}`.trim() : <FieldState fs={fs.duration} />
    case 'delivery_mode': return row.delivery_mode ? String(row.delivery_mode).replaceAll('_', ' ') : <FieldState fs={fs.delivery} />
    case 'intl_fee_year': return row.intl_fee_year ? String(row.intl_fee_year) : <FieldState fs={fs.provider_tuition} />
    case 'intakes': case 'intake_month': case 'intake_year': case 'commencement_date': case 'deadline': return intakeCell(key, row)
    case 'english': case 'academic_entry': case 'description': return <FieldState fs={fs[FS[key]]} />
    case 'last_published_at': return <Published row={row} />
    case 'official_url': return row.course_url ? <a className="cc-link" href={row.course_url} target="_blank" rel="noreferrer" onClick={e => e.stopPropagation()} title={row.course_url}>Open page</a> : <FieldState fs={fs.official_url} />
    case 'has_scholarship': return row.has_scholarship == null ? <Unknown /> : row.has_scholarship ? 'Linked' : 'None linked'
    case 'adapter_state': return <Adapter row={row} navigate={navigate} />
    case 'adapter_last_read_at': return row.adapter?.last_read_at ? fmtDateTime(row.adapter.last_read_at) : <span className="cc-unknown">Not read by an adapter</span>
    case 'adapter_result': return row.adapter?.result ? <span className="m-cell-clip" title={row.adapter.result}>{row.adapter.result}</span> : '—'
    case 'page_stored': return !row.page ? <span className="cc-unknown">No course page</span> : row.page.stored ? <StatusChip tone="success" label="Stored" /> : <StatusChip tone="warning" label="Not stored" title={row.page.read_status || undefined} />
    case 'source_identity': return !row.page ? '—' : <span title={`Page ${row.page.status || ''} · read ${row.page.read_status || 'not yet'}`}>{String(row.page.identity || row.page.status || '—').replaceAll('_', ' ')}</span>
    case 'layer4_status': return row.layer4_open == null ? <Unknown /> : row.layer4_open ? <StatusChip tone="violet" label={`${fmtNumber(row.layer4_open)} open`} /> : 'None open'
    case 'enrichment_status': { const e = row.enrichment; if (!e) return <Unknown />; return <span title="Field items: filled, waiting for review, failed, pending">{fmtNumber(e.filled)} filled · {fmtNumber(e.review)} review · {fmtNumber(e.failed)} failed{e.pending ? ` · ${fmtNumber(e.pending)} pending` : ''}</span> }
    case 'last_admitted_field': return row.last_admitted ? <span title={admissionTitle(row.last_admitted)}>{String(row.last_admitted.field).replaceAll('_', ' ')} · {SOURCE_WORDS[row.last_admitted.source] || row.last_admitted.source}</span> : <Unknown title={admissionTitle(null)} />
    case 'created_at': return row.created_at ? fmtDate(row.created_at) : <Unknown />
    case 'last_modified_at': { const v = row.last_modified_at ?? row.updated_at; return v ? <span data-modified title={`The course record itself, as its writers recorded it: ${fmtDateTime(v)}. Values held in other tables (fees, intakes, English requirements) change Last data admitted, not this.`}>{fmtDateTime(v)}</span> : <Unknown title="No change of the course record is recorded" /> }
    case 'last_admitted_at': return row.last_admitted_at ? <span data-admitted data-at={row.last_admitted_at} title={admissionTitle(row.last_admitted)}>{fmtDateTime(row.last_admitted_at)}</span> : <span data-admitted="unknown"><Unknown title={admissionTitle(null)} /></span>
    case 'lifecycle_status': return row.lifecycle_status ? <StatusChip value={row.lifecycle_status} /> : '—'
    case 'publication_status': return row.publication_status ? <StatusChip value={row.publication_status} /> : '—'
    default: return undefined
  }
}
export const NEW_CELL_KEYS = new Set(['country_name', 'city_names', 'campus_count', 'duration', 'delivery_mode', 'intl_fee_year', 'intakes', 'intake_month', 'intake_year', 'commencement_date', 'last_published_at', 'deadline', 'english', 'academic_entry', 'description', 'official_url', 'has_scholarship',
  'adapter_state', 'adapter_last_read_at', 'adapter_result', 'page_stored', 'source_identity', 'layer4_status', 'enrichment_status', 'last_admitted_field', 'created_at', 'last_modified_at', 'last_admitted_at', 'lifecycle_status', 'publication_status'])

/** The table columns for the person's layout, in their order, with their widths' limits. */
export function useCourseTableColumns(layout, limits, { navigate, hide = () => false } = {}) {
  return useMemo(() => layout.columns.filter(k => !hide(k)).map(k => { const c = columnOf(k); return { key: k, label: c.header, width: c.width, sortKey: c.sortKey || undefined, minWidth: minWidthOf(k, limits), ...(NEW_CELL_KEYS.has(k) ? { render: r => renderCourseCell(k, r, { navigate }) } : {}) } }), [layout.columns.join(','), limits, navigate, hide])
}
export { clampWidth }
