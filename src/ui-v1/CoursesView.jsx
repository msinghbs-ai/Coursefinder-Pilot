// v1.1 Counsellor UI, Courses (REQ-115, REQ-117; MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 screens 1, 1b, 1c). Classes are ui-* only (ui-kit.css).
// Reads: the governed courses_page read (rank 2 may call it) and the course detail read for Compare (at most 4). Lookups come from the database (s930).
import { useEffect, useMemo, useState } from 'react'
import { api } from '../lib/supabase.js'
import { useLookups, countryName } from '../lib/lookups.js'
import { money, humanise, duration, locGroups, fdate, annualFee, textOf } from './format.js'
import { COMPARE_MAX } from './saved-store.js'

const TEN = [['duration', 'Duration'], ['delivery', 'Delivery mode'], ['intakes', 'Intakes'], ['deadline', 'Application deadline'], ['english', 'English requirement'],
  ['academic_entry', 'Academic entry'], ['official_url', 'Course page'], ['description', 'Description'], ['level', 'Study level'], ['campus', 'Campus']]
export function readiness(row) {
  const fs = row?.field_states || {}
  const missing = TEN.filter(([k]) => fs[k]?.state !== 'populated').map(([, l]) => l)
  return { ready: TEN.length - missing.length, total: TEN.length, missing }
}

export function Locs({ cities, max = 4 }) {
  const g = locGroups(cities)
  if (!g.length) return <span className="ui-cell-sub">—</span>
  return <span className="ui-locs">{g.map(({ state, names }) => {
    const shown = names.slice(0, max), more = names.length - shown.length
    return <span key={state} className="ui-loc" title={`${state}: ${names.join(', ')}`}><strong>{state}</strong>{shown.length ? ' · ' + shown.join(', ') : ''}{more > 0 && <> <span className="ui-cell-sub">+{more} more</span></>}</span>
  })}</span>
}

function SaveButton({ saved, onToggle }) {
  return <button type="button" className="ui-save" aria-pressed={saved} aria-label={saved ? 'Remove from saved courses' : 'Save course'} title={saved ? 'Saved' : 'Save course'} onClick={e => { e.stopPropagation(); onToggle() }}>{saved ? '♥' : '♡'}</button>
}

const snapshotOf = r => ({ title: r.display_title || r.canonical_title, provider: r.provider_name, code: r.display_code?.code || r.course_code, cities: r.cities, level: r.level_name, delivery: r.delivery_mode, du: r.duration_unit, dv: r.duration_value, fee: r.fee_amount, cur: r.fee_currency, field_states: r.field_states })

