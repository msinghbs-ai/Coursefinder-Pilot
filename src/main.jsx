import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import {
  Activity, Attribute, BookOpen, Boxes, Building2, ChevronRight, CircleGauge,
  Database, GraduationCap, LayoutDashboard, ListChecks, LogOut, MapPin,
  RefreshCw, Search, Settings2, Sparkles, Tags, Workflow, X
} from 'lucide-react'
import { api, supabase } from './lib/supabase'
import './styles.css'

const nav = [
  ['Overview', [
    ['Dashboard', LayoutDashboard],
  ]],
  ['Catalogue', [
    ['Providers', Building2],
    ['Campuses', MapPin],
    ['Course Collections', Boxes],
    ['Courses', GraduationCap],
    ['Scholarships', Sparkles],
    ['Categories', Tags],
  ]],
  ['PIM Model', [
    ['Attributes', Attribute],
  ]],
  ['Data Quality', [
    ['Completeness', CircleGauge],
    ['Review Queue', ListChecks],
  ]],
  ['Enrichment', [
    ['Pipeline', Workflow],
    ['Jobs', Activity],
  ]],
  ['Administration', [
    ['Integrations', Database],
    ['Settings', Settings2],
  ]],
]

function App() {
  const [session, setSession] = useState(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [page, setPage] = useState('Dashboard')
  const [context, setContext] = useState(null)
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session ?? null)
      setLoadingSession(false)
    })
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) {
      setContext(null)
      return
    }
    api.context().then(setContext).catch(e => setError(e.message))
  }, [session])

  if (loadingSession) return <div className="boot">Loading Coursefinder Pilot…</div>
  if (!session) return <Login error={error} onError={setError} />

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">CF</div>
          <div><strong>Coursefinder</strong><span>Pilot PIM</span></div>
        </div>
        <nav className="nav">
          {nav.map(([group, items]) => (
            <div className="nav-group" key={group}>
              <div className="nav-label">{group}</div>
              {items.map(([label, Icon]) => (
                <button key={label} className={page === label ? 'nav-item active' : 'nav-item'} onClick={() => setPage(label)}>
                  <Icon size={17} /><span>{label}</span>
                </button>
              ))}
            </div>
          ))}
        </nav>
        <div className="account-card">
          <div className="avatar">{(session.user.email?.[0] || 'U').toUpperCase()}</div>
          <div className="account-meta"><strong>{context?.role || 'Pilot user'}</strong><span>{session.user.email}</span></div>
          <button className="icon-button" title="Sign out" onClick={() => supabase.auth.signOut()}><LogOut size={17} /></button>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <div className="eyebrow">Mumbai Pilot · v2.9.1 contract</div>
            <h1>{page}</h1>
          </div>
          <div className="topbar-actions"><span className="status-pill"><i />Connected</span></div>
        </header>
        {error && <div className="alert"><span>{error}</span><button onClick={() => setError('')}><X size={16}/></button></div>}
        <Page page={page} onError={setError} />
      </main>
    </div>
  )
}

function Login({ error, onError }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    onError('')
    const { error: authError } = await supabase.auth.signInWithPassword({ email, password })
    if (authError) onError(authError.message)
    setBusy(false)
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand"><div className="brand-mark large">CF</div><div><h1>Coursefinder Pilot</h1><p>Catalogue · PIM · Enrichment</p></div></div>
        <div className="login-copy"><h2>Sign in</h2><p>Use a user created in the Mumbai Pilot Supabase Auth project.</p></div>
        {error && <div className="alert compact">{error}</div>}
        <form onSubmit={submit}>
          <label>Email<input type="email" value={email} onChange={e => setEmail(e.target.value)} required autoComplete="email" /></label>
          <label>Password<input type="password" value={password} onChange={e => setPassword(e.target.value)} required autoComplete="current-password" /></label>
          <button className="primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        </form>
      </div>
    </div>
  )
}

