import './ui-kit.css'
// Coverage & completeness › Courses, top (v2.16.42, Platform Admin 18 Nov 2026 12:19: "metadata-driven tracked-field registry with no hardcoded
// 15-attribute ceiling"). Everything here comes from public.admin_coverage_telemetry_v1 (migration 20261118170000), which reads
// pipeline.field_coverage_daily and the registry pipeline.tracked_fields: a field recorded daily appears without a code change (under its code,
// marked Not labelled, until it has a registry row). Three parts:
//   1. Readiness: countries (AU, NZ, CA, UK, IE, US first) by domain, the share of values held, one blue scale (darker = fuller).
//   2. Courses by fields admitted: 0 of N to N of N, N = the registry's in-score fields.
//   3. Every field: a bar against its target, the change over coverage.velocity_days and a trend line over coverage.spark_days. A link to
//      act appears only where the field is below its target (Layer 4 › Inbox, Platform health › Queues & yield, ...). This replaces the Link
//      refresh supply rows and the Stalled fields counters.
// Until the read is live (its migration is S2-Build's to apply: Platform Admin 18 Nov 2026 14:23, no schema change in this lane) the screen
// falls back to public.admin_completeness_report: the latest fill of every recorded field by country, grouped into the same domains. The
// change, trend, targets and the fields-admitted bands say they are waiting for the read.
import React,{useEffect,useMemo,useState}from'react'
import{supabase}from'../lib/supabase'
import{Badge,Empty,Loading,SectionTitle,fmtNumber}from'./kit.jsx'
import{fmtDate}from'../lib/format.js'
import{plainError}from'../lib/errors'
export const COUNTRY_NAMES={AU:'Australia',NZ:'New Zealand',CA:'Canada',GB:'United Kingdom',IE:'Ireland',US:'United States'}
export const heat=p=>p==null?'none':p>=80?'4':p>=60?'3':p>=40?'2':p>=20?'1':'0'
const pct=p=>p==null?'—':`${Number(p).toFixed(1)}%`
export const delta=(now,then)=>now==null||then==null?null:Math.round((Number(now)-Number(then))*10)/10
// the domain of a recorded field when the registry is not readable (fallback only): by its code
export const DOMAIN_ORDER=[['courses','Courses'],['providers','Providers & campuses'],['aer','AER & grade scales'],['scholarships','Scholarships'],['destinations','Destination editions']]
export const domainOf=f=>/^(academic_entry|p_entry_matrix|v3_grade|g_)/.test(f)?'aer':/^(s_|p_scholarships)/.test(f)?'scholarships':/^(d_|v3_destination)/.test(f)?'destinations':/^(p_|v3_campus|v3_accred)/.test(f)?'providers':'courses'
export const LAUNCH=['AU','NZ','CA','GB','IE','US']
export function fromReport(r){
  const by={},grid={}
  for(const c of r?.cells||[])for(const f of c.fields||[]){const x=by[f.field]||(by[f.field]={field:f.field,label:f.label||f.field,unlabelled:!f.label||f.label===f.field,domain:domainOf(f.field),total:0,filled:0,pts:null,pct_then:null,target_pct:null})
    x.total+=Number(f.total||0);x.filled+=Number(f.filled||0);const g=grid[`${c.country_code}:${x.domain}`]||(grid[`${c.country_code}:${x.domain}`]={country:c.country_code,domain:x.domain,total:0,filled:0,fields:0});g.total+=Number(f.total||0);g.filled+=Number(f.filled||0);g.fields+=1}
  const pc=(a,b)=>b>0?Math.round(1000*a/b)/10:null
  const countries=[...LAUNCH,...(r?.countries||[]).filter(c=>!LAUNCH.includes(c))]
  return{fallback:true,day:r?.snapshot_date,countries,domains:DOMAIN_ORDER.map(([code,label])=>({code,label})),fields:Object.values(by).map(x=>({...x,pct:pc(x.filled,x.total)})).sort((a,b)=>a.field.localeCompare(b.field)),
    grid:Object.values(grid).map(g=>({...g,pct:pc(g.filled,g.total)})),score:null,unlabelled:Object.values(by).filter(x=>x.unlabelled).length}
}
const signed=d=>d==null?'no earlier figure':d===0?'no change':`${d>0?'+':'−'}${Math.abs(d).toFixed(1)} pts`

