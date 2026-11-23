// v1.1 Counsellor UI, Scholarships (screen 4). One read: public.counsellor_scholarships_list (s990). The Open / Closed / Opens status is worked out
// in the database on the Australia/Melbourne date; this screen never decides it from the browser clock.
import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { fdate, humanise } from './format.js'

const TONE = { Open: 'success', Closed: 'neutral', Opens: 'info', 'Dates not published': 'muted' }
const STATUSES = ['Open', 'Opens', 'Closed', 'Dates not published']

export default function ScholarshipsView() {
  const [q, setQ] = useState(''), [status, setStatus] = useState(''), [offset, setOffset] = useState(0)
  const [d, setD] = useState({ rows: [], total: 0, page_rows: 50, status_counts: {} }), [err, setErr] = useState(''), [busy, setBusy] = useState(false), [pick, setPick] = useState(null)
  useEffect(() => { setOffset(0) }, [q, status])
  useEffect(() => {
    let on = true
    const t = setTimeout(() => {
      setBusy(true); setErr('')
      supabase.rpc('counsellor_scholarships_list', { p_args: { q: q.trim() || null, status: status || null, offset } })
        .then(({ data, error }) => { if (error) throw error; if (on) setD(data || { rows: [], total: 0, page_rows: 50, status_counts: {} }) })
        .catch(() => on && setErr('Scholarships could not be loaded. Try again in a moment.'))
        .finally(() => on && setBusy(false))
    }, q ? 300 : 0)
    return () => { on = false; clearTimeout(t) }
  }, [q, status, offset])
  const hasPrev = offset > 0, hasNext = offset + d.page_rows < d.total
  return <>
    <div className="ui-page-head"><h1 className="ui-page-title">Scholarships</h1><span className="ui-page-sub">Published scholarships, with whether applications are open today (Melbourne time).</span></div>
    <section className="ui-filterbar" aria-label="Scholarship filters">
      <div className="ui-field ui-field-wide"><label htmlFor="uisq">Search</label><input id="uisq" className="ui-input" placeholder="Scholarship or provider" value={q} onChange={e => setQ(e.target.value)} /></div>
      <div className="ui-field"><label htmlFor="uiss">Application status</label><select id="uiss" className="ui-input" value={status} onChange={e => setStatus(e.target.value)}><option value="">Any status</option>{STATUSES.map(s => <option key={s} value={s}>{s === 'Opens' ? 'Opens later' : s}{d.status_counts?.[s] != null ? ` (${d.status_counts[s]})` : ''}</option>)}</select></div>
    </section>
    <section className="ui-gridwrap">
      <div className="ui-grid-caption"><span><strong>{Number(d.total || 0).toLocaleString('en-AU')}</strong> scholarships{busy ? ' · loading…' : ''}</span></div>
      {err && <div className="ui-alert" role="alert">{err}</div>}
      <table className="ui-grid" data-no-resize><thead><tr><th>Scholarship</th><th>Provider</th><th>Value</th><th>Applications</th><th>Status</th></tr></thead>
        <tbody>{d.rows.length ? d.rows.map(r => <tr key={r.id} onClick={() => setPick(r)}>
          <td data-primary><div className="ui-cell-title"><button type="button" className="ui-btn ui-btn-sm" onClick={() => setPick(r)}>{r.name}</button></div><div className="ui-cell-sub">{humanise(r.type)}</div></td>
          <td data-label="Provider">{r.provider_name || '—'}</td>
          <td data-label="Value">{r.value_text || 'Not stated'}</td>
          <td data-label="Applications">{r.open_date || r.close_date ? `${fdate(r.open_date) || '—'} to ${fdate(r.close_date) || '—'}` : 'Dates not published'}</td>
          <td data-label="Status"><span className="ui-badge" data-tone={TONE[r.status_key] || 'neutral'}>{r.status}</span></td></tr>)
          : <tr><td data-primary><div className="ui-emptystate"><p className="ui-emptystate-title">{busy ? 'Loading scholarships…' : 'No scholarships match these filters'}</p></div></td></tr>}</tbody></table>
      <div className="ui-filter-actions"><button type="button" className="ui-btn" disabled={!hasPrev || busy} onClick={() => setOffset(Math.max(0, offset - d.page_rows))}>Previous</button><button type="button" className="ui-btn" disabled={!hasNext || busy} onClick={() => setOffset(offset + d.page_rows)}>Next</button></div>
    </section>
    {pick && <><div className="ui-backdrop" onClick={() => setPick(null)} /><aside className="ui-drawer" role="dialog" aria-label={pick.name}>
      <div className="ui-drawer-head"><div><h2>{pick.name}</h2><div className="ui-page-sub">{pick.provider_name}</div></div><button type="button" className="ui-btn ui-btn-sm ui-close" onClick={() => setPick(null)}>Close</button></div>
      <div className="ui-drawer-body"><dl className="ui-kv">
        <dt>Status</dt><dd><span className="ui-badge" data-tone={TONE[pick.status_key] || 'neutral'}>{pick.status}</span></dd>
        <dt>Value</dt><dd>{pick.value_text || 'Not stated'}</dd>
        <dt>Who can apply</dt><dd>{humanise(pick.audience)}{pick.nationalities?.length ? ' · ' + pick.nationalities.join(', ') : ''}</dd>
        <dt>Application</dt><dd>{pick.application_required === false ? 'No separate application' : pick.application_required ? 'Application required' : 'Not stated'}</dd>
        <dt>Opens</dt><dd>{fdate(pick.open_date) || 'Not published'}</dd><dt>Closes</dt><dd>{fdate(pick.close_date) || 'Not published'}</dd>
        {pick.source_url && <><dt>Source</dt><dd><a href={pick.source_url} target="_blank" rel="noreferrer">Provider page</a></dd></>}
      </dl></div></aside></>}
  </>
}
