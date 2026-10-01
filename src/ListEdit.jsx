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
import{fmtMoney}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const UNITS=['weeks','months','years']
// v2.15.130: tuition, intakes and English in the list (migration 20261001140000_cf247_list_edit_course_facts).
const BASIS=[['annual','per year'],['per_semester','per semester'],['per_trimester','per trimester'],['total_indicative','whole course']]
const basisOf=b=>b==='indicative_annual'?'annual':(BASIS.some(x=>x[0]===b)?b:'annual')
const money=n=>n==null||n===''?'':fmtMoney(Number(n),'AUD',{decimals:0})
const tuitionText=t=>t&&t.amount!=null?`${money(t.amount)} ${BASIS.find(x=>x[0]===basisOf(t.basis))?.[1]||''}${t.fee_year?` · ${t.fee_year}`:''}`:''
const TEST_NAME={IELTS:'IELTS',PTE:'PTE',TOEFL_IBT:'TOEFL',CAE:'Cambridge'}
function intakesText(v){return (v||[]).map(i=>[i.label,i.year].filter(Boolean).join(' ')).join(', ')}
function englishText(v){return (v||[]).map(e=>`${TEST_NAME[e.test]||e.test} ${Number(e.overall)}`).join(', ')}
const items=t=>String(t||'').split(/[,;\n]+/).map(x=>x.trim()).filter(Boolean)
// Intakes: "Semester 1 2027, July" -> [{label, year, start_date}]; a start date already held for the same name and year is kept.
function intakeCalls(text,cur){
  const list=items(text);if(!list.length)return (cur||[]).length?[{action:'remove_intakes',args:{},confirm:'Remove all intakes for this course?'}]:[]
  const intakes=list.map(x=>{const m=x.match(/^(.*?)\s*\b(20\d{2})$/);const label=(m?m[1]:x).trim(),year=m?Number(m[2]):null
    if(!label)throw new Error(`"${x}": give the intake a name, for example February ${year||''}`.trim())
    const same=(cur||[]).find(i=>String(i.label).toLowerCase()===label.toLowerCase()&&(i.year??null)===year)
    return {label,year,start_date:same?.start_date||null}})
  return intakesText(intakes)===intakesText(cur)?[]:[{action:'set_intakes',args:{intakes}}]
}
// English: "IELTS 6.5, PTE 58" -> [{test, overall, components}]; sub-scores already held are kept when the overall score is unchanged.
function englishCalls(text,cur,ctx){
  const list=items(text);if(!list.length)return (cur||[]).length?[{action:'remove_english',args:{},confirm:'Remove all English requirements for this course?'}]:[]
  const tests=ctx?.english_tests||[]
  const find=w=>{const k=w.toLowerCase().replace(/[^a-z0-9]/g,'');return tests.find(t=>[t.code,t.name,TEST_NAME[t.code]].some(n=>String(n||'').toLowerCase().replace(/[^a-z0-9]/g,'')===k))
    ||(k.startsWith('toefl')?tests.find(t=>t.code==='TOEFL_IBT'):k.startsWith('cambridge')||k==='c1advanced'?tests.find(t=>t.code==='CAE'):null)}
  const out=list.map(x=>{const m=x.match(/^(.*?)\s+([0-9]+(?:\.[0-9]+)?)$/);if(!m)throw new Error(`"${x}": write the test then the overall score, for example IELTS 6.5`)
    const t=find(m[1]);if(!t)throw new Error(`"${m[1]}" is not a known English test (${tests.map(t=>TEST_NAME[t.code]||t.code).join(', ')})`)
    const prev=(cur||[]).find(e=>e.test===t.code),overall=m[2]
    return {test:t.code,overall,components:prev&&Number(prev.overall)===Number(overall)?(prev.components||{}):{}}})
  if(new Set(out.map(x=>x.test)).size!==out.length)throw new Error('each English test once only')
  return englishText(out)===englishText(cur)?[]:[{action:'set_english',args:{tests:out}}]
}

