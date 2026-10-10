// Record editing (v2.15.114, Decision 179 "CRUD first"): add, change and remove course and provider values by hand.
// A value entered here always wins: automation (Layer 1 sync, provider rules, Layer 3 and the page reader) does not
// overwrite it, and a value removed here is not filled in again, until someone chooses "Let automation update this".
// Curator and above edit values; PIM Operator and above add, archive and restore courses and providers.
// Read/write: public.admin_course_edit_read / admin_course_edit / admin_course_create,
// public.admin_provider_edit_read / admin_provider_edit / admin_provider_create
// (migration 20260930120000_cf247_crud_manual_first).
import React,{useEffect,useRef,useState}from'react'
import{Archive,Check,History,Lock,Pencil,Plus,RotateCcw,Trash2,Unlock,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'
import{CourseLinks,CURRENCY_BY_COUNTRY,ProviderApplicants}from'./CourseLinks'

export const MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December']
export const BASIS={annual:'Per year',per_semester:'Per semester',per_trimester:'Per trimester',total_indicative:'Whole course'}
const FIELD={official_url:'Official course page',intakes:'Intakes',english:'English requirement',tuition:'Tuition (international)',display_title:'Title',description:'Description',duration_value:'Duration',duration_unit:'Duration unit',delivery_mode:'Delivery',lifecycle_status:'Status',course_url:'Official course page',display_name:'Name',short_name:'Short name',website:'Website',phone:'Phone',email:'Email',primary_city:'City',address_line1:'Address',postcode:'Postcode',course_finder:'Course finder address'}
const ACTION={set_core:'Changed',set_official_url:'Set official page',remove_official_url:'Removed official page',set_intakes:'Set intakes',remove_intakes:'Removed intakes',set_english:'Set English requirement',remove_english:'Removed English requirement',set_tuition:'Set tuition',remove_tuition:'Removed tuition',release:'Handed back to automation',archive:'Archived',restore:'Restored',create:'Created',set_course_finder:'Set course finder address'}
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')

function useRecord(read,idKey,id,onError){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false)
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc(read,{[idKey]:id});if(error)throw error;setData(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{if(id)load()},[id])
  return[data,setData,busy,setBusy,load]
}

// v2.15.233 (Feature 1): whose an address is. Only the provider's own site, the regulator or a value entered by hand is used.
const SITE_VERDICT={own:['Provider\u2019s own site','tone-success'],regulator:['Regulator','tone-info'],third_party:['Third-party site: not used','tone-danger'],unconfirmed:['Not confirmed as the provider\u2019s own','tone-warning']}
function SiteVerdict({v}){const x=SITE_VERDICT[v];return x?<small className={`cf-chip ${x[1]}`} data-site-verdict={v}>{x[0]}</small>:null}
function LockNote({lock,onRelease,can}){
  // v2.15.225: a short coloured pill; the release link stays beside it
  if(!lock)return <span className="re-auto">Automated</span>
  return <span className="re-lock-wrap"><span className="re-lock" title="Automation will not change this value"><Lock size={11}/>{lock.mode==='removed'?'Removed by hand':'Entered by hand'}</span>
    {can&&<button type="button" className="re-link" onClick={onRelease}><Unlock size={11}/>Let automation update this</button>}</span>
}

function Row({label,lock,can,onRelease,children,editor,editing,setEditing,onRemove,removeLabel,wide=false}){
  return <div className={`re-row${editing?' editing':''}${wide?' wide':''}`}>
    <div className="re-row-head"><strong>{label}</strong><LockNote lock={lock} onRelease={onRelease} can={can}/></div>
    {editing?editor:<div className="re-row-body"><div className="re-value">{children}</div>{can&&<div className="re-actions">
      <Button compact onClick={()=>setEditing(true)} aria-label={`Change ${label}`}><Pencil size={13}/>Change</Button>
      {onRemove&&<Button compact variant="danger" onClick={onRemove} aria-label={`${removeLabel||'Remove'} ${label}`}><Trash2 size={13}/>{removeLabel||'Remove'}</Button>}
    </div>}</div>}
  </div>
}

function EditorFoot({onSave,onCancel,busy,valid=true}){return <div className="re-foot"><Button compact variant="primary" onClick={onSave} disabled={busy||!valid}><Check size={13}/>{busy?'Saving…':'Save'}</Button><Button compact onClick={onCancel} disabled={busy}><X size={13}/>Cancel</Button></div>}

