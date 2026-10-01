import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,ChevronLeft,ChevronRight,CircleGauge,Layers,ListChecks,RefreshCw,Table2}from'lucide-react'
import{adminRead}from'./lib/supabase'
import{fmtNumber,fmtDate,fmtDateTime,fmtPercent,fmtShare}from'./lib/format.js'
import{Metric,Button}from'./ui-kit'

// CF-247 complete coverage: every active Australian course is accounted for, attribute by attribute.
// Server: admin_read('course_coverage' | 'course_coverage_courses'), rebuilt hourly (security.course_coverage_build_v1,
// security.course_completeness_build_v1). R12: completeness states per attribute and the course completeness score
// (migration 20260929190000_cf247_coverage_completeness_states).
// Pipeline stages use one blue ordinal ramp (validated light, ordinal: steps 250/350/450/550/700; = --cf-seq-1..5).
export const COVERAGE_STAGES=[
  {key:'admitted',label:'Admitted',states:['admitted'],color:'#0d366b'},
  {key:'progress',label:'Found, awaiting admission or review',states:['candidate','in_review','awaiting_l3'],color:'#1c5cab'},
  {key:'read',label:'Page read, not published',states:['not_on_page'],color:'#2a78d6'},
  {key:'found',label:'Page found or site blocked',states:['page_found','blocked'],color:'#5598e7'},
  {key:'unreached',label:'Course page not found yet',states:['site_known','no_website','missing_l1'],color:'#86b6ef'},
]
// The nine completeness states (Design Reference §3). `built` marks the states the hourly build produces today;
// the others are always shown, as 0, so a gap is visible rather than hidden.
export const COMPLETENESS_STATES=[
  {key:'present',label:'Present',hint:'An admitted value is held',color:'var(--cf-green-700)',built:true},
  {key:'source_null',label:'Source says nothing',hint:'The source was read and does not publish this',color:'var(--cf-slate-400)',built:true},
  {key:'ambiguous',label:'Ambiguous',hint:'A value was found and awaits a decision (Layer 3 or Layer 4)',color:'var(--cf-amber-500)',built:true},
  {key:'not_yet_enriched',label:'Not yet enriched',hint:'The source has not been read yet',color:'var(--cf-slate-200)',built:true},
  {key:'stale',label:'Stale',hint:'Held, but past its refresh cycle',color:'var(--cf-orange-500)'},
  {key:'rejected',label:'Rejected',hint:'A found value was rejected',color:'var(--cf-red-600)'},
  {key:'suppressed',label:'Suppressed',hint:'Held but withheld from publication',color:'var(--cf-violet-400)'},
  {key:'not_applicable',label:'Not applicable',hint:'Does not apply to this course',color:'var(--cf-slate-300)'},
  {key:'zero',label:'Zero',hint:'The source states zero (for example no fee)',color:'var(--cf-blue-300)'},
]
const CSTATE=Object.fromEntries(COMPLETENESS_STATES.map(s=>[s.key,s]))
const STATE_LABEL={admitted:'Admitted',candidate:'Found on verified page (awaiting admission)',in_review:'In human review (Layer 4)',awaiting_l3:'Awaiting AI check (Layer 3)',not_on_page:'Page read, not published',
  blocked:'Site blocked',page_found:'Page found, not read',site_known:'Site known, page not found',no_website:'No website known',missing_l1:'Missing in CRICOS'}
// v2.15.132 (att-wide-table): short column headings; the full wording is on hover and in the legend.
const STATE_SHORT={admitted:'Admitted',candidate:'Awaiting admission',in_review:'Person',awaiting_l3:'AI check',not_on_page:'Not published',blocked:'Blocked',page_found:'Not read',site_known:'No page',no_website:'No site',missing_l1:'Not in CRICOS'}
const STATE_ORDER=['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']
const ATTR={official_url:{label:'Official course page',layer:'Layer 2'},provider_tuition:{label:'Provider tuition (fee year)',layer:'Layer 2'},
  english:{label:'English requirements',layer:'Layer 2'},intakes:{label:'Intakes / start dates',layer:'Layer 2'},
  registered_tuition:{label:'Registered tuition (CRICOS)',layer:'Layer 1'},duration:{label:'Duration (CRICOS)',layer:'Layer 1'},campus:{label:'Campus (CRICOS)',layer:'Layer 1'}}
const TIERS=[['','All providers'],['top_10','Top 10'],['top_11_40','11–40'],['top_41_100','41–100'],['rest','All others']]
const PAGE=50

