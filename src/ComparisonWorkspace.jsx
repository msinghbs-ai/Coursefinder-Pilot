import React,{useEffect,useMemo,useState}from'react'
import{Activity,ArrowLeftRight,BarChart3,GraduationCap,Search,Trash2,UsersRound,X}from'lucide-react'
import{adminRead}from'./lib/supabase'
import ProviderLogo from'./ProviderLogo'

const MAX=6
const COMPARE_SELECTION_KEY='coursefinder:compare-selection:v1'
function storedSelection(){try{const x=JSON.parse(localStorage.getItem(COMPARE_SELECTION_KEY)||'null');const type=x?.type==='course'?'course':'provider',ids=Array.isArray(x?.ids)?x.ids.map(String).filter(Boolean).slice(0,MAX):[];return{type,ids}}catch{return{type:'provider',ids:[]}}}
function persistSelection(type,ids){try{localStorage.setItem(COMPARE_SELECTION_KEY,JSON.stringify({type:type==='course'?'course':'provider',ids:[...new Set((ids||[]).map(String).filter(Boolean))].slice(0,MAX)}))}catch{}}
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
function RankingLine({label,series,edition}){
 const row=edition?(series?.history||[]).find(x=>String(x.edition_year)===String(edition)):series?.latest
 return <div className="cf-ranking-line"><span>{label}</span><b>{row?.rank_display||row?.rank_exact||'—'}</b><small>{row?.edition_year?`Edition ${row.edition_year}`:'Not available at selected edition'}</small></div>
}
function RankingTrend({label,series}){
 const history=[...(series?.history||[])].sort((a,b)=>Number(b.edition_year||0)-Number(a.edition_year||0))
 return <div className="cf-ranking-trend"><strong>{label}</strong>{history.length?<div>{history.map(x=><span key={x.edition_year}><small>{x.edition_year}</small><b>{x.rank_display||x.rank_exact||'—'}</b></span>)}</div>:<em>No retained ranking history</em>}</div>
}
function idsFrom(params){return String(params?.get?.('ids')||'').split(',').map(x=>x.trim()).filter(Boolean).slice(0,MAX)}
function routeSelection(params){const routeIds=idsFrom(params),hasIds=!!params?.has?.('ids'),routeType=params?.get?.('type')==='course'?'course':'provider';if(hasIds)return{type:routeType,ids:routeIds};const saved=storedSelection();return saved.ids.length?saved:{type:params?.has?.('type')?routeType:saved.type,ids:[]}}

