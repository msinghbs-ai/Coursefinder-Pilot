import {api,supabase} from './lib/supabase'
import './scheduled-jobs-config.css'

const CHANGE='CF-CHG-20260910-092'
const ROUTES={1:'#layer-1-operations',2:'#layer-2-enrichment',3:'#layer-3-ai-interpretation'}
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
const text=node=>String(node?.textContent||'').trim()
const human=value=>String(value??'').replaceAll('_',' ').replace(/\b\w/g,x=>x.toUpperCase())
const when=value=>{if(!value)return '—';const d=new Date(value);return Number.isNaN(d.valueOf())?String(value):d.toLocaleString()}
const state=value=>`<span class="cf-scheduler-v2__status" data-state="${esc(String(value||'').toLowerCase())}">${esc(human(value||'unknown'))}</span>`
const findHeading=label=>[...document.querySelectorAll('h1,h2,h3,h4')].find(x=>text(x)===label)
const tableRows=table=>[...table?.querySelectorAll('tbody tr')||[]].map(row=>[...row.children].map(text))
const normaliseFreshness=value=>String(value||'').trim().toLowerCase()

let scheduled=false
function scheduleMount(){if(scheduled)return;scheduled=true;setTimeout(()=>{scheduled=false;mount().catch(()=>{})},80)}

function parsePolicies(){
 const heading=findHeading('Source/entity freshness policies')
 const section=heading?.closest('section')
 const table=section?.querySelector('table.cf-scheduler-v2-original-policy-table')||section?.querySelector('table')
 if(!table)return {heading,section,table:null,rows:[]}
 const rows=tableRows(table).map(cells=>({
  layer:Number(String(cells[0]||'').replace(/\D/g,'')),country:cells[1]||'—',target:cells[2]||'',freshness:normaliseFreshness(cells[3]),nextDue:cells[4]||'—',enabled:/enabled/i.test(cells[5]||'')&&!/disabled/i.test(cells[5]||'')
 })).filter(x=>x.layer>=1&&x.layer<=3&&x.target&&x.target!=='UNBOUNDED')
 return {heading,section,table,rows}
}
function parseQueue(){
 const heading=findHeading('Targeted refresh queue')
 const table=heading?.closest('section')?.querySelector('table')
 return tableRows(table).map(cells=>({layer:cells[0]||'—',trigger:cells[1]||'—',target:cells[2]||'—',reason:cells[3]||'—',status:cells[4]||'—',created:cells[5]||'—'}))
}
function jobItems(value){return Array.isArray(value)?value:(value?.items||value?.rows||value?.jobs||[])}
function jobLayer(row){return row.layer??row.requested_layer??String(row.job_type||'').match(/layer[_ -]?(\d)/i)?.[1]??'—'}
function jobName(row){return row.job_name||row.job_type||row.source_label||row.source_name||row.source_code||row.id||'Job'}
function jobStarted(row){return row.started_at||row.created_at||row.queued_at||row.updated_at}
function jobFinished(row){return row.completed_at||row.finished_at||row.updated_at}
function jobResult(row){
 const accepted=row.accepted_count??row.accepted??row.applied_count
 const processed=row.processed_count??row.processed??row.selected_count
 const rejected=row.rejected_count??row.rejected??row.failed_count
 const bits=[]
 if(processed!=null)bits.push(`${processed} processed`)
 if(accepted!=null)bits.push(`${accepted} accepted`)
 if(rejected!=null)bits.push(`${rejected} rejected/failed`)
 return bits.join(' · ')||row.completion_class||row.failure_class||'—'
}
function setMessage(root,message,isError=false){const el=root.querySelector('[data-cf-scheduler-message]');if(!el)return;el.hidden=!message;el.dataset.error=String(Boolean(isError));el.textContent=message||''}
function dialogMarkup(){return `<dialog class="cf-scheduler-v2-dialog" data-cf-scheduler-dialog><form method="dialog"><h3 data-title>Schedule</h3><p data-context></p><div data-edit-fields><label>Cadence (days)<input name="cadence" type="number" min="1" max="3650" placeholder="Leave blank to keep current cadence"></label><label>Next run<input name="next_due" type="datetime-local"></label><label>Schedule status<select name="enabled"><option value="">Keep current status</option><option value="true">Enabled</option><option value="false">Disabled</option></select></label></div><label>Governance reason<textarea name="reason" required minlength="5" placeholder="Why is this schedule/action required?"></textarea></label><div class="cf-scheduler-v2-dialog__actions"><button value="cancel">Cancel</button><button value="confirm" data-primary>Confirm</button></div></form></dialog>`}