export const LIST_EDIT={
  course:{rpc:'admin_course_edit',idArg:'p_course_id',label:r=>r.canonical_title,sub:r=>[r.provider_name,r.course_code].filter(Boolean).join(' · '),
    fields:[
      {key:'display_title',label:'Title',width:220},
      {key:'duration',label:'Duration',width:150,kind:'duration'},
      {key:'delivery_mode',label:'Delivery',width:130,placeholder:'e.g. On campus'},
      {key:'official_url',label:'Course page',width:190,kind:'url',action:'set_official_url'},
      {key:'tuition',label:'Tuition',width:230,kind:'tuition'},
      {key:'intakes',label:'Intakes',width:200,kind:'text',toText:intakesText,toCalls:intakeCalls,placeholder:'e.g. February 2027, July 2027'},
      {key:'english',label:'English',width:190,kind:'text',toText:englishText,toCalls:englishCalls,placeholder:'e.g. IELTS 6.5, PTE 58'},
    ]},
  provider:{rpc:'admin_provider_edit',idArg:'p_provider_id',label:r=>r.canonical_name,sub:r=>[r.country_code,r.subdivision_name].filter(Boolean).join(' · '),
    fields:[
      {key:'display_name',label:'Name',width:260},
      {key:'primary_city',label:'City',width:150},
      {key:'website',label:'Website',width:240,kind:'url'},
      {key:'phone',label:'Phone',width:150},
      {key:'email',label:'Email',width:210},
    ]},
  // v2.15.130: campuses and scholarships (migration 20261001150000_cf247_campus_scholarship_edit).
  campus:{rpc:'admin_campus_edit',idArg:'p_campus_id',label:r=>r.name||r.campus_name,sub:r=>[r.provider_name,r.campus_code].filter(Boolean).join(' · '),
    fields:[
      {key:'name',label:'Name',width:220},
      {key:'address_line1',label:'Street address',width:240},
      {key:'city',label:'City',width:140},
      {key:'postcode',label:'Postcode',width:100},
      {key:'phone',label:'Phone',width:150},
      {key:'website',label:'Website',width:200,kind:'url'},
    ]},
  scholarship:{rpc:'admin_scholarship_edit',idArg:'p_scholarship_id',label:r=>r.name,sub:r=>r.provider_name||'',
    fields:[
      {key:'name',label:'Name',width:240},
      {key:'award_value_text',label:'Award as written',width:220},
      {key:'award_amount',label:'Amount (A$)',width:120,placeholder:'e.g. 5000'},
      {key:'award_percentage',label:'% of fees',width:100,placeholder:'e.g. 20'},
      {key:'application_close_date',label:'Applications close',width:150,kind:'date'},
      {key:'source_url',label:'Scholarship page',width:200,kind:'url'},
    ]},
}
// dd/mm/yyyy <-> yyyy-mm-dd for date cells.
const toAu=v=>{const m=String(v||'').match(/^(\d{4})-(\d{2})-(\d{2})/);return m?`${m[3]}/${m[2]}/${m[1]}`:String(v||'')}
const fromAu=v=>{const t=String(v||'').trim();if(!t)return '';const m=t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);if(!m)throw new Error('enter the date as dd/mm/yyyy');return `${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')}`}

