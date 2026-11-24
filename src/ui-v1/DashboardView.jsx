// v1.1 Dashboard (v1.2 plan, Slice 3; Platform Admin brief 24 Nov 2026 15:11). One Dashboard drawn for the signed-in role: the role line with its
// guide, then (Curator and above) the stored ops pulse as five KPI cards plus the active automations, Active failures (operators and above), and
// Continue where you left off. A Viewer or Counsellor (rank 1-2) starts with Search the catalogue and makes no pipeline read at all.
// Reads: admin_read 'platform_health' (the stored pulse) and, for operators, public.admin_automations_read() for the running-automation count
// (nothing is typed into this screen). Only the two ui-v1 stylesheets are imported.
import './tokens.css'
import './ui-kit.css'
import { useEffect, useState } from 'react'
import { Activity, ArrowRight, BookOpen, Building2, ClipboardCheck, Clock3, Gauge, GraduationCap, Inbox, OctagonAlert, Search, ShieldCheck, Sparkles, Timer, Wallet, XCircle } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { readPlatformHealth } from '../lib/health-read'
import { guideForRank } from '../guide/roleGuides'
import { pulseOf, withBudgetCap, kpiCards } from '../lib/ops-pulse.js'
import { dashboardFailures } from '../health-exec.js'
import { clearRecent, readRecent, resumeRecent, rememberCourseSearch } from '../lib/recent-activity'
import { fmtDateTime, fmtNumber } from '../lib/format.js'

const ICONS = { Activity, Gauge, Inbox, OctagonAlert, Wallet, Timer }
const TONE = { ok: 'success', warn: 'warning', crit: 'danger', info: 'neutral', unknown: 'neutral' }
const Meter = ({ pct, label }) => <span className="ui-meter" role="img" aria-label={label || (pct == null ? 'Not measured' : `${pct}%`)}><i style={{ width: `${pct == null ? 0 : Math.max(2, pct)}%` }} /></span>

function KpiCard({ k }) {
  const I = ICONS[k.icon] || Activity
  return <div className="ui-kpi" data-tone={TONE[k.tone] || 'neutral'} data-kpi={k.key}>
    <span className="ui-kpi-badge"><I size={18} aria-hidden="true" /></span>
    <div className="ui-kpi-body"><small>{k.label}</small>
      {k.bars ? <ul className="ui-kpi-bars" data-kpi-bars>{k.bars.map(b => <li key={b.cc} data-country-bar={b.cc}><span className="ui-kpi-cc" title={b.label}>{b.cc}</span><Meter pct={b.pct == null ? null : Math.round(b.pct)} label={`${b.label}: ${b.text}`} /><b>{b.text}</b></li>)}</ul>
        : <b className="ui-kpi-value">{k.value}</b>}
      {k.meterPct != null && <Meter pct={k.meterPct} label={`${k.meterPct}% of the daily cap`} />}
      {k.detail && <small>{k.detail}</small>}</div>
  </div>
}

// The running count of the scheduled automations (the catalogue's active, not retired, jobs): operators only; a refused read leaves the card out
function useAutomationCount(enabled) {
  const [n, setN] = useState(null)
  useEffect(() => {
    if (!enabled) return undefined
    let live = true
    supabase.rpc('admin_automations_read').then(({ data, error }) => {
      if (!live || error || !Array.isArray(data?.jobs)) return
      const jobs = data.jobs.filter(j => !j.retirement)
      setN({ running: jobs.filter(j => j.active).length, paused: jobs.filter(j => !j.active).length })
    }).catch(() => {})
    return () => { live = false }
  }, [enabled])
  return n
}

function DashboardPulse({ rank }) {
  const [h, setH] = useState(undefined), auto = useAutomationCount(rank >= 4)
  useEffect(() => { let live = true; readPlatformHealth().then(x => { if (live) setH(x || null) }); return () => { live = false } }, [])
  if (h === undefined) return <section className="ui-section" data-db-pulse="loading"><p className="ui-muted">Reading the stored figures…</p></section>
  const p = withBudgetCap(pulseOf(h), h)
  if (!p) return null
  const cards = kpiCards(p)
  if (auto) cards.push({ key: 'automations', icon: 'Timer', label: 'Automations running', tone: auto.paused ? 'warn' : 'ok', value: fmtNumber(auto.running), detail: auto.paused ? `${fmtNumber(auto.paused)} paused` : 'none paused' })
  return <>
    <section className="ui-section" data-db-pulse><div className="ui-kpis" data-pulse-strip>{cards.map(k => <KpiCard key={k.key} k={k} />)}</div>
      {p.refreshed_at && <p className="ui-muted" data-pulse-stamp>Stored figures from {fmtDateTime(p.refreshed_at)} (rebuilt every 5 minutes){p.run_ms != null ? ` · build ${fmtNumber(p.run_ms)} ms` : ''}</p>}</section>
    {rank >= 4 && <DashboardFailures health={h} />}</>
}

