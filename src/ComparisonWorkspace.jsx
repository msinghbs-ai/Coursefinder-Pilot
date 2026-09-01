import React,{useEffect,useMemo,useState}from'react'
import{Activity,ArrowLeftRight,BarChart3,GraduationCap,Search,Trash2,UsersRound,X}from'lucide-react'
import{adminRead}from'./lib/supabase'

const MAX=6
const human=v=>String(v??'').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())
const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null}
const fmtNumber=v=>{const n=num(v);return n==null?'—':n.toLocaleString()}
const pct=(v,unit)=>{const n=num(v);if(n==null)return'—';const u=String(unit||'').toLowerCase();if(u.includes('percent')||u==='%'||Math.abs(n)<=100)return n.toFixed(1)+'%';return n.toLocaleString(undefined,{maximumFractionDigits:1})}
const period=x=>[x?.collection_year_from,x?.collection_year_to].filter(Boolean).join('–')||'Period not supplied'
const level=x=>x?.study_level||'All study levels'
const outcomeKey=x=>[x?.survey_code||x?.source_label||'',x?.metric_code||x?.metric_name||'',x?.study_level_code||x?.study_level||'',x?.study_area_code||x?.study_area||'',x?.collection_year_from||'',x?.collection_year_to||''].join('|')
function groupFor(x){
 const s=`${x?.metric_name||''} ${x?.metric_code||''} ${x?.source_label||''}`.toLowerCase()
 if(/employment|salary|income|job/.test(s))return'Graduate employment & salary'
 if(/graduate|satisfaction|overall satisfaction/.test(s))return'Recent graduate satisfaction'
 return'Current student experience'
}
function valueText(x){
 if(!x)return'—'
 const unit=String(x.unit||'').toLowerCase()
 const n=num(x.metric_value)
 if(n==null)return x.is_suppressed?'Suppressed':'—'
 if(/dollar|currency|aud|salary/.test(unit)||(/salary|income/.test(String(x.metric_name||'').toLowerCase())&&n>1000))return'AUD '+Math.round(n).toLocaleString()
 return pct(n,x.unit)
}
function ciText(x){if(!x)return'';const lo=num(x.confidence_low),hi=num(x.confidence_high);return lo!=null&&hi!=null?`CI ${pct(lo,x.unit)} – ${pct(hi,x.unit)}`:''}
function benchmarkText(x){if(!x)return'';const b=num(x.national_benchmark);return b==null?'National benchmark unavailable':`National benchmark ${valueText({...x,metric_value:b})}`}
function idsFrom(params){return String(params?.get?.('ids')||'').split(',').map(x=>x.trim()).filter(Boolean).slice(0,MAX)}

