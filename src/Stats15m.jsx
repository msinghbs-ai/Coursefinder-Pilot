// Platform health › Work queues › Last 15 minutes (v2.15.320, Platform Admin 22 Oct 2026 21:57: "Give me stat's and toolset usuage every
// 15 minutes. Keep the lesson learnt and find gaps quickly"). Job stats-15m takes a snapshot every 15 minutes; server
// public.admin_stats_15m() gives the latest one and the fields held per country over the last stats.trend_hours hours.
import React,{useEffect,useState}from'react'
import{AlertTriangle,Gauge,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'

export const STAT_FIELDS=[['official_page','Official page'],['fee','Fee'],['english','English'],['intakes','Intakes'],['campus','Campus'],['delivery','Delivery'],['duration','Duration'],['level','Level'],['field_of_study','Field of study']]
const pct=(n,d)=>d?`${Math.round(n*1000/d)/10}%`:'—'
const signed=v=>v>0?`+${fmtNumber(v)}`:v<0?`−${fmtNumber(-v)}`:'0'
const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals

export default function Stats15m({onError}){
  const[d,setD]=useState(null)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_stats_15m');if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e));setD({})}}
  useEffect(()=>{load();const t=setInterval(load,300000);return()=>clearInterval(t)},[])
  if(!d)return <section className="m-panel"><Loading label="Reading the 15-minute stats…"/></section>
  const s=d.latest
  if(!s)return <section className="m-panel"><Empty text="No 15-minute snapshot yet (job stats-15m)."/></section>
  const countries=Object.entries(s.countries||{})
  const fc=s.firecrawl||{},calls=Object.entries(s.worker_calls_15m||{}).sort((a,b)=>b[1].calls-a[1].calls)
  const ai=(s.ai||[]).filter(a=>Number(a.spent_usd||0)>0)
  return <section className="m-panel" data-stats-15m>
    <SectionTitle icon={Gauge} title="Last 15 minutes" subtitle={`Snapshot ${fmtDateTime(s.at)} · taken every 15 minutes; the change is against the snapshot before and the same time yesterday.`} action={<Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>}/>
    {(s.gaps||[]).length>0&&<div className="st-gaps" role="status"><strong><AlertTriangle size={14}/> Gaps found ({fmtNumber(s.gaps.length)})</strong><ul>{s.gaps.map((g,i)=><li key={i}>{g.note}</li>)}</ul></div>}
    <div className="cf-table-wrap"><table className="cf-table st-table"><thead><tr><th>Field</th>{countries.map(([c,v])=><th key={c} className="num">{c} · {fmtNumber(v.now?.courses||0)} courses</th>)}</tr></thead><tbody>
      {STAT_FIELDS.map(([k,label])=><tr key={k}><td>{label}</td>{countries.map(([c,v])=>{const n=Number(v.now?.[k]||0),m=Number(v.change_15m?.[k]||0),day=v.change_24h?Number(v.change_24h[k]||0):null
        return <td key={c} className="num"><strong>{fmtNumber(n)}</strong> <span className="st-pct">{pct(n,Number(v.now?.courses||0))}</span><small className="st-chg">15 min {signed(m)}{day!=null?` · 24 h ${signed(day)}`:''}</small></td>})}</tr>)}
    </tbody></table></div>
    <div className="st-grid">
      <div><h4>Firecrawl</h4><p>Today {fmtNumber(fc.used_today||0)} of {fmtNumber(fc.total||0)} units</p><ul>{(fc.groups||[]).map(g=><li key={g.group}>{g.label}: {fmtNumber(g.used)} of {fmtNumber(g.share)}{g.refused?` · ${fmtNumber(g.refused)} refused`:''}{fc.last_15m?.[g.group]?` · ${fmtNumber(fc.last_15m[g.group])} in 15 min`:''}</li>)}</ul></div>
      <div><h4>AI today</h4>{ai.length?<ul>{ai.map(a=><li key={a.use}>{a.label}: US${Number(a.spent_usd).toFixed(2)} of {a.guard_usd?`US$${a.guard_usd}`:'no guard'} · {fmtNumber(a.calls)} calls</li>)}</ul>:<p>No AI spend today.</p>}</div>
      <div><h4>Worker calls, 15 min</h4>{calls.length?<ul>{calls.map(([m,v])=><li key={m}>{m}: {fmtNumber(v.calls)}{v.failed?` · ${fmtNumber(v.failed)} failed`:''}{v.avg_s!=null?` · ${v.avg_s} s avg, ${v.max_s} s max`:''}</li>)}</ul>:<p>No calls.</p>}</div>
      <div><h4>Tasks</h4><p>{fmtNumber(s.tasks?.running||0)} running · {fmtNumber(s.tasks?.queued||0)} queued · {fmtNumber(s.tasks?.not_moving||0)} not moving for an hour</p></div>
    </div>
  </section>
}
