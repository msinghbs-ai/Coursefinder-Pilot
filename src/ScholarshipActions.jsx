// On-demand scholarship tasks (v2.15.244, CF-247, Platform Admin 11 Oct 2026: "fire manually how to gather uni based
// scholarships or check from provider or course if any applicable scholarship is found and queried and gets attached on
// demand. Once this workflow fires some script it should be registered as job and visible under task manager").
// Each button starts a task (public.admin_jobs 'start'); the task queues the pages first in line, reads them through the
// scraper, attaches courses by the evidence rules and finishes on its own. Progress and Cancel are on the button and in
// Scheduled jobs › Task manager. Shown to Operators and above (the job system's own rule); hidden for everyone else.
import React,{useEffect,useState}from'react'
import{Search,RefreshCw,Sparkles}from'lucide-react'
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

// Scholarships › Coverage: several providers at once (one task)
export async function startProviderScans(providerIds,count){
  const reason=window.prompt(`Find scholarships now for ${count} provider(s)? Every page is read through the scraper (about one credit a page).\n\nReason (kept in the log):`)
  if(!reason||reason.trim().length<4)return null
  const{data,error}=await supabase.rpc('admin_jobs',{p_action:'start',p_args:{kind:'scholarship_provider_scan',args:{provider_ids:providerIds},reason:reason.trim()}})
  if(error)throw error
  return data
}
export{useCanRunTasks}
