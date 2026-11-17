// CF-247 Parallel Wave 2 (Platform Admin 17 Nov 2026 17:59; decisions 18:10): the six-step country and register induction wizard that
// Layer 1 › Sources › + Add source opens. A draft is saved at each step (public.admin_layer1_induction_save), so it can be left and continued.
//   1 Country and scheme  2 Source, connector and licence (REQ-68)  3 Field and category mapping (AI Auto-Map when the mapper is deployed)
//   4 Cadence and the staging keep period (set on activation in pipeline.source_retention_policies, which housekeeping-daily reads)  5 Dry-run preview (from the source's reader, when it has one)
//   6 Activation: the Platform Admin, with a reason. The source is created paused and stays paused; nothing runs from here.
// Drafting is Curator and above (Platform Admin 17 Nov 2026 20:45); activation is the Platform Admin's. The server checks every step again.
import React,{useCallback,useEffect,useMemo,useState}from'react'
import{Button,StatusChip,EmptyInline,fmtDateTime,fmtNumber}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{plainError}from'./lib/errors'
import{parseSample}from'./lib/sample-parse.js'
import'./layer1-induction.css'

export const STEPS=[['scheme','Country & scheme'],['source','Source & licence'],['mapping','Field mapping'],['cadence','Cadence & retention'],['dry_run','Dry-run preview'],['activate','Activation']]
export const MAPPER='layer1-ai-induction-mapper'
export const RUNNER='layer1-declarative-runner'
const CONNECTOR={csv_file:'CSV file',xlsx_file:'Excel file',json_api:'JSON API',html_pages:'Web pages',pdf_document:'PDF document',manual_upload:'Uploaded by hand'}
const TERMS={approved:'Approved',pending:'Pending (REQ-68)',not_required:'Not required'}
const CADENCE={weekly:'Weekly',monthly:'Monthly',annual:'Annual'}
const KIND={course_registration:'Course registration',provider_registration:'Provider registration',field_of_study:'Field of study',work_eligibility:'Work eligibility'}
const EMPTY={country_code:'',scheme:'',scheme_kind:'',field_scheme:'',target_record_type:'',parser_spec:null,source_label:'',source_url:'',authority_name:'',dataset_class:'register',connector_type:'',expected_format:'',licence_name:'',licence_url:'',attribution_text:'',terms_status:'',cadence:'',notes:'',sample_file_name:'',edition_archiving:true,staging_keep_days:'',sample:null}

