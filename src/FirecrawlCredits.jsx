// Firecrawl credits by university (v2.15.262, CF-247). Platform Admin, 12 Oct 2026 21:47: "Report Firecrawl credit used per uni and
// pages produced, that will give us how much waste is happening, and tweak it along." Shows today's budget by purpose (Melbourne day,
// settings in the Daily budget section of the Firecrawl card above) and, for the chosen window, each university's credits by purpose
// against the course pages produced (correct and wrong), credits per correct page and a waste flag. A university whose course-page
// search stopped (no correct page after the set number of searches) can be resumed by a Platform Admin with a reason.
// v2.15.265 (Platform Admin, 13 Oct 2026: "Refusals per university"): today's refused spends by university and reason, with its search
// order tier and whether its course search is held for an adapter check (Search again releases the hold).
// Reads: admin_firecrawl_credits(hours). Writes: admin_firecrawl_search_resume(provider, reason).
import React,{useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,fmtNumber}from'./ui-kit'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
export const FLAG={search_stopped:['Search stopped','danger'],no_pages:['No pages from 100+ credits','danger'],mostly_wrong:['Mostly wrong pages','warning'],scholarships_high:['High scholarship use','warning']}
const WINDOWS=[[1,'Last hour'],[24,'Last 24 hours'],[168,'Last 7 days']]
const pct=(a,b)=>b>0?Math.round(100*a/b):0
export const TIER=['Top 50','Australia, 30+ courses','Overseas','Small provider']
export const REASON={directory_site:'directory site',not_eligible:'fewer than 30 courses',university_cap:'scholarship cap',not_due:'central pages not due',search_stopped:'search stopped',share:'daily share used',day_total:'day’s total used'}
const reasonText=r=>Object.entries(r||{}).sort((a,b)=>b[1]-a[1]).map(([k,n])=>{const[g,why]=k.split(':');return`${REASON[why]||why} (${g.replace('_',' ')}) ${fmtNumber(n)}`}).join(', ')