const FAIL_SHOWN = 6
function DashboardFailures({ health }) {
  const rows = dashboardFailures(health)
  return <section className="ui-section" data-db-failures={rows.length}>
    <h2 className="ui-section-title">Active failures</h2>
    <p className="ui-muted">{rows.length ? 'Failures and warnings that need a person, worst first, with the screen to fix each.' : 'Nothing is failing.'}</p>
    {rows.length ? <ul className="ui-list ui-fails">{rows.slice(0, FAIL_SHOWN).map(r => <li key={r.key} data-db-failure={r.kind}>
      <span className="ui-badge" data-tone={r.tone === 'critical' ? 'danger' : 'warning'}><XCircle size={14} aria-hidden="true" />{r.tone === 'critical' ? 'Critical' : 'Warning'}</span>
      <span className="ui-fail-label"><b>{r.title}</b>{r.why && <small>{r.why}</small>}</span>
      <a className="ui-btn ui-btn-sm" href={r.href}>Open<ArrowRight size={13} /></a></li>)}</ul>
      : <p className="ui-muted" data-db-failures-none>No failure or warning needs a person.</p>}
    {rows.length > FAIL_SHOWN && <p className="ui-muted"><a href="#platform-health" data-db-failures-more>{rows.length - FAIL_SHOWN} more on Platform Health</a></p>}
  </section>
}

const RECENT_SHOWN = 3
const ROLE_ICON = r => r <= 2 ? Search : r === 3 ? ClipboardCheck : ShieldCheck
function RoleLine({ rank, navigate }) {
  const g = guideForRank(rank), RoleIcon = ROLE_ICON(Number(g.rank) || Number(rank) || 1)
  return <section className="ui-section ui-roleline" data-db-role={g.id}>
    <div><span className="ui-badge" data-tone="neutral"><RoleIcon size={14} aria-hidden="true" />{g.role} · rank {g.rank}</span><p className="ui-muted">{g.purpose}</p></div>
    <button type="button" className="ui-btn ui-btn-sm" onClick={() => navigate?.('guide', { tab: 'role-guides' })} data-db-role-guide><BookOpen size={14} />Your role guide</button></section>
}

function SearchStart({ actorId, navigate }) {
  const [q, setQ] = useState('')
  const go = e => { e.preventDefault(); rememberCourseSearch(actorId, q.trim()); navigate?.('courses') }
  return <section className="ui-section" data-db-search>
    <h2 className="ui-section-title">Search the catalogue</h2>
    <p className="ui-muted">Courses by title, field, city or provider. Every value shows where it came from.</p>
    <form className="ui-searchrow" onSubmit={go}><label className="ui-sr" htmlFor="db-search-q">Search courses</label>
      <input id="db-search-q" className="ui-input" value={q} onChange={e => setQ(e.target.value)} placeholder="For example: Master of Nursing Melbourne" data-db-search-q />
      <button type="submit" className="ui-btn ui-btn-primary" data-db-search-go><Search size={14} />Search courses</button></form>
    <div className="ui-starts">{[['courses', 'Courses', 'Fees, intakes, English and study load', GraduationCap], ['providers', 'Providers', 'Universities, TAFEs and colleges', Building2], ['scholarships', 'Scholarships', 'Open to international students', Sparkles]].map(([k, l, d, Icon]) =>
      <button type="button" key={k} className="ui-start" onClick={() => navigate?.(k)} data-db-start={k}><Icon size={16} /><span><strong>{l}</strong><small>{d}</small></span><ArrowRight size={13} /></button>)}</div>
  </section>
}

const KIND_LABEL = { search: 'Search', queue: 'Review queue', page: 'Page' }
function ContinueWhereLeft({ actorId }) {
  const [all, setItems] = useState(() => readRecent(actorId)), items = (all || []).slice(0, RECENT_SHOWN)
  useEffect(() => setItems(readRecent(actorId)), [actorId])
  return <section className="ui-section" data-db-recent>
    <h2 className="ui-section-title"><Clock3 size={14} aria-hidden="true" /> Continue where you left off</h2>
    <p className="ui-muted">Your 3 most recent searches, review queues and pages, kept on this browser only.</p>
    {items.length ? <><ul className="ui-list">{items.map(x => <li key={x.id} data-db-recent-item={x.kind}>
      <span className="ui-badge" data-tone="neutral">{KIND_LABEL[x.kind] || 'Page'}</span>
      <span className="ui-fail-label"><strong>{x.label}</strong>{x.detail && <small>{x.detail}</small>}</span>
      <small className="ui-muted">{x.at ? fmtDateTime(x.at) : ''}</small>
      <button type="button" className="ui-btn ui-btn-sm" onClick={() => resumeRecent(actorId, x)} aria-label={`Resume ${x.label}${x.detail ? ` ${x.detail}` : ''}`} data-db-recent-resume>Resume<ArrowRight size={13} /></button></li>)}</ul>
      <button type="button" className="ui-btn ui-btn-sm" onClick={() => { clearRecent(actorId); setItems([]) }} data-db-recent-clear>Clear</button></>
      : <p className="ui-muted" data-db-recent-empty>Nothing yet. Searches, review queues and pages you open will be listed here.</p>}
  </section>
}

export default function Dashboard({ onError, rank = 1, actorId = '', navigate }) {
  const r = Number(rank) || 1
  return <div className="ui-page" data-db-rank={r}>
    <RoleLine rank={r} navigate={navigate} />
    {r <= 2 && <SearchStart actorId={actorId} navigate={navigate} />}
    {r >= 3 && <DashboardPulse rank={r} />}
    <ContinueWhereLeft actorId={actorId} />
  </div>
}