function TextEdit({value,multiline,type='text',onSave,onCancel,busy,placeholder}){
  const[v,setV]=useState(value??'')
  return <div className="re-editor">{multiline?<textarea className="fv-input re-text" rows={4} value={v} onChange={e=>setV(e.target.value)}/>:<input className="fv-input" type={type} value={v} placeholder={placeholder} onChange={e=>setV(e.target.value)} autoFocus/>}
    <EditorFoot busy={busy} onSave={()=>onSave(v)} onCancel={onCancel}/></div>
}

function IntakeEdit({rows,onSave,onCancel,busy}){
  const year=new Date().getFullYear()+1
  const[list,setList]=useState(rows?.length?rows.map(r=>({label:MONTHS.find(m=>String(r.label||'').includes(m))||r.label||'',year:r.year?String(r.year):''})):[{label:'February',year:String(year)}])
  const set=(i,k,v)=>setList(l=>l.map((x,j)=>j===i?{...x,[k]:v}:x))
  return <div className="re-editor">{list.map((x,i)=><div className="re-line" key={i}>
      <select className="fv-input" value={MONTHS.includes(x.label)?x.label:''} onChange={e=>set(i,'label',e.target.value)} aria-label={`Intake ${i+1} month`}><option value="">{x.label&&!MONTHS.includes(x.label)?x.label:'Month…'}</option>{MONTHS.map(m=><option key={m}>{m}</option>)}</select>
      <input className="fv-input re-year" inputMode="numeric" placeholder="Year (optional)" value={x.year} onChange={e=>set(i,'year',e.target.value.replace(/\D/g,'').slice(0,4))} aria-label={`Intake ${i+1} year`}/>
      <Button compact onClick={()=>setList(l=>l.filter((_,j)=>j!==i))} disabled={list.length<2} aria-label={`Remove intake ${i+1}`}><X size={13}/></Button></div>)}
    <Button compact onClick={()=>setList(l=>[...l,{label:'',year:list[list.length-1]?.year||''}])}><Plus size={13}/>Add intake</Button>
    <EditorFoot busy={busy} valid={list.every(x=>x.label)} onSave={()=>onSave(list.map(x=>({label:x.label,...(x.year?{year:x.year}:{})})))} onCancel={onCancel}/></div>
}

function EnglishEdit({rows,tests,onSave,onCancel,busy}){
  const[list,setList]=useState(rows?.length?rows.map(r=>({test:r.test,overall:r.overall!=null?String(Number(r.overall)):'',min_band:r.components?.min_band!=null?String(r.components.min_band):''})):[{test:'IELTS',overall:'',min_band:''}])
  const set=(i,k,v)=>setList(l=>l.map((x,j)=>j===i?{...x,[k]:v}:x))
  const num=v=>v===''||/^\d+(\.\d+)?$/.test(v)
  return <div className="re-editor">{list.map((x,i)=><div className="re-line" key={i}>
      <select className="fv-input" value={x.test} onChange={e=>set(i,'test',e.target.value)} aria-label={`Test ${i+1}`}>{(tests||[]).map(t=><option key={t.code} value={t.code}>{t.name}</option>)}</select>
      <input className="fv-input re-score" inputMode="decimal" placeholder="Overall" value={x.overall} onChange={e=>set(i,'overall',e.target.value)} aria-label={`Test ${i+1} overall score`}/>
      <input className="fv-input re-score" inputMode="decimal" placeholder="Lowest band (optional)" value={x.min_band} onChange={e=>set(i,'min_band',e.target.value)} aria-label={`Test ${i+1} lowest band`}/>
      <Button compact onClick={()=>setList(l=>l.filter((_,j)=>j!==i))} disabled={list.length<2} aria-label={`Remove test ${i+1}`}><X size={13}/></Button></div>)}
    <Button compact onClick={()=>setList(l=>[...l,{test:(tests||[]).find(t=>!l.some(x=>x.test===t.code))?.code||'PTE',overall:'',min_band:''}])} disabled={list.length>=(tests||[]).length}><Plus size={13}/>Add test</Button>
    <EditorFoot busy={busy} valid={list.every(x=>x.overall!==''&&num(x.overall)&&num(x.min_band))&&new Set(list.map(x=>x.test)).size===list.length}
      onSave={()=>onSave(list.map(x=>({test:x.test,overall:x.overall,...(x.min_band?{components:{min_band:Number(x.min_band)}}:{})})))} onCancel={onCancel}/></div>
}

