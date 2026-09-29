// Layer 3 AI validation (v2.15.107): one page, five tabs.
//   Routing           per task class: the model in use, its fallback, status, today's calls and spend
//   Models & profiles active / candidate / retired, each with its pinned model id, task classes and last test
//   Test results      benchmark runs: stated exact, wrong admitted, withheld, cost
//   Spend             per day and profile, against the configured ceilings
//   Work queue        the existing operator workspace (run form, source-pattern queue, history), unchanged
// Read: public.admin_layer3_operations (migration 20260930000000_cf247_admin_ui_reads). Retired is optional
// (retired_at or last_validation_result.retired); retired profiles are collapsed by default.
import React,{useEffect,useMemo,useState}from'react'
import{BrainCircuit,CircleDollarSign,FlaskConical,RefreshCw,Route}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDate,fmtDateTime,fmtMoney,fmtNumber,fmtPercent}from'./ui-kit'
import{Layer3 as Layer3Workspace}from'./m2-3-intelligence-entry'

const usd=v=>fmtMoney(Number(v||0),'USD',{decimals:4})
const task=v=>String(v||'').replaceAll('_',' ').replace(/^\w/,c=>c.toUpperCase())
export function profileState(p){if(p?.state)return p.state;const retired=Boolean(p?.retired_at||p?.last_validation_result?.retired||p?.is_retired);if(retired)return'retired';return p?.enabled&&!p?.paused&&p?.quality_benchmark?.pass?'active':'candidate'}
const STATE_TONE={active:'success',candidate:'info',retired:'neutral'}

export default function Layer3Operations({tab='routing',rank,onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[failed,setFailed]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_layer3_operations',{p_args:{days:14}});if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{if(tab!=='work')load()},[])
  useEffect(()=>{if(tab!=='work'&&!data&&!busy)load()},[tab])
  if(tab==='work')return <div className="m-page-stack"><Layer3Workspace rank={rank} hideHeader onError={e=>onError?.(e?.message||String(e))}/></div>
  if(busy&&!data)return <section className="m-panel"><Loading label="Loading Layer 3…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Layer 3 figures could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const refresh=<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</Button>
  if(tab==='models')return <Models profiles={data.profiles||[]} action={refresh}/>
  if(tab==='tests')return <Tests tests={data.tests||[]} action={refresh}/>
  if(tab==='spend')return <Spend spend={data.spend||[]} profiles={data.profiles||[]} days={data.days||14} action={refresh}/>
  return <Routing routing={data.routing||[]} generatedAt={data.generated_at} action={refresh}/>
}

function Routing({routing,generatedAt,action}){
  const active=routing.filter(r=>r.status==='active'),calls=routing.reduce((n,r)=>n+Number(r.calls_today||0),0),spend=routing.reduce((n,r)=>n+Number(r.spend_today_usd||0),0)
  return <>
    <div className="cf-metric-grid">
      <Metric label="Task classes with a model" value={`${fmtNumber(active.length)} of ${fmtNumber(routing.length)}`} icon={Route} tone={active.length?'success':'warning'}/>
      <Metric label="Model calls today" value={calls} icon={BrainCircuit}/>
      <Metric label="Spend today" value={usd(spend)} icon={CircleDollarSign}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Route} title="Routing" subtitle={`Which pinned model checks each kind of task. When no model has passed its tests, that work waits safely. Updated ${fmtDateTime(generatedAt)}.`} action={action}/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Task</th><th>Model in use</th><th>Fallback</th><th>Status</th><th className="num">Calls today</th><th className="num">Spend today</th><th className="num">Waiting</th><th className="num">Sent to Layer 4</th></tr></thead><tbody>
        {routing.length?routing.map(r=><tr key={r.task_class}>
          <td><strong>{task(r.task_class)}</strong><span className="l3v-code">{fmtNumber(r.candidates||0)} profile{Number(r.candidates)===1?'':'s'} set up</span></td>
          <td>{r.active_model?<><span className="l3v-model">{r.active_model}</span><span className="l3v-code">{r.active_code}</span></>:'—'}</td>
          <td>{r.fallback_model?<><span className="l3v-model">{r.fallback_model}</span><span className="l3v-code">{r.fallback_code}</span></>:'None'}</td>
          <td>{r.status==='active'?<StatusChip value="active" tone="success" label="Active"/>:<StatusChip value="paused" tone="warning" label="No tested model — waiting"/>}</td>
          <td className="num">{fmtNumber(r.calls_today||0)}{r.requests_per_day?<span className="l3v-code">of {fmtNumber(r.requests_per_day)} a day</span>:null}</td>
          <td className="num">{usd(r.spend_today_usd)}</td>
          <td className="num">{fmtNumber(r.open_items||0)}</td>
          <td className="num">{fmtNumber(r.layer4_items||0)}</td>
        </tr>):<tr><td colSpan={8} className="cf-empty-cell">No task classes are set up.</td></tr>}
      </tbody></table></div>
      <p className="l3v-note">Each task uses exactly one pinned model; there is no automatic switching between models. A model is used only after it passes its tests and an administrator activates it.</p>
    </section>
  </>
}