export default function ComparisonWorkspace({routeParams,navigate,onError}){
 const initialSelection=routeSelection(routeParams),initialType=initialSelection.type
 const[type,setType]=useState(initialType),[ids,setIds]=useState(()=>initialSelection.ids),[query,setQuery]=useState(''),[searchRows,setSearchRows]=useState([]),[searchBusy,setSearchBusy]=useState(false),[providerQuery,setProviderQuery]=useState(''),[providerRows,setProviderRows]=useState([]),[providerBusy,setProviderBusy]=useState(false),[providerId,setProviderId]=useState(''),[providerName,setProviderName]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(false),[category,setCategory]=useState('Current student experience'),[studyLevel,setStudyLevel]=useState(''),[datasets,setDatasets]=useState({qilt:true,prisms:true,qs:false,the:false}),[year,setYear]=useState(''),[rankingSelection,setRankingSelection]=useState({qs:'',the:''}),[viewMode,setViewMode]=useState(idsFrom(routeParams).length===1?'trend':'snapshot')
 useEffect(()=>{const next=routeSelection(routeParams),t=next.type,nextIds=next.ids;setType(t);setIds(nextIds);if(nextIds.length===1)setViewMode('trend');else if(nextIds.length>1)setViewMode('snapshot')},[routeParams])
 useEffect(()=>{persistSelection(type,ids)},[type,ids.join(',')])
 useEffect(()=>{let live=true;if(!ids.length){setData({items:[],total:0});return}setBusy(true);adminRead('contextual_compare',{entity_type:type,ids}).then(x=>live&&setData(x)).catch(e=>onError?.(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[type,ids.join(',')])
 useEffect(()=>{let live=true;if(type!=='course'){setProviderRows([]);return}const q=providerQuery.trim();if(q.length<2){setProviderRows([]);return}const timer=setTimeout(()=>{setProviderBusy(true);adminRead('providers_page',{limit:20,offset:0,query:q,sort:'provider',direction:'asc'}).then(x=>{if(live)setProviderRows(x?.items||[])}).catch(e=>onError?.(e.message)).finally(()=>{if(live)setProviderBusy(false)})},220);return()=>{live=false;clearTimeout(timer)}},[providerQuery,type])
 useEffect(()=>{let live=true;const q=query.trim(),scopedCourse=type==='course'&&providerId;if(q.length<2&&!scopedCourse){setSearchRows([]);return}const timer=setTimeout(()=>{setSearchBusy(true);adminRead(type==='provider'?'providers_page':'courses_page',{limit:20,offset:0,query:q||null,provider_id:scopedCourse?providerId:null,sort:type==='provider'?'provider':'course',direction:'asc'}).then(x=>{if(live)setSearchRows((x?.items||[]).filter(r=>!ids.includes(String(r.id??r.course_id))))}).catch(e=>onError?.(e.message)).finally(()=>{if(live)setSearchBusy(false)})},220);return()=>{live=false;clearTimeout(timer)}},[query,type,ids.join(','),providerId])
 const items=data?.items||[]
 const allOutcomes=useMemo(()=>items.flatMap(e=>(e.contextual_insights?.student_outcomes?.items||[])),[items])
 const levels=useMemo(()=>[...new Set(allOutcomes.map(level).filter(Boolean))].sort(),[allOutcomes])
 const years=useMemo(()=>[...new Set(allOutcomes.flatMap(x=>[x.collection_year_to,x.collection_year_from]).filter(Boolean).map(String))].sort((a,b)=>Number(b)-Number(a)),[allOutcomes])
 const categories=useMemo(()=>['Current student experience','Recent graduate satisfaction','Graduate employment & salary'].filter(g=>allOutcomes.some(x=>groupFor(x)===g)),[allOutcomes])
 const rankingYearsFor=system=>[...new Set(items.flatMap(e=>(e.ranking_context?.[system]?.history||[]).map(x=>String(x.edition_year))))].sort((a,b)=>Number(b)-Number(a))
 const qsRankingYears=useMemo(()=>rankingYearsFor('qs_wur'),[items])
 const theRankingYears=useMemo(()=>rankingYearsFor('the_wur'),[items])
 useEffect(()=>{if(year===''&&years.length)setYear(years[0])},[years.join('|')])
 useEffect(()=>{setRankingSelection(x=>({...x,qs:x.qs&&qsRankingYears.includes(x.qs)?x.qs:(qsRankingYears[0]||''),the:x.the&&theRankingYears.includes(x.the)?x.the:(theRankingYears[0]||'')}))},[qsRankingYears.join('|'),theRankingYears.join('|')])
 const hasQS=items.some(e=>e.ranking_context?.qs_wur?.latest)
 const hasTHE=items.some(e=>e.ranking_context?.the_wur?.latest)
 useEffect(()=>{if(categories.length&&!categories.includes(category))setCategory(categories[0])},[categories.join('|')])
 const rows=useMemo(()=>{
   const map=new Map()
   for(const x of allOutcomes){
     if(groupFor(x)!==category)continue
     if(studyLevel&&level(x)!==studyLevel)continue
     if(viewMode==='snapshot'&&year&&String(x.collection_year_to||x.collection_year_from||'')!==year)continue
     const k=outcomeKey(x)
     if(!map.has(k))map.set(k,x)
   }
   return [...map.values()].sort((a,b)=>String(a.metric_name||'').localeCompare(String(b.metric_name||''))).slice(0,24)
 },[allOutcomes,category,studyLevel,year,viewMode])
 function commitSelection(nextType,nextIds){
  const bounded=[...new Set((nextIds||[]).map(String).filter(Boolean))].slice(0,MAX)
  setType(nextType);setIds(bounded);setData(bounded.length?null:{items:[],total:0})
  navigate?.('Compare',{type:nextType,ids:bounded.join(',')})
 }
 function switchType(next){setQuery('');setSearchRows([]);setProviderQuery('');setProviderRows([]);setProviderId('');setProviderName('');setStudyLevel('');setYear('');setRankingSelection({qs:'',the:''});commitSelection(next,[])}
 function chooseProvider(row){const id=String(row.id||'');if(!id)return;setProviderId(id);setProviderName(row.canonical_name||row.display_name||row.name||'Selected provider');setProviderQuery('');setProviderRows([]);setQuery('');setSearchRows([])}
 function clearProvider(){setProviderId('');setProviderName('');setProviderQuery('');setProviderRows([]);setQuery('');setSearchRows([])}
 function add(row){if(ids.length>=MAX)return;const id=String(row.id??row.course_id??'');if(!id||ids.includes(id))return;setQuery('');setSearchRows([]);commitSelection(type,[...ids,id])}
 function remove(id){commitSelection(type,ids.filter(x=>x!==String(id)))}
 function clear(){setQuery('');setSearchRows([]);persistSelection(type,[]);commitSelection(type,[])}
 return <div className="cf-compare-page">
  <section className="cf-compare-hero">
   <div><span>Layer 1 contextual intelligence</span><h2>Compare {type==='provider'?'providers':'courses'}</h2><p>QILT outcomes and PRISMS student-flow context are aligned only when their source grain, period and study context are compatible.</p></div>
   <div className="cf-compare-type"><button className={type==='provider'?'active':''} onClick={()=>switchType('provider')}><UsersRound size={15}/>Providers</button><button className={type==='course'?'active':''} onClick={()=>switchType('course')}><GraduationCap size={15}/>Courses</button></div>
  </section>

  <section className="cf-compare-picker" data-compare-picker={type}>
   <div className="cf-compare-picker-head"><div><strong>{ids.length} / {MAX} selected</strong><span>Add {type}s to build a like-for-like comparison.</span></div>{ids.length>0&&<button onClick={clear}><Trash2 size={14}/>Clear</button>}</div>
   {type==='course'&&<div className="cf-course-provider-picker">
    <div className="cf-course-provider-label"><span><strong>University / provider</strong><small>Choose any governed provider first, then browse or search its courses.</small></span>{providerId&&<button type="button" onClick={clearProvider}>All providers</button>}</div>
    {providerId?<div className="cf-provider-selected"><ProviderLogo providerId={providerId} name={providerName} size={34}/><span><small>Selected provider</small><strong>{providerName}</strong></span><button type="button" aria-label="Clear selected provider" onClick={clearProvider}><X size={14}/></button></div>:<label className="cf-compare-search provider"><Search size={16}/><input aria-label="Search universities or providers" value={providerQuery} onChange={e=>setProviderQuery(e.target.value)} placeholder="Search university or provider…"/>{providerBusy&&<span className="m-spinner tiny"/>}</label>}
    {providerRows.length>0&&<div className="cf-compare-results provider-results">{providerRows.map(r=><button type="button" key={r.id} onClick={()=>chooseProvider(r)}><span><strong>{r.canonical_name||r.display_name||r.name}</strong><small>{[r.country_code,r.subdivision_name,r.city].filter(Boolean).join(' · ')}</small></span><b>Choose</b></button>)}</div>}
   </div>}
   <label className="cf-compare-search"><Search size={16}/><input aria-label={`Search ${type}s to compare`} value={query} onChange={e=>setQuery(e.target.value)} placeholder={type==='course'?(providerId?`Search courses at ${providerName}…`:'Search course title, code or university…'):`Search ${type}s to compare…`}/>{searchBusy&&<span className="m-spinner tiny"/>}</label>
   {type==='course'&&providerId&&!query.trim()&&<div className="cf-compare-scope-note">Showing the first governed courses for <strong>{providerName}</strong>. Type to narrow the list.</div>}
   {searchRows.length>0&&<div className={`cf-compare-results ${type==='course'?'course-results':''}`}>{searchRows.map(r=><button type="button" key={r.id??r.course_id} disabled={ids.length>=MAX} onClick={()=>add(r)}><span><strong>{r.canonical_name||r.canonical_title||r.name}</strong><small>{type==='course'?[r.provider_name,r.course_code].filter(Boolean).join(' · '):[r.country_code,r.subdivision_name,r.city].filter(Boolean).join(' · ')}</small></span><b>Add +</b></button>)}</div>}
  </section>

  <section className="cf-compare-config">
   <div><strong>2. Choose statistics</strong><span>Current snapshot is the default for multi-provider comparison; use trend mode for retained multi-year history.</span><div className="cf-view-mode"><button className={viewMode==='snapshot'?'active':''} onClick={()=>setViewMode('snapshot')}>Current snapshot</button><button className={viewMode==='trend'?'active':''} onClick={()=>setViewMode('trend')}>Multi-year trend</button></div></div>
   <div className="cf-dataset-toggles cf-dataset-toggles-with-years">
    <button className={datasets.qilt?'active':''} onClick={()=>setDatasets(x=>({...x,qilt:!x.qilt}))}>QILT</button>
    <button className={datasets.prisms?'active':''} onClick={()=>setDatasets(x=>({...x,prisms:!x.prisms}))}>PRISMS</button>
    <div className={`cf-ranking-toggle ${datasets.qs?'active':''} ${!hasQS?'disabled':''}`}><button disabled={!hasQS} className={datasets.qs?'active':''} onClick={()=>setDatasets(x=>({...x,qs:!x.qs}))}>{hasQS?'QS':'QS · unavailable'}</button>{hasQS&&<label>Edition<select aria-label="QS ranking edition" value={rankingSelection.qs||qsRankingYears[0]||''} onChange={e=>setRankingSelection(x=>({...x,qs:e.target.value}))}><option value="multi">Multi-year</option>{qsRankingYears.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label>}</div>
    <div className={`cf-ranking-toggle ${datasets.the?'active':''} ${!hasTHE?'disabled':''}`}><button disabled={!hasTHE} className={datasets.the?'active':''} onClick={()=>setDatasets(x=>({...x,the:!x.the}))}>{hasTHE?'THE':'THE · unavailable'}</button>{hasTHE&&<label>Edition<select aria-label="THE ranking edition" value={rankingSelection.the||theRankingYears[0]||''} onChange={e=>setRankingSelection(x=>({...x,the:e.target.value}))}><option value="multi">Multi-year</option>{theRankingYears.map((y,i)=><option key={y} value={y}>{y}{i===0?' · latest':''}</option>)}</select></label>}</div>
   </div>
   {viewMode==='snapshot'?<label>3. QILT year<select value={year} onChange={e=>setYear(e.target.value)}>{years.map((y,i)=><option key={y} value={y}>{y}{i===0?' · current':''}</option>)}</select></label>:<div className="cf-trend-note"><strong>Multi-year QILT</strong><span>Retained year-specific metric rows are shown together; narrow with category and study level.</span></div>}
  </section>

  {!ids.length?<section className="cf-compare-empty"><ArrowLeftRight size={32}/><h3>Select up to six {type}s</h3><p>Search above, or open a {type} detail blade and choose Compare.</p></section>:busy&&!data?<section className="cf-compare-empty"><span className="m-spinner"/><p>Loading governed comparison…</p></section>:<>
   {datasets.qilt&&<section className="cf-compare-shell">
    <div className="cf-compare-tabs">{categories.map(x=><button key={x} className={category===x?'active':''} onClick={()=>setCategory(x)}>{x}</button>)}</div>
    <div className="cf-compare-controls"><label>Study level<select value={studyLevel} onChange={e=>setStudyLevel(e.target.value)}><option value="">All available levels</option>{levels.map(x=><option key={x} value={x}>{x}</option>)}</select></label><span><BarChart3 size={13}/>Like-for-like QILT rows only</span></div>
    <div className="cf-compare-scroll">
     <div className="cf-compare-grid" style={{'--cf-columns':Math.max(items.length,1)}}>
      <div className="cf-compare-label cf-compare-sticky cf-compare-top-sticky cf-compare-corner-sticky">Selected</div>
      {items.map(e=>{const logoProviderId=type==='provider'?e.id:e.provider_id;const logoName=type==='provider'?e.name:e.provider_name;return <article className="cf-compare-entity cf-compare-top-sticky" key={e.id}><button aria-label="Remove from comparison" onClick={()=>remove(e.id)}><X size={13}/></button><div className="cf-compare-entity-head"><ProviderLogo providerId={logoProviderId} name={logoName} size={42}/><span><strong>{e.name}</strong><small>{type==='course'?[e.provider_name,e.course_code,e.study_level].filter(Boolean).join(' · '):[e.country_code,e.subdivision,e.city].filter(Boolean).join(' · ')}</small></span></div></article>})}
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
   </section>}

   {datasets.prisms&&<section className="cf-flow-compare">
    <div className="cf-flow-title"><div><h3>International student flow</h3><p>PRISMS context retains Provider / geography / study-area / cohort grain and is never promoted to a Course outcome.</p></div><span>PRISMS</span></div>
    <div className="cf-flow-cards">{items.map(e=>{const g=e.contextual_insights?.student_flow||{},xs=g.items||[],x=xs.find(z=>!z.is_suppressed&&num(z.metric_value)!=null)||xs[0],logoProviderId=type==='provider'?e.id:e.provider_id,logoName=type==='provider'?e.name:e.provider_name;return <article key={e.id}><div className="cf-compare-entity-head"><ProviderLogo providerId={logoProviderId} name={logoName} size={34}/><span><strong>{e.name}</strong><small>{human(g.relationship_state||'not available')} · {human(g.granularity||'none')}</small></span></div><b>{x?.is_suppressed?'Suppressed':x?fmtNumber(x.metric_value):'—'}</b><span>{x?[x.metric_name||x.metric_code,x.subdivision,x.study_area,x.period_end].filter(Boolean).join(' · '):'No governed student-flow observation related at the accepted grain.'}</span></article>})}</div>
   </section>}

   {(datasets.qs||datasets.the)&&<section className="cf-flow-compare">
    <div className="cf-flow-title"><div><h3>Institutional world rankings</h3><p>QS and THE remain independent. Each enabled ranking uses its own edition selector; choose Multi-year only for that ranking when required.</p></div><span>Rankings</span></div>
    <div className="cf-flow-cards">{items.map(e=><article key={e.id}><strong>{e.name}</strong>
      {datasets.qs&&(rankingSelection.qs==='multi'?<RankingTrend label="QS" series={e.ranking_context?.qs_wur}/>:<RankingLine label="QS" series={e.ranking_context?.qs_wur} edition={rankingSelection.qs}/>)}
      {datasets.the&&(rankingSelection.the==='multi'?<RankingTrend label="THE" series={e.ranking_context?.the_wur}/>:<RankingLine label="THE" series={e.ranking_context?.the_wur} edition={rankingSelection.the}/>)}
    </article>)}</div>
   </section>}
   {!datasets.qilt&&!datasets.prisms&&!datasets.qs&&!datasets.the&&<section className="cf-compare-empty"><BarChart3 size={28}/><h3>Select at least one available dataset</h3><p>Only datasets with governed observations are selectable.</p></section>}
   <p className="cf-compare-authority">{data?.authority_note}</p>
  </>}

  <style>{`
.cf-compare-page{display:grid;gap:12px}.cf-compare-hero{border-radius:13px;background:#172033;color:#fff;border:1px solid #25324a;box-shadow:0 2px 10px rgba(15,23,42,.12);padding:18px 24px;display:flex;justify-content:space-between;gap:20px;align-items:center}.cf-compare-hero span{font-size:9px;text-transform:uppercase;letter-spacing:.1em;color:#a5b4fc;font-weight:850}.cf-compare-hero h2{font-size:24px;line-height:1.2;margin:3px 0}.cf-compare-hero p{font-size:10px;line-height:1.5;color:#cbd5e1;max-width:760px;margin:0}.cf-compare-type{display:flex;gap:6px}.cf-compare-type button{border:1px solid #334155;background:#25324a;color:#fff;border-radius:8px;padding:8px 11px;display:flex;align-items:center;gap:6px;font-size:9px;font-weight:800;cursor:pointer}.cf-compare-type button:hover{background:#2d3a52}.cf-compare-type button.active{background:#5b5ce2;border-color:#6d6ee8}
.cf-compare-config{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:12px;display:grid;grid-template-columns:minmax(190px,1fr) minmax(260px,2fr) minmax(200px,1fr);gap:14px;align-items:end}.cf-compare-config>div>strong,.cf-compare-config>div>span{display:block}.cf-compare-config>div>strong{font-size:10px}.cf-compare-config>div>span{font-size:8px;color:#64748b;margin-top:2px}.cf-view-mode{display:flex;gap:5px;margin-top:8px}.cf-view-mode button{border:1px solid #dbe3ee;background:#fff;border-radius:7px;padding:6px 8px;font-size:8px;font-weight:800;cursor:pointer}.cf-view-mode button.active{background:#eef2ff;border-color:#a5b4fc;color:#3730a3}.cf-trend-note{border:1px solid #e2e8f0;border-radius:8px;background:#f8fafc;padding:7px 8px}.cf-trend-note strong,.cf-trend-note span{display:block}.cf-trend-note strong{font-size:8.5px}.cf-trend-note span{font-size:7.5px;color:#64748b;margin-top:2px}.cf-dataset-toggles{display:flex;gap:6px;flex-wrap:wrap}.cf-dataset-toggles button{border:1px solid #dbe3ee;background:#fff;border-radius:999px;padding:7px 10px;font-size:8.5px;font-weight:850;cursor:pointer}.cf-dataset-toggles button.active{background:#172554;color:#fff;border-color:#172554}.cf-dataset-toggles button:disabled{opacity:.48;cursor:not-allowed}.cf-dataset-toggles-with-years{align-items:flex-start}.cf-ranking-toggle{display:grid;gap:5px;min-width:112px;padding:5px;border:1px solid #e2e8f0;border-radius:10px;background:#f8fafc}.cf-ranking-toggle.active{border-color:#a5b4fc;background:#eef2ff}.cf-ranking-toggle.disabled{opacity:.55}.cf-ranking-toggle>button{width:100%}.cf-ranking-toggle label{font-size:7px!important;color:#64748b!important}.cf-ranking-toggle select{margin-top:2px!important;padding:5px 6px!important;font-size:8px!important;background:#fff}.cf-compare-config label{font-size:8px;color:#64748b;font-weight:800}.cf-compare-config select{display:block;width:100%;margin-top:4px;border:1px solid #dbe3ee;border-radius:7px;padding:7px 8px;background:#fff;font:inherit;font-size:9px}
.cf-compare-picker{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:12px;position:relative}.cf-course-provider-picker{position:relative;margin-bottom:9px;padding-bottom:9px;border-bottom:1px solid #eef2f7}.cf-course-provider-label{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:6px}.cf-course-provider-label span,.cf-course-provider-label strong,.cf-course-provider-label small{display:block}.cf-course-provider-label strong{font-size:9px;color:#334155}.cf-course-provider-label small{font-size:8px;color:#64748b;margin-top:1px}.cf-course-provider-label>button{border:0;background:#eef2ff;color:#4338ca;border-radius:7px;padding:6px 8px;font-size:8px;font-weight:800;cursor:pointer}.cf-provider-selected{display:flex;align-items:center;gap:8px;border:1px solid #c7d2fe;background:#eef2ff;border-radius:9px;padding:8px 10px;color:#3730a3}.cf-provider-selected>span{display:grid;gap:1px;flex:1}.cf-provider-selected small{font-size:7px;color:#6366f1}.cf-provider-selected strong{font-size:10px;color:#312e81}.cf-provider-selected>button{border:0;background:transparent;color:#6366f1;display:grid;place-items:center;cursor:pointer}.cf-compare-search.provider{background:#fff}.cf-compare-results.provider-results{top:66px;z-index:30}.cf-compare-results.course-results{position:relative;left:auto;right:auto;top:auto;margin-top:5px;max-height:280px}.cf-compare-scope-note{font-size:8px;color:#64748b;padding:6px 2px 0}.cf-compare-scope-note strong{color:#334155}.cf-compare-picker-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}.cf-compare-picker-head strong,.cf-compare-picker-head span{display:block}.cf-compare-picker-head strong{font-size:11px}.cf-compare-picker-head span{font-size:9px;color:#64748b;margin-top:2px}.cf-compare-picker-head button{border:0;background:#fff1f2;color:#be123c;border-radius:7px;padding:6px 8px;display:flex;gap:5px;align-items:center;font-size:9px;font-weight:800;cursor:pointer}.cf-compare-search{display:flex;align-items:center;gap:7px;border:1px solid #dbe3ee;background:#f8fafc;border-radius:9px;padding:8px 10px}.cf-compare-search input{border:0;outline:0;background:transparent;width:100%;font:inherit;font-size:10px}.cf-compare-results{position:absolute;left:12px;right:12px;top:92px;z-index:20;background:#fff;border:1px solid #dbe3ee;border-radius:10px;box-shadow:0 18px 45px rgba(15,23,42,.15);padding:5px;max-height:300px;overflow:auto}.cf-compare-results button{width:100%;border:0;background:#fff;border-radius:8px;padding:8px;display:flex;align-items:center;justify-content:space-between;text-align:left;cursor:pointer}.cf-compare-results button:hover{background:#f8fafc}.cf-compare-results strong,.cf-compare-results small{display:block}.cf-compare-results strong{font-size:10px}.cf-compare-results small{font-size:8px;color:#64748b;margin-top:2px}.cf-compare-results b{font-size:9px;color:#5b5ce2}
.cf-compare-empty{min-height:260px;border:1px dashed #cbd5e1;border-radius:12px;background:#fff;display:grid;place-items:center;align-content:center;text-align:center;color:#64748b;padding:24px}.cf-compare-empty h3{color:#0f172a;margin:8px 0 3px}.cf-compare-empty p{font-size:10px;margin:0}
.cf-compare-shell{background:#fff;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}.cf-compare-tabs{display:flex;justify-content:center;gap:34px;padding:14px 14px 0;border-bottom:1px solid #eef2f7}.cf-compare-tabs button{border:0;border-bottom:3px solid transparent;background:transparent;padding:8px 4px 10px;font-size:9px;color:#64748b;cursor:pointer}.cf-compare-tabs button.active{border-color:#5b5ce2;color:#111827;font-weight:850}.cf-compare-controls{display:flex;justify-content:space-between;align-items:end;gap:12px;padding:10px 12px;background:#f8fafc}.cf-compare-controls label{font-size:8px;color:#64748b;font-weight:800}.cf-compare-controls select{display:block;margin-top:4px;border:1px solid #dbe3ee;border-radius:7px;padding:6px 8px;background:#fff;font:inherit;font-size:9px}.cf-compare-controls>span{display:flex;gap:5px;align-items:center;font-size:8px;color:#0f766e;font-weight:800}.cf-compare-scroll{overflow:auto;max-height:min(68vh,720px);position:relative;scrollbar-gutter:stable}.cf-compare-grid{display:grid;grid-template-columns:210px repeat(var(--cf-columns),minmax(185px,1fr));min-width:max(900px,100%)}.cf-compare-grid>*{border-right:1px solid #e5e7eb;border-bottom:1px solid #e5e7eb}.cf-compare-sticky{position:sticky;left:0;z-index:4;background:#f8fafc}.cf-compare-top-sticky{position:sticky;top:0;z-index:7;background:#fff;box-shadow:0 1px 0 #e5e7eb,0 5px 12px rgba(15,23,42,.04)}.cf-compare-corner-sticky{left:0;z-index:9;background:#f8fafc}.cf-compare-label{padding:10px;font-size:8px;text-transform:uppercase;letter-spacing:.05em;color:#64748b;font-weight:850;display:flex;align-items:end}.cf-compare-entity{position:relative;padding:11px 26px 11px 11px;min-height:74px;background:#fff}.cf-compare-top-sticky .cf-compare-entity-head{min-height:42px;align-items:center}.cf-compare-entity button{position:absolute;right:6px;top:6px;border:0;background:#f1f5f9;border-radius:999px;width:22px;height:22px;display:grid;place-items:center;color:#64748b;cursor:pointer}.cf-compare-entity strong,.cf-compare-entity small{display:block}.cf-compare-entity strong{font-size:10px;color:#0f172a}.cf-compare-entity small{font-size:7.8px;color:#64748b;line-height:1.4;margin-top:3px}.cf-compare-metric-label{padding:11px}.cf-compare-metric-label strong,.cf-compare-metric-label small{display:block}.cf-compare-metric-label strong{font-size:9.5px;color:#334155}.cf-compare-metric-label small{font-size:7.5px;line-height:1.4;color:#94a3b8;margin-top:2px}.cf-compare-value{padding:10px 11px;background:#fff;min-height:96px}.cf-compare-value>strong{display:block;font-size:21px;color:#0f8b8d;letter-spacing:-.03em}.cf-compare-value small,.cf-compare-value span,.cf-compare-value em{display:block}.cf-compare-value small{font-size:7.5px;color:#64748b;margin-top:2px;min-height:12px}.cf-compare-value span{font-size:8px;color:#64748b;margin-top:6px}.cf-compare-value em{font-size:7.5px;color:#94a3b8;margin-top:3px;font-style:normal}.cf-compare-no-rows{grid-column:1/-1;padding:26px;text-align:center;color:#64748b;font-size:9px}
.cf-flow-compare{border:1px solid #d7e7e6;background:linear-gradient(135deg,#f8ffff,#eefcf8);border-radius:12px;padding:12px}.cf-flow-title{display:flex;justify-content:space-between;gap:12px}.cf-flow-title h3{font-size:12px;margin:0}.cf-flow-title p{font-size:8.5px;color:#64748b;margin:3px 0 0}.cf-flow-title>span{background:#0f8b8d;color:#fff;border-radius:999px;padding:4px 8px;font-size:8px;font-weight:850;align-self:flex-start}.cf-flow-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:8px;margin-top:10px}.cf-flow-cards article{background:#fff;border:1px solid #dce9e8;border-radius:9px;padding:9px}.cf-flow-cards strong,.cf-flow-cards small,.cf-flow-cards b,.cf-flow-cards span{display:block}.cf-flow-cards strong{font-size:9.5px}.cf-flow-cards small{font-size:7.5px;color:#64748b;margin-top:2px}.cf-flow-cards b{font-size:18px;color:#0f8b8d;margin-top:8px}.cf-flow-cards span{font-size:7.8px;color:#64748b;line-height:1.45;margin-top:3px}.cf-ranking-line{display:grid;grid-template-columns:42px 1fr;gap:2px 8px;align-items:center;margin-top:8px;padding-top:8px;border-top:1px solid #e5e7eb}.cf-ranking-line>span{font-size:8px;font-weight:850;color:#334155}.cf-ranking-line>b{font-size:17px;color:#172554}.cf-ranking-line>small{grid-column:2;font-size:7.5px;color:#64748b}.cf-ranking-trend{margin-top:8px;padding-top:8px;border-top:1px solid #e5e7eb}.cf-ranking-trend>strong{font-size:8px;color:#334155}.cf-ranking-trend>div{display:flex;gap:5px;flex-wrap:wrap;margin-top:5px}.cf-ranking-trend>div>span{display:grid;gap:2px;min-width:54px;border:1px solid #e2e8f0;border-radius:6px;padding:5px;background:#f8fafc}.cf-ranking-trend small{font-size:7px;color:#64748b}.cf-ranking-trend b{font-size:12px!important;color:#172554!important;margin:0!important}.cf-ranking-trend em{font-size:7.5px;color:#94a3b8;font-style:normal}.cf-compare-authority{font-size:8px;color:#64748b;margin:0 2px}
@media(max-width:900px){.cf-compare-config{grid-template-columns:1fr 1fr}.cf-compare-config>div:first-child{grid-column:1/-1}}@media(max-width:760px){.cf-compare-config{grid-template-columns:1fr}.cf-compare-config>div:first-child{grid-column:auto}.cf-compare-hero{align-items:flex-start;flex-direction:column}.cf-compare-type{width:100%}.cf-compare-type button{flex:1;justify-content:center}.cf-compare-tabs{justify-content:flex-start;overflow:auto;gap:18px}.cf-compare-controls{align-items:flex-start;flex-direction:column}.cf-compare-grid{grid-template-columns:145px repeat(var(--cf-columns),minmax(160px,1fr))}.cf-compare-value>strong{font-size:18px}.cf-compare-results{top:94px}}
`}</style>
 </div>
}