export default function ComparisonWorkspace({routeParams,navigate,onError}){
 const initialType=routeParams?.get?.('type')==='course'?'course':'provider'
 const[type,setType]=useState(initialType),[ids,setIds]=useState(()=>idsFrom(routeParams)),[query,setQuery]=useState(''),[searchRows,setSearchRows]=useState([]),[searchBusy,setSearchBusy]=useState(false),[data,setData]=useState(null),[busy,setBusy]=useState(false),[category,setCategory]=useState('Current student experience'),[studyLevel,setStudyLevel]=useState('')
 useEffect(()=>{const t=routeParams?.get?.('type')==='course'?'course':'provider';setType(t);setIds(idsFrom(routeParams))},[routeParams])
 useEffect(()=>{let live=true;if(!ids.length){setData({items:[],total:0});return}setBusy(true);adminRead('contextual_compare',{entity_type:type,ids}).then(x=>live&&setData(x)).catch(e=>onError?.(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[type,ids.join(',')])
 useEffect(()=>{let live=true;const q=query.trim();if(q.length<2){setSearchRows([]);return}const timer=setTimeout(()=>{setSearchBusy(true);adminRead(type==='provider'?'providers_page':'courses_page',{limit:10,offset:0,query:q,sort:type==='provider'?'provider':'course',direction:'asc'}).then(x=>{if(live)setSearchRows((x?.items||[]).filter(r=>!ids.includes(String(r.id??r.course_id)))})}).catch(e=>onError?.(e.message)).finally(()=>live&&setSearchBusy(false))},220);return()=>{live=false;clearTimeout(timer)}},[query,type,ids.join(',')])
 const items=data?.items||[]
 const allOutcomes=useMemo(()=>items.flatMap(e=>(e.contextual_insights?.student_outcomes?.items||[])),[items])
 const levels=useMemo(()=>[...new Set(allOutcomes.map(level).filter(Boolean))].sort(),[allOutcomes])
 const categories=useMemo(()=>['Current student experience','Recent graduate satisfaction','Graduate employment & salary'].filter(g=>allOutcomes.some(x=>groupFor(x)===g)),[allOutcomes])
 useEffect(()=>{if(categories.length&&!categories.includes(category))setCategory(categories[0])},[categories.join('|')])
 const rows=useMemo(()=>{
   const map=new Map()
   for(const x of allOutcomes){
     if(groupFor(x)!==category)continue
     if(studyLevel&&level(x)!==studyLevel)continue
     const k=outcomeKey(x)
     if(!map.has(k))map.set(k,x)
   }
   return [...map.values()].sort((a,b)=>String(a.metric_name||'').localeCompare(String(b.metric_name||''))).slice(0,24)
 },[allOutcomes,category,studyLevel])
 function go(nextType,nextIds){navigate?.('Compare',{type:nextType,ids:nextIds.join(',')})}
 function switchType(next){setQuery('');setSearchRows([]);setStudyLevel('');go(next,[])}
 function add(row){if(ids.length>=MAX)return;const id=String(row.id??row.course_id);if(!id||ids.includes(id))return;go(type,[...ids,id]);setQuery('');setSearchRows([])}
 function remove(id){go(type,ids.filter(x=>x!==String(id)))}
 function clear(){go(type,[])}
 return <div className="cf-compare-page">
  <section className="cf-compare-hero">
   <div><span>Layer 1 contextual intelligence</span><h2>Compare {type==='provider'?'providers':'courses'}</h2><p>QILT outcomes and PRISMS student-flow context are aligned only when their source grain, period and study context are compatible.</p></div>
   <div className="cf-compare-type"><button className={type==='provider'?'active':''} onClick={()=>switchType('provider')}><UsersRound size={15}/>Providers</button><button className={type==='course'?'active':''} onClick={()=>switchType('course')}><GraduationCap size={15}/>Courses</button></div>
  </section>

  <section className="cf-compare-picker">
   <div className="cf-compare-picker-head"><div><strong>{ids.length} / {MAX} selected</strong><span>Add {type}s to build a like-for-like comparison.</span></div>{ids.length>0&&<button onClick={clear}><Trash2 size={14}/>Clear</button>}</div>
   <label className="cf-compare-search"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={`Search ${type}s to compare…`}/>{searchBusy&&<span className="m-spinner tiny"/>}</label>
   {searchRows.length>0&&<div className="cf-compare-results">{searchRows.map(r=><button key={r.id??r.course_id} disabled={ids.length>=MAX} onClick={()=>add(r)}><span><strong>{r.canonical_name||r.canonical_title||r.name}</strong><small>{type==='course'?[r.provider_name,r.course_code].filter(Boolean).join(' · '):[r.country_code,r.subdivision_name,r.city].filter(Boolean).join(' · ')}</small></span><b>Add +</b></button>)}</div>}
  </section>

  {!ids.length?<section className="cf-compare-empty"><ArrowLeftRight size={32}/><h3>Select up to six {type}s</h3><p>Search above, or open a {type} detail blade and choose Compare.</p></section>:busy&&!data?<section className="cf-compare-empty"><span className="m-spinner"/><p>Loading governed comparison…</p></section>:<>
   <section className="cf-compare-shell">
    <div className="cf-compare-tabs">{categories.map(x=><button key={x} className={category===x?'active':''} onClick={()=>setCategory(x)}>{x}</button>)}</div>
    <div className="cf-compare-controls"><label>Study level<select value={studyLevel} onChange={e=>setStudyLevel(e.target.value)}><option value="">All available levels</option>{levels.map(x=><option key={x} value={x}>{x}</option>)}</select></label><span><BarChart3 size={13}/>Like-for-like QILT rows only</span></div>
    <div className="cf-compare-scroll">
     <div className="cf-compare-grid" style={{'--cf-columns':Math.max(items.length,1)}}>
      <div className="cf-compare-label cf-compare-sticky">Selected</div>
      {items.map(e=><article className="cf-compare-entity" key={e.id}><button aria-label="Remove from comparison" onClick={()=>remove(e.id)}><X size={13}/></button><strong>{e.name}</strong><small>{type==='course'?[e.provider_name,e.course_code,e.study_level].filter(Boolean).join(' · '):[e.country_code,e.subdivision,e.city].filter(Boolean).join(' · ')}</small></article>)}
      {rows.length?rows.flatMap((r,ri)=>{
        const heading=<div className="cf-compare-metric-label cf-compare-sticky" key={`h-${outcomeKey(r)}`}><strong>{r.metric_name||r.metric_code}</strong><small>{[r.source_label,level(r),r.study_area,period(r)].filter(Boolean).join(' · ')}</small></div>
        const cells=items.map(e=>{
          const matches=(e.contextual_insights?.student_outcomes?.items||[]).filter(x=>outcomeKey(x)===outcomeKey(r))
          const x=matches[0]
          return <div className="cf-compare-value" key={`${e.id}-${outcomeKey(r)}`}><strong>{valueText(x)}</strong>{x?<><small>{ciText(x)}</small><span>{benchmarkText(x)}</span>{x.response_count!=null&&<em>{fmtNumber(x.response_count)} responses</em>}</>:<span>Not available at this exact grain</span>}</div>
        })
        return[heading,...cells]
      }):<div className="cf-compare-no-rows">No aligned QILT metrics match this category/study-level selection.</div>}
     </div>
    </div>
   </section>

   <section className="cf-flow-compare">
    <div className="cf-flow-title"><div><h3>International student flow</h3><p>PRISMS context retains Provider / geography / study-area / cohort grain and is never promoted to a Course outcome.</p></div><span>PRISMS</span></div>
    <div className="cf-flow-cards">{items.map(e=>{const g=e.contextual_insights?.student_flow||{},xs=g.items||[],x=xs.find(z=>!z.is_suppressed&&num(z.metric_value)!=null)||xs[0];return <article key={e.id}><strong>{e.name}</strong><small>{human(g.relationship_state||'not available')} · {human(g.granularity||'none')}</small><b>{x?.is_suppressed?'Suppressed':x?fmtNumber(x.metric_value):'—'}</b><span>{x?[x.metric_name||x.metric_code,x.subdivision,x.study_area,x.period_end].filter(Boolean).join(' · '):'No governed student-flow observation related at the accepted grain.'}</span></article>})}</div>
   </section>

   <p className="cf-compare-authority">{data?.authority_note}</p>
  </>}

  <style>{`
.cf-compare-page{display:grid;gap:12px}.cf-compare-hero{border-radius:14px;background:linear-gradient(135deg,#10133d,#172554 58%,#0f766e);color:#fff;padding:22px;display:flex;justify-content:space-between;gap:20px;align-items:end}.cf-compare-hero span{font-size:9px;text-transform:uppercase;letter-spacing:.1em;color:#c7d2fe;font-weight:850}.cf-compare-hero h2{font-size:25px;margin:4px 0}.cf-compare-hero p{font-size:10px;line-height:1.5;color:#dbeafe;max-width:760px;margin:0}.cf-compare-type{display:flex;gap:6px}.cf-compare-type button{border:1px solid rgba(255,255,255,.25);background:rgba(255,255,255,.09);color:#fff;border-radius:999px;padding:8px 11px;display:flex;align-items:center;gap:6px;font-size:9px;font-weight:800;cursor:pointer}.cf-compare-type button.active{background:#db3564;border-color:#db3564}
.cf-compare-picker{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:12px;position:relative}.cf-compare-picker-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}.cf-compare-picker-head strong,.cf-compare-picker-head span{display:block}.cf-compare-picker-head strong{font-size:11px}.cf-compare-picker-head span{font-size:9px;color:#64748b;margin-top:2px}.cf-compare-picker-head button{border:0;background:#fff1f2;color:#be123c;border-radius:7px;padding:6px 8px;display:flex;gap:5px;align-items:center;font-size:9px;font-weight:800;cursor:pointer}.cf-compare-search{display:flex;align-items:center;gap:7px;border:1px solid #dbe3ee;background:#f8fafc;border-radius:9px;padding:8px 10px}.cf-compare-search input{border:0;outline:0;background:transparent;width:100%;font:inherit;font-size:10px}.cf-compare-results{position:absolute;left:12px;right:12px;top:92px;z-index:20;background:#fff;border:1px solid #dbe3ee;border-radius:10px;box-shadow:0 18px 45px rgba(15,23,42,.15);padding:5px;max-height:300px;overflow:auto}.cf-compare-results button{width:100%;border:0;background:#fff;border-radius:8px;padding:8px;display:flex;align-items:center;justify-content:space-between;text-align:left;cursor:pointer}.cf-compare-results button:hover{background:#f8fafc}.cf-compare-results strong,.cf-compare-results small{display:block}.cf-compare-results strong{font-size:10px}.cf-compare-results small{font-size:8px;color:#64748b;margin-top:2px}.cf-compare-results b{font-size:9px;color:#db3564}
.cf-compare-empty{min-height:260px;border:1px dashed #cbd5e1;border-radius:12px;background:#fff;display:grid;place-items:center;align-content:center;text-align:center;color:#64748b;padding:24px}.cf-compare-empty h3{color:#0f172a;margin:8px 0 3px}.cf-compare-empty p{font-size:10px;margin:0}
.cf-compare-shell{background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}.cf-compare-tabs{display:flex;justify-content:center;gap:34px;padding:14px 14px 0;border-bottom:1px solid #eef2f7}.cf-compare-tabs button{border:0;border-bottom:3px solid transparent;background:transparent;padding:8px 4px 10px;font-size:9px;color:#64748b;cursor:pointer}.cf-compare-tabs button.active{border-color:#db3564;color:#111827;font-weight:850}.cf-compare-controls{display:flex;justify-content:space-between;align-items:end;gap:12px;padding:10px 12px;background:#f8fafc}.cf-compare-controls label{font-size:8px;color:#64748b;font-weight:800}.cf-compare-controls select{display:block;margin-top:4px;border:1px solid #dbe3ee;border-radius:7px;padding:6px 8px;background:#fff;font:inherit;font-size:9px}.cf-compare-controls>span{display:flex;gap:5px;align-items:center;font-size:8px;color:#0f766e;font-weight:800}.cf-compare-scroll{overflow:auto}.cf-compare-grid{display:grid;grid-template-columns:210px repeat(var(--cf-columns),minmax(185px,1fr));min-width:max(900px,100%)}.cf-compare-grid>*{border-right:1px solid #e5e7eb;border-bottom:1px solid #e5e7eb}.cf-compare-sticky{position:sticky;left:0;z-index:4;background:#f8fafc}.cf-compare-label{padding:10px;font-size:8px;text-transform:uppercase;letter-spacing:.05em;color:#64748b;font-weight:850;display:flex;align-items:end}.cf-compare-entity{position:relative;padding:11px 26px 11px 11px;min-height:74px;background:#fff}.cf-compare-entity button{position:absolute;right:6px;top:6px;border:0;background:#f1f5f9;border-radius:999px;width:22px;height:22px;display:grid;place-items:center;color:#64748b;cursor:pointer}.cf-compare-entity strong,.cf-compare-entity small{display:block}.cf-compare-entity strong{font-size:10px;color:#0f172a}.cf-compare-entity small{font-size:7.8px;color:#64748b;line-height:1.4;margin-top:3px}.cf-compare-metric-label{padding:11px}.cf-compare-metric-label strong,.cf-compare-metric-label small{display:block}.cf-compare-metric-label strong{font-size:9.5px;color:#334155}.cf-compare-metric-label small{font-size:7.5px;line-height:1.4;color:#94a3b8;margin-top:2px}.cf-compare-value{padding:10px 11px;background:#fff;min-height:96px}.cf-compare-value>strong{display:block;font-size:21px;color:#0f8b8d;letter-spacing:-.03em}.cf-compare-value small,.cf-compare-value span,.cf-compare-value em{display:block}.cf-compare-value small{font-size:7.5px;color:#64748b;margin-top:2px;min-height:12px}.cf-compare-value span{font-size:8px;color:#64748b;margin-top:6px}.cf-compare-value em{font-size:7.5px;color:#94a3b8;margin-top:3px;font-style:normal}.cf-compare-no-rows{grid-column:1/-1;padding:26px;text-align:center;color:#64748b;font-size:9px}
.cf-flow-compare{border:1px solid #d7e7e6;background:linear-gradient(135deg,#f8ffff,#eefcf8);border-radius:12px;padding:12px}.cf-flow-title{display:flex;justify-content:space-between;gap:12px}.cf-flow-title h3{font-size:12px;margin:0}.cf-flow-title p{font-size:8.5px;color:#64748b;margin:3px 0 0}.cf-flow-title>span{background:#0f8b8d;color:#fff;border-radius:999px;padding:4px 8px;font-size:8px;font-weight:850;align-self:flex-start}.cf-flow-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:8px;margin-top:10px}.cf-flow-cards article{background:#fff;border:1px solid #dce9e8;border-radius:9px;padding:9px}.cf-flow-cards strong,.cf-flow-cards small,.cf-flow-cards b,.cf-flow-cards span{display:block}.cf-flow-cards strong{font-size:9.5px}.cf-flow-cards small{font-size:7.5px;color:#64748b;margin-top:2px}.cf-flow-cards b{font-size:18px;color:#0f8b8d;margin-top:8px}.cf-flow-cards span{font-size:7.8px;color:#64748b;line-height:1.45;margin-top:3px}.cf-compare-authority{font-size:8px;color:#64748b;margin:0 2px}
@media(max-width:760px){.cf-compare-hero{align-items:flex-start;flex-direction:column}.cf-compare-type{width:100%}.cf-compare-type button{flex:1;justify-content:center}.cf-compare-tabs{justify-content:flex-start;overflow:auto;gap:18px}.cf-compare-controls{align-items:flex-start;flex-direction:column}.cf-compare-grid{grid-template-columns:145px repeat(var(--cf-columns),minmax(160px,1fr))}.cf-compare-value>strong{font-size:18px}.cf-compare-results{top:94px}}
`}</style>
 </div>
}
