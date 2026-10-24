// Platform health › Work queues › Why values are missing (v2.15.325, Platform Admin 23 Oct 2026 10:25: "cross check the gaps and
// accommodate the ai reader requiement. What is point of hourly reporting if you are not finding gaps and making the platform self
// sufficient"). Job gap-causes takes an hourly snapshot: for every active course and attribute, why the value is missing (the first
// cause that applies) and what the platform does about it. "Needs a change" means nothing automatic covers that cause.
// Server: public.admin_gap_causes(country).
import React,{useEffect,useMemo,useState}from'react'
import{SearchX,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'

export const GAP_ATTRS=[['official_page','Official page'],['fee','Fee'],['english','English'],['intakes','Intakes'],['campus','Campus'],['campus_region','Campus region'],['duration','Duration'],['delivery','Delivery'],['level','Level'],['field_of_study','Field of study'],['international','Open to international']]
const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const signed=v=>v>0?`+${fmtNumber(v)}`:v<0?`−${fmtNumber(-v)}`:''

export default function GapCauses({onError}){
  const[d,setD]=useState(null),[cc,setCc]=useState('NZ'),[attr,setAttr]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_gap_causes',{p_country:null});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e));setD({})}}
  useEffect(()=>{load()},[])
  const rows=useMemo(()=>(d?.rows||[]).filter(r=>r.country===cc&&(!attr||r.attribute===attr)),[d,cc,attr])
  const manual=useMemo(()=>(d?.rows||[]).filter(r=>r.country===cc&&!r.automatic).sort((a,b)=>b.courses-a.courses),[d,cc])
  if(!d)return <section className="m-panel"><Loading label="Reading why values are missing…"/></section>
  if(!d.at)return <section className="m-panel"><Empty text="No snapshot yet (job gap-causes, every hour at :55)."/></section>
  const label=a=>GAP_ATTRS.find(x=>x[0]===a)?.[1]||a
  return <section className="m-panel" data-gap-causes>
    <SectionTitle icon={SearchX} title="Why values are missing" subtitle={`Snapshot ${fmtDateTime(d.at)} · every hour. For each attribute: how many courses miss it, why, and what the platform does about it. "Needs a change" means nothing automatic covers that cause.`} action={<Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>}/>
    <div className="ef-row">
      <select className="fv-filter" aria-label="Country" value={cc} onChange={e=>setCc(e.target.value)}>{(d.countries||[]).map(c=><option key={c} value={c}>{c}</option>)}</select>
      <select className="fv-filter" aria-label="Attribute" value={attr} onChange={e=>setAttr(e.target.value)}><option value="">All attributes</option>{GAP_ATTRS.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
    </div>
    {manual.length>0&&<div className="st-gaps" role="status" data-gap-manual><strong>Needs a change ({fmtNumber(manual.reduce((n,r)=>n+r.courses,0))} course values)</strong><ul>{manual.slice(0,8).map((r,i)=><li key={i}>{label(r.attribute)}: {r.cause} · {fmtNumber(r.courses)} · {r.action}</li>)}</ul></div>}
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Attribute</th><th>Why it is missing</th><th className="num">Courses</th><th>What the platform does</th></tr></thead><tbody>
      {rows.map((r,i)=><tr key={i}><td>{label(r.attribute)}</td><td>{r.cause}</td><td className="num">{fmtNumber(r.courses)} <small className="st-chg">{signed(r.change)}</small></td>
        <td>{r.automatic?r.action:<StatusChip value="manual" tone="warning" label={`Needs a change · ${r.action}`}/>}</td></tr>)}
    </tbody></table></div>
  </section>
}
