// Fee reader (v2.15.309, CF-247). Platform Admin, 21 Oct 2026 20:02: "Build fee reader for nz unis and make sure its compatible to ca and
// upcoming countries. The logic has to be built by using ai model in the platform and collect and feed error to build and evolve data
// reader". Choices: "Automatic above confidence", "As published + yearly estimate", "NZ universities, then NZ rest, then CA".
// Per provider: its fee pages, the rows the AI read (as published, the yearly figure, the course, what happened), what went wrong
// (findings, fed back to the AI on the next read) and the reading notes. Country rules (currency, unit, full-time load) per country.
// Reads and writes: public.admin_fee_reader.
import React,{useEffect,useState}from'react'
import{Coins,RefreshCw,RotateCcw}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_fee_reader',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const OUTCOME={admitted:['Admitted','success'],review:['To Layer 4','warning'],conflict:['Differs from held fee','warning'],same:['Same as held','neutral'],no_course:['No matching course','danger'],
  domestic:['Domestic (kept)','neutral'],not_yearly:['Not a yearly fee','neutral'],skipped:['Skipped','neutral'],replaced:['Replaced by a newer read','neutral']}
const FINDING={no_rows:'No fee rows on the page',unmatched_row:'Row matched no course',currency:'Different currency',unit_unknown:'Fee unit not understood',outlier:'Outside the usual range',
  quote_missing:'Rows not found on the page',conflict:'Differs from a held fee',rejected:'Rejected or corrected by a person',page_changed:'Page changed',rows_dropped:'Far fewer rows than before',read_failed:'Read failed'}
const money=v=>v==null?'—':fmtNumber(Math.round(Number(v)))
// v2.15.315: the fetch status in words, and what the AI fee reader got from the page
const FETCH={found:'Waiting to be fetched',reading:'Being fetched',read:'Fetched',parsed:'Fetched',no_values:'Fetched',failed:'Could not fetch',rejected:'Stopped by a person'}
const aiText=p=>{const l=p.last;if(p.stopped)return 'Not read (stopped)';if(!l)return p.status==='found'||p.status==='reading'?'Read after it is fetched':'Not read yet'
  if(l.state==='queued')return 'Waiting for the AI (next 10-minute run)';if(l.state==='leased')return 'Being read now';if(l.state==='failed')return `Failed: ${l.error||'error'}`
  return `${l.rows?`${fmtNumber(l.rows)} fee rows`:'No fee rows on the page'} · ${fmtDateTime(l.at)}`}
// v2.15.314: a fee printed for a number of points ("$19,929.84 (for 60 points)") says so, and the yearly figure says how it was worked out
const unitText=r=>r.units_covered?`for ${fmtNumber(r.units_covered)} points`:String(r.unit||'').replace('_',' ')
const yearlyHow=(r,ft)=>r.yearly==null?'':r.units_covered&&ft&&Number(r.units_covered)!==ft?`estimate: ${money(r.amount_min)} ÷ ${r.units_covered} × ${ft}`:r.yearly_basis==='indicative_annual'?'estimate':''