function TuitionEdit({row,onSave,onCancel,busy,currency='AUD'}){
  const[v,setV]=useState({amount:row?.amount!=null?String(Math.round(Number(row.amount))):'',fee_year:row?.fee_year?String(row.fee_year):String(new Date().getFullYear()+1),basis:BASIS[row?.basis]?row.basis:'annual',currency:row?.currency||currency})
  return <div className="re-editor"><div className="re-line">
      <input className="fv-input re-amount" inputMode="numeric" placeholder="Amount, e.g. 45000" value={v.amount} onChange={e=>setV({...v,amount:e.target.value.replace(/[^\d.]/g,'')})} aria-label="Tuition amount"/>
      <select className="fv-input" value={v.currency} onChange={e=>setV({...v,currency:e.target.value})} aria-label="Currency">{['AUD','NZD','CAD','GBP','USD','EUR'].map(c=><option key={c}>{c}</option>)}</select>
      <select className="fv-input" value={v.basis} onChange={e=>setV({...v,basis:e.target.value})} aria-label="Fee period">{Object.entries(BASIS).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
      <input className="fv-input re-year" inputMode="numeric" placeholder="Fee year" value={v.fee_year} onChange={e=>setV({...v,fee_year:e.target.value.replace(/\D/g,'').slice(0,4)})} aria-label="Fee year"/></div>
    <EditorFoot busy={busy} valid={Number(v.amount)>=100} onSave={()=>onSave(v)} onCancel={onCancel}/></div>
}

function HistoryList({rows}){
  if(!rows?.length)return null
  return <details className="re-history"><summary><History size={12}/>Changes made by hand ({rows.length})</summary><ul>{rows.map((h,i)=><li key={i}><span>{fmtDateTime(h.at)}</span><strong>{ACTION[h.action]||h.action}{h.field&&h.action!=='create'?` · ${FIELD[h.field]||h.field}`:''}</strong><small>{[h.by,h.reason].filter(Boolean).join(' · ')}</small></li>)}</ul></details>
}

// v2.15.159 (Platform Admin, 3 Oct 2026 09:26: "the existing field that has the data needs the edit button, not another
// foldable edit field"): inline mode shows every value with its Change button as soon as the course opens; no fold,
// no separate comparison strip. The fold stays available for the older callers.
export function CourseEditor({courseId,onChanged,onError,inline=false}){
  const[data,setData,busy,setBusy]=useRecord('admin_course_edit_read','p_course_id',courseId,onError)
  const[open,setOpen]=useState(inline),[editing,setEditing]=useState(''),[reason,setReason]=useState(''),[country,setCountry]=useState('')
  useEffect(()=>{if(!courseId)return;supabase.rpc('admin_course_links_read',{p_course_id:courseId}).then(({data:d})=>setCountry(d?.applicants?.country||'')).catch(()=>{})},[courseId])
  if(!data)return busy?<section className="m-detail-section re-panel"><Loading label="Loading editable values…"/></section>:null
  const c=data.course||{},locks=data.locks||{},can=Boolean(data.can_edit)&&!busy
  const act=async(action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_course_edit',{p_course_id:courseId,p_action:action,p_args:{...args,...(reason.trim()?{reason:reason.trim()}:{})}});if(error)throw error;setData(d);setEditing('');onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const release=f=>act('release',{field:f},`Let automation update ${FIELD[f]||f} again? The next automated value may replace this one.`)
  const ed=k=>({editing:editing===k,setEditing:x=>setEditing(x?k:'')})
  const link=(data.official_links||[])[0],tuition=(data.tuition||[])[0],manualCount=Object.keys(locks).filter(k=>k!=='course_url').length
  return <section className="m-detail-section re-panel" data-editor="course">
    {inline?<div className="re-toggle re-static"><Pencil size={14}/><span><strong>Course values</strong><small>{manualCount?`${manualCount} value${manualCount===1?'':'s'} entered by hand`:'All from automation'}</small></span></div>
    :<button type="button" className="re-toggle" onClick={()=>setOpen(o=>!o)} aria-expanded={open}><Pencil size={14}/><span><strong>Edit this course</strong><small>{manualCount?`${manualCount} value${manualCount===1?'':'s'} entered by hand`:'All values come from automation'}</small></span><span className="re-caret">{open?'Hide':'Show'}</span></button>}
    {open&&<div className={`re-body${inline?' re-grid':''}`}>
      {!data.can_edit&&<p className="l3v-note">You can view these values. A Curator or above can change them.</p>}
      {data.can_edit&&<label className="re-reason"><small>Reason for the change (optional)</small><input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="e.g. Checked on the university website 1 Oct 2026"/></label>}
      <Row wide label="Official course page" lock={locks.official_url} can={can} onRelease={()=>release('official_url')} {...ed('url')}
        onRemove={link?()=>act('remove_official_url',{},'Record that this course has no official page? The page search stops for this course.'):null} removeLabel="No page"
        editor={<TextEdit value={link?.url} type="url" placeholder="https://" busy={busy} onSave={v=>act('set_official_url',{url:v})} onCancel={()=>setEditing('')}/>}>
        {link?<a href={link.url} target="_blank" rel="noreferrer" className="cf-link">{link.url}</a>:locks.official_url?.mode==='removed'?'No official page':'—'}
      </Row>
      <CourseLinks courseId={courseId} reason={reason} onChanged={onChanged} onError={onError}/>
      <Row label="Intakes" lock={locks.intakes} can={can} onRelease={()=>release('intakes')} {...ed('intakes')}
        onRemove={data.intakes?.length?()=>act('remove_intakes',{},'Remove all intakes for this course? Automation will not add them back.'):null}
        editor={<IntakeEdit rows={data.intakes} busy={busy} onSave={v=>act('set_intakes',{intakes:v})} onCancel={()=>setEditing('')}/>}>
        {data.intakes?.length?data.intakes.map(x=>[x.label,x.year].filter(Boolean).join(' ')).join(', '):'—'}
      </Row>
      <Row label="English requirement" lock={locks.english} can={can} onRelease={()=>release('english')} {...ed('english')}
        onRemove={data.english?.length?()=>act('remove_english',{},'Remove the English requirement for this course? Automation will not add it back.'):null}
        editor={<EnglishEdit rows={data.english} tests={data.english_tests} busy={busy} onSave={v=>act('set_english',{tests:v})} onCancel={()=>setEditing('')}/>}>
        {data.english?.length?data.english.map(x=>`${x.test_name} ${Number(x.overall)}${x.components?.min_band!=null?` (no band below ${x.components.min_band})`:''}`).join('; '):'—'}
      </Row>
      <Row label="Tuition from the course page (international)" lock={locks.tuition} can={can} onRelease={()=>release('tuition')} {...ed('tuition')}
        onRemove={tuition?()=>act('remove_tuition',{},'Remove the current tuition for this course? Automation will not add it back.'):null}
        editor={<TuitionEdit row={tuition} currency={CURRENCY_BY_COUNTRY[country]||'AUD'} busy={busy} onSave={v=>act('set_tuition',v)} onCancel={()=>setEditing('')}/>}>
        {tuition?`${fmtMoney(tuition.amount,tuition.currency||CURRENCY_BY_COUNTRY[country]||'AUD')} · ${BASIS[tuition.basis]||String(tuition.basis||'').replaceAll('_',' ')}${tuition.fee_year?` · ${tuition.fee_year}`:''}`:country==='AU'?<span>— <span className="l3v-code" data-tuition-note>None on the course page; the registered CRICOS cost applies</span></span>:'—'}
      </Row>
      <Row label="Title shown" lock={locks.display_title} can={can} onRelease={()=>release('display_title')} {...ed('title')}
        editor={<TextEdit value={c.display_title||c.canonical_title} busy={busy} onSave={v=>act('set_core',{field:'display_title',value:v})} onCancel={()=>setEditing('')}/>}>
        {c.display_title||c.canonical_title}{c.display_title&&c.display_title!==c.canonical_title&&<span className="l3v-code">Registered title: {c.canonical_title}</span>}
      </Row>
      <Row label="Duration" lock={locks.duration_value} can={can} onRelease={()=>release('duration_value')} {...ed('duration')}
        editor={<TextEdit value={c.duration_value!=null?String(Number(c.duration_value)):''} placeholder={`Number of ${c.duration_unit||'weeks'}`} busy={busy} onSave={v=>act('set_core',{field:'duration_value',value:v})} onCancel={()=>setEditing('')}/>}>
        {c.duration_value!=null?`${fmtNumber(Number(c.duration_value))} ${c.duration_unit||''}`:'—'}
      </Row>
      <Row label="Delivery" lock={locks.delivery_mode} can={can} onRelease={()=>release('delivery_mode')} {...ed('delivery')}
        editor={<TextEdit value={c.delivery_mode} placeholder="e.g. On campus" busy={busy} onSave={v=>act('set_core',{field:'delivery_mode',value:v})} onCancel={()=>setEditing('')}/>}>
        {c.delivery_mode||'—'}
      </Row>
      <Row wide label="Description" lock={locks.description} can={can} onRelease={()=>release('description')} {...ed('description')}
        editor={<TextEdit value={c.description} multiline busy={busy} onSave={v=>act('set_core',{field:'description',value:v})} onCancel={()=>setEditing('')}/>}>
        <span className="re-desc">{c.description||'—'}</span>
      </Row>
      {data.can_manage&&<div className="re-manage"><span>Course status: <StatusChip value={c.lifecycle_status} tone={c.lifecycle_status==='active'?'success':'warning'} label={c.lifecycle_status==='active'?'Active':'Archived'}/></span>
        {c.lifecycle_status==='active'?<Button compact variant="danger" onClick={()=>act('archive',{},'Archive this course? It stops being searched for and processed. You can restore it later.')} disabled={busy}><Archive size={13}/>Archive course</Button>
          :<Button compact onClick={()=>act('restore')} disabled={busy}><RotateCcw size={13}/>Restore course</Button>}</div>}
      <HistoryList rows={data.history}/>
    </div>}
  </section>
}

// v2.15.166 (Platform Admin, 3 Oct 2026 14:12: "provide the fields to be edited inline — no collapse"): inline mode shows
// the provider's values with their Change buttons as soon as the drawer opens, grouped by priority — identity (name,
// website, city, course finder, applicants, description), then the read-only facts passed in `facts`, then contact
// details — so the page reads header › provider values › contacts › rankings. The fold stays for older callers.
export function ProviderEditor({providerId,onChanged,onError,inline=false,facts=null}){
  const[data,setData,busy,setBusy]=useRecord('admin_provider_edit_read','p_provider_id',providerId,onError)
  const[open,setOpen]=useState(inline),[editing,setEditing]=useState(''),[reason,setReason]=useState('')
  if(!data)return busy?<section className="m-detail-section re-panel"><Loading label="Loading editable values…"/></section>:null
  const p=data.provider||{},locks=data.locks||{},can=Boolean(data.can_edit)&&!busy,cf=data.course_finder
  const act=async(action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_provider_edit',{p_provider_id:providerId,p_action:action,p_args:{...args,...(reason.trim()?{reason:reason.trim()}:{})}});if(error)throw error;setData(d);setEditing('');onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const release=f=>act('release',{field:f},`Let automation update ${FIELD[f]||f} again?`)
  const ed=k=>({editing:editing===k,setEditing:x=>setEditing(x?k:'')})
  const text=(key,label,opts={})=><Row key={key} wide={Boolean(opts.multiline)} label={label} lock={locks[key]} can={can} onRelease={()=>release(key)} {...ed(key)}
      editor={<TextEdit value={p[key]} type={opts.type} multiline={opts.multiline} placeholder={opts.placeholder} busy={busy} onSave={v=>act('set_core',{field:key,value:v})} onCancel={()=>setEditing('')}/>}>
      {opts.link&&p[key]?<><a href={p[key]} target="_blank" rel="noreferrer" className="cf-link">{p[key]}</a>{opts.extra}</>:<span className={opts.multiline?'re-desc':''}>{p[key]||'—'}</span>}</Row>
  const manualCount=Object.keys(locks).length
  return <section className="m-detail-section re-panel" data-editor="provider">
    {inline?<div className="re-toggle re-static"><Pencil size={14}/><span><strong>Provider values</strong><small>{manualCount?`${manualCount} value${manualCount===1?'':'s'} entered by hand`:'All from automation'}</small></span></div>
    :<button type="button" className="re-toggle" onClick={()=>setOpen(o=>!o)} aria-expanded={open}><Pencil size={14}/><span><strong>Edit this provider</strong><small>{manualCount?`${manualCount} value${manualCount===1?'':'s'} entered by hand`:'All values come from automation'}</small></span><span className="re-caret">{open?'Hide':'Show'}</span></button>}
    {open&&<div className={`re-body${inline?' re-grid':''}`}>
      {!data.can_edit&&<p className="l3v-note">You can view these values. A Curator or above can change them.</p>}
      {data.can_edit&&<label className="re-reason"><small>Reason for the change (optional)</small><input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)}/></label>}
      {text('display_name','Name shown')}
      {text('website','Website',{type:'url',link:true,placeholder:'https://',extra:<> <SiteVerdict v={p.website_verdict}/></>})}
      {inline&&text('primary_city','City')}
      <ProviderApplicants providerId={providerId} onChanged={onChanged} onError={onError}/>
      <Row label="Course finder address" lock={locks.course_finder} can={can} onRelease={()=>release('course_finder')} {...ed('finder')}
        editor={<TextEdit value={cf?.address} type="url" placeholder="https://… the page or site that lists the courses" busy={busy} onSave={v=>act('set_course_finder',{url:v},'Use this address to find course pages? The provider goes back into page discovery.')} onCancel={()=>setEditing('')}/>}>
        {cf?.address?<><a href={cf.address} target="_blank" rel="noreferrer" className="cf-link">{cf.address}</a> <SiteVerdict v={cf.verdict}/><span className="l3v-code">{[cf.status,cf.pages_found!=null&&`${fmtNumber(cf.pages_found)} course pages found`,cf.mapped_at&&`last looked ${fmtDateTime(cf.mapped_at)}`].filter(Boolean).join(' · ')}</span></>:<span className="l3v-code">{cf?.status==='no_website'?'Not found yet: the website search is looking for the provider\u2019s own site':'—'}</span>}
      </Row>
      {inline&&text('description','Description',{multiline:true})}
      {facts}
      {inline&&<h4 className="re-group">Contact details</h4>}
      {text('phone','Phone')}
      {text('email','Email',{type:'email'})}
      {text('address_line1','Address')}
      {!inline&&text('primary_city','City')}
      {text('postcode','Postcode')}
      {!inline&&text('description','Description',{multiline:true})}
      {data.can_manage&&<div className="re-manage"><span>Provider status: <StatusChip value={p.lifecycle_status} tone={p.lifecycle_status==='active'?'success':'warning'} label={p.lifecycle_status==='active'?'Active':'Archived'}/></span>
        {p.lifecycle_status==='active'?<Button compact variant="danger" onClick={()=>act('archive',{},'Archive this provider? Its courses stay as they are. You can restore it later.')} disabled={busy}><Archive size={13}/>Archive provider</Button>
          :<Button compact onClick={()=>act('restore')} disabled={busy}><RotateCcw size={13}/>Restore provider</Button>}</div>}
      <HistoryList rows={data.history}/>
    </div>}
  </section>
}

function ProviderPicker({value,onPick,onError}){
  const[q,setQ]=useState(''),[hits,setHits]=useState([]),t=useRef(null)
  useEffect(()=>{clearTimeout(t.current);if(q.trim().length<2){setHits([]);return}t.current=setTimeout(async()=>{try{const{data,error}=await supabase.rpc('admin_priority_search',{p_kind:'provider',p_q:q.trim()});if(error)throw error;setHits(data||[])}catch(e){onError?.(errText(e))}},300);return()=>clearTimeout(t.current)},[q])
  if(value)return <div className="re-picked"><strong>{value.label}</strong><Button compact onClick={()=>onPick(null)}><X size={13}/>Change</Button></div>
  return <div><input className="fv-input" type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Type the provider name" aria-label="Find the provider"/>
    {hits.length>0&&<ul className="pq-hits">{hits.map(h=><li key={h.id}><div><strong>{h.label}</strong><span className="l3v-code">{h.detail}</span></div><Button compact variant="primary" onClick={()=>onPick(h)}><Plus size={13}/>Choose</Button></li>)}</ul>}</div>
}

export function CreateRecord({type,onCreated,onClose,onError}){
  const[v,setV]=useState({}),[provider,setProvider]=useState(null),[lists,setLists]=useState({countries:[],states:[]}),[busy,setBusy]=useState(false)
  useEffect(()=>{if(type!=='provider')return;supabase.rpc('admin_priority_read').then(({data})=>setLists({countries:data?.countries||[],states:data?.states||[]}))},[type])
  const set=(k,x)=>setV(s=>({...s,[k]:x}))
  const save=async()=>{setBusy(true);try{const args=type==='course'?{...v,provider_id:provider?.id}:v;const{data,error}=await supabase.rpc(type==='course'?'admin_course_create':'admin_provider_create',{p_args:args});if(error)throw error;onCreated?.(type==='course'?data?.course?.id:data?.provider?.id)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const valid=type==='course'?Boolean(provider&&v.title?.trim()):Boolean(v.name?.trim()&&v.country_id)
  const country=lists.countries.find(c=>c.id===v.country_id)
  return <div className="re-modal-backdrop" role="dialog" aria-modal="true" aria-label={`Add a ${type}`}><div className="re-modal">
    <div className="re-modal-head"><h3>{type==='course'?'Add a course':'Add a provider'}</h3><button type="button" onClick={onClose} aria-label="Close"><X size={16}/></button></div>
    <p className="l3v-note">{type==='course'?'For a course that is not on a register. Registered courses (for example CRICOS) arrive automatically.':'For a provider that is not on a register. Registered providers arrive automatically.'}</p>
    {type==='course'?<div className="re-form">
      <div className="re-field"><small>Provider</small><ProviderPicker value={provider} onPick={setProvider} onError={onError}/></div>
      <label><small>Course title</small><input className="fv-input" value={v.title||''} onChange={e=>set('title',e.target.value)}/></label>
      <label><small>Course code (optional, e.g. the CRICOS code)</small><input className="fv-input" value={v.course_code||''} onChange={e=>set('course_code',e.target.value.toUpperCase())}/></label>
      <div className="re-line"><label><small>Duration (optional)</small><input className="fv-input re-year" inputMode="decimal" value={v.duration_value||''} onChange={e=>set('duration_value',e.target.value.replace(/[^\d.]/g,''))}/></label>
        <label><small>Unit</small><select className="fv-input" value={v.duration_unit||'weeks'} onChange={e=>set('duration_unit',e.target.value)}>{['weeks','months','years'].map(u=><option key={u}>{u}</option>)}</select></label>
        <label><small>Delivery (optional)</small><input className="fv-input" value={v.delivery_mode||''} onChange={e=>set('delivery_mode',e.target.value)} placeholder="e.g. On campus"/></label></div>
      <label><small>Description (optional)</small><textarea className="fv-input re-text" rows={3} value={v.description||''} onChange={e=>set('description',e.target.value)}/></label>
    </div>:<div className="re-form">
      <label><small>Provider name</small><input className="fv-input" value={v.name||''} onChange={e=>set('name',e.target.value)}/></label>
      <div className="re-line"><label><small>Country</small><select className="fv-input" value={v.country_id||''} onChange={e=>setV(s=>({...s,country_id:e.target.value,subdivision_id:''}))}><option value="">Choose…</option>{lists.countries.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label><small>State or region (optional)</small><select className="fv-input" value={v.subdivision_id||''} onChange={e=>set('subdivision_id',e.target.value)} disabled={!v.country_id}><option value="">—</option>{lists.states.filter(s=>country&&s.country===country.name).map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label></div>
      <label><small>Website (optional)</small><input className="fv-input" type="url" placeholder="https://" value={v.website||''} onChange={e=>set('website',e.target.value)}/></label>
      <label><small>City (optional)</small><input className="fv-input" value={v.city||''} onChange={e=>set('city',e.target.value)}/></label>
    </div>}
    <label className="re-reason"><small>Reason (optional, kept in the history)</small><input className="fv-input" value={v.reason||''} onChange={e=>set('reason',e.target.value)}/></label>
    <div className="re-foot"><Button compact variant="primary" onClick={save} disabled={busy||!valid}><Plus size={13}/>{busy?'Adding…':type==='course'?'Add course':'Add provider'}</Button><Button compact onClick={onClose} disabled={busy}>Cancel</Button></div>
  </div></div>
}