export default function FirecrawlCredits({onError}){
  const[hours,setHours]=useState(24),[d,setD]=useState(null),[busy,setBusy]=useState(false),[only,setOnly]=useState(false)
  const load=async(h=hours)=>{try{const{data,error}=await supabase.rpc('admin_firecrawl_credits',{p_hours:h});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load(hours)},[hours])
  const resume=async u=>{const reason=ask(`Search course pages again for ${u.name}? Check its website first.`);if(!reason)return;setBusy(true)
    try{const{error}=await supabase.rpc('admin_firecrawl_search_resume',{p_provider_id:u.provider_id,p_reason:reason});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const b=d?.budget||{},t=d?.totals||{},rows=(d?.universities||[]).filter(u=>!only||u.flag)
  const fcPages=(t.fc_ok||0)+(t.fc_wrong||0)
  return <Card id="services.toolset.firecrawl.credits" title="Firecrawl credits by university" data-fc-by-uni
    subtitle="What Firecrawl was used for and what it produced. Credits are counted by the platform; the bill can be a little higher. Today’s budget follows the Daily budget settings above."
    meta={d?<span className={`cf-chip tone-${t.flagged?'warning':'success'}`}>{t.flagged?`${fmtNumber(t.flagged)} flagged`:'Nothing flagged'}</span>:null}>
    {!d?<Loading label="Loading credits…"/>:<>
      <h4 className="sl-h4">Today (Melbourne time){b.on?'':' — observe only, nothing is stopped'}</h4>
      <div className="cf-table-wrap"><table className="cf-table" data-fc-budget><thead><tr><th>Purpose</th><th className="num">Used</th><th className="num">Share</th><th className="num">Used %</th><th className="num">Refused today</th></tr></thead><tbody>
        {(b.groups||[]).map(g=><tr key={g.group} data-fc-group={g.group}><td>{g.label}</td><td className="num">{fmtNumber(Math.round(g.used))}</td><td className="num">{fmtNumber(g.share)}</td>
          <td className="num"><span className={`cf-chip tone-${pct(g.used,g.share)>=100?'danger':pct(g.used,g.share)>=80?'warning':'success'}`}>{pct(g.used,g.share)}%</span></td><td className="num">{fmtNumber(g.refused)}</td></tr>)}
        <tr data-fc-group="total"><td><strong>Billed today (from the balance)</strong></td><td className="num"><strong>{fmtNumber(Math.round(b.billed_today||0))}</strong></td><td className="num">{fmtNumber(b.total)}</td>
          <td className="num"><span className={`cf-chip tone-${pct(b.billed_today,b.total)>=100?'danger':pct(b.billed_today,b.total)>=80?'warning':'success'}`}>{pct(b.billed_today,b.total)}%</span></td><td className="num">—</td></tr>
      </tbody></table></div>
      <div className="fcc-bar">
        <div className="tn-mode" role="group" aria-label="Window">{WINDOWS.map(([h,l])=><Button key={h} compact className={h===hours?'is-active':''} aria-pressed={h===hours} onClick={()=>setHours(h)}>{l}</Button>)}</div>
        <label className="fcc-only"><input type="checkbox" checked={only} onChange={e=>setOnly(e.target.checked)}/> Flagged only</label>
        <Button compact onClick={()=>load()}><RefreshCw size={14}/>Refresh</Button>
      </div>
      <p className="sl-sub" data-fc-totals>{fmtNumber(Math.round(t.units||0))} credits across {fmtNumber(t.universities||0)} universities: finding {fmtNumber(Math.round(t.course_search||0))}, reading {fmtNumber(Math.round(t.reads||0))}, scholarships {fmtNumber(Math.round(t.scholarships||0))}, central {fmtNumber(Math.round(t.central||0))}, other {fmtNumber(Math.round(t.other||0))}.
        {' '}Course pages: {fmtNumber((t.fc_ok||0)+(t.direct_ok||0))} correct ({fmtNumber(t.direct_ok||0)} read directly at no cost); Firecrawl reads {fmtNumber(t.fc_ok||0)} correct and {fmtNumber(t.fc_wrong||0)} wrong or failed ({pct(t.fc_wrong||0,fcPages)}% waste).</p>
      {rows.length===0?<Empty text={only?'No university is flagged.':'No Firecrawl use in this window.'}/>:
      <div className="cf-table-wrap"><table className="cf-table" data-fc-unis><thead><tr><th>University</th><th>Country</th><th className="num">Credits</th><th className="num">Finding</th><th className="num">Reading</th><th className="num">Scholarships</th><th className="num">Central</th><th className="num">Correct pages</th><th className="num">Wrong (Firecrawl)</th><th className="num">Credits per correct page</th><th>Flag</th><th></th></tr></thead><tbody>
        {rows.map(u=><tr key={u.provider_id} data-fc-uni={u.provider_id}>
          <td>{u.name||u.provider_id}</td><td>{u.country||'—'}</td><td className="num">{fmtNumber(Math.round(u.units))}</td><td className="num">{fmtNumber(Math.round(u.course_search))}</td><td className="num">{fmtNumber(Math.round(u.reads))}</td>
          <td className="num">{fmtNumber(Math.round(u.scholarships))}</td><td className="num">{fmtNumber(Math.round(u.central))}</td><td className="num">{fmtNumber(u.correct)}</td><td className="num">{fmtNumber(u.fc_wrong)}</td>
          <td className="num">{u.per_correct==null?'—':u.per_correct}</td>
          <td>{u.flag?<span className={`cf-chip tone-${FLAG[u.flag]?.[1]||'warning'}`}>{FLAG[u.flag]?.[0]||u.flag}</span>:''}</td>
          <td>{u.stopped&&d.can_manage&&<Button compact disabled={busy} onClick={()=>resume(u)}>Search again</Button>}</td></tr>)}
      </tbody></table></div>}
      <h4 className="sl-h4">Refused today, by university</h4>
      {(d.refused_by_uni||[]).length===0?<Empty text="Nothing refused today."/>:
      <div className="cf-table-wrap"><table className="cf-table" data-fc-refused><thead><tr><th>University</th><th>Country</th><th>Search order</th><th className="num">Refused</th><th>Why</th><th></th></tr></thead><tbody>
        {d.refused_by_uni.map(u=><tr key={u.provider_id} data-fc-refused-uni={u.provider_id}>
          <td>{u.name||u.provider_id}</td><td>{u.country||'—'}</td><td>{TIER[u.tier]||'—'}</td><td className="num">{fmtNumber(u.n)}</td><td>{reasonText(u.reasons)}</td>
          <td>{u.held?<>{' '}<span className="cf-chip tone-warning">Search held</span>{d.can_manage&&<Button compact disabled={busy} onClick={()=>resume(u)}>Search again</Button>}</>:''}</td></tr>)}
      </tbody></table></div>}
    </>}
  </Card>
}
