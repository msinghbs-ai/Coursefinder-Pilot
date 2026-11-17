// CF-247 Reference data › API field dictionary and Grade scale conversions (Platform Admin 17 Nov 2026 23:05, UI audit of the new API v3 fields).
// Two read-only reference tables, each with a search box, its filters and pages. Nothing is edited here: the dictionary is issued with each API
// release and the conversions are loaded by the pipeline. Read: public.admin_reference_table_read(kind, args), Curator and above
// (migration 20261118005000). The page size is the setting Reference data: rows per page.
import React,{useCallback,useEffect,useState}from'react'
import{Search}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'
import'./reference-tables.css'

const show=v=>v==null||v===''?'—':typeof v==='object'?JSON.stringify(v):String(v)
const KINDS={
  api_fields:{title:'API field dictionary',sub:'Every field the website and Zoho APIs return: where it comes from, its type and the request that asked for it. Issued with each API release; read-only here.',
    empty:'No field matches. Clear the search or the filters.',none:'The dictionary holds no fields yet.',
    cols:[['api_surface','API'],['version','Version'],['endpoint','Endpoint'],['field_path','Field'],['data_type','Type'],['is_nullable','Can be empty'],['allowed_values','Allowed values'],['source','Read from'],['req_ids','Requests'],['introduced_in','Since'],['description','Meaning']]},
  grade_scales:{title:'Grade scale conversions',sub:'How a grade on each country’s scale reads on the common 0 to 100 scale used for entry requirements. Loaded by the pipeline; read-only here.',
    empty:'No conversion matches. Clear the search or the filters.',none:'No grade scale conversions are loaded yet, so normalised grades are not filled.',
    cols:[['country_name','Country'],['qualification_name','Qualification'],['board_or_stream','Board or stream'],['scale_code','Scale'],['raw','Grade on that scale'],['normalized_0_100','On 0 to 100'],['is_active','In use'],['updated_at','Updated']]},
}
function cell(kind,k,r){
  if(k==='source')return r.source_table?`${r.source_table}${r.source_column?'.'+r.source_column:''}`:'—'
  if(k==='req_ids')return(r.req_ids||[]).length?r.req_ids.join(', '):'—'
  if(k==='is_nullable')return r.is_nullable==null?'—':r.is_nullable?'Yes':'No'
  if(k==='is_active')return <StatusChip tone={r.is_active?'success':'neutral'} label={r.is_active?'In use':'Not in use'}/>
  if(k==='raw')return r.raw_grade_label||(r.raw_min_value!=null||r.raw_max_value!=null?`${show(r.raw_min_value)} to ${show(r.raw_max_value)}`:'—')
  if(k==='updated_at')return r.updated_at?fmtDate(r.updated_at):'—'
  if(k==='version'&&r.deprecated_in)return `${r.version} (retired in ${r.deprecated_in})`
  return show(r[k])
}
export default function ReferenceTables({kind,onError,client=null}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args)),K=KINDS[kind]
  const[d,setD]=useState(null),[err,setErr]=useState(''),[typed,setTyped]=useState(''),[f,setF]=useState({query:'',offset:0})
  const load=useCallback(()=>{setErr('');Promise.resolve(rpc('admin_reference_table_read',{p_kind:kind,p_args:f})).then(({data,error})=>{if(error){const m=plainError(error);setErr(m);onError?.(m)}else setD(data)}).catch(e=>setErr(plainError(e)))},[kind,JSON.stringify(f)])
  useEffect(()=>{load()},[load])
  useEffect(()=>{setD(null);setTyped('');setF({query:'',offset:0})},[kind])
  if(!K)return null
  const set=(k,v)=>setF(x=>({...x,[k]:v,offset:0})),total=d?.total??0,page=d?.page_rows||50,from=total?f.offset+1:0,to=Math.min(f.offset+page,total)
  const filtered=Boolean(f.query||f.surface||f.version||f.country||f.active)
  return <section className="cf-card rft" data-reference-table={kind}>
    <div className="rft-head"><div><h3>{K.title}</h3><p className="sl-sub">{K.sub}</p></div>
      {d&&<span className="sl-sub" data-rft-count>{filtered?`${fmtNumber(total)} of ${fmtNumber(d.all_rows)}`:fmtNumber(d.all_rows)} {kind==='api_fields'?'fields':'conversions'}</span>}</div>
    <form className="rft-filters" onSubmit={e=>{e.preventDefault();set('query',typed.trim())}}>
      <label className="rft-search"><Search size={14}/><input value={typed} maxLength={120} onChange={e=>setTyped(e.target.value)} placeholder={kind==='api_fields'?'Search a field, endpoint, source column or request (for example study_load or REQ-76)':'Search a qualification, board, scale or country'} aria-label="Search" data-rft-search/></label>
      <Button compact type="submit" data-rft-go>Search</Button>
      {kind==='api_fields'&&<><label>API<select value={f.surface||''} onChange={e=>set('surface',e.target.value)} data-rft-surface><option value="">All</option>{(d?.filters?.surfaces||[]).map(s=><option key={s} value={s}>{s}</option>)}</select></label>
        <label>Version<select value={f.version||''} onChange={e=>set('version',e.target.value)} data-rft-version><option value="">All</option>{(d?.filters?.versions||[]).map(s=><option key={s} value={s}>{s}</option>)}</select></label></>}
      {kind==='grade_scales'&&<><label>Country<select value={f.country||''} onChange={e=>set('country',e.target.value)} data-rft-country><option value="">All</option>{(d?.filters?.countries||[]).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
        <label>In use<select value={f.active||''} onChange={e=>set('active',e.target.value)} data-rft-active><option value="">All</option><option value="true">In use</option><option value="false">Not in use</option></select></label></>}
      {filtered&&<Button compact onClick={()=>{setTyped('');setF({query:'',offset:0})}} data-rft-clear>Clear</Button>}
    </form>
    {err?<EmptyInline text={err}/>:!d?<p className="sl-sub">Loading…</p>:!d.rows.length?<EmptyInline text={d.all_rows?K.empty:K.none}/>:
      <div className="m-table-wrap"><table className="m-table rft-table"><thead><tr>{K.cols.map(([k,l])=><th key={k}>{l}</th>)}</tr></thead>
        <tbody>{d.rows.map((r,i)=><tr key={i} data-rft-row>{K.cols.map(([k])=><td key={k} className={k==='field_path'||k==='source'?'rft-code':k==='description'?'rft-wide':undefined}>{cell(kind,k,r)}</td>)}</tr>)}</tbody></table></div>}
    {d&&total>page&&<div className="rft-pager" data-rft-pager><span className="sl-sub">{fmtNumber(from)} to {fmtNumber(to)} of {fmtNumber(total)}</span>
      <Button compact disabled={f.offset<=0} onClick={()=>setF(x=>({...x,offset:Math.max(0,x.offset-page)}))} data-rft-prev>Previous</Button>
      <Button compact disabled={to>=total} onClick={()=>setF(x=>({...x,offset:x.offset+page}))} data-rft-next>Next</Button></div>}
  </section>
}
