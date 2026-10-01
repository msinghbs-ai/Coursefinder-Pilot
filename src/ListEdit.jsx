// Edit in the list (v2.15.120): Courses and Providers can be edited in place in the list, one cell at a time.
// Platform Admin, 1 Oct 2026: "can this be modernise and have inline edit on existing fields? Or better edit in list
// view on visible columns?"
// Click a cell (or Tab to it and press Enter) to edit; Enter or leaving the cell saves, Esc cancels. Each save uses the
// same per-field edit as the record drawer, so it is role-checked, logged, and locked so automation will not change it.
// Read: public.admin_catalogue_edit_rows(type, ids) (migration 20260930180000_cf247_list_edit_rows);
// write: public.admin_course_edit / public.admin_provider_edit (migration 20260930120000_cf247_crud_manual_first).
import React,{useEffect,useRef,useState}from'react'
import{Check,Lock}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Loading}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const UNITS=['weeks','months','years']

export const LIST_EDIT={
  course:{rpc:'admin_course_edit',idArg:'p_course_id',label:r=>r.canonical_title,sub:r=>[r.provider_name,r.course_code].filter(Boolean).join(' · '),
    fields:[
      {key:'display_title',label:'Title',width:280},
      {key:'duration',label:'Duration',width:170,kind:'duration'},
      {key:'delivery_mode',label:'Delivery',width:160,placeholder:'e.g. On campus'},
      {key:'official_url',label:'Course page',width:280,kind:'url',action:'set_official_url'},
    ]},
  provider:{rpc:'admin_provider_edit',idArg:'p_provider_id',label:r=>r.canonical_name,sub:r=>[r.country_code,r.subdivision_name].filter(Boolean).join(' · '),
    fields:[
      {key:'display_name',label:'Name',width:260},
      {key:'primary_city',label:'City',width:150},
      {key:'website',label:'Website',width:240,kind:'url'},
      {key:'phone',label:'Phone',width:150},
      {key:'email',label:'Email',width:210},
    ]},
}

export default function ListEdit({type,rows,onError}){
  const cfg=LIST_EDIT[type],ids=rows.map(r=>r.id??r.course_id).filter(Boolean)
  const[vals,setVals]=useState(null),[can,setCan]=useState(false),[saving,setSaving]=useState(''),[saved,setSaved]=useState(''),[rowErr,setRowErr]=useState({})
  useEffect(()=>{let live=true;setVals(null);(async()=>{try{const{data,error}=await supabase.rpc('admin_catalogue_edit_rows',{p_type:type,p_ids:ids});if(error)throw error;if(live){setVals(data?.rows||{});setCan(Boolean(data?.can_edit))}}catch(e){onError?.(errText(e))}})();return()=>{live=false}},[type,ids.join(',')])
  if(!vals)return <Loading label="Loading editable fields…"/>
  const save=async(id,field,value)=>{
    const key=`${id}:${field.key}`,cur=vals[id]||{}
    const calls=field.kind==='duration'
      ?[...(String(value.value??'')!==String(cur.duration_value??'')?[{action:'set_core',args:{field:'duration_value',value:value.value===''?null:value.value},lock:'duration_value'}]:[]),
        ...(value.unit!==(cur.duration_unit||'')?[{action:'set_core',args:{field:'duration_unit',value:value.unit||null},lock:'duration_unit'}]:[])]
      :String(value??'')===String(cur[field.key]??'')?[]
      :field.action==='set_official_url'?[{action:value?'set_official_url':'remove_official_url',args:value?{url:value}:{},lock:'official_url'}]
      :[{action:'set_core',args:{field:field.key,value:value===''?null:value},lock:field.key}]
    if(!calls.length)return true
    setSaving(key);setRowErr(x=>({...x,[id]:''}))
    try{
      for(const c of calls){const{error}=await supabase.rpc(cfg.rpc,{[cfg.idArg]:id,p_action:c.action,p_args:c.args});if(error)throw error}
      setVals(v=>{const r={...(v[id]||{})};if(field.kind==='duration'){r.duration_value=value.value===''?null:value.value;r.duration_unit=value.unit||null}else r[field.key]=value||null;r.locks={...(r.locks||{}),...Object.fromEntries(calls.map(c=>[c.lock,'value']))};return{...v,[id]:r}})
      setSaved(key);setTimeout(()=>setSaved(s=>s===key?'':s),2000);return true
    }catch(e){setRowErr(x=>({...x,[id]:errText(e)}));return false}finally{setSaving('')}
  }
  return <div className="m-table-wrap le-wrap"><table className="m-table le-table" data-list-edit={type}>
    <thead><tr><th style={{minWidth:220}}>{type==='course'?'Course':'Provider'}</th>{cfg.fields.map(f=><th key={f.key} style={{minWidth:f.width}}>{f.label}</th>)}</tr></thead>
    <tbody>{rows.map(r=>{const id=r.id??r.course_id,v=vals[id]||{},locks=v.locks||{}
      return <React.Fragment key={id}><tr data-edit-row={id}>
        <td><span className="m-cell-title"><strong>{cfg.label(r)||'—'}</strong><small>{cfg.sub(r)}</small></span></td>
        {cfg.fields.map(f=>{const k=`${id}:${f.key}`,locked=f.kind==='duration'?(locks.duration_value||locks.duration_unit):locks[f.key]
          return <td key={f.key} className="le-cell"><Cell field={f} value={f.kind==='duration'?{value:v.duration_value!=null?String(Number(v.duration_value)):'',unit:v.duration_unit||''}:(v[f.key]??'')} can={can} busy={saving===k} ok={saved===k} locked={Boolean(locked)} label={`${f.label} for ${cfg.label(r)}`} onSave={x=>save(id,f,x)}/></td>})}
      </tr>{rowErr[id]&&<tr className="le-err-row"><td colSpan={cfg.fields.length+1}><p className="fr-error" role="alert">{rowErr[id]}</p></td></tr>}</React.Fragment>})}</tbody>
  </table>
  <p className="l3v-note"><Lock size={11}/> marks a value entered by hand: automation will not change it. Open the record to let automation update it again.</p></div>
}

