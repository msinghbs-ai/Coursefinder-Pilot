import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,ChevronLeft,ChevronRight,RefreshCw,Table2}from'lucide-react'
import{adminRead}from'./lib/supabase'

// CF-247 complete coverage: every active Australian course is accounted for, attribute by attribute.
// Server: admin_read('course_coverage' | 'course_coverage_courses'), rebuilt hourly (security.course_coverage_build_v1).
// Colour: one blue ordinal ramp by pipeline stage (validated light, ordinal: steps 250/350/450/550/700).
export const COVERAGE_STAGES=[
  {key:'admitted',label:'Admitted',states:['admitted'],color:'#0d366b'},
  {key:'progress',label:'Found, awaiting admission or review',states:['candidate','in_review','awaiting_l3'],color:'#1c5cab'},
  {key:'read',label:'Page read, not published',states:['not_on_page'],color:'#2a78d6'},
  {key:'found',label:'Page found or site blocked',states:['page_found','blocked'],color:'#5598e7'},
  {key:'unreached',label:'Course page not found yet',states:['site_known','no_website','missing_l1'],color:'#86b6ef'},
]
const STATE_LABEL={admitted:'Admitted',candidate:'Found on verified page (awaiting admission)',in_review:'In human review (L4)',awaiting_l3:'Awaiting AI check (L3)',not_on_page:'Page read, not published',
  blocked:'Site blocked',page_found:'Page found, not read',site_known:'Site known, page not found',no_website:'No website known',missing_l1:'Missing in CRICOS'}
const STATE_ORDER=['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']
const ATTR={official_url:{label:'Official course page',layer:'Layer 2'},provider_tuition:{label:'Provider tuition (fee year)',layer:'Layer 2'},
  english:{label:'English requirements',layer:'Layer 2'},intakes:{label:'Intakes / start dates',layer:'Layer 2'},
  registered_tuition:{label:'Registered tuition (CRICOS)',layer:'Layer 1'},duration:{label:'Duration (CRICOS)',layer:'Layer 1'},campus:{label:'Campus (CRICOS)',layer:'Layer 1'}}
const TIERS=[['','All providers'],['top_10','Top 10'],['top_11_40','11–40'],['top_41_100','41–100'],['rest','All others']]
const PAGE=50