export default function FeeReader({onError}){
  const[ov,setOv]=useState(null),[pid,setPid]=useState('')
  const load=()=>call('overview').then(setOv).catch(e=>onError?.(errText(e)))
  useEffect(()=>{load()},[])
  if(!ov)return <section className="m-panel"><Loading label="Loading the fee reader…"/></section>
  const ps=ov.providers||[]
  return <Card id="layer2.enrich.fees" title="Fee reader (AI)" icon={Coins}
    subtitle={`Reads providers' fee pages with the platform's AI model: every row as published, a yearly figure (estimated from a fee per credit, point or term, or from a fee printed for a number of points: fee ÷ points × the full-time year), the matching course. Rows are admitted when the match is at least ${Math.round(Number(ov.scope?.auto_confidence||0)*100)}% sure and the other checks pass; the rest go to Layer 4. Mistakes are kept and given to the AI on the next read. Scope and limits: Settings › Pipeline settings › Enrichment (Fee reader).`}
    meta={<StatusChip value="scope" tone="info" label={`${(ov.scope?.countries||[]).join(', ')} · ${(ov.scope?.types||[]).join(', ')}`}/>} data-fee-reader>
    <div className="fc-actions"><Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button><small className="sd-desc">AI spend today: US$ {Number(ov.spend_today||0).toFixed(3)}</small></div>
    {ps.length===0?<Empty text="No provider in scope yet."/>:<div className="dq-table-wrap"><table className="dq-table"><thead><tr><th>Provider</th><th className="num">Fee pages (read)</th><th>Last read</th><th>Rows</th><th className="num">Problems</th><th className="num">Courses with a fee</th><th/></tr></thead>
      <tbody>{ps.map(p=><tr key={p.provider_id} data-fee-provider>
        <td><strong>{p.name}</strong><small>{p.country}</small></td><td className="num">{fmtNumber(p.pages)} ({fmtNumber(p.pages_read)})</td>
        <td><small>{p.last_read?fmtDateTime(p.last_read):'Not read yet'}</small></td>
        <td><small>{Object.entries(p.outcomes||{}).map(([k,n])=>`${(OUTCOME[k]||[k])[0]} ${n}`).join(' · ')||'—'}</small></td>
        <td className="num">{fmtNumber(p.open_findings)}</td><td className="num">{fmtNumber(p.courses_with_fee)} of {fmtNumber(p.courses)}</td>
        <td><Button compact onClick={()=>setPid(pid===p.provider_id?'':p.provider_id)}>{pid===p.provider_id?'Close':'Open'}</Button></td></tr>)}</tbody></table></div>}
    {pid&&<ProviderFees pid={pid} name={(ps.find(x=>x.provider_id===pid)||{}).name} fullTime={((ov.profiles||[]).find(c=>c.country_code===(ps.find(x=>x.provider_id===pid)||{}).country)||{}).full_time_units_a_year} onError={onError} onChanged={load}/>}
    <h3 className="sd-subhead">Country rules</h3>
    <div className="dq-table-wrap"><table className="dq-table" data-fee-profiles><thead><tr><th>Country</th><th>Currency</th><th>Usually published</th><th className="num">Full-time year</th><th className="num">Terms a year</th><th>Notes</th></tr></thead>
      <tbody>{(ov.profiles||[]).map(c=><tr key={c.country_code}><td>{c.country_code}</td><td>{c.currency_code}</td><td>{String(c.usual_unit).replace('_',' ')}</td>
        <td className="num">{c.full_time_units_a_year} {c.unit_name}</td><td className="num">{c.terms_a_year}</td><td><small>{c.notes}</small></td></tr>)}</tbody></table></div>
  </Card>
}