export default function ListEdit({type,rows,onError}){
  const cfg=LIST_EDIT[type],ids=rows.map(r=>r.id??r.course_id).filter(Boolean)
  const[vals,setVals]=useState(null),[ctx,setCtx]=useState({}),[can,setCan]=useState(false),[saving,setSaving]=useState(''),[saved,setSaved]=useState(''),[rowErr,setRowErr]=useState({})
  useEffect(()=>{let live=true;setVals(null);(async()=>{try{const{data,error}=await supabase.rpc('admin_catalogue_edit_rows',{p_type:type,p_ids:ids});if(error)throw error;if(live){setVals(data?.rows||{});setCtx({english_tests:data?.english_tests||[]});setCan(Boolean(data?.can_edit))}}catch(e){onError?.(errText(e))}})();return()=>{live=false}},[type,ids.join(',')])
  if(!vals)return <Loading label="Loading editable fields…"/>
  const save=async(id,field,value)=>{
    const key=`${id}:${field.key}`,cur=vals[id]||{}
    let calls
    try{calls=field.kind==='tuition'
      ?(value.amount===''?(cur.tuition?[{action:'remove_tuition',args:{},confirm:'Remove the tuition fee for this course?'}]:[])
        :(String(Number(value.amount))===String(Number(cur.tuition?.amount))&&String(value.fee_year||'')===String(cur.tuition?.fee_year||'')&&value.basis===basisOf(cur.tuition?.basis))?[]
        :[{action:'set_tuition',args:{amount:String(value.amount).replace(/[^0-9.]/g,''),fee_year:value.fee_year||null,basis:value.basis}}])
      :field.toCalls?field.toCalls(value,cur[field.key],ctx):null}catch(e){setRowErr(x=>({...x,[id]:e.message}));return false}
    if(calls)for(const c of calls)if(c.confirm&&!window.confirm(c.confirm))return false
    if(!calls)try{calls=field.kind==='duration'
      ?[...(String(value.value??'')!==String(cur.duration_value??'')?[{action:'set_core',args:{field:'duration_value',value:value.value===''?null:value.value},lock:'duration_value'}]:[]),
        ...(value.unit!==(cur.duration_unit||'')?[{action:'set_core',args:{field:'duration_unit',value:value.unit||null},lock:'duration_unit'}]:[])]
      :field.kind==='date'?(()=>{const iso=fromAu(value);return iso===String(cur[field.key]??'').slice(0,10)?[]:[{action:'set_core',args:{field:field.key,value:iso===''?null:iso},lock:field.key}]})()
      :String(value??'')===String(cur[field.key]??'')?[]
      :field.action==='set_official_url'?[{action:value?'set_official_url':'remove_official_url',args:value?{url:value}:{},lock:'official_url'}]
      :[{action:'set_core',args:{field:field.key,value:value===''?null:value},lock:field.key}]}catch(e){setRowErr(x=>({...x,[id]:e.message}));return false}
    if(!calls.length)return true
    setSaving(key);setRowErr(x=>({...x,[id]:''}))
    try{
      for(const c of calls){const{error}=await supabase.rpc(cfg.rpc,{[cfg.idArg]:id,p_action:c.action,p_args:c.args});if(error)throw error}
      if(field.kind==='tuition'||field.toCalls){const{data}=await supabase.rpc('admin_catalogue_edit_rows',{p_type:type,p_ids:[id]});if(data?.rows?.[id])setVals(v=>({...v,[id]:data.rows[id]}))}
      else setVals(v=>{const r={...(v[id]||{})};if(field.kind==='duration'){r.duration_value=value.value===''?null:value.value;r.duration_unit=value.unit||null}else r[field.key]=field.kind==='date'?(fromAu(value)||null):(value||null);r.locks={...(r.locks||{}),...Object.fromEntries(calls.map(c=>[c.lock,'value']))};return{...v,[id]:r}})
      setSaved(key);setTimeout(()=>setSaved(s=>s===key?'':s),2000);return true
    }catch(e){setRowErr(x=>({...x,[id]:errText(e)}));return false}finally{setSaving('')}
  }
  return <div className="m-table-wrap le-wrap"><table className="m-table le-table" data-list-edit={type}>
    <thead><tr><th style={{minWidth:220}}>{({course:'Course',provider:'Provider',campus:'Campus',scholarship:'Scholarship'})[type]}</th>{cfg.fields.map(f=><th key={f.key} style={{minWidth:f.width}}>{f.label}</th>)}</tr></thead>
    <tbody>{rows.map(r=>{const id=r.id??r.course_id,v=vals[id]||{},locks=v.locks||{}
      return <React.Fragment key={id}><tr data-edit-row={id}>
        <td><span className="m-cell-title"><strong>{cfg.label(r)||'—'}</strong><small>{cfg.sub(r)}</small></span></td>
        {cfg.fields.map(f=>{const k=`${id}:${f.key}`,locked=f.kind==='duration'?(locks.duration_value||locks.duration_unit):locks[f.key]
          return <td key={f.key} className="le-cell"><Cell field={f} value={f.kind==='duration'?{value:v.duration_value!=null?String(Number(v.duration_value)):'',unit:v.duration_unit||''}:f.kind==='tuition'?{amount:v.tuition?.amount!=null?String(Number(v.tuition.amount)):'',fee_year:v.tuition?.fee_year?String(v.tuition.fee_year):'',basis:basisOf(v.tuition?.basis)}:f.toText?f.toText(v[f.key]):f.kind==='date'?toAu(v[f.key]):(v[f.key]!=null?String(v[f.key]):'')} can={can} busy={saving===k} ok={saved===k} locked={Boolean(locked)} label={`${f.label} for ${cfg.label(r)}`} onSave={x=>save(id,f,x)}/></td>})}
      </tr>{rowErr[id]&&<tr className="le-err-row"><td colSpan={cfg.fields.length+1}><p className="fr-error" role="alert">{rowErr[id]}</p></td></tr>}</React.Fragment>})}</tbody>
  </table>
  <p className="l3v-note"><Lock size={11}/> marks a value entered by hand: automation will not change it. Open the record to let automation update it again.</p></div>
}

