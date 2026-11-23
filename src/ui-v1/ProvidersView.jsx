// v1.1 Counsellor UI, Universities & Providers (screens 3, 3a, 3b; REQ-116, REQ-118). Reads: the governed providers_page and provider_detail reads
// (rank 2 may call them); no operator read (IR-021). The Study Square representation fields are not held yet (S2-RM-Design), so every provider
// shows Not recorded until the additive v3 columns arrive: it is never shown as Not Represented.
import { useEffect, useState } from 'react'
import { api, supabase } from '../lib/supabase.js'
import { useLookups, countryName } from '../lib/lookups.js'
import { humanise, fdate } from './format.js'
import { Locs } from './CoursesView.jsx'

export const REP = { represented: ['Represented', 'success'], direct: ['Direct', 'info'], not_represented: ['Not Represented', 'neutral'] }
export function RepBadge({ rep }) {
  const m = rep && REP[rep.representation_status]
  if (!m) return <span className="ui-badge" data-tone="muted" data-rep="not_recorded" title="Study Square has not recorded a status for this provider">Not recorded</span>
  const mk = (rep.restriction_mode === 'include' || rep.restriction_mode === 'exclude') && rep.restriction_markets?.length
  return <><span className="ui-badge" data-tone={m[1]} data-rep={rep.representation_status} title={`Study Square: ${m[0]}`}>{m[0]}</span>{mk && <span className="ui-market" data-market={rep.restriction_mode}>{rep.restriction_mode === 'exclude' ? 'Except' : 'Only'} {rep.restriction_markets.join(', ')}</span>}</>
}

/** REQ-118 (s1012 read): Study Square's relationship with each provider and its market restriction. The drawer shows the agreement's end date; the screen does not decide an agreement has ended from the browser clock. */
export function useRepresentation() {
  const [map, setMap] = useState(() => new Map())
  useEffect(() => {
    let on = true
    supabase.rpc('admin_provider_representation_read_v1', { p_provider: null }).then(({ data, error }) => {
      if (!on || error) return
      setMap(new Map((data || []).map(x => [x.provider_id, x])))
    })
    return () => { on = false }
  }, [])
  return map
}

export default function ProvidersView() {
  const lk = useLookups(), reps = useRepresentation()
  const [q, setQ] = useState(''), [country, setCountry] = useState(''), [offset, setOffset] = useState(0)
  const [page, setPage] = useState({ items: [], total: 0, limit: 50 }), [err, setErr] = useState(''), [busy, setBusy] = useState(false), [pick, setPick] = useState(null)
  useEffect(() => { setOffset(0) }, [q, country])
  useEffect(() => {
    let on = true
    const t = setTimeout(() => {
      setBusy(true); setErr('')
      api.providerPage({ query: q.trim(), country, limit: 50, offset, lifecycle: 'active' })
        .then(p => on && setPage({ items: p?.items || [], total: Number(p?.total || 0), limit: Number(p?.limit || 50) }))
        .catch(() => on && setErr('Providers could not be loaded. Try again in a moment.'))
        .finally(() => on && setBusy(false))
    }, q ? 300 : 0)
    return () => { on = false; clearTimeout(t) }
  }, [q, country, offset])
  const countries = (lk.countries || []).filter(c => c.target)
  return <>
    <div className="ui-page-head"><h1 className="ui-page-title">Universities &amp; Providers</h1><span className="ui-page-sub">Every active provider, with its courses, campuses and Study Square status.</span></div>
    <section className="ui-filterbar" aria-label="Provider filters">
      <div className="ui-field ui-field-wide"><label htmlFor="uipq">Search</label><input id="uipq" className="ui-input" placeholder="University or provider" value={q} onChange={e => setQ(e.target.value)} /></div>
      <div className="ui-field"><label htmlFor="uipc">Country</label><select id="uipc" className="ui-input" value={country} onChange={e => setCountry(e.target.value)}><option value="">All countries</option>{countries.map(c => <option key={c.code} value={c.code}>{c.name || countryName(lk, c.code)}</option>)}</select></div>
    </section>
    <section className="ui-gridwrap">
      <div className="ui-grid-caption"><span><strong>{page.total.toLocaleString('en-AU')}</strong> providers{busy ? ' · loading…' : ''}</span></div>
      {err && <div className="ui-alert" role="alert">{err}</div>}
      <table className="ui-grid" data-no-resize><thead><tr><th>Provider</th><th>Country</th><th>City</th><th className="ui-num">Courses</th><th>Study Square</th></tr></thead>
        <tbody>{page.items.length ? page.items.map(p => <tr key={p.id} onClick={() => setPick(p)}>
          <td data-primary><div className="ui-cell-title"><button type="button" className="ui-btn ui-btn-sm" onClick={() => setPick(p)}>{p.display_name || p.canonical_name}</button></div></td>
          <td data-label="Country">{p.country_name || countryName(lk, p.country_code)}</td><td data-label="City">{humanise(p.city?.toLowerCase())}</td>
          <td data-label="Courses" className="ui-num">{Number(p.course_count || 0).toLocaleString('en-AU')}</td>
          <td data-label="Study Square"><RepBadge rep={reps.get(p.id) || p.provider_representation} /></td></tr>)
          : <tr><td data-primary><div className="ui-emptystate"><p className="ui-emptystate-title">{busy ? 'Loading providers…' : 'No providers match these filters'}</p></div></td></tr>}</tbody></table>
      <div className="ui-filter-actions"><button type="button" className="ui-btn" disabled={offset <= 0 || busy} onClick={() => setOffset(Math.max(0, offset - page.limit))}>Previous</button><button type="button" className="ui-btn" disabled={offset + page.limit >= page.total || busy} onClick={() => setOffset(offset + page.limit)}>Next</button></div>
    </section>
    {pick && <ProviderDrawer p={pick} rep={reps.get(pick.id) || pick.provider_representation} onClose={() => setPick(null)} />}
  </>
}