function ProviderFees({pid,name,fullTime,onError,onChanged}){
  const[d,setD]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[showOld,setShowOld]=useState(false),[addUrl,setAddUrl]=useState('')
  const load=()=>call('provider',{provider:pid}).then(setD).catch(e=>onError?.(errText(e)))
  useEffect(()=>{setD(null);load()},[pid])
  if(!d)return <Loading compact/>
  const page=async(action,args,q)=>{const r=window.prompt(`${q}. Reason (kept in the log):`);if(!r||r.trim().length<4)return false;setBusy(true);try{await call(action,{provider:pid,...args,reason:r.trim()});setNote(action==='page_add'?'Page added: fetched within about 10 minutes, then read by the AI.':action==='page_stop'?'Page stopped.':'Page will be read again within 10 minutes.');await load();onChanged?.();return true}catch(e){onError?.(errText(e));return false}finally{setBusy(false)}}
  const again=async()=>{setBusy(true);try{const r=await call('read_again',{provider:pid,reason:reason.trim()});setNote(`${r?.queued||0} page(s) queued; they are read within 10 minutes.`);setReason('');load();onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const open=(d.findings||[]).filter(f=>!f.resolved_at)
  const replaced=(d.rows||[]).filter(r=>r.outcome==='replaced').length
  const rows=(d.rows||[]).filter(r=>showOld||r.outcome!=='replaced')
  const ft=Number(fullTime)||null
  return <div className="plan-run" data-fee-provider-panel>
    <h3 className="sd-subhead">{name}: fee pages</h3>
    {/* v2.15.315 (Platform Admin 22 Oct 2026 15:57, Otago: "how to change the existing non-producing URL in UI and replace them ... can we add
        manually in UI"): each page says what the AI got from it; Stop a page that gives no fees, Start again, Add a fee page by hand */}
    <div className="dq-table-wrap"><table className="dq-table" data-fee-pages><thead><tr><th>Page</th><th>Fetched</th><th>AI fee reader</th><th className="num">Fees on the page</th>{d.can_run&&<th/>}</tr></thead>
      <tbody>{(d.pages||[]).map(p=><tr key={p.id} data-fee-page={p.stopped?'stopped':'on'}><td><a className="cf-link" href={p.url} target="_blank" rel="noreferrer">{p.url}</a><small>{p.found_via==='manual'?'added by hand':'found by search'}</small></td>
        <td><small>{FETCH[p.status]||p.status}{p.read_at?` · ${fmtDateTime(p.read_at)}`:''}</small></td>
        <td><small>{aiText(p)}</small></td>
        <td className="num">{p.stopped&&!p.fees?'—':fmtNumber(p.fees||0)}<small>{[p.admitted>0&&`${fmtNumber(p.admitted)} admitted`,p.already_held>0&&`${fmtNumber(p.already_held)} already on the course`,p.to_review>0&&`${fmtNumber(p.to_review)} to Layer 4`].filter(Boolean).join(' · ')}</small></td>
        {d.can_run&&<td>{p.stopped?<Button compact disabled={busy} onClick={()=>page('page_resume',{page:p.id},`Start reading ${p.url} again`)}>Start again</Button>
          :<Button compact disabled={busy} onClick={()=>page('page_stop',{page:p.id},`Stop reading ${p.url} (fees it gave stay)`)}>Stop</Button>}</td>}</tr>)}</tbody></table></div>
    {d.can_run&&<div className="fc-actions" data-fee-page-add><input value={addUrl} onChange={e=>setAddUrl(e.target.value)} placeholder="https://… the provider's international fee page" aria-label="Fee page address" style={{minWidth:'28rem'}}/>
      <Button compact disabled={busy||!/^https?:\/\/\S{6,}$/.test(addUrl.trim())} onClick={()=>page('page_add',{url:addUrl.trim()},`Add ${addUrl.trim()} as a fee page of ${name}`).then(ok=>ok&&setAddUrl(''))}>Add a fee page</Button>
      <small className="sd-desc">An added page is fetched within about 10 minutes (about 1 Firecrawl credit), then read by the AI on the next run. Fees matched to a course at least as sure as the setting are admitted to that course's tuition; the rest go to Layer 4.</small></div>}
    {d.can_run&&<div className="fc-actions"><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason to read again" aria-label="Reason"/>
      <Button compact onClick={again} disabled={busy||reason.trim().length<4}><RotateCcw size={14}/>Read again</Button>{note&&<small className="sd-desc" role="status">{note}</small>}</div>}
    <h3 className="sd-subhead">Rows read</h3>
    {/* v2.15.314 (Platform Admin 22 Oct 2026 15:21, "AUT fix - how can we make that available in the UI?"): the quote, the points a fee is for
        and how the yearly figure was worked out are shown on each row; rows replaced by a newer read are hidden behind a count */}
    {replaced>0&&<small className="sd-desc" data-fee-replaced>{fmtNumber(replaced)} earlier row(s) were replaced when the page was read again. <button type="button" className="cf-link" onClick={()=>setShowOld(!showOld)}>{showOld?'Hide them':'Show them'}</button></small>}
    {rows.length===0?<Empty text="No rows read yet."/>:<div className="dq-table-wrap"><table className="dq-table" data-fee-rows><thead><tr><th>Qualification</th><th className="num">As published</th><th className="num">Yearly</th><th>Course</th><th>Outcome</th></tr></thead>
      <tbody>{rows.map(r=>{const[l,t]=OUTCOME[r.outcome]||[r.outcome,'neutral'];return <tr key={r.id}>
        <td><strong>{r.qualification}</strong>{r.subject&&<small>{r.subject}</small>}<small>{r.audience} · {r.fee_year||'year not stated'}</small>{r.quote&&<small className="fee-quote" data-fee-quote>“{r.quote}”</small>}</td>
        <td className="num">{r.currency_code} {money(r.amount_min)}{r.amount_max?`–${money(r.amount_max)}`:''}<small data-fee-unit>{unitText(r)}</small></td>
        <td className="num">{money(r.yearly)}<small>{yearlyHow(r,ft)}</small></td>
        <td><small>{r.course||'—'}{r.match_confidence!=null?` · ${Math.round(r.match_confidence*100)}% sure`:''}</small></td>
        <td><StatusChip value={r.outcome} tone={t} label={l}/>{r.note&&<small>{r.note}</small>}</td></tr>})}</tbody></table></div>}
    <h3 className="sd-subhead">Problems the reader learns from ({open.length} open)</h3>
    {(d.findings||[]).length===0?<Empty text="None so far."/>:<ul className="sd-desc" data-fee-findings>{(d.findings||[]).slice(0,30).map(f=><li key={f.id}>{f.resolved_at?'Resolved: ':''}<strong>{FINDING[f.kind]||f.kind}</strong> ({f.times}×){f.key?` — ${f.key}`:''}{f.detail?.read_as&&<small data-fee-finding-detail>Read as {String(f.detail.read_as).replace('_',' ')}; it is {f.detail.is}.{f.detail.quote?` “${f.detail.quote}”`:''}</small>}</li>)}</ul>}
    <h3 className="sd-subhead">Reading notes {d.notes?`(version ${d.notes.version}, by ${d.notes.updated_by==='person'?'a person':'the AI'})`:''}</h3>
    <p className="sd-desc">{d.notes?.notes||'None yet; the AI writes them on its first read.'}</p>
  </div>
}
