
import React,{useEffect,useMemo,useRef,useState}from'react'
import{ArrowDown,ArrowUp,Check,ChevronDown,ChevronLeft,ChevronRight,Columns3,Download,ExternalLink,FileUp,Mail,Phone,Plus,RefreshCw,RotateCcw,Save,Search,ShieldCheck,Trash2,Upload,UsersRound,X}from'lucide-react'
import{api}from'./lib/supabase'
import'./provider-contacts.css'

const PAGE_SIZE=50
const DEFAULT_COLUMNS=[
 {key:'provider_name',label:'Provider',width:250,sortKey:'provider',visible:true},
 {key:'contact',label:'Contact / Team',width:220,sortKey:'contact',visible:true},
 {key:'job_title',label:'Job title',width:220,sortKey:'title',visible:true},
 {key:'functional_area',label:'Functional area',width:180,visible:true},
 {key:'region_scope',label:'Region',width:160,sortKey:'region',visible:true},
 {key:'countries_or_markets',label:'Countries / Markets',width:200,visible:true},
 {key:'work_email',label:'Email',width:230,visible:true},
 {key:'work_phone',label:'Phone',width:150,visible:true},
 {key:'record_type',label:'Type',width:120,visible:true},
 {key:'verification_state',label:'Verification',width:135,visible:true},
 {key:'verified_on',label:'Verified',width:125,sortKey:'verified',visible:true},
 {key:'source_authority',label:'Source',width:135,visible:true},
 {key:'lifecycle_status',label:'Status',width:110,sortKey:'status',visible:true},
]
const blankForm={provider_id:'',record_type:'named_staff',full_name:'',team_name:'',job_title:'',functional_area:'',region_scope:'',countries_or_markets:'',work_email:'',work_phone:'',staff_location:'',verification_state:'current',verified_on:'',source_url:'',source_page_title:'',source_notes:'',reason:''}
const text=v=>String(v??'')
const human=v=>text(v).replace(/_/g,' ').replace(/\b\w/g,m=>m.toUpperCase())
const rowsOf=d=>d?.items??d?.rows??[]
const fmtDate=v=>{if(!v)return'—';const s=String(v);if(/^\d{4}-\d{2}-\d{2}$/.test(s))return s.split('-').reverse().join('/');const d=new Date(v);return Number.isNaN(d.getTime())?s:d.toLocaleDateString('en-AU')}
const fmtDateTime=v=>{if(!v)return'—';const d=new Date(v);return Number.isNaN(d.getTime())?String(v):d.toLocaleString('en-AU')}
const tone=v=>['active','current','official_current_page','official_university_source','applied','validated','create','update','restore','unchanged'].includes(v)?'success':['deleted','failed','invalid','conflict'].includes(v)?'danger':['inactive','stale','partial','provider_ambiguous','provider_unmatched','duplicate','skipped'].includes(v)?'warning':'neutral'
function Badge({value}){const v=text(value||'unknown').toLowerCase();return <span className={'pc-badge pc-'+tone(v)}>{human(v)}</span>}
function Btn({children,onClick,disabled=false,primary=false,danger=false}){return <button className={'pc-button '+(primary?'primary ':'')+(danger?'danger':'')} onClick={onClick} disabled={disabled}>{children}</button>}