function Page({ page, onError }) {
  if (page === 'Dashboard') return <Dashboard onError={onError} />
  if (page === 'Providers') return <Providers onError={onError} />
  if (page === 'Courses') return <Courses onError={onError} />
  if (page === 'Scholarships') return <Scholarships onError={onError} />
  if (page === 'Attributes') return <Attributes onError={onError} />
  if (page === 'Completeness') return <Completeness onError={onError} />
  if (page === 'Review Queue') return <ReviewQueue onError={onError} />
  if (page === 'Pipeline') return <Pipeline onError={onError} />
  if (page === 'Jobs') return <Jobs onError={onError} />
  return <ComingSoon page={page} />
}

function Dashboard({ onError }) {
  const [data, setData] = useState(null)
  const [busy, setBusy] = useState(true)
  const load = () => {
    setBusy(true)
    api.dashboard().then(setData).catch(e => onError(e.message)).finally(() => setBusy(false))
  }
  useEffect(load, [])
  const stats = [
    ['Providers', data?.providers ?? '—', Building2],
    ['Courses', data?.courses ?? '—', GraduationCap],
    ['Search documents', data?.search_documents ?? '—', Search],
    ['Attributes', data?.attributes ?? '—', Attribute],
    ['Scholarships', data?.scholarships ?? '—', Sparkles],
    ['Open reviews', data?.open_reviews ?? '—', ListChecks],
    ['Jobs', data?.jobs ?? '—', Activity],
    ['Evidence', data?.evidence ?? '—', BookOpen],
  ]
  return (
    <div className="stack">
      <div className="section-head"><div><h2>Pilot operating snapshot</h2><p>Read-only view of the Mumbai pilot catalogue and processing state.</p></div><button className="secondary" onClick={load}><RefreshCw size={15} className={busy ? 'spin' : ''}/>Refresh</button></div>
      <div className="metric-grid">{stats.map(([label, value, Icon]) => <div className="metric-card" key={label}><div className="metric-icon"><Icon size={18}/></div><div><span>{label}</span><strong>{value}</strong></div></div>)}</div>
      <div className="grid-two">
        <section className="panel"><div className="panel-title"><div><span className="kicker">Environment</span><h3>Pilot foundation</h3></div></div><div className="fact-list"><Fact label="Region" value="Mumbai (ap-south-1)"/><Fact label="Search generation" value={data?.search_generation ?? '—'}/><Fact label="Access" value="Authenticated RPC bridge"/><Fact label="Mode" value="Read-only UI baseline"/></div></section>
        <section className="panel"><div className="panel-title"><div><span className="kicker">Build focus</span><h3>Next UI capabilities</h3></div></div><div className="roadmap-list"><Roadmap n="01" title="Catalogue workspace" text="Providers, courses, collections and academic options."/><Roadmap n="02" title="PIM configuration" text="Families, groups, attributes, options and categories."/><Roadmap n="03" title="Governance" text="Completeness, evidence and Layer 4 review actions."/></div></section>
      </div>
    </div>
  )
}