export function CoverageView(){
  const[tier,setTier]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('')
  const[pick,setPick]=useState(null),[list,setList]=useState(null),[offset,setOffset]=useState(0),[listBusy,setListBusy]=useState(false),[tip,setTip]=useState(null)
  const load=()=>{setBusy(true);setError('');adminRead('course_coverage',tier?{tier}:{}).then(setData).catch(e=>setError(e.message||String(e))).finally(()=>setBusy(false))}
  useEffect(()=>{setPick(null);load()},[tier])
  useEffect(()=>{
    if(!pick){setList(null);return}
    setListBusy(true)
    adminRead('course_coverage_courses',{attribute:pick.attribute,state:pick.state,tier:tier||null,limit:PAGE,offset})
      .then(setList).catch(e=>setError(e.message||String(e))).finally(()=>setListBusy(false))
  },[pick,offset])
  const attrs=data?.attributes||[]
  const l2=attrs.filter(a=>ATTR[a.attribute]?.layer==='Layer 2')
  const trend=useMemo(()=>{const m=new Map();for(const t of data?.trend||[]){if(!m.has(t.date))m.set(t.date,{});m.get(t.date)[t.attribute]=t}return[...m.entries()]},[data])

  return <div className="cc-wrap">
    <section className="cc-filters" aria-label="Provider tier">
      <span>Provider tier</span>
      {TIERS.map(([k,l])=><button key={k||'all'} className={tier===k?'active':''} onClick={()=>setTier(k)}>{l}</button>)}
      <button className="dq-icon" title="Refresh" onClick={load} disabled={busy}><RefreshCw size={15}/></button>
    </section>
    {error&&<div className="dq-alert"><AlertTriangle size={16}/><span>{error}</span></div>}
    <section className="cc-kpis">
      <div className="cc-kpi"><small>Courses accounted for</small><strong>{fmt(data?.courses)}</strong><em>{fmt(data?.providers)} providers · every course has a state for every attribute</em></div>
      {l2.map(a=>{const n=Number(a.states?.admitted||0),t=Number(a.total||0);return <div className="cc-kpi" key={a.attribute}>
        <small>{ATTR[a.attribute].label}</small><strong>{pct(n,t)}</strong><em>{fmt(n)} of {fmt(t)} admitted</em></div>})}
    </section>

    <section className="cc-panel">
      <header><div><h2>Coverage by attribute</h2><p>Share of courses at each stage. Hover a segment for counts; select a count in the table to list the courses.</p></div>
        <small>{data?.computed_at?`Updated ${new Date(data.computed_at).toLocaleString('en-AU',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'})} · rebuilt hourly`:''}</small></header>
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
            <div className="cc-bar-value">{pct(Number(a.states?.admitted||0),total)}</div>
          </div>})}
        {tip&&<div className="cc-tip" style={{left:tip.x+12,top:tip.y+12}}><strong>{tip.attr}</strong><span>{tip.stage}</span><b>{fmt(tip.n)} courses · {pct(tip.n,tip.total)}</b></div>}
      </div>
    </section>

    <section className="cc-panel">
      <header><div><h2><Table2 size={14}/> Courses by state</h2><p>Exact counts. Select a number to see those courses.</p></div></header>
      <div className="dq-table-wrap"><table className="dq-table cc-table"><thead><tr><th>Attribute</th>{STATE_ORDER.map(s=><th key={s}>{STATE_LABEL[s]}</th>)}<th>Total</th></tr></thead>
        <tbody>{attrs.map(a=><tr key={a.attribute}><td><strong>{ATTR[a.attribute]?.label||a.attribute}</strong><small>{ATTR[a.attribute]?.layer}</small></td>
          {STATE_ORDER.map(s=>{const n=Number(a.states?.[s]||0);return <td key={s}>{n?<button className={`cc-count ${pick?.attribute===a.attribute&&pick?.state===s?'active':''}`} onClick={()=>{setOffset(0);setPick({attribute:a.attribute,state:s})}}>{fmt(n)}</button>:<span className="cc-zero">–</span>}</td>})}
          <td><strong>{fmt(a.total)}</strong></td></tr>)}</tbody></table></div>
    </section>

    {pick&&<section className="cc-panel">
      <header><div><h2>{ATTR[pick.attribute]?.label} · {STATE_LABEL[pick.state]}</h2><p>{fmt(list?.total)} courses{tier?` · ${TIERS.find(t=>t[0]===tier)?.[1]}`:''}</p></div><button className="dq-secondary" onClick={()=>setPick(null)}>Close</button></header>
      {listBusy?<div className="dq-skeleton-list">{Array.from({length:5}).map((_,i)=><div className="dq-skeleton row" key={i}/>)}</div>:
      <div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Course</th><th>CRICOS</th><th>Provider</th><th>Tier</th></tr></thead><tbody>
        {(list?.items||[]).map(r=><tr key={r.course_id}><td><button className="dq-entity-link" onClick={()=>{location.hash=`#courses?id=${encodeURIComponent(r.course_id)}`}}><strong>{r.title}</strong></button></td><td>{r.cricos||'—'}</td><td>{r.provider_name}</td><td>{TIERS.find(t=>t[0]===r.tier)?.[1]}</td></tr>)}
      </tbody></table></div>}
      <footer className="dq-pager"><button disabled={offset===0||listBusy} onClick={()=>setOffset(Math.max(0,offset-PAGE))}><ChevronLeft size={15}/>Previous</button><span>{fmt(Math.min(offset+1,list?.total||0))}–{fmt(Math.min(offset+PAGE,list?.total||0))} of {fmt(list?.total)}</span><button disabled={offset+PAGE>=(list?.total||0)||listBusy} onClick={()=>setOffset(offset+PAGE)}>Next<ChevronRight size={15}/></button></footer>
    </section>}

    <section className="cc-panel">
      <header><div><h2>Daily trend</h2><p>Admitted share per Layer 2 attribute, one row per day (kept from 29 Sep 2026).</p></div></header>
      <div className="dq-table-wrap"><table className="dq-table cc-table"><thead><tr><th>Date</th>{l2.map(a=><th key={a.attribute}>{ATTR[a.attribute].label}</th>)}</tr></thead>
        <tbody>{trend.slice().reverse().map(([d,row])=><tr key={d}><td><strong>{new Date(d).toLocaleDateString('en-AU',{day:'2-digit',month:'short',year:'numeric'})}</strong></td>
          {l2.map(a=>{const r=row[a.attribute];return <td key={a.attribute}>{r?<><strong>{pct(Number(r.admitted||0),Number(r.total||0))}</strong><small>{fmt(r.admitted||0)} courses</small></>:'—'}</td>})}</tr>)}</tbody></table></div>
    </section>
  </div>
}

function stageCount(a,s){return s.states.reduce((t,k)=>t+Number(a.states?.[k]||0),0)}
function fmt(v){const n=Number(v);return Number.isFinite(n)?n.toLocaleString('en-AU'):'—'}
function pct(n,t){if(!t)return'—';const p=n/t*100;return`${p<10&&p>0?p.toFixed(1):Math.round(p)}%`}
