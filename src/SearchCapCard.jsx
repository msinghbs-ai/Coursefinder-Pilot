// Jobs › Priority queue › Course-page search budget (v2.15.155, Platform Admin request 3 Oct 2026 00:57: "Where do I
// increase search cap?"). The course-page search (Firecrawl search, 2 credits each) stops for the month when this cap
// would be passed; the queue waits and resumes when the cap is raised or a new month starts. It is separate from the
// Firecrawl monthly limit and safety reserve in Layer 2 › Scraper config, which still apply.
// Read: public.admin_course_link_search_settings() (Pipeline Operator and above); write: the same with
// p_monthly_credit_cap (Platform Admin, 1,000 to 500,000) — migration 20261003000300.
import React,{useEffect,useState}from'react'
import{Search,Save}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,SectionTitle}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export default function SearchCapCard(){
  const[s,setS]=useState(null),[cap,setCap]=useState(''),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState('')
  const load=async(arg=null)=>{setErr('');const{data,error}=await supabase.rpc('admin_course_link_search_settings',arg==null?{}:{p_monthly_credit_cap:arg});if(error)throw error;setS(data);setCap(String(data?.monthly_credit_cap??''));return data}
  useEffect(()=>{load().catch(e=>setErr(errText(e)))},[])
  if(!s)return <section className="m-panel" data-search-cap>{err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading the search budget…"/>}</section>
  const used=Number(s.used_this_month||0),limit=Number(s.monthly_credit_cap||0),left=Math.max(0,limit-used)
  const save=async()=>{
    const v=Number(cap)
    if(!Number.isInteger(v)||v<1000||v>500000){setErr('Enter a whole number between 1,000 and 500,000.');return}
    if(!window.confirm(`Set the course-page search cap to ${fmtNumber(v)} credits a month? Each search uses 2 Firecrawl credits. The Firecrawl monthly limit and safety reserve still apply.`))return
    setBusy(true);setSaved('')
    try{const d=await load(v);if(Number(d?.monthly_credit_cap)!==v)throw new Error('The new cap did not save; refresh and try again');setSaved(`Saved: ${fmtNumber(v)} credits a month.`)}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  return <section className="m-panel" data-search-cap>
    <SectionTitle icon={Search} title="Course-page search budget" subtitle="Searches for a course's own page on its university's site (2 Firecrawl credits each). When this month's cap is reached the searches wait until the cap is raised or the month ends."/>
    <dl className="fs-totals">
      <div><dt>Used this month</dt><dd>{fmtNumber(used)}</dd></div>
      <div><dt>Monthly cap</dt><dd>{fmtNumber(limit)}</dd></div>
      <div><dt>Left</dt><dd data-left>{fmtNumber(left)}</dd></div>
      <div><dt>Searches waiting</dt><dd>{fmtNumber(Number(s.queued||0))}</dd></div>
    </dl>
    {left<200&&Number(s.queued||0)>0&&<p className="pp-caveat" data-cap-reached>The cap is reached, so {fmtNumber(Number(s.queued))} searches are waiting.</p>}
    {s.can_change?<div className="sd-actions"><label><small>Monthly cap (credits)</small> <input aria-label="Course-page search monthly cap" type="number" min="1000" max="500000" step="1000" value={cap} onChange={e=>setCap(e.target.value)}/></label>
      <Button compact variant="primary" onClick={save} disabled={busy||String(limit)===cap}><Save size={13}/>Save cap</Button></div>
      :<p className="sd-desc">Only a Platform Admin can change the cap.</p>}
    {saved&&<p className="sd-desc" role="status">{saved}</p>}
    {err&&<p className="fr-error" role="alert">{err}</p>}
  </section>
}