function Providers({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  useEffect(() => { api.providers().then(setRows).catch(e => onError(e.message)) }, [])
  const shown = useMemo(() => rows.filter(r => `${r.canonical_name} ${r.country_code} ${r.city || ''}`.toLowerCase().includes(q.toLowerCase())), [rows, q])
  return <TablePage title="Provider catalogue" subtitle="Canonical institutions with stable IDs and catalogue counts." q={q} setQ={setQ} count={shown.length} columns={['Provider','Country','City','Courses','Lifecycle','Publication']} rows={shown.map(r => [<CellTitle key="n" title={r.canonical_name} sub={r.stable_key}/>, r.country_code, r.city || '—', r.course_count ?? 0, <Badge key="l" text={r.lifecycle_status}/>, <Badge key="p" text={r.publication_status}/>])}/>
}

function Courses({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  useEffect(() => { api.courses().then(setRows).catch(e => onError(e.message)) }, [])
  const shown = useMemo(() => rows.filter(r => `${r.canonical_title} ${r.provider_name} ${r.level_code || ''} ${r.field_of_study || ''}`.toLowerCase().includes(q.toLowerCase())), [rows, q])
  return <TablePage title="Course workspace" subtitle="PIM-style catalogue list. Editing and bulk actions will be added after read UAT." q={q} setQ={setQ} count={shown.length} columns={['Course','Provider','Level','Field','Delivery','Completeness','Publication']} rows={shown.map(r => [<CellTitle key="n" title={r.canonical_title} sub={r.stable_key}/>, r.provider_name, r.level_code || '—', r.field_of_study || '—', r.delivery_mode || '—', <Score key="s" value={r.completeness_score}/>, <Badge key="p" text={r.publication_status}/>])}/>
}

function Scholarships({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  useEffect(() => { api.scholarships().then(setRows).catch(e => onError(e.message)) }, [])
  const shown = useMemo(() => rows.filter(r => `${r.name} ${r.provider_name || ''}`.toLowerCase().includes(q.toLowerCase())), [rows, q])
  return <TablePage title="Scholarships" subtitle="Scholarship catalogue and scope model." q={q} setQ={setQ} count={shown.length} columns={['Scholarship','Provider','Year','Audience','Type','Award','Publication']} rows={shown.map(r => [<CellTitle key="n" title={r.name} sub={r.stable_key}/>, r.provider_name || '—', r.academic_year || '—', r.audience || '—', r.scholarship_type || '—', r.award_value_text || '—', <Badge key="p" text={r.publication_status}/>])}/>
}

function Attributes({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  useEffect(() => { api.attributes().then(setRows).catch(e => onError(e.message)) }, [])
  const shown = useMemo(() => rows.filter(r => `${r.name} ${r.code} ${r.group_name || ''}`.toLowerCase().includes(q.toLowerCase())), [rows, q])
  return <TablePage title="Attribute definitions" subtitle="Global PIM definitions; family/group editing follows after read UAT." q={q} setQ={setQ} count={shown.length} columns={['Attribute','Entity','Group','Type','Filter','Search','Vector','Status']} rows={shown.map(r => [<CellTitle key="n" title={r.name} sub={r.code}/>, r.entity_type, r.group_name || '—', r.data_type, yn(r.is_filterable), yn(r.is_searchable), yn(r.include_in_vector), <Badge key="s" text={r.status}/>])}/>
}

function Completeness({ onError }) {
  const [rows, setRows] = useState([])
  useEffect(() => { api.courses(1000).then(setRows).catch(e => onError(e.message)) }, [])
  const sorted = [...rows].sort((a,b) => (a.completeness_score ?? 0) - (b.completeness_score ?? 0))
  const avg = rows.length ? Math.round(rows.reduce((s,r) => s + Number(r.completeness_score || 0), 0) / rows.length) : 0
  return <div className="stack"><div className="metric-grid compact-grid"><MiniMetric label="Average completeness" value={`${avg}%`}/><MiniMetric label="Has fee" value={rows.filter(r=>r.has_fee).length}/><MiniMetric label="Has intake" value={rows.filter(r=>r.has_intake).length}/><MiniMetric label="Has English" value={rows.filter(r=>r.has_english).length}/></div><TablePage embedded title="Lowest completeness" subtitle="Current pilot course population ordered by completeness score." count={sorted.length} columns={['Course','Provider','Level','Fee','Intake','English','Score']} rows={sorted.map(r => [r.canonical_title, r.provider_name, r.level_code || '—', yn(r.has_fee), yn(r.has_intake), yn(r.has_english), <Score key="s" value={r.completeness_score}/>])}/></div>
}

function ReviewQueue({ onError }) {
  const [rows, setRows] = useState([])
  useEffect(() => { api.reviews().then(setRows).catch(e => onError(e.message)) }, [])
  return <TablePage title="Layer 4 review queue" subtitle="Decision workspace will be enabled when role-checked write APIs are promoted." count={rows.length} columns={['Created','Domain','Field','Priority','Status','Reopened']} rows={rows.map(r => [date(r.created_at), r.domain, r.field_code || '—', r.priority ?? '—', <Badge key="s" text={r.status}/>, r.reopen_reason || '—'])}/>
}

function Pipeline({ onError }) {
  const [jobs, setJobs] = useState([])
  useEffect(() => { api.jobs().then(setJobs).catch(e => onError(e.message)) }, [])
  const groups = ['regulatory','acquisition','enrichment','review'].map(domain => ({ domain, count: jobs.filter(j => j.domain === domain).length }))
  return <div className="stack"><div className="layer-grid">{groups.map((g,i) => <div className="layer-card" key={g.domain}><span>Layer {i+1}</span><strong>{title(g.domain)}</strong><p>{layerText(i+1)}</p><b>{g.count} jobs</b></div>)}</div><section className="panel"><div className="panel-title"><div><span className="kicker">Flow</span><h3>Canonical enrichment path</h3></div></div><div className="pipeline-flow"><Flow label="Layer 1" text="Regulatory truth"/><ChevronRight/><Flow label="Layer 2" text="Evidence acquisition"/><ChevronRight/><Flow label="Layer 3" text="LLM normalisation"/><ChevronRight/><Flow label="Layer 4" text="Human review"/></div></section></div>
}

function Jobs({ onError }) {
  const [rows, setRows] = useState([])
  useEffect(() => { api.jobs().then(setRows).catch(e => onError(e.message)) }, [])
  return <TablePage title="Pipeline jobs" subtitle="Operational execution history." count={rows.length} columns={['Created','Domain','Job','Status','Attempts','Duration','Error']} rows={rows.map(r => [date(r.created_at), r.domain, r.job_type, <Badge key="s" text={r.status}/>, r.attempt_count ?? 0, duration(r.started_at,r.completed_at), r.error_text || '—'])}/>
}

function ComingSoon({ page }) {
  return <section className="empty-state"><div className="empty-icon"><Boxes size={24}/></div><span className="kicker">UI contract next</span><h2>{page}</h2><p>The database model exists, but this screen will use a dedicated v2.9.1 API contract rather than direct internal-schema access.</p></section>
}

function TablePage({ title, subtitle, q, setQ, count, columns, rows, embedded=false }) {
  return <section className={embedded ? 'panel' : 'panel full'}><div className="panel-title table-title"><div><span className="kicker">{count} records</span><h2>{title}</h2><p>{subtitle}</p></div>{setQ && <div className="searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search…"/></div>}</div><div className="table-wrap"><table><thead><tr>{columns.map(c=><th key={c}>{c}</th>)}</tr></thead><tbody>{rows.length ? rows.map((cells,i)=><tr key={i}>{cells.map((cell,j)=><td key={j}>{cell}</td>)}</tr>) : <tr><td colSpan={columns.length}><div className="table-empty">No records returned.</div></td></tr>}</tbody></table></div></section>
}

function CellTitle({ title, sub }) { return <div className="cell-title"><strong>{title}</strong><span>{sub}</span></div> }
function Badge({ text='unknown' }) { const v=String(text || 'unknown'); return <span className={`badge badge-${v.toLowerCase().replace(/[^a-z0-9]+/g,'-')}`}>{v.replaceAll('_',' ')}</span> }
function Score({ value=0 }) { const n=Math.round(Number(value || 0)); return <div className="score"><span><i style={{width:`${Math.max(0,Math.min(100,n))}%`}}/></span><b>{n}%</b></div> }
function Fact({ label, value }) { return <div><span>{label}</span><strong>{value}</strong></div> }
function Roadmap({ n, title, text }) { return <div><b>{n}</b><div><strong>{title}</strong><span>{text}</span></div></div> }
function MiniMetric({ label, value }) { return <div className="metric-card mini"><span>{label}</span><strong>{value}</strong></div> }
function Flow({ label, text }) { return <div><span>{label}</span><strong>{text}</strong></div> }
function yn(v) { return <span className={v ? 'yes' : 'no'}>{v ? 'Yes' : 'No'}</span> }
function title(v='') { return v.charAt(0).toUpperCase()+v.slice(1) }
function date(v) { return v ? new Date(v).toLocaleString() : '—' }
function duration(a,b) { if(!a || !b) return '—'; const ms=new Date(b)-new Date(a); return ms<1000?`${ms} ms`:`${(ms/1000).toFixed(1)} s` }
function layerText(n) { return ({1:'Regulatory identity and authoritative source ingestion.',2:'Deterministic discovery, scraping and evidence capture.',3:'Model-assisted extraction and structured normalisation.',4:'Auditable review, correction and publication governance.'})[n] }

createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>)
