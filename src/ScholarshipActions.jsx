// On-demand scholarship tasks (v2.15.244, CF-247, Platform Admin 11 Oct 2026: "fire manually how to gather uni based
// scholarships or check from provider or course if any applicable scholarship is found and queried and gets attached on
// demand. Once this workflow fires some script it should be registered as job and visible under task manager").
// Each button starts a task (public.admin_jobs 'start'); the task queues the pages first in line, reads them through the
// scraper, attaches courses by the evidence rules and finishes on its own. Progress and Cancel are on the button and in
// Scheduled jobs › Task manager. Shown to Operators and above (the job system's own rule); hidden for everyone else.
import React,{useEffect,useState}from'react'
import{Search,RefreshCw,Sparkles,Globe,Power}from'lucide-react'
import{Button,StatusChip,fmtDateTime}from'./ui-kit'
import{supabase}from'./lib/supabase'
import JobButton from'./JobButton'

function useCanRunTasks(){
  const[can,setCan]=useState(false)
  useEffect(()=>{let live=true;supabase.rpc('admin_jobs',{p_action:'read',p_args:{limit:1}}).then(({error})=>{if(live)setCan(!error)}).catch(()=>{});return()=>{live=false}},[])
  return can
}
const Wrap=({children,note})=><div className="sa-actions" data-scholarship-actions>{children}{note&&<small className="sl-sub">{note}</small>}</div>

// Provider record: map the university's site through the scraper, screen candidate pages, admit and read every scholarship
export function ProviderScholarshipAction({providerId,name}){
  const can=useCanRunTasks()
  if(!can||!providerId)return null
  return <Wrap note="Maps the site through the scraper, finds and reads every scholarship page, and links courses from the evidence. Progress is also in Task manager.">
    <JobButton kind="scholarship_provider_scan" scope={providerId} args={{provider_ids:[providerId]}} icon={Search} label="Find scholarships now"
      question={`Find scholarships now for ${name||'this provider'}? Every page is read through the scraper (about one credit a page).`}/>
  </Wrap>
}

// v2.15.271 (Platform Admin, 14 Oct 2026: "skip scholarship search for any provider whose website is a directory site ... I need visible
// flag in provider for such rows. Which we can toggle to enable"): Off automatically when the only website known is a directory site.
// A Pipeline Operator turns it On with a reason and the provider's own website (a fresh search starts), or Off with a reason.
// public.admin_provider_sch_search('states' | 'set').
export function ProviderScholarshipSearch({providerId,onChanged}){
  const[s,setS]=useState(null),[open,setOpen]=useState(false),[site,setSite]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const load=()=>supabase.rpc('admin_provider_sch_search',{p_action:'states',p_args:{provider_ids:[providerId]}}).then(({data,error})=>{if(error)throw error;const x=(data||{})[providerId]||null;setS(x);setSite(x?.own_site||'')}).catch(e=>setErr(String(e?.message||e)))
  useEffect(()=>{if(providerId)load()},[providerId])
  if(!providerId||!s)return null
  const turnOn=!s.on,ok=reason.trim().length>=4&&(!turnOn||/^https?:\/\/[^\s/]+\.[^\s]+$/.test(site.trim()))
  const save=async()=>{setBusy(true);setErr('');try{const{data,error}=await supabase.rpc('admin_provider_sch_search',{p_action:'set',p_args:{provider_id:providerId,on:turnOn,reason:reason.trim(),website:turnOn?site.trim():null}});if(error)throw error;setS((data||{})[providerId]||s);setOpen(false);setReason('');onChanged?.()}catch(e){setErr(String(e?.message||e).replace(/^.*?ERROR:\s*/,''))}finally{setBusy(false)}}
  return <div className="sa-flag" data-sch-search={s.on?'on':'off'}>
    <div className="sa-flag-row"><span>Scholarship search</span>
      <StatusChip tone={s.on?'success':'warning'} label={s.on?'On':s.directory_only&&s.auto?'Off · directory site':'Off'} title={s.reason||undefined}/>
      {s.can_manage&&<Button compact onClick={()=>setOpen(o=>!o)}><Power size={13}/>{s.on?'Turn off':'Turn on'}</Button>}</div>
    {!s.on&&<small className="sl-sub">{s.reason||'Switched off.'}{s.set_at?` · ${fmtDateTime(s.set_at)}`:''}. Scholarship pages are not searched or read for this provider.</small>}
    {open&&<div className="sa-flag-form">
      {turnOn&&<label><small>Provider's own website</small><input className="fv-input" value={site} onChange={e=>setSite(e.target.value)} placeholder="https://www.example.edu.au"/></label>}
      <label><small>Reason (kept in the log)</small><input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)}/></label>
      <Button compact variant="primary" disabled={busy||!ok} onClick={save}>{turnOn?'Turn on and search':'Turn off'}</Button>
      {turnOn&&<small className="sl-sub">The search starts from this website. Directory sites are refused. The 30-course rule and the credit caps still apply.</small>}
    </div>}
    {err&&<small className="fr-error" role="alert">{err}</small>}
  </div>
}