export default function Layer1InductionWizard({rank=0,onDone,onCancel,client=null,invoke=null}){
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const call=invoke||((name,body)=>supabase.functions.invoke(name,{body}))
  const[o,setO]=useState(null),[drafts,setDrafts]=useState([]),[id,setId]=useState(null),[item,setItem]=useState(null),[f,setF]=useState(EMPTY),[maps,setMaps]=useState([])
  const[step,setStep]=useState(0),[busy,setBusy]=useState(''),[err,setErr]=useState(''),[note,setNote]=useState(''),[reason,setReason]=useState(''),[mapper,setMapper]=useState(null)
  const open=useCallback(async(draftId)=>{setErr('')
    const{data,error}=await rpc('admin_layer1_induction_read',{p_id:draftId||null});if(error){setErr(plainError(error));return}
    setO(data.options);setDrafts(data.drafts||[])
    if(data.item){const p=data.item.payload||{};setItem(data.item);setId(data.item.id);setMaps(data.item.mappings||[])
      setF({...EMPTY,...p,country_code:data.item.country_code,staging_keep_days:p.staging_keep_days??''})}
  },[id])
  useEffect(()=>{open(null)},[])
  // the AI mapper is S2-Build's edge function: the button switches on by itself once it answers
  useEffect(()=>{let live=true;Promise.resolve(call(MAPPER,{action:'status'})).then(({data,error})=>{if(live)setMapper(!error&&data?.ok?data:false)}).catch(()=>{if(live)setMapper(false)});return()=>{live=false}},[])
  // the dry run reads the first rows with the draft's AI-built parser spec through S2-Build's layer1-declarative-runner; it writes nothing and switches nothing on
  const dryRun=async()=>{if(!id)return;setBusy('dry');setErr('');setNote('')
    try{const{data,error}=await call(RUNNER,{action:'dry_run',induction_id:id});if(error||data?.ok===false)setErr(plainError(error||{message:data?.error||'The dry run did not run.'}))
      else setNote(data?.status==='passed'?'Dry run passed. Nothing was written.':`Dry run failed: ${data?.message||'see the result below'}.`)}
    catch(e){setErr(plainError(e))}
    await open(id);setBusy('')}
  const set=k=>e=>setF(x=>({...x,[k]:e.target.type==='checkbox'?e.target.checked:e.target.value}))
  const schemes=useMemo(()=>(o?.schemes||[]).filter(s=>s.country_code===f.country_code),[o,f.country_code])
  const fieldList=useMemo(()=>(o?.categories||[]).flatMap(c=>c.fields.map(x=>({...x,category_key:c.key,category:c.label}))),[o])
  const steps=item?.steps||{}
  const closed=item&&item.status!=='draft'
  async function save(next){setBusy('save');setErr('');setNote('')
    try{const{parser_validation:_pv,...rest}=f
      const payload={...rest,staging_keep_days:f.staging_keep_days===''||f.staging_keep_days==null?null:Number(f.staging_keep_days)}
      const{data,error}=await rpc('admin_layer1_induction_save',{p_id:id,p_payload:payload,p_mappings:maps});if(error)throw error
      setItem(data.item);setId(data.item.id);setNote('Draft saved.');if(next!=null)setStep(next);return data.item}
    catch(e){setErr(plainError(e));return null}finally{setBusy('')}}
  async function onFile(e){const file=e.target.files?.[0];if(!file)return
    if(file.size>5*1024*1024){setErr('The sample is larger than 5 MB. Save the first few hundred rows as a small file and upload that.');return}
    const text=await file.text();const s=parseSample(file.name,text,Number(o?.sample_rows||20))
    if(!s){setErr('No rows were found in that file. Upload a CSV, tab-separated, JSON or saved web page (HTML with a table) sample.');return}
    setF(x=>({...x,sample:s,sample_file_name:file.name}));setErr('')
    setMaps(m=>[...m,...s.columns.filter(c=>!m.some(x=>x.source_field===c)).map(c=>({source_field:c,target_field:'',category_key:'',by:'manual'}))])}
  const setMap=(i,patch)=>setMaps(m=>m.map((x,j)=>j===i?{...x,...patch,by:x.by==='ai'||x.by==='ai_adjusted'?'ai_adjusted':'manual'}:x))
  async function autoMap(){setBusy('map');setErr('');setNote('')
    try{const saved=await save(null);if(!saved)return
      const{data,error}=await call(MAPPER,{action:'map',induction_id:saved.id,target_record_type:f.target_record_type,country_code:f.country_code,connector_type:f.connector_type,source_url:f.source_url,sample:{columns:f.sample?.columns||maps.map(m=>m.source_field),rows:(f.sample?.rows||[]).slice(0,20)},...(f.sample?.table_index!=null?{source:{table_index:f.sample.table_index,header_row:f.sample.header_row}}:{}),
        target_fields:fieldList.map(x=>({field:x.field,label:x.label,category_key:x.category_key})),categories:(o?.categories||[]).map(c=>({key:c.key,label:c.label,description:c.description}))})
      if(error||!data?.ok)throw new Error(data?.error||error?.message||'The mapper did not answer.')
      const sug=new Map((data.suggestions||[]).map(s=>[s.source_field,s]))
      setMaps(m=>{const have=new Set(m.map(x=>x.source_field));const merged=m.map(x=>{const s=sug.get(x.source_field);return s&&!x.target_field&&!x.category_key?{...x,target_field:s.target_field||'',category_key:s.category_key||'',confidence:s.confidence,note:s.reason||x.note,by:'ai'}:x})
        for(const s of data.suggestions||[])if(!have.has(s.source_field))merged.push({source_field:s.source_field,target_field:s.target_field||'',category_key:s.category_key||'',confidence:s.confidence,note:s.reason||'',by:'ai'});return merged})
      if(data.parser_spec&&typeof data.parser_spec==='object')setF(x=>({...x,parser_spec:{...data.parser_spec,record_type:data.parser_spec.record_type||x.target_record_type},parser_validation:data.validation||null}))
      setNote(`AI Auto-Map suggested ${(data.suggestions||[]).length} mappings${data.parser_spec?' and a parser spec':''}${data.model?` (${data.model})`:''}. Check each one; nothing is saved until Save & continue.`)}
    catch(e){setErr(plainError(e))}finally{setBusy('')}}
  async function activate(){const why=reason.trim();if(why.length<4){setErr('Give a reason for activating this source (it is kept in the control log).');return}
    setBusy('activate');setErr('');setNote('')
    try{const saved=await save(null);if(!saved)return
      const{data,error}=await rpc('admin_layer1_induction_activate',{p_id:saved.id,p_reason:why});if(error)throw error
      setItem(data.item);setNote(data.dry_run==='passed'?'Activated. The source is saved paused; resume it on its row when you are ready for the first load.':'Activated and saved paused. It waits for a reader and a passing dry run before it can be resumed.');onDone?.(data)}
    catch(e){setErr(plainError(e))}finally{setBusy('')}}
  async function cancelDraft(){const why=window.prompt('Cancel this draft? It is kept, marked cancelled.\n\nReason (kept in the control log):');if(!why||why.trim().length<4)return
    const{error}=await rpc('admin_layer1_induction_cancel',{p_id:id,p_reason:why.trim()});if(error){setErr(plainError(error));return}onCancel?.()}
  if(rank<3)return <EmptyInline text="Adding a source opens for Curator and above."/>
  if(!o)return err?<EmptyInline text={err}/>:<p className="sl-sub">Loading…</p>
  const dr=item?.dry_run
  const done=k=>k==='activate'?Boolean(steps.activated):Boolean(steps[k])
  const body=[
    // 1
    <div className="l1i-grid" key="s1" data-l1i-step="scheme">
      <label>Country<select value={f.country_code} onChange={e=>setF(x=>({...x,country_code:e.target.value,scheme:'',scheme_kind:'',field_scheme:''}))} disabled={closed} data-l1i-country><option value="">Choose…</option>{o.countries.map(c=><option key={c.code} value={c.code}>{c.name} ({c.code})</option>)}</select></label>
      <label>Registration scheme<select value={f.scheme?`${f.scheme}|${f.scheme_kind}`:''} onChange={e=>{const[a,b]=e.target.value.split('|');setF(x=>({...x,scheme:a||'',scheme_kind:b||''}))}} disabled={closed||!schemes.length} data-l1i-scheme><option value="">Choose…</option>{schemes.filter(s=>s.kind!=='field_of_study').map(s=><option key={s.scheme+s.kind} value={`${s.scheme}|${s.kind}`}>{s.label||s.scheme} · {KIND[s.kind]||s.kind}</option>)}</select></label>
      <label>Native field-of-study scheme<select value={f.field_scheme} onChange={set('field_scheme')} disabled={closed||!schemes.length} data-l1i-field-scheme><option value="">None or not known</option>{schemes.filter(s=>s.kind==='field_of_study').map(s=><option key={s.scheme} value={s.scheme}>{s.label||s.scheme}</option>)}</select></label>
      <label>Target record type<select value={f.target_record_type} onChange={e=>setF(x=>({...x,target_record_type:e.target.value,parser_spec:null}))} disabled={closed} data-l1i-record-type><option value="">Choose…</option>{(o.record_types||[]).map(t=><option key={t.key} value={t.key}>{t.label}</option>)}</select>
        <small>{(o.record_types||[]).find(t=>t.key===f.target_record_type)?.help||'What each row of this source becomes. The AI mapper builds the parser spec for this type.'}</small></label>
      {f.country_code&&!schemes.length&&<p className="l1i-warn" data-l1i-no-scheme>No registration scheme is registered for {f.country_code} yet. A scheme is added to the reference list first (a database change), then this source can be set up.</p>}
    </div>,
    // 2
    <div className="l1i-grid" key="s2" data-l1i-step="source">
      <label className="wide">Name<input value={f.source_label} onChange={set('source_label')} disabled={closed} placeholder="For example: QQI course register" data-l1i-label/></label>
      <label className="wide">Source address (https)<input type="url" value={f.source_url} onChange={set('source_url')} disabled={closed} placeholder="https://" data-l1i-url/></label>
      <label>Authority that publishes it<input value={f.authority_name} onChange={set('authority_name')} disabled={closed}/></label>
      <label>Type<select value={f.dataset_class} onChange={set('dataset_class')} disabled={closed}><option value="register">Register</option><option value="statistics">Statistics</option></select></label>
      <label>Connector type<select value={f.connector_type} onChange={set('connector_type')} disabled={closed} data-l1i-connector><option value="">Choose…</option>{o.connector_types.map(k=><option key={k} value={k}>{CONNECTOR[k]||k}</option>)}</select></label>
      <label>Sample file (CSV, tab-separated, JSON, or a saved web page with a table)<input type="file" accept=".csv,.tsv,.txt,.json,.html,.htm,text/csv,application/json,text/html" onChange={onFile} disabled={closed} data-l1i-sample/>
        <small>{f.sample?`${f.sample_file_name||'Sample'}: ${fmtNumber(f.sample.columns.length)} columns, ${fmtNumber(f.sample.total_rows||0)} rows${f.sample.table_index!=null?` in table ${fmtNumber(f.sample.table_index+1)} of ${fmtNumber(f.sample.tables||1)} on the page`:''}; the first ${fmtNumber(f.sample.rows.length)} are kept with the draft.`:'Read in your browser; only the column names and the first rows are kept.'}</small></label>
      <label>Dataset licence<input value={f.licence_name} onChange={set('licence_name')} disabled={closed} placeholder="For example: CC BY 4.0"/></label>
      <label>Licence address (https)<input type="url" value={f.licence_url} onChange={set('licence_url')} disabled={closed} placeholder="https://"/></label>
      <label className="wide">Attribution shown with the data<input value={f.attribution_text} onChange={set('attribution_text')} disabled={closed} placeholder="For example: Source: Australian Bureau of Statistics"/></label>
      <label>Terms of use<select value={f.terms_status} onChange={set('terms_status')} disabled={closed} data-l1i-terms><option value="">Choose…</option>{o.terms_statuses.map(k=><option key={k} value={k}>{TERMS[k]||k}</option>)}</select>
        <small>Data is republished only with approved terms (REQ-68). Pending terms are recorded with the activation.</small></label>
    </div>,
    // 3
    <div key="s3" data-l1i-step="mapping">
      <div className="l1i-bar"><p className="sl-sub">Map each source field to the platform field it fills and its enrichment category. Leave a field unmapped to ignore it.</p>
        <span className="l1i-actions"><Button compact disabled={closed||!mapper||!f.target_record_type||busy!==''} title={mapper?undefined:'AI Auto-Map switches on when the mapper is deployed'} onClick={autoMap} data-l1i-automap>{busy==='map'?'Mapping…':'AI Auto-Map'}</Button>
          <StatusChip tone={mapper?'success':'neutral'} label={mapper?'AI mapper ready':mapper===null?'Checking the AI mapper…':'AI mapper not deployed yet: map by hand'}/>
          <Button compact disabled={closed} onClick={()=>setMaps(m=>[...m,{source_field:'',target_field:'',category_key:'',by:'manual'}])} data-l1i-add-map>Add a field</Button></span></div>
      {maps.length?<div className="l1i-scroll"><table className="cf-table"><thead><tr><th>Source field</th><th>Sample</th><th>Platform field</th><th>Enrichment category</th><th>By</th><th></th></tr></thead>
        <tbody>{maps.map((m,i)=>{const ci=f.sample?.columns?.indexOf(m.source_field)??-1;const ex=ci>=0?(f.sample.rows.find(r=>r[ci])||[])[ci]:''
          return <tr key={i} data-l1i-map={m.source_field}><td><input value={m.source_field} onChange={e=>setMap(i,{source_field:e.target.value})} disabled={closed} aria-label="Source field"/></td><td className="l1i-ex">{String(ex||'—').slice(0,60)}</td>
            <td><select value={m.target_field||''} onChange={e=>{const t=fieldList.find(x=>x.field===e.target.value);setMap(i,{target_field:e.target.value,category_key:t?t.category_key:m.category_key})}} disabled={closed} aria-label="Platform field"><option value="">Not mapped</option>{(o.categories||[]).map(c=><optgroup key={c.key} label={c.label}>{c.fields.map(x=><option key={x.field} value={x.field}>{x.label}</option>)}</optgroup>)}</select></td>
            <td><select value={m.category_key||''} onChange={e=>setMap(i,{category_key:e.target.value})} disabled={closed} aria-label="Enrichment category"><option value="">None</option>{(o.categories||[]).map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select></td>
            <td>{m.by==='ai'?`AI${m.confidence!=null?` ${Math.round(Number(m.confidence)*100)}%`:''}`:m.by==='ai_adjusted'?'AI, adjusted':'By hand'}</td>
            <td><Button compact disabled={closed} onClick={()=>setMaps(x=>x.filter((_,j)=>j!==i))} aria-label={`Remove ${m.source_field||'field'}`}>Remove</Button></td></tr>})}</tbody></table></div>
        :<EmptyInline text="No fields yet. Upload a sample in step 2 to list its columns, or add a field by hand."/>}
      <div className="l1i-spec" data-l1i-parser-spec={f.parser_spec?'present':'none'}>
        <h4>Parser spec for {(o.record_types||[]).find(t=>t.key===f.target_record_type)?.label||'the target record type'}</h4>
        {f.parser_spec?<>
          <p className="sl-sub">Proposed by the AI mapper. Target: <strong>{f.parser_spec.target_table||'not stated'}</strong>. {f.parser_validation?(f.parser_validation.ok?'Validated against the sample.':`Not valid yet: ${(f.parser_validation.errors||[]).join('; ')||'see the spec'}.`):'Validation was not reported.'} On activation it becomes the AI-built parser of this source.</p>
          <ul className="l1i-routing" data-l1i-routing>{(o.categories||[]).map(c=>{const k=maps.filter(m=>m.category_key===c.key).length;return k?<li key={c.key}><strong>{c.label}</strong>: {fmtNumber(k)} {k===1?'field':'fields'}</li>:null})}</ul>
          <pre className="l1i-json" tabIndex={0} aria-label="Parser spec (JSON)">{JSON.stringify(f.parser_spec,null,2)}</pre>
          <Button compact disabled={closed} onClick={()=>setF(x=>({...x,parser_spec:null,parser_validation:null}))} data-l1i-spec-discard>Discard the spec</Button></>
          :<p className="sl-sub">{mapper?'Press AI Auto-Map to have the parser spec, target table and category routing proposed for this record type.':'The parser spec is proposed by the AI mapper, which is not deployed yet. Without one the source is saved with no parser and waits for a reader.'}</p>}
      </div>
    </div>,
    // 4
    <div className="l1i-grid" key="s4" data-l1i-step="cadence">
      <label>Cadence<select value={f.cadence} onChange={set('cadence')} disabled={closed} data-l1i-cadence><option value="">Choose…</option>{o.cadences.map(k=><option key={k} value={k}>{CADENCE[k]||k}</option>)}</select></label>
      <label className="l1i-check"><input type="checkbox" checked={Boolean(f.edition_archiving)} onChange={set('edition_archiving')} disabled={closed}/> Keep each accepted edition (edition archiving)</label>
      <label>Staging kept (days)<input type="number" min="30" max="3650" value={f.staging_keep_days??''} onChange={set('staging_keep_days')} disabled={closed} placeholder={`Platform period: ${o.retention_defaults?.staging_keep_days??90} days`} data-l1i-staging-days/>
        <small>How long applied staging rows of this source are kept (30 to 3,650 days). Leave empty to follow the platform period of {o.retention_defaults?.staging_keep_days??90} days.</small></label>
      <p className="sl-sub wide" data-l1i-retention-note>On activation this period is set for the source on Storage &amp; retention, where the nightly housekeeping reads it. Pruning is {o.retention_defaults?.staging_prune_on?'on':'off (the nightly run only reports what would go)'}. Accepted editions and stored evidence are never pruned; hashes of removed staging rows are kept {o.retention_defaults?.raw_hash_keep_years??7} years.</p>
      <label className="wide">Notes<input value={f.notes} onChange={set('notes')} disabled={closed}/></label>
    </div>,
    // 5
    <div key="s5" data-l1i-step="dry_run">
      <p className="sl-sub">A dry run reads the first {fmtNumber(o.dry_run_rows)} rows through the source&rsquo;s reader and changes nothing. A campus postcode below {Math.round(Number(o.postcode_min_share)*100)}% in one locality is counted as an escalation to Layer 4.</p>
      {dr?<div className="l1i-metrics" data-l1i-dry-run={dr.status}>{[['Rows read',dr.rows_read],['Would insert',dr.inserts],['Would update',dr.updates],['Departures',dr.departures],[`Postcodes under ${Math.round(Number(o.postcode_min_share)*100)}%`,dr.postcode_escalations]].map(([l,v])=><div key={l}><small>{l}</small><strong>{fmtNumber(v||0)}</strong></div>)}
          <div><small>Result</small><StatusChip tone={dr.status==='passed'?'success':'danger'} label={dr.status==='passed'?'Passed':'Failed'}/></div>
          <p className="sl-sub wide">{dr.reader?`Reader: ${dr.reader}. `:''}Recorded {fmtDateTime(dr.recorded_at)}.{dr.message?` ${dr.message}`:''}</p></div>
        :<div className="l1i-wait" data-l1i-dry-run="waiting_for_reader"><StatusChip tone="warning" label={f.parser_spec?'Ready for a dry run':'Waiting for a reader'}/><p>{f.parser_spec?'This draft has an AI-built parser spec (step 3). Run a dry run to read the first rows of the source file with it; nothing is written.':'This source has no parser spec yet, so there is nothing to preview: use AI Auto-Map in step 3 with a sample of the file. You can still activate it: it is saved paused and stays paused until its reader is built and a dry run passes.'}</p></div>}
      <div className="l1i-actions"><Button compact disabled={!id||closed||!f.parser_spec||busy!==''} onClick={dryRun} data-l1i-dry-run-start>{busy==='dry'?'Running…':'Run dry run'}</Button>
        <Button compact disabled={!id||busy!==''} onClick={()=>open(id)} data-l1i-dry-refresh>Check again</Button></div>
      {f.parser_spec&&f.connector_type!=='html_pages'&&!/\.(csv|xlsx|json)(\?|$)/i.test(f.source_url||'')?<p className="sl-sub" data-l1i-dry-file-note>The dry run reads a CSV, XLSX or JSON file, or a table on a web page when the connector is Web pages. If the source address is a landing page, enter the address of the file itself in step 2.</p>:null}
    </div>,
    // 6
    <div key="s6" data-l1i-step="activate">
      <ul className="l1i-check-list">{STEPS.slice(0,5).map(([k,l],i)=><li key={k}><StatusChip tone={done(k)?'success':k==='dry_run'?'warning':'danger'} label={done(k)?'Done':k==='dry_run'?(steps.dry_run_state==='failed'?'Failed':'Waiting for a reader'):'Not finished'}/> Step {i+1}: {l}</li>)}</ul>
      {f.terms_status==='pending'&&<p className="l1i-warn">Terms of use are pending (REQ-68): the source can be loaded but its data is not republished until the terms are approved.</p>}
      {closed?<p className="sl-sub" data-l1i-closed>This induction is {item.status}{item.activated_at?` (${fmtDateTime(item.activated_at)})`:''}. {item.activation_reason||item.status_reason||''}</p>
        :<div className="l1i-grid"><label className="wide">Reason for activation (kept in the control log)<input value={reason} onChange={e=>setReason(e.target.value)} disabled={rank<6} placeholder="For example: QQI register approved for Ireland" data-l1i-reason/></label>
          <p className="sl-sub wide">Activation is the Platform Admin&rsquo;s. It creates the source <strong>paused</strong>; nothing is loaded until the source is resumed on its row.</p></div>}
    </div>]
  return <section className="l1i" data-l1-induction-wizard aria-label="Add a source">
    <div className="l1i-head"><h3>Add a source</h3>
      {!id&&drafts.filter(d=>d.status==='draft').length>0&&<label className="l1i-drafts">Continue a draft<select value="" onChange={e=>e.target.value&&open(e.target.value)} data-l1i-drafts><option value="">Choose…</option>{drafts.filter(d=>d.status==='draft').map(d=><option key={d.id} value={d.id}>{d.country_code} · {d.label||'Unnamed'} · {fmtDateTime(d.updated_at)}</option>)}</select></label>}</div>
    <ol className="l1i-steps" role="tablist" aria-label="Steps">{STEPS.map(([k,l],i)=><li key={k}><button type="button" role="tab" aria-selected={step===i} className={`l1i-step${step===i?' is-on':''}${done(k)?' is-done':''}`} onClick={()=>setStep(i)} data-l1i-tab={k}><span>{i+1}</span>{l}</button></li>)}</ol>
    {err&&<p className="l1i-warn" role="alert" data-l1i-error>{err}</p>}
    {note&&<p className="l1i-note" role="status" data-l1i-note>{note}</p>}
    <div className="l1i-body">{body[step]}</div>
    <div className="l1i-foot">
      <span className="l1i-actions"><Button compact onClick={onCancel} disabled={busy!==''}>Close</Button>{id&&!closed&&<Button compact onClick={cancelDraft} disabled={busy!==''} data-l1i-cancel-draft>Cancel draft</Button>}</span>
      <span className="l1i-actions">{step>0&&<Button compact onClick={()=>setStep(step-1)} disabled={busy!==''}>Back</Button>}
        {step<5&&!closed&&<Button compact variant="primary" disabled={busy!==''||!f.country_code} onClick={()=>save(step+1)} data-l1i-next>{busy==='save'?'Saving…':'Save & continue'}</Button>}
        {step<5&&closed&&<Button compact onClick={()=>setStep(step+1)}>Next</Button>}
        {step===5&&!closed&&<Button compact variant="primary" disabled={busy!==''||rank<6||reason.trim().length<4} title={rank<6?'Needs Platform Admin':undefined} onClick={activate} data-l1i-activate>{busy==='activate'?'Activating…':'Activate (saved paused)'}</Button>}</span>
    </div>
  </section>
}