async function control(policy,action,values,root){
 setMessage(root,action==='queue_now'?'Queueing bounded on-demand request…':'Saving governed schedule change…')
 const {data,error}=await supabase.rpc('scheduler_policy_control',{
  p_layer:policy.layer,p_country_code:policy.country==='—'?null:policy.country,p_target:policy.target,p_freshness_class:policy.freshness,
  p_action:action,p_cadence_days:values.cadence?Number(values.cadence):null,p_next_due_at:values.nextDue?new Date(values.nextDue).toISOString():null,
  p_enabled:values.enabled===''?null:values.enabled==='true',p_reason:values.reason
 })
 if(error)throw error
 const request=data?.request_id?` Request ${String(data.request_id).slice(0,8)}…`:''
 const result=action==='queue_now'?(data?.state==='already_active'?`An active bounded request already exists.${request}`:`On-demand request queued.${request}`):'Schedule updated.'
 setMessage(root,result)
 const refresh=findHeading('Source/entity freshness policies')?.closest('section')?.querySelector('button')
 if(refresh&&/refresh/i.test(text(refresh)))refresh.click()
 setTimeout(scheduleMount,500)
}
function openDialog(root,policy,action){
 const dialog=root.querySelector('[data-cf-scheduler-dialog]'),form=dialog.querySelector('form')
 form.reset();dialog.querySelector('[data-title]').textContent=action==='queue_now'?`Run Layer ${policy.layer} on demand`:'Edit schedule'
 dialog.querySelector('[data-context]').textContent=`Layer ${policy.layer} · ${policy.country} · ${policy.target} · ${human(policy.freshness)}`
 dialog.querySelector('[data-edit-fields]').hidden=action==='queue_now'
 dialog.showModal()
 dialog.onclose=async()=>{
  if(dialog.returnValue!=='confirm')return
  const fd=new FormData(form),reason=String(fd.get('reason')||'').trim()
  if(reason.length<5){setMessage(root,'A governance reason of at least 5 characters is required.',true);return}
  try{await control(policy,action,{cadence:String(fd.get('cadence')||''),nextDue:String(fd.get('next_due')||''),enabled:String(fd.get('enabled')||''),reason},root)}catch(error){setMessage(root,error?.message||String(error),true)}
 }
}

function renderPolicies(rows){return rows.map((p,index)=>`<tr><td>Layer ${p.layer}</td><td>${esc(p.country)}</td><td><strong>${esc(p.target)}</strong></td><td>${esc(human(p.freshness))}</td><td>${esc(p.nextDue)}</td><td>${state(p.enabled?'enabled':'disabled')}</td><td><div class="cf-scheduler-v2__row-actions"><button data-edit-policy="${index}">Edit schedule</button><button data-run-policy="${index}" data-primary>Run on demand</button><a class="cf-scheduler-v2__link" href="${ROUTES[p.layer]}">Open Layer ${p.layer}</a></div></td></tr>`).join('')}
function renderQueue(rows){return rows.slice(0,10).map(r=>`<tr><td>${esc(r.layer)}</td><td>${esc(r.trigger)}</td><td>${esc(r.target)}</td><td>${state(String(r.status).toLowerCase())}</td><td>${esc(r.created)}</td><td>${esc(r.reason)}</td></tr>`).join('')}
function renderJobs(rows){return rows.slice(0,10).map(r=>`<tr><td>${esc(String(jobLayer(r)).replace(/^L/i,'Layer '))}</td><td><strong>${esc(jobName(r))}</strong><br><small>${esc(String(r.id||r.job_id||''))}</small></td><td>${state(r.status||r.state||'unknown')}</td><td>${esc(human(r.run_mode||r.mode||r.trigger_type||'—'))}</td><td>${esc(when(jobStarted(r)))}</td><td>${esc(when(jobFinished(r)))}</td><td>${esc(jobResult(r))}</td><td><div class="cf-scheduler-v2__row-actions"><a class="cf-scheduler-v2__link" href="#jobs">Jobs</a><a class="cf-scheduler-v2__link" href="#evidence">Evidence</a></div></td></tr>`).join('')}