// Course record: read the provider's scholarship pages again and apply the course-link rules; the task lists what changed
export function CourseScholarshipAction({courseId,title}){
  const can=useCanRunTasks()
  if(!can||!courseId)return null
  return <Wrap note="Reads the provider's scholarship pages again through the scraper and attaches the ones whose page covers this course. The task lists what was added or removed.">
    <JobButton kind="scholarship_course_check" scope={courseId} args={{course_id:courseId}} icon={Sparkles} label="Check scholarships for this course"
      question={`Check scholarships for ${title||'this course'}? The provider's scholarship pages are read again through the scraper.`}/>
  </Wrap>
}

// Scholarship record: read its page again now
export function ScholarshipReadAction({scholarshipId,name}){
  const can=useCanRunTasks()
  if(!can||!scholarshipId)return null
  return <Wrap>
    <JobButton kind="scholarship_reread" scope={scholarshipId} args={{scholarship_ids:[scholarshipId]}} icon={RefreshCw} label="Read again now" variant=""
      question={`Read "${name||'this scholarship'}" again now through the scraper?`}/>
  </Wrap>
}

// v2.15.245 (Platform Admin bugs 11/10-2, Feature 2): a provider entered by hand, or from a country with no register, is filled in from its
// own website: the website is searched for and verified when none is recorded, then its contacts are read and its central pages found.
export function ProviderFillAction({providerId,name,website}){
  const can=useCanRunTasks()
  if(!can||!providerId)return null
  return <Wrap note={website?'Reads its public contacts and looks for its central pages (key dates, international fees, English requirements) with Firecrawl. Progress is also in Task manager.':'No website is recorded: it is searched for and verified first, then contacts and central pages follow. Progress is also in Task manager.'}>
    <JobButton kind="provider_fill" scope={providerId} args={{provider_id:providerId}} icon={Globe} variant="" label={website?'Fill in from website again':'Fill in from website'}
      question={`Fill in ${name||'this provider'} from its website?${website?'':' Its website is searched for and verified first (about 2 Firecrawl credits).'}`}/>
  </Wrap>
}

// Scholarships › Coverage: several providers at once (one task)
export async function startProviderScans(providerIds,count){
  // v2.15.247 (bugs 11/10-4): confirm only, no reason; the log records "Started from Scholarships › Coverage"
  if(!window.confirm(`Find scholarships now for ${count} provider(s)? Every page is read through the scraper (about one credit a page).`))return null
  const{data,error}=await supabase.rpc('admin_jobs',{p_action:'start',p_args:{kind:'scholarship_provider_scan',args:{provider_ids:providerIds},from:'Scholarships › Coverage'}})
  if(error)throw error
  return data
}
export{useCanRunTasks}