function ProviderDrawer({ p, rep, onClose }) {
  const lk = useLookups()
  const [d, setD] = useState(null), [tab, setTab] = useState('overview'), [err, setErr] = useState('')
  useEffect(() => { let on = true; api.providerDetail(p.id).then(x => on && setD(x || {})).catch(() => on && setErr('Provider details could not be loaded.')); return () => { on = false } }, [p.id])
  const [pc, setPc] = useState(null), [pcErr, setPcErr] = useState('')
  useEffect(() => { if (tab !== 'contacts' || pc) return; let on = true; supabase.rpc('provider_partner_contacts_v1', { p_provider_id: p.id, p_status: 'active' }).then(({ data, error }) => { if (!on) return; if (error) setPcErr('Partner contacts could not be loaded.'); else setPc(data || {}) }); return () => { on = false } }, [tab, p.id])
  const camps = d?.campuses_page?.items || d?.campuses_page?.rows || []
  const points = d?.international_contacts?.items || (Array.isArray(d?.international_contacts) ? d.international_contacts : [])
  return <><div className="ui-backdrop" onClick={onClose} /><aside className="ui-drawer" role="dialog" aria-label={p.display_name || p.canonical_name}>
    <div className="ui-drawer-head"><div><h2>{p.display_name || p.canonical_name}</h2><div className="ui-page-sub"><RepBadge rep={rep} /></div></div><button type="button" className="ui-btn ui-btn-sm ui-close" onClick={onClose}>Close</button></div>
    <div className="ui-tabs" role="tablist">{[['overview', 'Overview'], ['contacts', 'Contacts']].map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={tab === k} onClick={() => setTab(k)}>{l}</button>)}</div>
    <div className="ui-drawer-body">{err && <div className="ui-alert" role="alert">{err}</div>}{!d && !err && <p className="ui-note">Loading…</p>}
      {d && tab === 'overview' && <dl className="ui-kv"><dt>Country</dt><dd>{p.country_name || p.country_code}</dd>
        <dt>Market restriction</dt><dd data-restriction>{(rep?.restriction_mode === 'include' || rep?.restriction_mode === 'exclude') && rep.restriction_markets?.length ? `${rep.restriction_mode === 'include' ? 'Only these markets' : 'All markets except'}: ${rep.restriction_markets.map(c => countryName(lk, c) || c).join(', ')}` : rep ? 'No restriction recorded' : 'Not recorded'}{rep?.effective_to ? ` · agreement to ${fdate(rep.effective_to)}` : ''}</dd>
        <dt>Study Square</dt><dd>{rep ? <RepBadge rep={rep} /> : 'Not recorded by Study Square'}</dd>
        <dt>Courses</dt><dd>{Number(d.course_count ?? p.course_count ?? 0).toLocaleString('en-AU')}</dd><dt>Scholarships</dt><dd>{Number(d.scholarship_count ?? 0).toLocaleString('en-AU')}</dd>
        <dt>Campuses</dt><dd>{camps.length ? <Locs max={99} cities={camps.map(c => ({ subdivision_code: c.subdivision_code, subdivision_name: c.subdivision_name, city: c.city || c.locality, campus: c.campus_name || c.name }))} /> : '—'}</dd>
        {(d.website || p.website) && <><dt>Website</dt><dd><a href={d.website || p.website} target="_blank" rel="noreferrer">Provider website</a></dd></>}</dl>}
      {d && tab === 'contacts' && <>
        <section className="ui-section-head"><h3>Study Square partner contacts</h3></section>
        {pcErr && <div className="ui-alert" role="alert">{pcErr}</div>}{!pc && !pcErr && <p className="ui-note">Loading…</p>}
        {pc && (pc.rows || []).length > 0 && <ul className="ui-list" data-partner-contacts>{pc.rows.map(c => <li key={c.contact_id}><strong>{c.full_name || c.team_name || c.job_title || 'Contact'}</strong>{[c.job_title, c.functional_area, c.region_scope, c.countries_or_markets].filter(Boolean).map(x => ' · ' + x).join('')}<br />{[c.work_email, c.work_phone, c.staff_location].filter(Boolean).join(' · ') || 'No contact details recorded'}{c.verified_on ? ' · verified ' + fdate(c.verified_on) : ''}</li>)}</ul>}
        {pc && (pc.rows || []).length === 0 && <div className="ui-emptystate"><p className="ui-emptystate-title">No partner contacts recorded for this provider</p><p className="ui-note">Partner contacts come from Study Square's own partner records.{pc.inactive_count > 0 ? ` ${pc.inactive_count} inactive contact${pc.inactive_count === 1 ? ' is' : 's are'} held.` : ' None are held for this provider yet.'}</p></div>}
        {points.length > 0 && <><section className="ui-section-head"><h3>Public contact points</h3></section><ul className="ui-list">{points.map((c, i) => <li key={i}>{[c.role || c.label || c.kind, c.value || c.email || c.phone].filter(Boolean).join(' · ')}</li>)}</ul></>}</>}
    </div></aside></>
}