const shortUrl=u=>{try{const x=new URL(u);const p=x.pathname.replace(/\/$/,'');return x.host.replace(/^www\./,'')+(p.length>28?'/…'+p.slice(-24):p)}catch{return String(u||'')}}

function Cell({field,value,can,busy,ok,locked,label,onSave}){
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(value),ref=useRef(null)
  useEffect(()=>{if(!edit)setDraft(field.kind==='duration'?{...value,unit:value.unit||'weeks'}:field.kind==='tuition'?{...value,basis:value.basis||'annual'}:value)},[JSON.stringify(value),edit])
  useEffect(()=>{if(edit)ref.current?.focus()},[edit])
  const shown=field.kind==='duration'?(value.value?`${value.value} ${value.unit||''}`.trim():''):field.kind==='tuition'?tuitionText(value.amount?value:null):field.kind==='url'?shortUrl(value):String(value||'')
  const commit=async()=>{if(await onSave(['duration','tuition'].includes(field.kind)?draft:String(draft).trim()))setEdit(false)}
  const key=e=>{if(e.key==='Escape'){setEdit(false)}if(e.key==='Enter'){e.preventDefault();commit()}}
  const blur=e=>{if(!e.currentTarget.contains(e.relatedTarget))commit()}
  if(!can)return <span className="le-view">{shown||'—'}{locked&&<Lock size={11} className="le-lock" aria-label="Entered by hand"/>}</span>
  if(!edit)return <button type="button" className={`le-view le-btn${ok?' le-ok':''}`} aria-label={`Edit ${label}`} title={field.kind==='url'?String(value||''):undefined} onClick={()=>setEdit(true)}>
    <span className={shown?'':'le-empty'}>{shown||'Add'}</span>{locked&&<Lock size={11} className="le-lock" aria-label="Entered by hand"/>}{ok&&<Check size={12} className="le-tick"/>}</button>
  if(field.kind==='tuition')return <span className="le-duration le-tuition" onBlur={blur} onKeyDown={key}>
    <input ref={ref} className="fv-input" inputMode="decimal" aria-label={`${label} amount`} placeholder="A$" value={draft.amount} onChange={e=>setDraft(d=>({...d,amount:e.target.value}))} disabled={busy}/>
    <select className="fv-input" aria-label={`${label} basis`} value={draft.basis} onChange={e=>setDraft(d=>({...d,basis:e.target.value}))} disabled={busy}>{BASIS.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
    <input className="fv-input le-year" inputMode="numeric" aria-label={`${label} year`} placeholder="Year" value={draft.fee_year} onChange={e=>setDraft(d=>({...d,fee_year:e.target.value}))} disabled={busy}/></span>
  if(field.kind==='duration')return <span className="le-duration" onBlur={blur} onKeyDown={key}>
    <input ref={ref} className="fv-input" inputMode="decimal" aria-label={label} value={draft.value} onChange={e=>setDraft(d=>({...d,value:e.target.value}))} disabled={busy}/>
    <select className="fv-input" aria-label={`${label} unit`} value={draft.unit||'weeks'} onChange={e=>setDraft(d=>({...d,unit:e.target.value}))} disabled={busy}>{UNITS.map(u=><option key={u}>{u}</option>)}</select></span>
  return <input ref={ref} className="fv-input le-input" type={field.kind==='url'?'url':'text'} aria-label={label} value={draft} placeholder={field.placeholder||''} onChange={e=>setDraft(e.target.value)} onKeyDown={key} onBlur={blur} disabled={busy}/>
}