export default function CoursesView({ saved, userId }) {
  const lk = useLookups()
  const [q, setQ] = useState(''), [country, setCountry] = useState(''), [level, setLevel] = useState('')
  const [view, setView] = useState('all'), [offset, setOffset] = useState(0)
  const [page, setPage] = useState({ items: [], total: 0, limit: 50 }), [err, setErr] = useState(''), [busy, setBusy] = useState(false)
  const [cmp, setCmp] = useState([]), [open, setOpen] = useState(false), [, bump] = useState(0), [detailRow, setDetailRow] = useState(null)
  useEffect(() => saved.subscribe(() => bump(n => n + 1)), [saved])
  useEffect(() => { setOffset(0) }, [q, country, level])
  useEffect(() => {
    if (view !== 'all') return
    let on = true
    const t = setTimeout(() => {
      setBusy(true); setErr('')
      api.coursePage({ query: q.trim(), country, level, limit: 50, offset, lifecycle: 'active' })
        .then(p => on && setPage({ items: p?.items || [], total: Number(p?.total || 0), limit: Number(p?.limit || 50) }))
        .catch(() => on && setErr('Courses could not be loaded. Try again in a moment.'))
        .finally(() => on && setBusy(false))
    }, q ? 300 : 0)
    return () => { on = false; clearTimeout(t) }
  }, [q, country, level, offset, view])

  const savedRows = saved.list()
  const rows = view === 'saved' ? savedRows.map(s => ({ id: s.id, display_title: s.title, provider_name: s.provider, display_code: { code: s.code }, cities: s.cities, level_name: s.level, delivery_mode: s.delivery, duration_unit: s.du, duration_value: s.dv, fee_amount: s.fee, fee_currency: s.cur, field_states: s.field_states })) : page.items
  const toggleCmp = id => setCmp(c => c.includes(id) ? c.filter(x => x !== id) : c.length >= COMPARE_MAX ? c : [...c, id])
  const levels = useMemo(() => (lk.study_levels || []).map(l => [l.code, l.name || l.label || humanise(l.code)]), [lk])
  const countries = useMemo(() => (lk.countries || []).filter(c => c.target).map(c => [c.code, c.name || countryName(lk, c.code)]), [lk])
  const hasPrev = offset > 0, hasNext = offset + page.limit < page.total

  return <>
    <div className="ui-page-head"><h1 className="ui-page-title">Courses</h1><span className="ui-page-sub">Every active course, with fees, intakes, entry and English requirements.</span></div>
    <section className="ui-filterbar" aria-label="Course filters">
      <div className="ui-field ui-field-wide"><label htmlFor="uiq">Search</label><input id="uiq" className="ui-input" placeholder="Course, code or provider" value={q} onChange={e => setQ(e.target.value)} /></div>
      <div className="ui-field"><label htmlFor="uic">Country</label><select id="uic" className="ui-input" value={country} onChange={e => setCountry(e.target.value)}><option value="">All countries</option>{countries.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></div>
      <div className="ui-field"><label htmlFor="uil">Study level</label><select id="uil" className="ui-input" value={level} onChange={e => setLevel(e.target.value)}><option value="">All levels</option>{levels.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></div>
    </section>
    {view === 'saved' && <section className="ui-savedbar" aria-label="Compare saved courses"><div><strong>Saved courses</strong><div className="ui-note">Pick up to {COMPARE_MAX} saved courses, then open the side-by-side comparison. Saved courses stay in your list until you remove them.</div></div>
      <div className="ui-filter-actions"><button type="button" className="ui-btn ui-btn-primary" disabled={!cmp.length} onClick={() => setOpen(true)}>Compare selected ({cmp.length})</button><button type="button" className="ui-btn" onClick={() => setCmp([])}>Clear selection</button></div></section>}
    <section className="ui-gridwrap">
      <div className="ui-grid-caption">
        <span className="ui-seg" role="tablist" aria-label="Course list"><button type="button" aria-current={view === 'all'} onClick={() => setView('all')}>All courses</button><button type="button" aria-current={view === 'saved'} onClick={() => setView('saved')}>♥ Saved ({saved.count()})</button></span>
        {view === 'saved' ? <span><strong>{savedRows.length}</strong> saved courses · {cmp.length} of {COMPARE_MAX} selected to compare</span> : <span><strong>{page.total.toLocaleString('en-AU')}</strong> courses{busy ? ' · loading…' : ''}</span>}
      </div>
      {err && <div className="ui-alert" role="alert">{err}</div>}
      <table className="ui-grid" data-no-resize><thead><tr><th>Course</th><th>Location</th><th>Level</th><th>Delivery</th><th>Duration</th><th className="ui-num">Tuition</th><th>Completeness</th></tr></thead>
        <tbody>{rows.length ? rows.map(r => { const rd = readiness(r), on = cmp.includes(r.id); return <tr key={r.id}>
          <td data-primary><div className="ui-cell-head"><div><div className="ui-cell-title"><button type="button" className="ui-btn ui-btn-sm" onClick={() => setDetailRow(r)}>{r.display_title || r.canonical_title}</button></div><div className="ui-cell-sub">{r.provider_name}{(r.display_code?.code || r.course_code) ? ' · ' + (r.display_code?.code || r.course_code) : ''}</div></div>
            <SaveButton saved={saved.has(r.id)} onToggle={() => saved.toggle(r.id, snapshotOf(r))} /></div>
            {view === 'saved' && <div className="ui-chip-row ui-cell-badges"><button type="button" className="ui-btn ui-btn-sm" aria-pressed={on} disabled={!on && cmp.length >= COMPARE_MAX} title={!on && cmp.length >= COMPARE_MAX ? `Up to ${COMPARE_MAX} courses` : undefined} onClick={() => toggleCmp(r.id)}>{on ? '✓ In compare' : 'Add to compare'}</button></div>}</td>
          <td data-label="Location"><Locs cities={r.cities} /></td>
          <td data-label="Level">{r.level_name || '—'}</td>
          <td data-label="Delivery">{humanise(r.delivery_mode)}</td>
          <td data-label="Duration">{duration(r.duration_value, r.duration_unit)}</td>
          <td data-label="Tuition" className="ui-num">{money(r.fee_amount, r.fee_currency)}</td>
          <td data-label="Completeness"><span className="ui-badge" data-tone={rd.ready >= 8 ? 'success' : rd.ready >= 5 ? 'warning' : 'neutral'} title={rd.missing.length ? 'Missing: ' + rd.missing.join(', ') : 'All ten facts held'}>{rd.ready}/{rd.total} ready</span></td></tr> })
          : <tr><td data-primary>{view === 'saved' ? <div className="ui-emptystate"><p className="ui-emptystate-title">No saved courses yet</p><p className="ui-note">Select ♡ on any course to save it here.</p></div> : <div className="ui-emptystate"><p className="ui-emptystate-title">{busy ? 'Loading courses…' : 'No courses match these filters'}</p></div>}</td></tr>}</tbody></table>
      {view === 'all' && <div className="ui-filter-actions"><button type="button" className="ui-btn" disabled={!hasPrev || busy} onClick={() => setOffset(Math.max(0, offset - page.limit))}>Previous</button><button type="button" className="ui-btn" disabled={!hasNext || busy} onClick={() => setOffset(offset + page.limit)}>Next</button></div>}
    </section>
    {detailRow && <CourseDrawer row={detailRow} saved={saved} snapshot={snapshotOf(detailRow)} onClose={() => setDetailRow(null)} />}
    {open && <CompareModal ids={cmp} rowsById={Object.fromEntries(savedRows.map(s => [s.id, s]))} onRemove={toggleCmp} onClose={() => setOpen(false)} />}
  </>
}

const ROWS = [
  ['Annual tuition fee', d => annualFee(d)],
  ['Duration', d => duration(d.duration_value, d.duration_unit)],
  ['State & campus', d => <Locs cities={(d.campuses || []).map(c => ({ subdivision_code: c.subdivision_code, subdivision_name: c.subdivision_name, city: c.city || c.locality, campus: c.campus_name || c.name }))} max={99} />],
  ['Intakes & exact start dates', d => (d.intakes || []).length ? <ul className="ui-lines">{d.intakes.map((i, k) => <li key={k}>{i.start_date ? fdate(i.start_date) : `${i.label || ''} ${i.year || ''}`.trim() + ' (month only)'}</li>)}</ul> : 'Not published by provider'],
  ['Academic entry requirements', d => textOf(d.entry_summary) || 'Not recorded'],
  ['English (IELTS · PTE · TOEFL)', d => (d.english || []).length ? <ul className="ui-lines">{d.english.map((e, k) => <li key={k}>{e.test_code}: {e.overall_score}{e.components && Object.keys(e.components).length ? ' (' + Object.entries(e.components).map(([a, b]) => `${humanise(a)} ${b}`).join(', ') + ')' : ''}</li>)}</ul> : 'Not recorded'],
  ['Available scholarships', d => textOf(d.course_scholarships) || 'None recorded'],
]

export function CompareModal({ ids, rowsById, onRemove, onClose }) {
  const [det, setDet] = useState({})
  useEffect(() => {
    let on = true
    ids.filter(id => !det[id]).forEach(id => api.courseDetail(id).then(d => on && setDet(x => ({ ...x, [id]: d || { error: true } }))).catch(() => on && setDet(x => ({ ...x, [id]: { error: true } }))))
    return () => { on = false }
  }, [ids.join(',')])
  const loaded = ids.filter(id => det[id] && !det[id].error).length
  return <><div className="ui-backdrop" onClick={onClose} /><div className="ui-modal ui-modal-wide" role="dialog" aria-label="Compare courses" data-selected={ids.length}>
    <div className="ui-drawer-head ui-modal-head"><div><h2>Compare courses</h2><div className="ui-page-sub">Comparing {ids.length} of {ids.length} selected · up to {COMPARE_MAX}{loaded < ids.length ? ' · loading…' : ''}</div></div><button type="button" className="ui-btn ui-btn-sm ui-close" onClick={onClose}>Close</button></div>
    {!ids.length ? <div className="ui-emptystate"><p className="ui-emptystate-title">No courses selected</p></div> :
      <div className="ui-compare" style={{ '--n': ids.length }}><div className="ui-compare-corner" />
        {ids.map(id => <div key={id} className="ui-compare-head" data-cmp-col={id}><div className="ui-cell-title">{rowsById[id]?.title || det[id]?.display_title}</div><div className="ui-cell-sub">{rowsById[id]?.provider || det[id]?.provider_name}</div><button type="button" className="ui-btn ui-btn-sm" onClick={() => onRemove(id)}>Remove</button></div>)}
        {ROWS.map(([label, fn]) => <FragmentRow key={label} label={label} ids={ids} det={det} fn={fn} />)}
      </div>}
    <p className="ui-note">Practical counselling columns only: fees, duration, location, intakes, entry, English and scholarships. Rankings and survey results are not part of this comparison.</p></div></>
}
function FragmentRow({ label, ids, det, fn }) {
  return <><div className="ui-compare-label">{label}</div>{ids.map(id => <div key={id} className="ui-compare-cell" data-label={label}>{!det[id] ? '…' : det[id].error ? 'Could not be loaded' : fn(det[id])}</div>)}</>
}

/** Screen 2: the course detail drawer. One read (course_detail); fees, intakes with exact dates, English sub-scores, entry, scholarships, location, the provider's own page. */
export function CourseDrawer({ row, saved, snapshot, onClose }) {
  const [d, setD] = useState(null), [tab, setTab] = useState('overview'), [err, setErr] = useState(''), [, bump] = useState(0)
  useEffect(() => saved.subscribe(() => bump(n => n + 1)), [saved])
  useEffect(() => { let on = true; api.courseDetail(row.id).then(x => on && setD(x || {})).catch(() => on && setErr('Course details could not be loaded.')); return () => { on = false } }, [row.id])
  const title = row.display_title || row.canonical_title
  const isSaved = saved.has(row.id)
  const feeRows = (d?.fees || []).filter(f => f.amount != null)
  const link = d?.course_url
  return <><div className="ui-backdrop" onClick={onClose} /><aside className="ui-drawer" role="dialog" aria-label={title}>
    <div className="ui-drawer-head"><div><h2>{title}</h2><div className="ui-page-sub">{row.provider_name}</div></div><button type="button" className="ui-btn ui-btn-sm ui-close" onClick={onClose}>Close</button></div>
    <div className="ui-tabs" role="tablist">{[['overview', 'Overview'], ['fees', 'Fees & intakes'], ['requirements', 'Entry & English'], ['links', 'Links']].map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={tab === k} onClick={() => setTab(k)}>{l}</button>)}</div>
    <div className="ui-drawer-body">{err && <div className="ui-alert" role="alert">{err}</div>}{!d && !err && <p className="ui-note">Loading…</p>}
      {d && tab === 'overview' && <dl className="ui-kv"><dt>Study level</dt><dd>{d.level_name || row.level_name || '—'}</dd><dt>Field of study</dt><dd>{d.field_name || '—'}</dd>
        <dt>Delivery</dt><dd>{humanise(d.delivery_mode)}</dd><dt>Duration</dt><dd>{duration(d.duration_value, d.duration_unit)}</dd>
        <dt>State & campus</dt><dd><Locs max={99} cities={(d.campuses || []).map(c => ({ subdivision_code: c.subdivision_code, subdivision_name: c.subdivision_name, city: c.city || c.locality, campus: c.campus_name || c.name }))} /></dd>
        <dt>Course code</dt><dd>{d.course_code || '—'}</dd>{d.description && <><dt>About</dt><dd>{d.description}</dd></>}</dl>}
      {d && tab === 'fees' && <><section className="ui-section-head"><h3>Tuition</h3></section>{feeRows.length ? <ul className="ui-list">{feeRows.map((f, i) => <li key={i}>{money(f.amount, f.currency)} · {humanise(f.basis)}{f.audience ? ' · ' + humanise(f.audience) : ''}{f.year ? ' · ' + f.year : ''}</li>)}</ul> : <p className="ui-note">Not published by provider.</p>}
        <section className="ui-section-head"><h3>Intakes</h3></section>{(d.intakes || []).length ? <ul className="ui-list">{d.intakes.map((i, k) => <li key={k}>{i.start_date ? fdate(i.start_date) : `${i.label || ''} ${i.year || ''}`.trim() + ' (month only)'}{i.deadline ? ' · apply by ' + fdate(i.deadline) : ''}</li>)}</ul> : <p className="ui-note">Not published by provider.</p>}</>}
      {d && tab === 'requirements' && <><section className="ui-section-head"><h3>Academic entry</h3></section><p>{textOf(d.entry_summary) || 'Not recorded'}</p>
        <section className="ui-section-head"><h3>English</h3></section>{(d.english || []).length ? <ul className="ui-list">{d.english.map((e, k) => <li key={k}><strong>{e.test_name || e.test_code}</strong>: overall {e.overall_score}{e.components && Object.keys(e.components).length ? ' · ' + Object.entries(e.components).map(([a, b]) => `${humanise(a)} ${b}`).join(', ') : ''}</li>)}</ul> : <p className="ui-note">Not recorded.</p>}
        <section className="ui-section-head"><h3>Scholarships</h3></section><p>{textOf(d.course_scholarships) || 'None recorded'}</p></>}
      {d && tab === 'links' && <dl className="ui-kv"><dt>Course page</dt><dd>{link ? <a href={link} target="_blank" rel="noreferrer">Provider course page</a> : 'Not published by provider'}</dd>{d.provider_website && <><dt>Provider website</dt><dd><a href={d.provider_website} target="_blank" rel="noreferrer">Provider website</a></dd></>}</dl>}
    </div>
    <div className="ui-drawer-foot"><button type="button" className="ui-btn" aria-pressed={isSaved} onClick={() => saved.toggle(row.id, snapshot)}>{isSaved ? '♥ Saved' : '♡ Save course'}</button></div></aside></>
}