function Cell({field,value,can,busy,ok,locked,label,onSave}){
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(value),ref=useRef(null)
  useEffect(()=>{if(!edit)setDraft(field.kind==='duration'?{...value,unit:value.unit||'weeks'}:value)},[JSON.stringify(value),edit])
  useEffect(()=>{if(edit)ref.current?.focus()},[edit])
  const shown=field.kind==='duration'?(value.value?`${value.value} ${value.unit||''}`.trim():''):String(value||'')
  const commit=async()=>{if(await onSave(field.kind==='duration'?draft:String(draft).trim()))setEdit(false)}
  const key=e=>{if(e.key==='Escape'){setEdit(false)}if(e.key==='Enter'){e.preventDefault();commit()}}
  const blur=e=>{if(!e.currentTarget.contains(e.relatedTarget))commit()}
  if(!can)return <span className="le-view">{shown||'—'}{locked&&<Lock size={11} className="le-lock" aria-label="Entered by hand"/>}</span>
  if(!edit)return <button type="button" className={`le-view le-btn${ok?' le-ok':''}`} aria-label={`Edit ${label}`} onClick={()=>setEdit(true)}>
    <span className={shown?'':'le-empty'}>{shown||'Add'}</span>{locked&&<Lock size={11} className="le-lock" aria-label="Entered by hand"/>}{ok&&<Check size={12} className="le-tick"/>}</button>
  if(field.kind==='duration')return <span className="le-duration" onBlur={blur} onKeyDown={key}>
    <input ref={ref} className="fv-input" inputMode="decimal" aria-label={label} value={draft.value} onChange={e=>setDraft(d=>({...d,value:e.target.value}))} disabled={busy}/>
    <select className="fv-input" aria-label={`${label} unit`} value={draft.unit||'weeks'} onChange={e=>setDraft(d=>({...d,unit:e.target.value}))} disabled={busy}>{UNITS.map(u=><option key={u}>{u}</option>)}</select></span>
  return <input ref={ref} className="fv-input le-input" type={field.kind==='url'?'url':'text'} aria-label={label} value={draft} placeholder={field.placeholder||''} onChange={e=>setDraft(e.target.value)} onKeyDown={key} onBlur={blur} disabled={busy}/>
}