function Spark({pts,label}){
  const xs=(pts||[]).filter(p=>p.pct!=null)
  if(xs.length<2)return <span className="ui-ct-spark-empty" aria-hidden="true">·</span>
  const w=72,h=20,min=Math.min(...xs.map(p=>p.pct)),max=Math.max(...xs.map(p=>p.pct)),span=Math.max(1,max-min)
  const pt=(p,i)=>`${(i/(xs.length-1)*(w-4)+2).toFixed(1)},${(h-2-(p.pct-min)/span*(h-4)).toFixed(1)}`
  return <svg className="ui-ct-spark" width={w} height={h} viewBox={`0 0 ${w} ${h}`} role="img" aria-label={`${label}: ${xs.map(p=>`${fmtDate(p.day)} ${pct(p.pct)}`).join(', ')}`}>
    <title>{xs.map(p=>`${fmtDate(p.day)}: ${pct(p.pct)}`).join('\n')}</title>
    <polyline points={xs.map(pt).join(' ')}/><circle cx={pt(xs[xs.length-1],xs.length-1).split(',')[0]} cy={pt(xs[xs.length-1],xs.length-1).split(',')[1]} r="2"/></svg>
}

export default function CoverageTelemetry({onError}){
  const[d,setD]=useState(null),[country,setCountry]=useState(''),[below,setBelow]=useState(false),[table,setTable]=useState(false)
  useEffect(()=>{let live=true;setD(null);(async()=>{
    const ok=x=>x&&typeof x==='object'&&!Array.isArray(x)
    const{data,error}=await supabase.rpc('admin_coverage_telemetry_v1',{p_args:country?{country}:{}})
    if(!error&&ok(data)&&Array.isArray(data.fields)){if(live)setD(data);return}
    // the read is not live yet: the completeness report (every recorded field by country, latest day)
    const r=await supabase.rpc('admin_completeness_report',{})
    if(!live)return
    if(r.error||!ok(r.data)){onError?.(plainError(r.error||error||{message:'Coverage could not be read.'}));setD({});return}
    const fb=fromReport(r.data);setD(country?{...fb,grid:fb.grid.filter(g=>g.country===country)}:fb)})().catch(e=>{if(live){onError?.(plainError(e));setD({})}});return()=>{live=false}},[country])
  const fields=d?.fields||[],domains=d?.domains||[],grid=d?.grid||[],score=d?.score||{},bands=score.bands||[]
  const cell=useMemo(()=>Object.fromEntries(grid.map(g=>[`${g.country}:${g.domain}`,g])),[grid])
  const maxBand=Math.max(1,...bands.map(b=>Number(b.courses||0))) // bands are [] until the read is live
  if(!d)return <section className="ui-card" data-coverage-telemetry><Loading label="Reading coverage…"/></section>
  if(!fields.length)return <section className="ui-card" data-coverage-telemetry><Empty text="No coverage has been recorded yet."/></section>
  const vel=d.velocity_days||7,shown=fields.filter(f=>!below||(f.pct!=null&&f.target_pct!=null&&f.pct<f.target_pct))
  return <div className="ui-stack" data-coverage-telemetry>
    <section className="ui-card ui-ct-head">
      <SectionTitle title="Coverage now" subtitle={`Recorded every hour; figures for ${d.day?fmtDate(d.day):'today'}.${d.fallback?'':` Change is against ${d.then?fmtDate(d.then):`${vel} days earlier`}.`}`} action={<div className="ui-l3c-actions">
        <select className="ui-filterbar" value={country} onChange={e=>setCountry(e.target.value)} aria-label="Country" data-ct-country><option value="">All countries</option>{(d.countries||[]).map(c=><option key={c} value={c}>{COUNTRY_NAMES[c]||c}</option>)}</select>
        <label className="ui-fcc-only"><input type="checkbox" checked={below} onChange={e=>setBelow(e.target.checked)} data-ct-below/> Below target only</label></div>}/>
    </section>

    <section className="ui-card" data-ct-grid>
      <SectionTitle title="Readiness by country" subtitle="The share of values held across each domain's fields. Darker is fuller; Not started means nothing is recorded for that country yet."/>
      <div className="ui-tablewrap"><table className="ui-table ui-ct-grid"><thead><tr><th>Country</th>{domains.map(x=><th key={x.code}>{x.label}</th>)}</tr></thead><tbody>
        {(d.countries||[]).map(c=><tr key={c} data-ct-row={c}><td><strong>{COUNTRY_NAMES[c]||c}</strong></td>{domains.map(x=>{const g=cell[`${c}:${x.code}`],p=g?.pct??null
          return <td key={x.code} className={`ui-ct-cell ui-ct-heat-${g?heat(p):'none'}`} data-ct-cell={`${c}:${x.code}`} title={g?`${fmtNumber(g.filled)} of ${fmtNumber(g.total)} values across ${g.fields} fields`:'Nothing recorded'}>{g?pct(p):'Not started'}</td>})}</tr>)}
      </tbody></table></div>
    </section>

    {d.fallback&&<p className="ui-l3v-note" role="status" data-ct-fallback>Showing the latest fill of every recorded field by country. Targets, the change over {vel} days, trend lines and Courses by fields admitted (0 of N to N of N) appear when the coverage read is live; its database change is with S2-Build.</p>}
    {score.bands&&<section className="ui-card" data-ct-score>
      <SectionTitle title="Courses by fields admitted" subtitle={`How many of the ${fmtNumber(score.n)} scored fields each of ${fmtNumber(score.courses)} courses has admitted. The scored fields are set in the field registry, so the scale grows when one is added.`}
        action={<button type="button" className="ui-btn ui-compact" aria-pressed={table} onClick={()=>setTable(!table)} data-ct-table-toggle>{table?'Show as chart':'Show as table'}</button>}/>
      {table?<div className="ui-tablewrap"><table className="ui-table" data-ct-bands-table><thead><tr><th>Fields admitted</th><th className="ui-num">Courses</th></tr></thead><tbody>{bands.map(b=><tr key={b.admitted}><td>{b.admitted} of {score.n}</td><td className="ui-num">{fmtNumber(b.courses)}</td></tr>)}</tbody></table></div>
      :<div className="ui-ct-bands" role="img" aria-label={bands.map(b=>`${b.admitted} of ${score.n}: ${fmtNumber(b.courses)} courses`).join('; ')}>
        {bands.map(b=>{const n=Number(b.courses||0),top=n===maxBand;return <div key={b.admitted} className="ui-ct-band" data-ct-band={b.admitted} title={`${b.admitted} of ${score.n} fields admitted: ${fmtNumber(n)} courses`}>
          <span className="ui-ct-band-n">{top?fmtNumber(n):''}</span><i style={{height:`${Math.max(n?2:0,n/maxBand*100)}%`}}/><small>{b.admitted}</small></div>})}
        <p className="ui-ct-axis">fields admitted, of {score.n}</p></div>}
    </section>}

    <section className="ui-card" data-ct-fields>
      <SectionTitle title="Every field" subtitle={`Each bar is the share of records holding the value; the mark is its target. Change is over ${vel} days. A link to act shows only where a field is below its target.${d.unlabelled?` ${d.unlabelled} field${d.unlabelled===1?' is':'s are'} not labelled yet.`:''}`}/>
      {domains.map(x=>{const fs=shown.filter(f=>f.domain===x.code);return fs.length?<div key={x.code} className="ui-ct-domain" data-ct-domain={x.code}><h3 className="ui-sl-h4">{x.label}</h3>{fs.map(f=><FieldRow key={f.field} f={f}/>)}</div>:null})}
      {shown.some(f=>!f.domain)&&<div className="ui-ct-domain" data-ct-domain="unassigned"><h3 className="ui-sl-h4">Not yet in a domain</h3>{shown.filter(f=>!f.domain).map(f=><FieldRow key={f.field} f={f}/>)}</div>}
      {!shown.length&&<Empty text="Every field is at or above its target."/>}
    </section>
  </div>
}