function ProfileCard({p}){
  const st=profileState(p),t=p.last_test
  return <article className={`l3v-card${st==='retired'?' is-retired':''}`}>
    <header><div><strong>{p.code}</strong><span className="l3v-model">{p.model_identifier}</span></div><StatusChip value={st} tone={STATE_TONE[st]} label={task(st)}/></header>
    <dl>
      <dt>Tasks</dt><dd>{(p.allowed_task_classes||[]).map(task).join(', ')||'—'}</dd>
      <dt>Last test</dt><dd>{t?<><StatusChip value={t.status} tone={t.status==='pass'?'success':'danger'} label={t.status==='pass'?'Passed':'Failed'}/> {fmtDate(t.at)}</>:'Not tested yet'}</dd>
      {t?.summary&&<><dt/><dd><small>{t.summary}</small></dd></>}
      <dt>Today</dt><dd>{fmtNumber(p.calls_today||0)} calls · {usd(p.spend_today_usd)}</dd>
      <dt>Limits</dt><dd>{fmtNumber(p.requests_per_day||0)} calls a day · cost ceiling {usd(p.cost_ceiling_usd)}</dd>
      {p.fallback_code&&<><dt>Fallback</dt><dd>{p.fallback_code}</dd></>}
      {st==='retired'&&<><dt>Retired</dt><dd>{p.retired_at?fmtDate(p.retired_at):'Yes'}{p.retired_reason?` · ${p.retired_reason}`:''}</dd></>}
      {st!=='retired'&&p.paused&&<><dt>Paused</dt><dd>{p.last_validation_result?.pause_reason||'Waiting for a passing test and activation'}</dd></>}
    </dl>
  </article>
}

function Models({profiles,action}){
  const by=s=>profiles.filter(p=>profileState(p)===s),active=by('active'),candidate=by('candidate'),retired=by('retired')
  return <>
    <section className="m-panel"><SectionTitle icon={BrainCircuit} title={`Active (${fmtNumber(active.length)})`} subtitle="Passed their tests and switched on. Only these are used." action={action}/>
      {active.length?<div className="l3v-cards">{active.map(p=><ProfileCard key={p.id} p={p}/>)}</div>:<Empty text="No model is active. Layer 3 work waits until one passes its tests and is activated."/>}</section>
    <section className="m-panel"><SectionTitle icon={FlaskConical} title={`Candidates (${fmtNumber(candidate.length)})`} subtitle="Set up but not in use: still being tested, failed a test, or paused."/>
      {candidate.length?<div className="l3v-cards">{candidate.map(p=><ProfileCard key={p.id} p={p}/>)}</div>:<Empty text="No candidate profiles."/>}</section>
    <section className="m-panel"><details className="l3v-retired"><summary>Retired ({fmtNumber(retired.length)}) — kept for the record, never used</summary>
      {retired.length?<div className="l3v-cards">{retired.map(p=><ProfileCard key={p.id} p={p}/>)}</div>:<Empty text="No retired profiles."/>}</details></section>
  </>
}