// v2.15.112: view 'courses' (course completeness) or 'attributes' (attribute completeness and pipeline stage); both
// kept by default for older callers. Platform Admin 30 Sep 2026: separate course and attribute completion in tabs.
export function CoverageView({view='all'}={}){
  const[tier,setTier]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('')
  const[pick,setPick]=useState(null),[list,setList]=useState(null),[offset,setOffset]=useState(0),[listBusy,setListBusy]=useState(false),[tip,setTip]=useState(null)
  const load=()=>{setBusy(true);setError('');adminRead('course_coverage',tier?{tier}:{}).then(setData).catch(e=>setError(e.message||String(e))).finally(()=>setBusy(false))}
  useEffect(()=>{setPick(null);load()},[tier])
  useEffect(()=>{
    if(!pick){setList(null);return}
    setListBusy(true)
    const filter=pick.cstate?{completeness_state:pick.cstate}:{state:pick.state}
    adminRead('course_coverage_courses',{attribute:pick.attribute,...filter,tier:tier||null,limit:PAGE,offset})
      .then(setList).catch(e=>setError(e.message||String(e))).finally(()=>setListBusy(false))
  },[pick,offset])
  const attrs=data?.attributes||[]
  const cstates=data?.completeness_states||[]
  const score=data?.completeness||null
  const l2=attrs.filter(a=>ATTR[a.attribute]?.layer==='Layer 2')
  const trend=useMemo(()=>{const m=new Map();for(const t of data?.trend||[]){if(!m.has(t.date))m.set(t.date,{});m.get(t.date)[t.attribute]=t}return[...m.entries()]},[data])
  const scoreByDate=useMemo(()=>Object.fromEntries((score?.trend||[]).map(t=>[t.date,t])),[score])
  const pickLabel=pick?(pick.cstate?CSTATE[pick.cstate]?.label:STATE_LABEL[pick.state]):''
  const choose=p=>{setOffset(0);setPick(p)}
  const maxBand=Math.max(1,...(score?.by_admitted||[]).map(b=>Number(b.courses||0)))

  return <div className="cc-wrap">
    {/* v2.15.131 (cc-counts-consistency): say what is counted here, as other screens count different sets. */}
    <p className="cc-scope" data-count-scope>Counts here cover <strong>{fmtNumber(data?.courses||0)} active Australian courses</strong>, recounted every hour. Courses lists every course in any status and country.</p>
    <section className="cf-filterbar" aria-label="Provider tier">
      <span>Provider tier</span>
      {TIERS.map(([k,l])=><button key={k||'all'} className={tier===k?'active':''} onClick={()=>setTier(k)}>{l}</button>)}
      <Button compact className="cf-icon-btn cc-refresh" title="Refresh" aria-label="Refresh" onClick={load} disabled={busy}><RefreshCw size={14}/></Button>
    </section>
    {error&&<div className="dq-alert"><AlertTriangle size={16}/><span>{error}</span></div>}

    {view!=='attributes'&&<>
    <section className="cf-metric-grid cc-score" aria-label="Course completeness">
      <Metric icon={CircleGauge} tone="info" label="Course completeness score" value={score?fmtPercent(score.completeness):'—'}
        detail={score?`Average share of a course's ${fmtNumber(score.attributes||7)} attributes that are admitted`:'Rebuilt hourly'}/>
      <Metric icon={ListChecks} tone="success" label="Accounted for" value={score?fmtPercent(score.accounted_pct):'—'}
        detail="Admitted, awaiting a decision, or the source says nothing"/>
      <Metric icon={Layers} tone="violet" label="Fully complete courses" value={score?fmtNumber(score.fully_complete):'—'}
        detail={score?`${fmtShare(score.fully_complete,score.courses)} of ${fmtNumber(score.courses)} courses have every attribute`:''}/>
      <Metric label="Courses accounted for" value={fmtNumber(data?.courses)} detail={`${fmtNumber(data?.providers)} providers · every course has a state for every attribute`}/>
    </section>
    </>}
    {view!=='courses'&&<>
    <section className="cf-metric-grid cc-kpis">
      {l2.map(a=>{const n=Number(a.states?.admitted||0),t=Number(a.total||0);return <Metric key={a.attribute} label={ATTR[a.attribute].label} value={fmtShare(n,t)} detail={`${fmtNumber(n)} of ${fmtNumber(t)} admitted`}/>})}
    </section>
    </>}

    {view!=='courses'&&<>
    <section className="cc-panel">
      <header><div><h2><Table2 size={14}/> Completeness by attribute</h2><p>Every course, one completeness state per attribute. Select a count to list those courses. States the hourly build does not record yet show as –.</p></div>
        <small>{score?.computed_at?`Updated ${fmtDateTime(score.computed_at)} · rebuilt hourly`:''}</small></header>
      <div className="cc-legend">{COMPLETENESS_STATES.filter(s=>s.built).map(s=><span key={s.key} title={s.hint}><i style={{background:s.color}}/>{s.label}</span>)}</div>
      <div className="cc-bars" onMouseLeave={()=>setTip(null)}>
        {busy&&!data?<div className="dq-skeleton domain"/>:cstates.map(a=>{const total=Number(a.total||0);return <div className="cc-bar-row" key={a.attribute}>
          <div className="cc-bar-label"><strong>{ATTR[a.attribute]?.label||a.attribute}</strong><small>{ATTR[a.attribute]?.layer}</small></div>
          <div className="cc-bar" role="img" aria-label={`${ATTR[a.attribute]?.label}: ${COMPLETENESS_STATES.map(s=>`${s.label} ${fmtNumber(a.states?.[s.key]||0)}`).join(', ')}`}>
            {COMPLETENESS_STATES.map(s=>{const n=Number(a.states?.[s.key]||0);if(!n)return null;return <span key={s.key} style={{width:`${n/total*100}%`,background:s.color}}
              onMouseMove={e=>setTip({x:e.clientX,y:e.clientY,attr:ATTR[a.attribute]?.label,stage:s.label,n,total})}/>})}
          </div>
          <div className="cc-bar-value">{fmtShare(Number(a.states?.present||0),total)}</div>
        </div>})}
      </div>
      <div className="dq-table-wrap"><table className="dq-table cc-table cc-states"><thead><tr><th>Attribute</th>{COMPLETENESS_STATES.map(s=><th key={s.key} className="num" title={s.built?s.hint:`${s.hint}. Not recorded by the hourly build yet.`}>{s.label}</th>)}<th className="num">Total</th></tr></thead>
        <tbody>{cstates.map(a=><tr key={a.attribute}><td><strong>{ATTR[a.attribute]?.label||a.attribute}</strong><small>{ATTR[a.attribute]?.layer}</small></td>
          {COMPLETENESS_STATES.map(s=>{const n=Number(a.states?.[s.key]||0);return <td key={s.key} className="num">{n?<button className={`cc-count ${pick?.attribute===a.attribute&&pick?.cstate===s.key?'active':''}`} onClick={()=>choose({attribute:a.attribute,cstate:s.key})}>{fmtNumber(n)}</button>:<span className="cc-zero">–</span>}</td>})}
          <td className="num"><strong>{fmtNumber(a.total)}</strong></td></tr>)}</tbody></table></div>
    </section>
    </>}

    {view!=='attributes'&&<>
    <section className="cc-panel">
      <header><div><h2>Courses by attributes admitted</h2><p>How many of each course's {fmtNumber(score?.attributes||7)} attributes are admitted. The completeness score is the average of these shares.</p></div></header>
      <div className="cc-bands">{(score?.by_admitted||[]).map(b=>{const n=Number(b.courses||0);return <div className="cc-band" key={b.admitted}>
        <span>{fmtNumber(b.admitted)} of {fmtNumber(score?.attributes||7)}</span><i><b style={{width:`${Math.max(1,n/maxBand*100)}%`}}/></i><em>{fmtNumber(n)} <small>{fmtShare(n,score?.courses)}</small></em></div>})}
        {!busy&&!(score?.by_admitted||[]).length&&<div className="cf-empty">No completeness build yet.</div>}</div>
    </section>
    </>}

    {view!=='courses'&&<>
    <section className="cc-panel">
      <header><div><h2>Coverage by pipeline stage</h2><p>Where each attribute is in the pipeline. The panel above says whether a course has a value; this one says how far the work to get it has gone. Hover a segment for counts; select a count in the table to list the courses.</p></div>
        <small>{data?.computed_at?`Updated ${fmtDateTime(data.computed_at)} · rebuilt hourly`:''}</small></header>
      <div className="cc-legend">{COVERAGE_STAGES.map(s=><span key={s.key}><i style={{background:s.color}}/>{s.label}</span>)}</div>
      <div className="cc-bars" onMouseLeave={()=>setTip(null)}>
        {busy&&!data?<div className="dq-skeleton domain"/>:attrs.map(a=>{
          const total=Number(a.total||0)
          return <div className="cc-bar-row" key={a.attribute}>
            <div className="cc-bar-label"><strong>{ATTR[a.attribute]?.label||a.attribute}</strong><small>{ATTR[a.attribute]?.layer}</small></div>
            <div className="cc-bar" role="img" aria-label={`${ATTR[a.attribute]?.label}: ${COVERAGE_STAGES.map(s=>`${s.label} ${stageCount(a,s)}`).join(', ')}`}>
              {COVERAGE_STAGES.map(s=>{const n=stageCount(a,s);if(!n)return null;return <span key={s.key} style={{width:`${n/total*100}%`,background:s.color}}
                onMouseMove={e=>setTip({x:e.clientX,y:e.clientY,attr:ATTR[a.attribute]?.label,stage:s.label,n,total})}/>})}
            </div>
            <div className="cc-bar-value">{fmtShare(Number(a.states?.admitted||0),total)}</div>
          </div>})}
      </div>
      {tip&&<div className="cc-tip" style={{left:tip.x+12,top:tip.y+12}}><strong>{tip.attr}</strong><span>{tip.stage}</span><b>{fmtNumber(tip.n)} courses · {fmtShare(tip.n,tip.total)}</b></div>}
      <div className="dq-table-wrap"><table className="dq-table cc-table"><thead><tr><th>Attribute</th>{STATE_ORDER.map(s=><th key={s} className="num" title={STATE_LABEL[s]}>{STATE_SHORT[s]||STATE_LABEL[s]}</th>)}<th className="num">Total</th></tr></thead>
        <tbody>{attrs.map(a=><tr key={a.attribute}><td><strong>{ATTR[a.attribute]?.label||a.attribute}</strong><small>{ATTR[a.attribute]?.layer}</small></td>
          {STATE_ORDER.map(s=>{const n=Number(a.states?.[s]||0);return <td key={s} className="num">{n?<button className={`cc-count ${pick?.attribute===a.attribute&&pick?.state===s?'active':''}`} onClick={()=>choose({attribute:a.attribute,state:s})}>{fmtNumber(n)}</button>:<span className="cc-zero">–</span>}</td>})}
          <td className="num"><strong>{fmtNumber(a.total)}</strong></td></tr>)}</tbody></table></div>
    </section>
    </>}

    {view!=='courses'&&<>
    {pick&&<section className="cc-panel">
      <header><div><h2>{ATTR[pick.attribute]?.label} · {pickLabel}</h2><p>{fmtNumber(list?.total)} courses{tier?` · ${TIERS.find(t=>t[0]===tier)?.[1]}`:''}</p></div><Button compact onClick={()=>setPick(null)}>Close</Button></header>
      {listBusy?<div className="dq-skeleton-list">{Array.from({length:5}).map((_,i)=><div className="dq-skeleton row" key={i}/>)}</div>:
      <div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Course</th><th>CRICOS</th><th>Provider</th><th>Tier</th><th className="num">Course completeness</th></tr></thead><tbody>
        {(list?.items||[]).map(r=><tr key={r.course_id}><td><button className="dq-entity-link" onClick={()=>{location.hash=`#courses?id=${encodeURIComponent(r.course_id)}`}}><strong>{r.title}</strong></button></td><td>{r.cricos||'—'}</td><td>{r.provider_name}</td><td>{TIERS.find(t=>t[0]===r.tier)?.[1]}</td><td className="num">{fmtPercent(r.completeness)}</td></tr>)}
      </tbody></table></div>}
      <footer className="dq-pager"><button disabled={offset===0||listBusy} onClick={()=>setOffset(Math.max(0,offset-PAGE))}><ChevronLeft size={15}/>Previous</button><span>{fmtNumber(Math.min(offset+1,list?.total||0))}–{fmtNumber(Math.min(offset+PAGE,list?.total||0))} of {fmtNumber(list?.total)}</span><button disabled={offset+PAGE>=(list?.total||0)||listBusy} onClick={()=>setOffset(offset+PAGE)}>Next<ChevronRight size={15}/></button></footer>
    </section>}
    </>}

    {view!=='attributes'&&<>
    <section className="cc-panel">
      <header><div><h2>Daily trend</h2><p>Course completeness score and admitted share per Layer 2 attribute, one row per day (kept from 29 Sep 2026){tier?'. The score columns are for all providers.':'.'}</p></div></header>
      <div className="dq-table-wrap"><table className="dq-table cc-table"><thead><tr><th>Date</th><th className="num">Completeness</th><th className="num">Accounted for</th><th className="num">Fully complete</th>{l2.map(a=><th key={a.attribute}>{ATTR[a.attribute].label}</th>)}</tr></thead>
        <tbody>{trend.slice().reverse().map(([d,row])=>{const sc=scoreByDate[d];return <tr key={d}><td><strong>{fmtDate(d)}</strong></td>
          <td className="num">{sc?fmtPercent(sc.completeness):'—'}</td><td className="num">{sc?fmtPercent(sc.accounted_pct):'—'}</td><td className="num">{sc?fmtNumber(sc.fully_complete):'—'}</td>
          {l2.map(a=>{const r=row[a.attribute];return <td key={a.attribute}>{r?<><strong>{fmtShare(Number(r.admitted||0),Number(r.total||0))}</strong><small>{fmtNumber(r.admitted||0)} courses</small></>:'—'}</td>})}</tr>})}</tbody></table></div>
    </section>
    </>}
  </div>
}

function stageCount(a,s){return s.states.reduce((t,k)=>t+Number(a.states?.[k]||0),0)}