function FieldRow({f}){
  const dd=delta(f.pct,f.pct_then),low=f.pct!=null&&f.target_pct!=null&&f.pct<f.target_pct
  return <div className={`ui-ct-row${low?' ui-ct-low':''}`} data-ct-field={f.field}>
    <div className="ui-ct-name"><strong>{f.label}</strong>{f.unlabelled&&<span data-ct-unlabelled><Badge tone="warning">Not labelled</Badge></span>}<small>{f.total==null?'Nothing recorded yet':`${fmtNumber(f.filled)} of ${fmtNumber(f.total)}`}</small></div>
    <div className="ui-ct-bar" role="img" aria-label={`${f.label}: ${pct(f.pct)}${f.target_pct!=null?` against a target of ${f.target_pct}%`:''}`}><i style={{width:`${Math.max(0,Math.min(100,Number(f.pct||0)))}%`}}/>{f.target_pct!=null&&<b style={{left:`${Math.min(100,Number(f.target_pct))}%`}} aria-hidden="true"/>}</div>
    <span className="ui-ct-pct">{pct(f.pct)}</span>
    <span className={`ui-ct-delta${dd>0?' up':dd<0?' down':''}`} data-ct-delta>{f.pts===null&&f.pct_then===null&&f.target_pct===null?'—':signed(dd)}</span>
    <Spark pts={f.pts} label={f.label}/>
    <span className="ui-ct-act">{low&&f.action_href?<a href={f.action_href} className="ui-link" data-ct-action={f.action_href}>{f.action_label||'Act'}</a>:low?<small>{f.note||'Below target'}</small>:null}</span>
  </div>
}