function Tests({tests,action}){
  const[profile,setProfile]=useState('')
  const options=useMemo(()=>[...new Set(tests.map(t=>t.profile_code).filter(Boolean))].sort(),[tests])
  const rows=profile?tests.filter(t=>t.profile_code===profile):tests
  return <section className="m-panel">
    <SectionTitle icon={FlaskConical} title="Test results" subtitle="Each run checks a model against known answers before it is allowed to work." action={action}/>
    <div className="l3v-filter"><label>Profile <select value={profile} onChange={e=>setProfile(e.target.value)} aria-label="Filter test results by profile"><option value="">All profiles</option>{options.map(o=><option key={o}>{o}</option>)}</select></label><span>{fmtNumber(rows.length)} run{rows.length===1?'':'s'}</span></div>
    <p className="l3v-note"><b>Stated exact</b>: the page states a value and the model gave exactly that value. <b>Wrong admitted</b>: the model gave a value that would have been accepted but was wrong (including inventing a value the page does not state) — this must be zero. <b>Withheld</b>: the page states a value but the model held back; safe, but the value is not filled.</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>When</th><th>Profile and model</th><th>Result</th><th className="num">Stated exact</th><th className="num">Wrong admitted</th><th className="num">Withheld</th><th className="num">Calls</th><th className="num">Cost</th></tr></thead><tbody>
      {rows.length?rows.map(t=><tr key={t.id} title={t.summary||''}>
        <td>{fmtDateTime(t.at)}</td>
        <td><span className="l3v-model">{t.model}</span><span className="l3v-code">{t.profile_code}</span></td>
        <td><StatusChip value={t.status} tone={t.status==='pass'?'success':'danger'} label={t.status==='pass'?'Passed':'Failed'}/></td>
        <td className="num">{fmtNumber(t.stated_exact||0)} of {fmtNumber(t.stated_total||0)}{t.stated_total?<span className="l3v-code">{fmtPercent(100*t.stated_exact/t.stated_total)}</span>:null}</td>
        <td className={`num ${Number(t.wrong_admitted)>0?'l3v-bad':'l3v-good'}`}>{fmtNumber(t.wrong_admitted||0)}</td>
        <td className="num">{fmtNumber(t.withheld||0)}</td>
        <td className="num">{fmtNumber(t.calls||0)}</td>
        <td className="num">{usd(t.cost_usd)}</td>
      </tr>):<tr><td colSpan={8} className="cf-empty-cell">No test runs recorded.</td></tr>}
    </tbody></table></div>
  </section>
}

function Spend({spend,profiles,days,action}){
  const today=spend.filter(s=>s.day===spend[0]?.day)
  const total=spend.reduce((n,s)=>n+Number(s.live_cost_usd||0)+Number(s.test_cost_usd||0),0),live=spend.reduce((n,s)=>n+Number(s.live_cost_usd||0),0)
  const byDay=useMemo(()=>{const m=new Map();for(const s of spend){const v=m.get(s.day)||{day:s.day,live:0,test:0};v.live+=Number(s.live_cost_usd||0);v.test+=Number(s.test_cost_usd||0);m.set(s.day,v)}return[...m.values()]},[spend])
  return <>
    <div className="cf-metric-grid">
      <Metric label={`Spend, last ${days} days`} value={usd(total)} icon={CircleDollarSign}/>
      <Metric label="Of which live work" value={usd(live)} detail="The rest is testing"/>
      <Metric label="Spend on the latest day" value={usd(today.reduce((n,s)=>n+Number(s.live_cost_usd||0)+Number(s.test_cost_usd||0),0))} detail={spend[0]?.day?fmtDate(spend[0].day):''}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={CircleDollarSign} title="Spend by day and profile" subtitle="Live work and testing are shown separately. The bar compares the day's total with the profile's configured cost ceiling; red means over it." action={action}/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Day</th><th>Profile and model</th><th className="num">Live calls</th><th className="num">Live cost</th><th className="num">Test calls</th><th className="num">Test cost</th><th>Against ceiling</th></tr></thead><tbody>
        {spend.length?spend.map(s=>{const t=Number(s.live_cost_usd||0)+Number(s.test_cost_usd||0),c=Number(s.cost_ceiling_usd||0),pct=c>0?Math.min(100,t/c*100):0;return <tr key={s.day+(s.profile_code||'none')}>
          <td>{fmtDate(s.day)}</td>
          <td><span className="l3v-model">{s.model||'Unknown model'}</span><span className="l3v-code">{s.profile_code||'No profile recorded'}</span></td>
          <td className="num">{fmtNumber(s.live_calls||0)}</td><td className="num">{usd(s.live_cost_usd)}</td>
          <td className="num">{fmtNumber(s.test_calls||0)}</td><td className="num">{usd(s.test_cost_usd)}</td>
          <td>{c>0?<><span className={`l3v-bar${t>c?' over':''}`} title={`${usd(t)} of ${usd(c)}`}><i style={{width:`${pct}%`}}/></span><span className="l3v-code">{usd(t)} of {usd(c)}</span></>:<span className="l3v-code">No ceiling set · {usd(t)}</span>}</td>
        </tr>}):<tr><td colSpan={7} className="cf-empty-cell">No Layer 3 spend recorded in the last {days} days.</td></tr>}
      </tbody></table></div>
    </section>
    <section className="m-panel"><SectionTitle title="Daily totals"/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Day</th><th className="num">Live</th><th className="num">Testing</th><th className="num">Total</th></tr></thead><tbody>{byDay.map(d=><tr key={d.day}><td>{fmtDate(d.day)}</td><td className="num">{usd(d.live)}</td><td className="num">{usd(d.test)}</td><td className="num"><strong>{usd(d.live+d.test)}</strong></td></tr>)}</tbody></table></div>
    </section>
  </>
}
