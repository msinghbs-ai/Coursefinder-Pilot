// CF-247 s1044 (Platform Admin brief 24 Nov 2026 15:11; backend s1025): the Counsellor's in-app Report an issue (from the course drawer) and My reports.
// Reads and writes only the two Counsellor RPCs (public.counsellor_feedback_list_v1 / counsellor_feedback_submit_v1, rank 2 sees and sends their own).
// The issue categories come from the database (list.categories); no list is written here. Zoho counsellor reports are a separate channel and untouched.
import { useEffect, useState } from 'react'
import './tokens.css'
import './ui-kit.css'
import { supabase } from '../lib/supabase.js'
import { fdate, humanise } from './format.js'

const list = async args => { const { data, error } = await supabase.rpc('counsellor_feedback_list_v1', { p_args: args || {} }); if (error) throw new Error(error.message); return data || {} }
const STATUS = { open: ['Open', 'warning'], fixed: ['Fixed', 'success'], not_changed: ['Not changed', 'neutral'] }
const httpsOnly = u => (/^https:\/\/[^\s/]+/i.test(String(u || '')) ? String(u) : '')

/** The Report an issue form of one course: categories, a note, the campus and the source page; sends what the screen showed. */
export function ReportIssue({ row, detail, snapshot, onClose }) {
  const [cats, setCats] = useState(null), [pick, setPick] = useState([]), [notes, setNotes] = useState(''), [campus, setCampus] = useState('')
  const [url, setUrl] = useState(httpsOnly(detail?.course_url)), [busy, setBusy] = useState(false), [err, setErr] = useState(''), [done, setDone] = useState(false)
  useEffect(() => { let on = true; list({ scope: 'mine', limit: 1 }).then(d => on && setCats(d.categories || [])).catch(e => on && (setErr(e.message), setCats([]))); return () => { on = false } }, [])
  const campuses = (detail?.campuses || []).filter(c => c.id)
  const send = async () => {
    setBusy(true); setErr('')
    try {
      const { data, error } = await supabase.rpc('counsellor_feedback_submit_v1', { p_args: { course_id: row.id, campus_id: campus || undefined, issue_categories: pick, notes: notes.trim() || undefined, source_url: url.trim() || undefined, displayed_snapshot: snapshot || undefined } })
      if (error) throw new Error(error.message)
      if (!data?.ok) throw new Error('The report was not saved.')
      setDone(true)
    } catch (e) { setErr(String(e.message || e).replace(/^INVALID_INPUT: |^LIMIT: /, '')) } finally { setBusy(false) }
  }
  const title = row.display_title || row.canonical_title
  return <><div className="ui-backdrop" onClick={onClose} /><div className="ui-modal" role="dialog" aria-label="Report a data issue" data-report-issue>
    <h2>Report a data issue</h2><div className="ui-page-sub">{title} · {row.provider_name}</div>
    {done ? <><p className="ui-note" role="status" data-report-done>Thank you. Your report is with the data team. You can follow it under My reports.</p><div className="ui-modal-foot"><a className="ui-btn" href="#ui-v1/reports" onClick={onClose}>Open My reports</a><button type="button" className="ui-btn ui-btn-primary" onClick={onClose}>Close</button></div></> : <>
      {err && <div className="ui-alert" role="alert">{err}</div>}
      <fieldset className="ui-field" data-report-categories><legend className="ui-note">What looks wrong? (choose at least one)</legend>
        {cats === null ? <p className="ui-note">Loading…</p> : cats.map(c => <label key={c.key} className="ui-check"><input type="checkbox" checked={pick.includes(c.key)} onChange={() => setPick(p => p.includes(c.key) ? p.filter(x => x !== c.key) : [...p, c.key])} /> {c.label}</label>)}</fieldset>
      <div className="ui-field"><label htmlFor="rp-note">Note</label><textarea id="rp-note" className="ui-input" rows={3} maxLength={2000} value={notes} onChange={e => setNotes(e.target.value)} placeholder="What did you expect to see?" /></div>
      {campuses.length > 0 && <div className="ui-field"><label htmlFor="rp-campus">Campus (optional)</label><select id="rp-campus" className="ui-input" value={campus} onChange={e => setCampus(e.target.value)}><option value="">Not about one campus</option>{campuses.map(c => <option key={c.id} value={c.id}>{c.campus_name || c.name}</option>)}</select></div>}
      <div className="ui-field"><label htmlFor="rp-url">Source page (optional, https)</label><input id="rp-url" className="ui-input" value={url} onChange={e => setUrl(e.target.value)} placeholder="https://" /></div>
      <p className="ui-note">What this screen showed is sent with the report, so the team can see what you saw.</p>
      <div className="ui-modal-foot"><button type="button" className="ui-btn" onClick={onClose}>Cancel</button><button type="button" className="ui-btn ui-btn-primary" disabled={busy || !pick.length} onClick={send} data-report-send>{busy ? 'Sending…' : 'Send report'}</button></div></>}
  </div></>
}

/** My reports: the Counsellor's own reports, newest first, with the Curator's closing note. */
export default function MyReportsView() {
  const [status, setStatus] = useState(''), [d, setD] = useState(null), [err, setErr] = useState('')
  useEffect(() => { let on = true; setD(null); setErr(''); list({ scope: 'mine', status: status || undefined, limit: 100 }).then(x => on && setD(x)).catch(e => on && setErr(e.message)); return () => { on = false } }, [status])
  const catName = k => (d?.categories || []).find(c => c.key === k)?.label || humanise(k)
  return <div data-my-reports>
    <section className="ui-section-head"><div><h1>My reports</h1><div className="ui-page-sub">Data issues you have reported, and what the data team did about each.</div></div></section>
    <div className="ui-pillbar" role="group" aria-label="Status">{[['', 'All'], ['open', 'Open'], ['fixed', 'Fixed'], ['not_changed', 'Not changed']].map(([k, l]) => <button key={k} type="button" className="ui-btn ui-btn-sm" aria-pressed={status === k} data-report-filter={k} onClick={() => setStatus(k)}>{l}</button>)}</div>
    {err && <div className="ui-alert" role="alert">{err}</div>}
    {!d && !err ? <p className="ui-note">Loading…</p> : d && !(d.items || []).length ? <div className="ui-emptystate"><p className="ui-emptystate-title">No reports yet</p><p className="ui-note">Open a course and choose Report a data issue.</p></div>
      : <ul className="ui-list" data-report-list>{(d?.items || []).map(r => { const [lab, tone] = STATUS[r.status] || [humanise(r.status), 'neutral']; return <li key={r.id} data-report={r.id}>
        <div><strong>{r.course || 'Course'}</strong> · {r.provider || ''} <span className="ui-badge" data-tone={tone}>{lab}</span></div>
        <div className="ui-note">{(r.issue_categories || []).map(catName).join(', ')} · sent {fdate(r.created_at)}</div>
        {r.notes && <div>{r.notes}</div>}
        {r.triage_note && <div className="ui-note" data-report-triage>Data team: {r.triage_note}{r.triaged_at ? ` (${fdate(r.triaged_at)})` : ''}</div>}</li> })}</ul>}
  </div>
}
