// CF-247 F-AER.04 D3 (Platform Admin decision D3, 11 Nov 2026): source management inside the existing Catalogue › Entry requirements › Sources, reads and holds view.
// Attach a provider's entry-requirements address or PDF with its classes; the database checks ownership (the provider's own website host), reuse of an existing source or
// stored copy and the existing reader before anything is added (public.admin_aer_source 'check'), then a Platform Admin attaches it with a reason. A PDF goes through edge
// function aer-source-upload, which stores it where the fetch step stores PDFs. Every read goes to Layer 4. The AER source discovery outcomes and campaign figures
// (public.admin_aer_discovery) sit below. No new registry: sources stay in pipeline.entry_matrix_sources.
import React,{useEffect,useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import{FilterSelect}from'./DataTable'
import{plainError}from'./lib/errors'

export const SOURCE_CLASSES=[['country_table','Country table'],['international_qualification','International qualification'],['national_qualification','National qualification'],
  ['undergraduate','Undergraduate'],['postgraduate','Postgraduate'],['course_specific','Course-specific']]
const CLASS_LABEL=Object.fromEntries(SOURCE_CLASSES)
export const classLabels=cls=>(cls||[]).map(c=>CLASS_LABEL[c]||c).join(', ')
const opt=(value,label)=>({value,label})
const src=async args=>{const{data,error}=await supabase.rpc('admin_aer_source',{p_args:args});if(error)throw error;return data}

// classes, version, last verified and next retry for the sources on the page
export function useSourceMeta(ids){
  const[meta,setMeta]=useState({}),key=ids.join(',')
  useEffect(()=>{let live=true;if(!ids.length){setMeta({});return}src({action:'meta',source_ids:ids}).then(d=>{if(live)setMeta(d||{})}).catch(()=>{if(live)setMeta({})});return()=>{live=false}},[key])
  return meta
}

export function SourceAttach({providers=[],providerId='',onAttached}){
  const[open,setOpen]=useState(false),[pid,setPid]=useState(providerId),[url,setUrl]=useState(''),[title,setTitle]=useState(''),[cls,setCls]=useState([]),[file,setFile]=useState(null)
  const[reason,setReason]=useState(''),[chk,setChk]=useState(null),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  useEffect(()=>{setPid(providerId)},[providerId])
  useEffect(()=>{setChk(null);setMsg('')},[pid,url,cls.join(','),file])
  const how=file?'pdf_upload':'url'
  const sha=async f=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('')
  const check=async()=>{setBusy(true);setMsg('');try{setChk(await src({action:'check',provider_id:pid,url,classes:cls,how,...(file?{sha256:await sha(file),bytes:file.size}:{})}))}catch(e){setMsg(plainError(e))}finally{setBusy(false)}}
  const attach=async()=>{setBusy(true);setMsg('');try{
    let r
    if(file){const form=new FormData();form.append('provider_id',pid);form.append('url',url);form.append('title',title);form.append('classes',cls.join(','));form.append('reason',reason);form.append('file',file)
      const{data,error}=await supabase.functions.invoke('aer-source-upload',{body:form});if(error||data?.error)throw new Error(data?.reason||error?.message||'Upload failed');r=data}
    else{r=await src({action:'attach',provider_id:pid,url,title,classes:cls,reason});if(!r?.attached)throw new Error(r?.reason||'Not attached')}
    setMsg(r.outcome||'Attached.');setChk(null);setUrl('');setTitle('');setFile(null);setReason('');setCls([]);onAttached?.()
  }catch(e){setMsg(plainError(e))}finally{setBusy(false)}}
  const toggle=c=>setCls(x=>x.includes(c)?x.filter(y=>y!==c):[...x,c])
  if(!open)return <div className="aer-attach-closed"><button type="button" className="m-secondary compact" data-aer-attach-open onClick={()=>setOpen(true)}>Attach a source</button></div>
  return <section className="m-panel m-catalogue-panel" data-aer-attach>
    <div className="m-workspace-head"><div><h2>Attach a source</h2><p>The provider's own entry-requirements page or PDF. It is checked first: the address must be on the provider's own website, an existing source or stored copy is reused, and the existing reader reads it. Its rows go to Layer 4.</p></div>
      <button type="button" className="m-secondary compact" onClick={()=>setOpen(false)}>Close</button></div>
    <div className="aer-attach-grid">
      <FilterSelect label="Provider" value={pid} onChange={v=>setPid(v)} options={providers.map(p=>opt(p.id,p.name))}/>
      <label><small>Address where the provider publishes it</small><input data-aer-attach-url value={url} onChange={e=>setUrl(e.target.value)} placeholder="https://www.example.edu.au/admissions/entry-requirements"/></label>
      <label><small>Title (optional)</small><input value={title} onChange={e=>setTitle(e.target.value)}/></label>
      <label><small>PDF (optional: upload when the site cannot be fetched)</small><input type="file" accept="application/pdf,.pdf" data-aer-attach-file onChange={e=>setFile(e.target.files?.[0]||null)}/></label>
    </div>
    <fieldset className="aer-attach-classes" data-aer-attach-classes><legend><small>Classes (one or more)</small></legend>
      {SOURCE_CLASSES.map(([k,l])=><label key={k}><input type="checkbox" checked={cls.includes(k)} onChange={()=>toggle(k)}/> {l}</label>)}</fieldset>
    <div className="aer-attach-actions"><button type="button" className="m-secondary compact" disabled={busy||!pid||!url||!cls.length} data-aer-attach-check onClick={check}>{busy&&!chk?'Checking…':'Check'}</button></div>
    {chk&&<div className="aer-attach-check" data-aer-attach-result={chk.ok?'ok':chk.rule}>
      {chk.ok?<>
        <p><StatusChip tone="success" label="Provider's own website"/> {chk.host} · {chk.reader}{chk.reuse?<> · <StatusChip tone="info" label={chk.reuse==='stored_copy'?'Stored copy reused':'Existing source reused'}/></>:null}</p>
        <p><small>{chk.next_action}</small></p><p><small>Machine admission: {chk.machine_admission}</small></p>
        {chk.can_attach?<div className="aer-attach-actions"><input data-aer-attach-reason value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason (kept in the log)"/>
          <button type="button" className="m-primary compact" disabled={busy||reason.trim().length<5} data-aer-attach-go onClick={attach}>{busy?'Attaching…':file?'Upload and attach':'Attach'}</button></div>
          :<p><small data-aer-attach-owner>The Platform Admin attaches sources.</small></p>}
      </>:<p className="fr-error" role="alert"><StatusChip tone="danger" label="Not attached"/> {chk.reason}</p>}
    </div>}
    {msg&&<p role="status" data-aer-attach-msg>{msg}</p>}
  </section>
}

const OUTCOME_LABEL={source_read:'Source read',source_found:'Source waiting to be read',source_reading:'Source being read',source_failed:'Source failed',source_inactive:'Source withdrawn',
  source_robots_disallowed:'Site does not allow fetching',source_pdf_step_b:'PDF waiting',entry_source_found:'Entry page found',course_pages_found:'Course pages only',no_entry_page:'No entry page',
  no_website:'No website',website_is_directory:'Website is a directory',not_asked:'Not asked yet',searching:'Searching',refused:'Budget wait',failed:'Search failed',search_failed:'Search failed (no tries left)'}

export function SourceDiscovery(){
  const[d,setD]=useState(null),[out,setOut]=useState(''),[q,setQ]=useState(''),[off,setOff]=useState(0),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  // a failure shows here, inside the panel; the rest of the Sources view is unaffected
  useEffect(()=>{let live=true;setBusy(true);supabase.rpc('admin_aer_discovery',{p_args:{outcome:out,q,limit:25,offset:off}}).then(({data,error})=>{if(!live)return;if(error){setErr(plainError(error));setD(null)}else{setErr('');setD(data)}setBusy(false)}).catch(e=>{if(live){setErr(plainError(e));setBusy(false)}});return()=>{live=false}},[out,q,off])
  const m=d?.metrics||{},c=d?.campaign||{},sp=m.spare||{}
  return <section className="m-panel m-catalogue-panel" data-aer-discovery>
    <div className="m-workspace-head"><div><h2>Source discovery</h2><p>Every eligible provider without an entry source, searched on its own website until each has an outcome (campaign ceiling {fmtNumber(Number(c.credit_cap_now||0))} credits).</p></div>
      <div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(Number(d?.with_outcome||0))}</strong><span>of {fmtNumber(Number(d?.providers||0))} with an outcome</span></>}</div></div>
    {err&&<p className="fr-error" role="status" data-aer-discovery-error>{err}</p>}
    <div className="aer-discovery-figures" data-aer-discovery-metrics>
      <span><strong>{fmtNumber(Number(m.providers_attempted||0))}</strong> asked</span>
      <span><strong>{fmtNumber(Number(m.usable_sources||0))}</strong> usable sources ({fmtNumber(Number(m.new_sources||0))} new)</span>
      <span><strong>{fmtNumber(Number(m.not_found||0))}</strong> no entry page</span>
      <span><strong>{fmtNumber(Number(m.credits||0))}</strong> credits{m.cost_per_usable_source!=null?` · ${m.cost_per_usable_source} a usable source`:''}</span>
      <span data-aer-discovery-spare><strong>{fmtNumber(Number(m.spare_credits_today||0))}</strong> spare credits today · room {fmtNumber(Number(sp.room||0))} ({sp.why||'—'})</span>
      <span><StatusChip value={c.state} label={c.state||'—'}/></span>
    </div>
    <div className="m-filter-bar"><FilterSelect label="Outcome" value={out} onChange={v=>{setOut(v);setOff(0)}} options={Object.keys(d?.by_outcome||{}).map(k=>opt(k,`${OUTCOME_LABEL[k]||k} (${d.by_outcome[k]})`))}/>
      <label><small>Provider</small><input value={q} onChange={e=>{setQ(e.target.value);setOff(0)}} placeholder="Search provider"/></label></div>
    <table className="m-table aer-discovery-table"><thead><tr><th>Provider</th><th>Courses</th><th>Outcome</th><th>Source</th><th>Last checked</th><th>Next</th></tr></thead>
      <tbody>{(d?.rows||[]).map(r=><tr key={r.provider_id} data-aer-discovery-row={r.outcome}><td>{r.provider}</td><td>{fmtNumber(Number(r.courses||0))}</td><td>{OUTCOME_LABEL[r.outcome]||r.outcome}</td>
        <td>{r.source_url?<a className="cf-link" href={r.source_url} target="_blank" rel="noreferrer">{r.source_type}</a>:'—'}</td><td>{r.last_checked?fmtDate(r.last_checked):'—'}</td><td><small>{r.next_action}</small></td></tr>)}</tbody></table>
    <div className="aer-attach-actions"><button type="button" className="m-secondary compact" disabled={off===0} onClick={()=>setOff(Math.max(0,off-25))}>Previous</button>
      <button type="button" className="m-secondary compact" disabled={(d?.rows||[]).length<25} onClick={()=>setOff(off+25)}>Next</button></div>
  </section>
}