function ProviderPicker({value,label='',onChange,disabled=false}){
 const[open,setOpen]=useState(false),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0}),[busy,setBusy]=useState(false)
 const ref=useRef(null)
 useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};document.addEventListener('mousedown',close);return()=>document.removeEventListener('mousedown',close)},[])
 useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.catalogueFilterPage({kind:'provider',query,limit:10,offset}).then(x=>live&&setData(x||{items:[],total:0})).catch(()=>live&&setData({items:[],total:0})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,query,offset])
 const items=data.items||[],total=Number(data.total||0)
 return <div className="pc-provider-picker" ref={ref}><button type="button" className="pc-picker-button" onClick={()=>!disabled&&setOpen(x=>!x)} disabled={disabled}><span>{label||'All Providers'}</span><ChevronDown size={14}/></button>{open&&<div className="pc-picker-pop"><label><Search size={13}/><input autoFocus value={query} onChange={e=>{setQuery(e.target.value);setOffset(0)}} placeholder="Search Provider…"/></label>{!value&&<button type="button" className="selected" onClick={()=>{onChange('','');setOpen(false)}}>All Providers</button>}{items.map(x=><button type="button" key={x.value} className={String(value)===String(x.value)?'selected':''} onClick={()=>{onChange(x.value,x.label);setOpen(false)}}><span>{x.label}</span><small>{x.meta}</small></button>)}{!items.length&&!busy&&<div className="pc-empty-mini">No Providers found.</div>}{total>10&&<div className="pc-picker-pager"><button type="button" disabled={!offset} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{Math.floor(offset/10)+1}/{Math.max(1,Math.ceil(total/10))}</span><button type="button" disabled={offset+10>=total} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>
}

function ColumnManager({columns,setColumns,onClose}){
 const move=(i,d)=>setColumns(cols=>{const n=[...cols],j=i+d;if(j<0||j>=n.length)return cols;[n[i],n[j]]=[n[j],n[i]];return n})
 const patch=(i,p)=>setColumns(cols=>cols.map((c,j)=>j===i?{...c,...p}:c))
 return <div className="pc-column-pop"><div className="pc-pop-head"><strong>Columns</strong><button onClick={onClose}><X size={15}/></button></div><p>Show, reorder and resize the grid. Saved for this browser.</p><div className="pc-column-list">{columns.map((c,i)=><div key={c.key}><label><input type="checkbox" checked={c.visible!==false} onChange={e=>patch(i,{visible:e.target.checked})}/><span>{c.label}</span></label><div><button disabled={i===0} onClick={()=>move(i,-1)}><ChevronLeft size={13}/></button><button disabled={i===columns.length-1} onClick={()=>move(i,1)}><ChevronRight size={13}/></button><button onClick={()=>patch(i,{width:Math.max(90,(c.width||140)-20)})}>−</button><small>{c.width||140}px</small><button onClick={()=>patch(i,{width:Math.min(420,(c.width||140)+20)})}>+</button></div></div>)}</div><button className="pc-reset-columns" onClick={()=>setColumns(DEFAULT_COLUMNS)}>Reset columns</button></div>
}

function Cell({row,keyName}){
 const v=row[keyName]
 if(keyName==='contact')return <span className="pc-main-cell"><strong>{row.full_name||row.team_name||'International team'}</strong><small>{human(row.record_type)}</small></span>
 if(keyName==='provider_name')return <span className="pc-main-cell"><strong>{row.provider_name||'—'}</strong><small>{row.provider_stable_key||row.country_code||''}</small></span>
 if(keyName==='work_email')return v?<span className="pc-contact-link"><Mail size={12}/>{v}</span>:'—'
 if(keyName==='work_phone')return v?<span className="pc-contact-link"><Phone size={12}/>{v}</span>:'—'
 if(keyName==='verified_on')return fmtDate(v)
 if(['record_type','verification_state','source_authority','lifecycle_status'].includes(keyName))return <Badge value={v}/>
 return v==null||v===''?'—':String(v)
}

function Grid({rows,columns,sort,direction,onSort,onSelect,loading}){
 const visible=columns.filter(c=>c.visible!==false)
 return <div className="pc-table-wrap"><table className="pc-table"><thead><tr>{visible.map(c=><th key={c.key} style={{minWidth:c.width,width:c.width}}><button disabled={!c.sortKey} onClick={()=>c.sortKey&&onSort(c.sortKey)}>{c.label}{sort===c.sortKey&&(direction==='asc'?<ArrowUp size={12}/>:<ArrowDown size={12}/>)}</button></th>)}</tr></thead><tbody>{loading&&!rows.length?Array.from({length:7}).map((_,i)=><tr key={i}>{visible.map(c=><td key={c.key}><span className="pc-skeleton"/></td>)}</tr>):rows.length?rows.map(r=><tr key={r.id} onClick={()=>onSelect(r.id)}>{visible.map(c=><td key={c.key}><Cell row={r} keyName={c.key}/></td>)}</tr>):<tr><td colSpan={visible.length}><div className="pc-empty">No Provider Contacts match the current filters.</div></td></tr>}</tbody></table></div>
}

function ContactForm({initial,isNew,providerLabel,onCancel,onSave,busy}){
 const[form,setForm]=useState({...blankForm,...initial}),[pLabel,setPLabel]=useState(providerLabel||'')
 useEffect(()=>{setForm({...blankForm,...initial});setPLabel(providerLabel||'')},[JSON.stringify(initial),providerLabel])
 const patch=(k,v)=>setForm(f=>({...f,[k]:v}))
 return <div className="pc-form"><div className="pc-form-grid">
  <label className="wide"><span>Provider *</span><ProviderPicker value={form.provider_id} label={pLabel} disabled={!isNew} onChange={(v,l)=>{patch('provider_id',v);setPLabel(l)}}/></label>
  <label><span>Record type *</span><select value={form.record_type} disabled={!isNew} onChange={e=>patch('record_type',e.target.value)}><option value="named_staff">Named staff</option><option value="team_contact">Team contact</option></select></label>
  <label><span>{form.record_type==='team_contact'?'Team name':'Staff name *'}</span><input value={form.record_type==='team_contact'?form.team_name:form.full_name} onChange={e=>patch(form.record_type==='team_contact'?'team_name':'full_name',e.target.value)}/></label>
  <label><span>Job title</span><input value={form.job_title} onChange={e=>patch('job_title',e.target.value)}/></label>
  <label><span>Functional area</span><input value={form.functional_area} onChange={e=>patch('functional_area',e.target.value)}/></label>
  <label><span>Region scope</span><input value={form.region_scope} onChange={e=>patch('region_scope',e.target.value)}/></label>
  <label><span>Countries / markets</span><input value={form.countries_or_markets} onChange={e=>patch('countries_or_markets',e.target.value)}/></label>
  <label><span>Professional email</span><input type="email" value={form.work_email} onChange={e=>patch('work_email',e.target.value)}/></label>
  <label><span>Work phone</span><input value={form.work_phone} onChange={e=>patch('work_phone',e.target.value)}/></label>
  <label><span>Staff location</span><input value={form.staff_location} onChange={e=>patch('staff_location',e.target.value)}/></label>
  <label><span>Verification</span><input value={form.verification_state} onChange={e=>patch('verification_state',e.target.value)}/></label>
  <label><span>Verified on</span><input type="date" value={form.verified_on||''} onChange={e=>patch('verified_on',e.target.value)}/></label>
  <label className="wide"><span>Official source URL</span><input type="url" value={form.source_url} onChange={e=>patch('source_url',e.target.value)}/></label>
  <label className="wide"><span>Source page title</span><input value={form.source_page_title} onChange={e=>patch('source_page_title',e.target.value)}/></label>
  <label className="wide"><span>Source / operator notes</span><textarea rows="3" value={form.source_notes} onChange={e=>patch('source_notes',e.target.value)}/></label>
  <label className="wide"><span>Change reason *</span><input value={form.reason} onChange={e=>patch('reason',e.target.value)} placeholder="Reason retained in audit history"/></label>
 </div><div className="pc-form-actions"><Btn onClick={onCancel}>Cancel</Btn><Btn primary disabled={busy||!form.provider_id||(form.record_type==='named_staff'&&!form.full_name)} onClick={()=>onSave({...form,reason:form.reason||((isNew?'Create':'Update')+' Provider Contact')})}><Save size={14}/>{busy?'Saving…':'Save contact'}</Btn></div></div>
}

function Drawer({id,isNew,rank,onClose,onChanged,onError}){
 const[data,setData]=useState(null),[busy,setBusy]=useState(false),[edit,setEdit]=useState(isNew),[tab,setTab]=useState('contact'),[mutating,setMutating]=useState(false)
 async function fetchDetail(){if(isNew||!id)return;setBusy(true);try{setData(await api.providerContactDetail(id))}catch(e){onError(e.message)}finally{setBusy(false)}}
 useEffect(()=>{fetchDetail()},[id,isNew])
 useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();document.addEventListener('keydown',k);return()=>document.removeEventListener('keydown',k)},[onClose])
 const contact=data?.contact||{},current=data?.current||{}
 const initial=isNew?blankForm:{provider_id:contact.provider_id||'',record_type:contact.record_type||'named_staff',full_name:current.full_name||'',team_name:current.team_name||'',job_title:current.job_title||'',functional_area:current.functional_area||'',region_scope:current.region_scope||'',countries_or_markets:current.countries_or_markets||'',work_email:current.work_email||'',work_phone:current.work_phone||'',staff_location:current.staff_location||'',verification_state:current.verification_state||'current',verified_on:current.verified_on||'',source_url:current.source_url||'',source_page_title:current.source_page_title||'',source_notes:current.source_notes||'',reason:''}
 async function save(payload){setMutating(true);try{await api.providerContactManage(isNew?'create':'update',isNew?payload:{...payload,contact_id:id});await onChanged();if(isNew)onClose();else{setEdit(false);await fetchDetail()}}catch(e){onError(e.message)}finally{setMutating(false)}}
 async function action(name,payload={}){setMutating(true);try{await api.providerContactManage(name,{contact_id:id,...payload});await fetchDetail();await onChanged()}catch(e){onError(e.message)}finally{setMutating(false)}}
 const title=isNew?'Add Provider Contact':(current.full_name||current.team_name||contact.provider_name||'Provider Contact')
 return <><button className="pc-drawer-backdrop" onClick={onClose}/><aside className="pc-drawer"><div className="pc-drawer-head"><div><small>{isNew?'New contact':'Provider Contact'}</small><h2>{title}</h2>{!isNew&&<p>{contact.provider_name}</p>}</div><button onClick={onClose}><X size={18}/></button></div>{busy?<div className="pc-drawer-loading">Loading managed contact…</div>:edit?<ContactForm initial={initial} isNew={isNew} providerLabel={contact.provider_name||''} busy={mutating} onCancel={()=>isNew?onClose():setEdit(false)} onSave={save}/>:<><div className="pc-tabs">{['contact','source','history','audit'].map(t=><button key={t} className={tab===t?'active':''} onClick={()=>setTab(t)}>{human(t)}</button>)}</div><div className="pc-drawer-body">
  {tab==='contact'&&<div className="pc-detail-grid"><div><small>Provider</small><strong>{contact.provider_name||'—'}</strong></div><div><small>Status</small><Badge value={contact.lifecycle_status}/></div><div><small>Type</small><strong>{human(contact.record_type)}</strong></div><div><small>Staff / team</small><strong>{current.full_name||current.team_name||'—'}</strong></div><div><small>Job title</small><strong>{current.job_title||'—'}</strong></div><div><small>Functional area</small><strong>{current.functional_area||'—'}</strong></div><div><small>Region</small><strong>{current.region_scope||'—'}</strong></div><div><small>Countries / markets</small><strong>{current.countries_or_markets||'—'}</strong></div><div><small>Email</small><strong>{current.work_email||'—'}</strong></div><div><small>Phone</small><strong>{current.work_phone||'—'}</strong></div><div><small>Location</small><strong>{current.staff_location||'—'}</strong></div><div><small>Verified</small><strong>{fmtDate(current.verified_on)}</strong></div></div>}
  {tab==='source'&&<div className="pc-source-block"><div className="pc-detail-grid"><div><small>Source class</small><strong>{human(current.source_class)}</strong></div><div><small>Authority</small><Badge value={current.source_authority}/></div><div><small>Verification</small><Badge value={current.verification_state}/></div><div><small>Evidence</small><strong>{current.evidence_id||'—'}</strong></div></div>{current.source_url&&<a className="pc-source-link" href={current.source_url} target="_blank" rel="noreferrer">Open official source <ExternalLink size={13}/></a>}{current.source_page_title&&<p><strong>{current.source_page_title}</strong></p>}{current.source_notes&&<p>{current.source_notes}</p>}<h3>A15 source observations</h3>{(data?.source_observations||[]).map(o=><div className="pc-history-row" key={o.id}><span><strong>{o.full_name||o.team_name||'Observation'}</strong><small>{human(o.source_class)} · {fmtDate(o.last_verified_at)}</small></span><Badge value={o.verification_state}/></div>)}</div>}
  {tab==='history'&&<div className="pc-history-list">{(data?.versions||[]).length?data.versions.map(v=><div className="pc-history-row" key={v.id}><span><strong>Version {v.version_no} · {v.full_name||v.team_name||'Contact'}</strong><small>{v.change_reason||human(v.source_class)} · {fmtDateTime(v.created_at)}</small></span><Badge value={v.verification_state}/></div>):<div className="pc-empty">No version history.</div>}</div>}
  {tab==='audit'&&<div className="pc-history-list">{(data?.audit||[]).length?data.audit.map(a=><div className="pc-history-row" key={a.id}><span><strong>{human(a.event_type)}</strong><small>{a.reason||'Governed action'} · {fmtDateTime(a.created_at)}</small></span></div>):<div className="pc-empty">No audit events.</div>}</div>}
 </div>{rank>=5&&<div className="pc-drawer-actions">{contact.lifecycle_status==='deleted'?<Btn primary disabled={mutating} onClick={()=>action('restore',{reason:'Restore Provider Contact from managed module'})}><RotateCcw size={14}/>Restore</Btn>:<><Btn disabled={mutating} onClick={()=>setEdit(true)}><Save size={14}/>Edit</Btn><Btn disabled={mutating} onClick={()=>action('verify')}><ShieldCheck size={14}/>Verify today</Btn>{contact.lifecycle_status==='active'?<Btn disabled={mutating} onClick={()=>action('deactivate',{reason:'Deactivate Provider Contact'})}>Deactivate</Btn>:<Btn disabled={mutating} onClick={()=>action('activate',{reason:'Activate Provider Contact'})}>Activate</Btn>}<Btn danger disabled={mutating} onClick={()=>{const reason=window.prompt('Reason for deleting this contact?');if(reason)action('delete',{reason})}}><Trash2 size={14}/>Delete</Btn></>}</div>}</>}</aside></>
}

