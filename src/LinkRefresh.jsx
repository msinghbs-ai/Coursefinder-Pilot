// Coverage › Courses › Link refresh (v2.15.133, Decision 201). How often each kind of course link is re-checked, for all
// countries, one country or one provider (the most specific schedule wins), and which third-party and regulatory
// portals supply links. The job "Refresh course links" (Automations) applies the schedules every 10 minutes.
// Read/write: public.admin_link_refresh_read / admin_link_refresh_edit (Pipeline Operator and above change them).
import React,{useEffect,useState}from'react'
import{CalendarClock,Check,Plus,RefreshCw,Trash2,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,SectionTitle,StatusChip}from'./ui-kit'
import{fmtDateTime,fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const KIND={regulator:'Regulator',admission_centre:'Admission centre',government_portal:'Government portal',aggregator:'Course directory'}
const APPLICANT={any:'All applicants',international:'International applicants',domestic:'Mostly domestic applicants'}
const result=r=>r?[r.reread!=null&&`${fmtNumber(r.reread)} pages re-read`,r.searched_again!=null&&`${fmtNumber(r.searched_again)} searched again`,r.verified!=null&&`${fmtNumber(r.verified)} links re-confirmed`,r.unverified&&`${fmtNumber(r.unverified)} pages gone`,r.regulator_added&&`${fmtNumber(r.regulator_added)} regulator links added`].filter(Boolean).join(' · '):''

export default function LinkRefresh(){
  const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[adding,setAdding]=useState(false)
  const[f,setF]=useState({country:'',link_type:'official_course',every_days:'30'})
  const load=async()=>{setErr('');try{const{data:d,error}=await supabase.rpc('admin_link_refresh_read');if(error)throw error;setData(d)}catch(e){setErr(errText(e))}}
  useEffect(()=>{load()},[])
  const edit=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);setErr('')
    try{const{data:d,error}=await supabase.rpc('admin_link_refresh_edit',{p_action:action,p_args:args});if(error)throw error;setData(d);setAdding(false)}
    catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!data)return err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading link refresh…"/>
  const can=Boolean(data.can_edit)&&!busy
  return <section className="m-panel lr-panel" data-link-refresh>
    <SectionTitle icon={CalendarClock} title="Link refresh" subtitle="How often course links are checked again. A schedule for one country or provider replaces the all-countries one for its courses; new countries follow the all-countries schedules."
      action={<div className="sd-actions"><Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>{can&&<Button compact onClick={()=>setAdding(a=>!a)}><Plus size={14}/>Add schedule</Button>}</div>}/>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {adding&&<div className="cl-form" data-add-schedule>
      <label><small>Country</small><select className="fv-input" value={f.country} onChange={e=>setF({...f,country:e.target.value})} aria-label="Country"><option value="">All countries</option>{(data.countries||[]).map(c=><option key={c} value={c}>{c}</option>)}</select></label>
      <label><small>Link</small><select className="fv-input" value={f.link_type} onChange={e=>setF({...f,link_type:e.target.value})} aria-label="Link type">{(data.types||[]).map(t=><option key={t.code} value={t.code}>{t.label}</option>)}</select></label>
      <label><small>Every (days)</small><input className="fv-input re-year" inputMode="numeric" value={f.every_days} onChange={e=>setF({...f,every_days:e.target.value.replace(/\D/g,'').slice(0,3)})} aria-label="Every how many days"/></label>
      <div className="re-foot"><Button compact variant="primary" disabled={busy||!(Number(f.every_days)>=1&&Number(f.every_days)<=365)} onClick={()=>edit('save_policy',f)}><Check size={13}/>Save</Button><Button compact onClick={()=>setAdding(false)}><X size={13}/>Cancel</Button></div>
    </div>}
    <div className="cf-table-wrap"><table className="cf-table" data-schedules><thead><tr><th>Link</th><th>Applies to</th><th>Every</th><th>On</th><th>Last run</th><th></th></tr></thead>
      <tbody>{(data.policies||[]).map(p=><tr key={p.id}>
        <td>{p.type_label}</td><td>{p.provider||p.country_name||'All countries'}</td>
        <td>{can?<select className="fv-input" value={p.every_days} onChange={e=>edit('save_policy',{id:p.id,link_type:p.link_type,every_days:e.target.value})} aria-label={`${p.type_label} every`}>{[...new Set([7,14,30,60,90,180,365,p.every_days])].sort((a,b)=>a-b).map(d=><option key={d} value={d}>{d} days</option>)}</select>:`${p.every_days} days`}</td>
        <td>{can?<input type="checkbox" checked={Boolean(p.active)} onChange={e=>edit('save_policy',{id:p.id,link_type:p.link_type,every_days:p.every_days,active:e.target.checked})} aria-label={`${p.type_label} schedule on`}/>:<StatusChip value={p.active?'on':'off'} tone={p.active?'success':'neutral'} label={p.active?'On':'Off'}/>}</td>
        <td>{p.last_run_at?<><span>{fmtDateTime(p.last_run_at)}</span><small className="sd-desc">{result(p.last_result)}</small></>:'—'}</td>
        <td>{can&&(p.country||p.provider_id)&&<Button compact variant="danger" onClick={()=>edit('remove_policy',{id:p.id},'Remove this schedule? Its courses follow the all-countries schedule again.')} aria-label="Remove schedule"><Trash2 size={13}/></Button>}</td>
      </tr>)}</tbody></table></div>

    <h4 className="lr-sub">Portals that supply course links</h4>
    <div className="cf-table-wrap"><table className="cf-table" data-portals><thead><tr><th>Portal</th><th>Country</th><th>Kind</th><th>For</th><th>Every</th><th>On</th></tr></thead>
      <tbody>{(data.portals||[]).map(p=><tr key={p.code} data-portal={p.code}>
        <td><a href={p.base_url} target="_blank" rel="noreferrer" className="cf-link">{p.label}</a>{p.notes&&<small className="sd-desc">{p.notes}</small>}</td>
        <td>{p.country||'—'}</td><td>{KIND[p.kind]||p.kind}</td><td>{APPLICANT[p.applicant]||p.applicant}</td><td>{p.every_days} days</td>
        <td>{can?<input type="checkbox" checked={Boolean(p.active)} onChange={e=>edit('portal',{code:p.code,active:e.target.checked},e.target.checked?`Switch on ${p.label}? Its links are only used after the reader confirms each course's page.`:null)} aria-label={`${p.label} on`}/>:<StatusChip value={p.active?'on':'off'} tone={p.active?'success':'neutral'} label={p.active?'On':'Off'}/>}</td>
      </tr>)}</tbody></table></div>
  </section>
}