async function mount(){
 const parsed=parsePolicies()
 if(!parsed.section||!parsed.table)return
 const queue=parseQueue()
 const signature=JSON.stringify({policies:parsed.rows,queue})
 const existing=parsed.section.querySelector('.cf-scheduler-v2')
 if(existing?.dataset.signature===signature)return
 if(existing)existing.remove()
 parsed.table.classList.add('cf-scheduler-v2-original-policy-table');parsed.table.hidden=true
 let jobs=[]
 try{jobs=jobItems(await api.jobs(50))}catch{}
 const root=document.createElement('div');root.className='cf-scheduler-v2';root.dataset.cfSchedulerEnhanced='true';root.dataset.signature=signature
 root.innerHTML=`<div class="cf-scheduler-v2__head"><div><h2>Scheduled Jobs & Run Control</h2><p>Governed schedule configuration, bounded Layer 1–3 on-demand queueing, recent queue status and job/evidence follow-through. Generic historical replay/reset remains disabled.</p></div><div class="cf-scheduler-v2__actions"><button data-refresh>Refresh</button><a class="cf-scheduler-v2__link" href="#jobs">Open Jobs</a><a class="cf-scheduler-v2__link" href="#evidence">Open Evidence</a></div></div><div class="cf-scheduler-v2__summary"><article><strong>${parsed.rows.length}</strong><span>Bounded Layer 1–3 schedules</span></article><article><strong>${queue.filter(x=>/queued|running/i.test(x.status)).length}</strong><span>Queued / active refresh requests shown</span></article><article><strong>${jobs.length}</strong><span>Recent governed job records loaded through admin_read</span></article></div><div class="cf-scheduler-v2__links"><a class="cf-scheduler-v2__link" href="#layer-1-operations">Layer 1 — Regulatory</a><a class="cf-scheduler-v2__link" href="#layer-2-enrichment">Layer 2 — Enrichment</a><a class="cf-scheduler-v2__link" href="#layer-3-ai-interpretation">Layer 3 — AI Interpretation</a></div><div class="cf-scheduler-v2__message" data-cf-scheduler-message hidden></div><div class="cf-scheduler-v2__subhead"><h3>Schedule Configuration</h3><span class="cf-scheduler-v2__status">${esc(CHANGE)}</span></div><div class="cf-scheduler-v2__table-wrap"><table><thead><tr><th>Layer</th><th>Country</th><th>Scheduled Target</th><th>Freshness Policy</th><th>Next Run</th><th>Schedule Status</th><th>Actions</th></tr></thead><tbody>${renderPolicies(parsed.rows)||'<tr><td colspan="7" class="cf-scheduler-v2__empty">No bounded Layer 1–3 policies are currently visible.</td></tr>'}</tbody></table></div><p class="cf-scheduler-v2__note">“Run on demand” queues the same bounded policy target used by the governed scheduler. It does not retry/reset an arbitrary historical job and does not bypass Layer-specific qualification, Evidence or publication controls.</p><div class="cf-scheduler-v2__subhead"><h3>Latest Refresh Queue</h3><a class="cf-scheduler-v2__link" href="#jobs">Follow in Jobs</a></div><div class="cf-scheduler-v2__table-wrap"><table><thead><tr><th>Layer</th><th>Trigger</th><th>Target</th><th>Status</th><th>Queued At</th><th>Reason / Result</th></tr></thead><tbody>${renderQueue(queue)||'<tr><td colspan="6" class="cf-scheduler-v2__empty">No recent refresh requests are visible.</td></tr>'}</tbody></table></div><div class="cf-scheduler-v2__subhead"><h3>Recent Job Runs</h3><div class="cf-scheduler-v2__links"><a class="cf-scheduler-v2__link" href="#jobs">All Jobs</a><a class="cf-scheduler-v2__link" href="#evidence">Evidence</a></div></div><div class="cf-scheduler-v2__table-wrap"><table><thead><tr><th>Layer</th><th>Job / Source</th><th>Status</th><th>Run Mode</th><th>Started</th><th>Completed</th><th>Result</th><th>Follow</th></tr></thead><tbody>${renderJobs(jobs)||'<tr><td colspan="8" class="cf-scheduler-v2__empty">No recent job records returned by the governed Jobs read surface.</td></tr>'}</tbody></table></div>${dialogMarkup()}`
 parsed.section.insertBefore(root,parsed.table)
 root.querySelector('[data-refresh]').addEventListener('click',()=>{const refresh=parsed.section.querySelector('button:not([data-refresh])');if(refresh&&/refresh/i.test(text(refresh)))refresh.click();setTimeout(scheduleMount,450)})
 root.querySelectorAll('[data-edit-policy]').forEach(button=>button.addEventListener('click',()=>openDialog(root,parsed.rows[Number(button.dataset.editPolicy)],'edit_schedule')))
 root.querySelectorAll('[data-run-policy]').forEach(button=>button.addEventListener('click',()=>openDialog(root,parsed.rows[Number(button.dataset.runPolicy)],'queue_now')))
}

addEventListener('hashchange',scheduleMount)
new MutationObserver(scheduleMount).observe(document.documentElement,{subtree:true,childList:true})
scheduleMount()