function ImportPanel({onClose,onApplied,onError,navigate}){
 const[file,setFile]=useState(null),[country,setCountry]=useState('AU'),[dateFormat,setDateFormat]=useState('mdy'),[busy,setBusy]=useState(false),[result,setResult]=useState(null),[detail,setDetail]=useState(null),[history,setHistory]=useState([])
 async function refresh(){try{setHistory(rowsOf(await api.providerContactImports({limit:20,country})))}catch(e){onError(e.message)}}
 useEffect(()=>{refresh()},[country])
 async function upload(){if(!file)return;setBusy(true);try{const r=await api.uploadProviderContactFile({countryCode:country,dateFormat,file});setResult(r);if(r?.batch_id)setDetail(await api.providerContactImportDetail(r.batch_id));await refresh()}catch(e){onError(e.message)}finally{setBusy(false)}}
 async function apply(){if(!result?.batch_id)return;setBusy(true);try{const r=await api.providerContactImportControl({action:'apply',batchId:result.batch_id});setResult(x=>({...x,apply:r}));setDetail(await api.providerContactImportDetail(result.batch_id));await refresh();await onApplied()}catch(e){onError(e.message)}finally{setBusy(false)}}
 const actions=result?.dry_run?.actions||detail?.batch?.dry_run_summary?.actions||{}
 const layer4Pending=Number(result?.dry_run?.layer4_review_pending??detail?.batch?.dry_run_summary?.layer4_review_pending??0)
 const unresolved=Number(actions.provider_ambiguous||0)+Number(actions.provider_unmatched||0)+Number(actions.invalid||0)+Number(actions.conflict||0)
 return <><button className="pc-modal-backdrop" onClick={onClose}/><section className="pc-import-modal"><div className="pc-modal-head"><div><small>PIM Operator import</small><h2>Provider Contact CSV</h2><p>Private Evidence upload → dry-run → reviewed APPLY. Raw contact files are not published to Search, Website or Zoho.</p></div><button onClick={onClose}><X size={18}/></button></div><div className="pc-import-grid"><label><span>Country</span><select value={country} onChange={e=>setCountry(e.target.value)}><option value="AU">Australia</option><option value="NZ">New Zealand</option><option value="CA">Canada</option><option value="GB">United Kingdom</option><option value="US">United States</option><option value="IE">Ireland</option></select></label><label><span>CSV date format</span><select value={dateFormat} onChange={e=>setDateFormat(e.target.value)}><option value="mdy">Month/day/year — 9/1/2026 = 1 Sep 2026</option><option value="dmy">Day/month/year — 9/1/2026 = 9 Jan 2026</option></select></label><label className="wide pc-file-drop"><FileUp size={20}/><span>{file?.name||'Choose Provider Contact CSV'}</span><input type="file" accept=".csv,text/csv" onChange={e=>setFile(e.target.files?.[0]||null)}/></label></div><div className="pc-import-actions"><Btn primary disabled={!file||busy} onClick={upload}><Upload size={14}/>{busy?'Processing…':'Upload & dry-run'}</Btn>{result?.batch_id&&!result?.duplicate&&<Btn primary disabled={busy} onClick={apply}><Check size={14}/>Apply validated rows</Btn>}</div>{result&&<div className="pc-import-summary"><div><small>Batch</small><strong>{result.batch_id||'Existing duplicate'}</strong></div><div><small>Rows</small><strong>{result.row_count??detail?.batch?.dry_run_summary?.rows??'—'}</strong></div><div><small>Unresolved</small><strong>{unresolved}</strong></div><div><small>Layer 4 pending</small><strong>{layer4Pending}</strong></div>{Object.entries(actions).map(([k,v])=><div key={k}><small>{human(k)}</small><strong>{v}</strong></div>)}</div>}{layer4Pending>0&&<div className="pc-layer4-callout"><ShieldCheck size={15}/><div><strong>{layer4Pending} contact reconciliation item(s) parked in Layer 4</strong><small>Deterministic rows can APPLY now. Human decisions remain auditable and do not block the rest of the import.</small></div>{navigate&&<button onClick={()=>{onClose();navigate('Layer 4 — Human Resolution')}}>Open Layer 4</button>}</div>}{detail?.rows?.length>0&&<div className="pc-import-rows"><h3>Dry-run reconciliation</h3>{detail.rows.slice(0,100).map(r=><div key={r.id} className="pc-import-row"><span><strong>#{r.row_number} · {r.normalized_payload?.full_name||r.normalized_payload?.team_name||r.current_institution_name}</strong><small>{r.mapped_provider_name||r.current_institution_name||'Provider unresolved'}</small></span><Badge value={r.proposed_action}/></div>)}</div>}<div className="pc-import-history"><h3>Recent imports</h3>{history.length?history.map(h=><button key={h.id} onClick={async()=>{setResult({batch_id:h.id});setDetail(await api.providerContactImportDetail(h.id))}}><span><strong>{h.original_filename}</strong><small>{fmtDateTime(h.uploaded_at)}</small></span><Badge value={h.status}/></button>):<div className="pc-empty-mini">No import batches yet.</div>}</div></section></>
}

function csvValue(v){let s=v==null?'':String(v);if(/^[=+\-@]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"'}
const exportField=(r,k)=>k==='contact'?(r.full_name||r.team_name||''):(r[k]??'')

export default function ProviderContactsWorkspace({rank,onError,navigate,initialProviderId=''}) {
 const[query,setQuery]=useState(''),[debounced,setDebounced]=useState(''),[offset,setOffset]=useState(0),[sort,setSort]=useState('provider'),[direction,setDirection]=useState('asc'),[data,setData]=useState(null),[busy,setBusy]=useState(false)
 const[filters,setFilters]=useState({country:'',providerId:initialProviderId,lifecycle:'active',recordType:'',sourceAuthority:'',verification:'',hasEmail:'',hasPhone:'',freshness:''}),[providerLabel,setProviderLabel]=useState(initialProviderId?'Selected Provider':'')
 const[selected,setSelected]=useState(''),[adding,setAdding]=useState(false),[importOpen,setImportOpen]=useState(false),[columnsOpen,setColumnsOpen]=useState(false)
 const[columns,setColumns]=useState(()=>{try{const v=JSON.parse(localStorage.getItem('coursefinder:provider-contacts:columns:v1')||'null');return Array.isArray(v)?v:DEFAULT_COLUMNS}catch{return DEFAULT_COLUMNS}})
 useEffect(()=>{const t=setTimeout(()=>setDebounced(query),250);return()=>clearTimeout(t)},[query])
 useEffect(()=>{localStorage.setItem('coursefinder:provider-contacts:columns:v1',JSON.stringify(columns))},[columns])
 const args=useMemo(()=>({limit:PAGE_SIZE,offset,query:debounced,...filters,sort,direction}),[offset,debounced,JSON.stringify(filters),sort,direction])
 async function load(){setBusy(true);try{setData(await api.providerContactsPage(args))}catch(e){onError(e.message)}finally{setBusy(false)}}
 useEffect(()=>{load()},[JSON.stringify(args)])
 useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters),sort,direction])
 const rows=rowsOf(data),total=Number(data?.total||0),summary=data?.summary||{},page=Math.floor(offset/PAGE_SIZE)+1,pages=Math.max(1,Math.ceil(total/PAGE_SIZE))
 const patch=(k,v)=>setFilters(f=>({...f,[k]:v}))
 const changeSort=k=>{if(sort===k)setDirection(d=>d==='asc'?'desc':'asc');else{setSort(k);setDirection('asc')}}
 async function exportCsv(){if(rank<5)return;setBusy(true);try{let all=[],o=0;while(o<10000){const r=await api.providerContactsPage({...args,limit:200,offset:o}),batch=rowsOf(r);all=all.concat(batch);if(batch.length<200||all.length>=Number(r.total||0))break;o+=200}const visible=columns.filter(c=>c.visible!==false),csv=[visible.map(c=>csvValue(c.label)).join(','),...all.map(r=>visible.map(c=>csvValue(exportField(r,c.key))).join(','))].join('\r\n');await api.providerContactExportAudit({rowCount:all.length,filters,columns:visible.map(c=>c.key)});const blob=new Blob([csv],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='provider-contacts-'+new Date().toISOString().slice(0,10)+'.csv';document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(url)}catch(e){onError(e.message)}finally{setBusy(false)}}
 return <div className="pc-page"><section className="pc-hero"><div><span className="pc-kicker"><UsersRound size={14}/>Catalogue module</span><h2>Provider Contacts</h2><p>Manage international recruitment contacts as stable Provider-linked records while preserving A15 observations, Evidence, versions and audit.</p></div><div className="pc-hero-actions">{rank>=5&&<><Btn primary onClick={()=>setAdding(true)}><Plus size={14}/>Add contact</Btn><Btn onClick={()=>setImportOpen(true)}><Upload size={14}/>Import CSV</Btn><Btn disabled={busy} onClick={exportCsv}><Download size={14}/>Export view</Btn></>}<div className="pc-column-anchor"><Btn onClick={()=>setColumnsOpen(x=>!x)}><Columns3 size={14}/>Columns</Btn>{columnsOpen&&<ColumnManager columns={columns} setColumns={setColumns} onClose={()=>setColumnsOpen(false)}/>}</div></div></section>
 <section className="pc-metrics"><div><small>Active contacts</small><strong>{Number(summary.active||0).toLocaleString()}</strong></div><div><small>Providers covered</small><strong>{Number(summary.providers||0).toLocaleString()}</strong></div><div><small>Stale / unverified</small><strong>{Number(summary.stale||0).toLocaleString()}</strong></div><div><small>Deleted / restorable</small><strong>{Number(summary.deleted||0).toLocaleString()}</strong></div></section>
 <section className="pc-panel"><div className="pc-search-row"><label className="pc-search"><Search size={15}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search Provider, contact, title, region, market, email, phone or source…"/>{query&&<button onClick={()=>setQuery('')}><X size={13}/></button>}</label><Btn disabled={busy} onClick={load}><RefreshCw size={14}/>Refresh</Btn></div><div className="pc-filters">
  <label><span>Country</span><select value={filters.country} onChange={e=>patch('country',e.target.value)}><option value="">All</option><option value="AU">Australia</option><option value="NZ">New Zealand</option><option value="CA">Canada</option><option value="GB">United Kingdom</option><option value="US">United States</option><option value="IE">Ireland</option></select></label>
  <label className="provider"><span>Provider</span><ProviderPicker value={filters.providerId} label={providerLabel} onChange={(v,l)=>{patch('providerId',v);setProviderLabel(l)}}/></label>
  <label><span>Status</span><select value={filters.lifecycle} onChange={e=>patch('lifecycle',e.target.value)}><option value="">All</option>{['active','inactive','deleted'].map(x=><option value={x} key={x}>{human(x)}</option>)}</select></label>
  <label><span>Type</span><select value={filters.recordType} onChange={e=>patch('recordType',e.target.value)}><option value="">All</option>{['named_staff','team_contact'].map(x=><option value={x} key={x}>{human(x)}</option>)}</select></label>
  <label><span>Source</span><select value={filters.sourceAuthority} onChange={e=>patch('sourceAuthority',e.target.value)}><option value="">All</option>{['first_party','manual','licensed_enrichment'].map(x=><option value={x} key={x}>{human(x)}</option>)}</select></label>
  <label><span>Verification</span><select value={filters.verification} onChange={e=>patch('verification',e.target.value)}><option value="">All</option>{['current','official_current_page','official_university_source','manual','stale','unverified'].map(x=><option value={x} key={x}>{human(x)}</option>)}</select></label>
  <label><span>Email</span><select value={filters.hasEmail} onChange={e=>patch('hasEmail',e.target.value)}><option value="">Any</option><option value="true">Present</option><option value="false">Missing</option></select></label>
  <label><span>Phone</span><select value={filters.hasPhone} onChange={e=>patch('hasPhone',e.target.value)}><option value="">Any</option><option value="true">Present</option><option value="false">Missing</option></select></label>
  <label><span>Freshness</span><select value={filters.freshness} onChange={e=>patch('freshness',e.target.value)}><option value="">Any</option><option value="current">Verified ≤ 365 days</option><option value="stale">Stale / never verified</option><option value="unverified">Never verified</option></select></label>
 </div><Grid rows={rows} columns={columns} sort={sort} direction={direction} onSort={changeSort} onSelect={setSelected} loading={busy}/><div className="pc-pager"><span>Page <strong>{page}</strong> of {pages} · {total.toLocaleString()} records</span><div><button disabled={!offset} onClick={()=>setOffset(o=>Math.max(0,o-PAGE_SIZE))}>Previous</button><button disabled={offset+PAGE_SIZE>=total} onClick={()=>setOffset(o=>o+PAGE_SIZE)}>Next</button></div></div></section>
 {rank<5&&<div className="pc-readonly"><ShieldCheck size={15}/><span>Read-only view. PIM Operator or Platform Admin is required for create, edit, import, export, delete and restore.</span></div>}
 {(selected||adding)&&<Drawer id={selected} isNew={adding} rank={rank} onClose={()=>{setSelected('');setAdding(false)}} onChanged={load} onError={onError}/>}
 {importOpen&&<ImportPanel onClose={()=>setImportOpen(false)} onApplied={load} onError={onError} navigate={navigate}/>}
 </div>
}
