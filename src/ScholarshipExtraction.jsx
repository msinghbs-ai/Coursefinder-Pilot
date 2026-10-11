// Scholarships › Extraction (v2.15.249, CF-247; Platform Admin bugs 11/10-6, 11 Oct 2026: "Just like courses adapter i need
// scholarship to be read by code using Firecrawl but then use AI to extract attributes. Simple code extraction fields are making
// too many mistakes and rejecting the values. I can't validate and check every page.")
// Pages are still read by code through the scraper (Firecrawl) and stored; a pinned AI model then reads each stored page and
// answers with the scholarship's facts, each proven by an exact quote that the worker checks against the page. Nothing is
// admitted by AI until a model has been qualified on the sample (pages with known answers), made active, and AI admission is
// switched on: a passing qualification never switches anything on by itself. AI-admitted scholarships go through the same
// hourly publish checks as before.
// Read and write: admin_scholarship_ai(action, args). Platform Admin for every change.
import React,{useEffect,useState}from'react'
import{CheckCircle2,ExternalLink,FileText,Play,RefreshCw,XCircle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const VERDICT={scholarship:['Scholarship','success'],listing:['Lists several','info'],not_scholarship:['Not a scholarship','neutral'],unproven:['Name not proven','warning']}
const AUD={international:'International',both:'International and domestic',domestic:'Domestic only',not_stated:'Not stated'}
const host=u=>{try{const x=new URL(u);return x.hostname.replace(/^www\./,'')+x.pathname.replace(/\/$/,'')}catch{return u}}
const pct=(a,b)=>b?`${Math.round(100*a/b)}%`:'—'
export function aiValue(v){if(!v)return'—';const n=x=>x==null?'':fmtNumber(x);if(v.kind==='percentage')return `${n(v.percentage)}% of tuition`;if(v.kind==='fixed_amount')return `${v.currency||''} ${n(v.amount)}`.trim();if(v.kind==='full_tuition')return'Full tuition';if(v.kind==='non_monetary')return'A benefit (no amount)';if(v.kind==='tiers')return(v.tiers||[]).map(t=>`${t.label}: ${t.percentage!=null?n(t.percentage)+'%':n(t.amount)}`).join('; ')||'Tiers';return'Not stated'}
export function aiVerdict(e){if(e?.error)return <StatusChip value="failed" tone="danger" label="Failed" title={e.error}/>;const[l,t]=VERDICT[e?.verdict]||[e?.verdict||'—','neutral'];return <StatusChip value={e?.verdict} tone={t} label={l}/>}
const Proof=({ok,label})=><span className={`sx-proof ${ok?'ok':'no'}`} title={ok?`${label}: quote found on the page`:`${label}: not proven (quote not on the page, or not stated)`}>{ok?<CheckCircle2 size={12}/>:<XCircle size={12}/>}{label}</span>

// A change that needs a reason: the button opens a one-line reason box and Confirm.
function ReasonAction({label,confirm='Confirm',variant,disabled,onDo,placeholder='Reason (kept in the log)',testid}){
  const[open,setOpen]=useState(false),[r,setR]=useState(''),[busy,setBusy]=useState(false)
  if(!open)return <Button compact variant={variant} disabled={disabled} onClick={()=>setOpen(true)} data-sx-action={testid}>{label}</Button>
  return <span className="sx-reason"><input value={r} onChange={e=>setR(e.target.value)} placeholder={placeholder} aria-label={`Reason: ${label}`} autoFocus/>
    <Button compact variant="primary" disabled={busy||r.trim().length<4} onClick={async()=>{setBusy(true);try{await onDo(r.trim());setOpen(false);setR('')}finally{setBusy(false)}}} data-sx-confirm={testid}>{busy?'Working…':confirm}</Button>
    <Button compact onClick={()=>{setOpen(false);setR('')}}>Cancel</Button></span>
}

export default function ScholarshipExtraction({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[fail,setFail]=useState('')
  const load=async()=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_scholarship_ai',{p_action:'read',p_args:{}});if(error)throw error;setD(data)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const act=async(action,args,done)=>{setFail('');setMsg('');try{const{data,error}=await supabase.rpc('admin_scholarship_ai',{p_action:action,p_args:args});if(error)throw error;setD(data);if(done)setMsg(done)}catch(e){setFail(errText(e));throw e}}
  useEffect(()=>{load()},[])
  const waiting=d?.queue?.waiting||0
  useEffect(()=>{if(!waiting)return;const t=setInterval(()=>{if(document.visibilityState==='visible')load()},15000);return()=>clearInterval(t)},[waiting])
  if(!d)return <div className="m-page-stack"><section className="m-panel">{busy?<Loading label="Loading extraction…"/>:<p>Could not load.</p>}</section></div>
  const can=d.can_manage,models=d.models||[],scores=d.scores||{},runs=d.qualify_runs||[],active=models.find(m=>m.status==='active'),chain=(d.chain||[]).map(c=>models.find(m=>m.code===c)).filter(Boolean)
  const lastRun=code=>runs.find(r=>r.model_code===code&&String(r.prompt_version)===String(d.prompt_version))
  return <div className="m-page-stack sx" data-scholarship-extraction>
    <section className="m-panel">
      <div className="m-workspace-head"><div><h2>Extraction</h2><p>Code reads each scholarship page through the scraper and keeps a copy; an AI model then reads the copy and answers with the scholarship's facts. Every fact must quote the page, and the quote is checked.</p></div>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
      <div className="sc-tiles">
        <div data-sx-admission><small>AI admission</small><strong>{d.ai_admission?'On':'Off'}</strong><span>{d.ai_admission?'AI answers decide which pages are admitted':'Rules decide; AI answers are recorded only'}</span></div>
        <div data-sx-chain><small>Models, in order</small><strong>{chain.length?chain.map(m=>m.label.split(' ').slice(0,2).join(' ')).join(' → '):'None'}</strong><span>{chain.length?`then Layer 4 › AI could not decide (${fmtNumber(d.reviews_pending||0)} waiting)`:'qualify models, then set the order'}</span></div>
        <div><small>Pages waiting</small><strong>{fmtNumber(waiting)}</strong><span>{fmtNumber(d.queue?.done_today||0)} read today</span></div>
        <div><small>AI cost today</small><strong>US${Number(d.cost_today||0).toFixed(2)}</strong><span>instructions v{d.prompt_version||1}</span></div>
      </div>
      {can&&<div className="sx-row">
        {d.ai_admission
          ?<ReasonAction label="Switch AI admission off" testid="admission-off" onDo={r=>act('set_admission',{on:false,reason:r},'AI admission is off. Rules decide again.')}/>
          :<ReasonAction label="Switch AI admission on" variant="primary" disabled={!active} testid="admission-on" onDo={r=>act('set_admission',{on:true,reason:r},'AI admission is on. New and re-read pages are decided by the AI answer.')}/>}
        <ReasonAction label="Re-check the watch list with AI" disabled={!active} testid="backfill" onDo={r=>act('backfill',{scope:'watch',reason:r},'Queued. Progress is in Scheduled jobs › Task manager.')}/>
        <ReasonAction label="Re-read parked scholarships with AI" disabled={!active} testid="reroute" onDo={r=>act('reroute_parked',{reason:r},'Queued: active scholarships not published, and held ones, are read again by the AI. A hold a person made stays. Progress is in Scheduled jobs › Task manager.')}/>
        <a className="cf-link" href="#layer-4-review?tab=aireview" data-sx-reviews-link>AI could not decide: {fmtNumber(d.reviews_pending||0)}</a>
        {!active&&<small className="sc-sub">Both need an active model.</small>}
      </div>}
      {msg&&<p role="status" className="sc-note" data-sx-note>{msg}</p>}
      {fail&&<p role="alert" className="sc-note sc-bad" data-sx-fail>{fail}</p>}
    </section>

    <section className="m-panel" data-sx-models>
      <h3>Models</h3>
      <p className="sc-sub">Each model is qualified on the sample below with the current instructions. Qualifying never makes a model active; that is a separate step. The first model reads every page; the next reads it again only when the first one's reply fails or a fact it states is not proven on the page; a page no model can settle goes to Layer 4.</p>
      {can&&<ChainEditor models={models} chain={d.chain||[]} qualified={code=>{const r=lastRun(code);return r&&r.state==='done'}} act={act}/>}
      <div className="cf-table-wrap"><table className="cf-table">
        <thead><tr><th>Model</th><th>Status</th><th className="num" title="Scholarship or not, as expected">Scholarship right</th><th className="num">International right</th><th className="num">Offered right</th><th className="num" title="Answers whose quotes failed the page check">Proofs failed</th><th className="num">Failed</th><th className="num">Cost a page</th><th>Last qualification</th>{can&&<th/>}</tr></thead>
        <tbody>{models.map(m=>{const s=scores[m.code]||{},run=lastRun(m.code);return <tr key={m.code} data-sx-model={m.code}>
          <td><strong>{m.label}</strong><small className="sc-sub"> {m.model_identifier}</small></td>
          <td>{(d.chain||[]).includes(m.code)?<StatusChip value="active" tone="success" label={(d.chain||[]).indexOf(m.code)===0?'Reads first':`Reads ${['','second','third'][(d.chain||[]).indexOf(m.code)]}`}/>:<StatusChip value={m.status} tone={m.status==='retired'?'neutral':'info'} label={m.status==='retired'?'Retired':'Candidate'}/>}</td>
          <td className="num">{s.pages?`${fmtNumber(s.scholarship_right)} / ${fmtNumber(s.pages)} (${pct(s.scholarship_right,s.pages)})`:'—'}</td>
          <td className="num">{s.international_checked?`${fmtNumber(s.international_right)} / ${fmtNumber(s.international_checked)}`:'—'}</td>
          <td className="num">{s.offered_checked?`${fmtNumber(s.offered_right)} / ${fmtNumber(s.offered_checked)}`:'—'}</td>
          <td className="num">{s.pages?fmtNumber(s.proofs_failed):'—'}</td>
          <td className="num">{s.pages?fmtNumber(s.errors):'—'}</td>
          <td className="num">{s.pages?`US$${Number(s.cost_per_page||0).toFixed(4)}`:'—'}</td>
          <td>{run?<><StatusChip value={run.state}/> <small className="sc-sub">{fmtNumber(run.progress?.done||0)} of {fmtNumber(run.progress?.total||0)} · {fmtDateTime(run.at)}</small></>:<span className="sc-sub">Not yet</span>}</td>
          {can&&<td className="sx-actions"><ReasonAction label="Qualify" testid={`qualify-${m.code}`} disabled={run&&['queued','running'].includes(run.state)} onDo={r=>act('qualify',{model_code:m.code,reason:r},`Qualifying ${m.label} on ${fmtNumber((d.sample||[]).filter(x=>x.active).length)} pages.`)}/>
            {m.status!=='active'&&<ReasonAction label="Make active" testid={`activate-${m.code}`} disabled={!run||run.state!=='done'} onDo={r=>act('activate',{model_code:m.code,reason:r},`${m.label} is the active model. AI admission is unchanged.`)}/>}</td>}
        </tr>})}</tbody>
      </table></div>
    </section>

    <Sample d={d} can={can} act={act}/>
    <Instructions d={d} can={can} act={act}/>
    <TestPage d={d} can={can} act={act} models={models}/>
    <Recent rows={d.recent||[]}/>
  </div>
}

// v2.15.250: the order the models read in (each qualified with the current instructions)
function ChainEditor({models,chain,qualified,act}){
  const usable=models.filter(m=>m.status!=='retired'),[first,setFirst]=useState(chain[0]||''),[then,setThen]=useState(chain[1]||'')
  useEffect(()=>{setFirst(chain[0]||'');setThen(chain[1]||'')},[chain.join(',')])
  const order=[first,then].filter(Boolean),ok=order.length>0&&new Set(order).size===order.length&&order.every(qualified),same=order.join(',')===chain.join(',')
  return <div className="sx-row" data-sx-chain-editor>
    <label>Reads first <select value={first} onChange={e=>setFirst(e.target.value)} aria-label="Model that reads first"><option value="">Choose</option>{usable.map(m=><option key={m.code} value={m.code}>{m.label}</option>)}</select></label>
    <label>Then <select value={then} onChange={e=>setThen(e.target.value)} aria-label="Model that reads next"><option value="">No second model</option>{usable.filter(m=>m.code!==first).map(m=><option key={m.code} value={m.code}>{m.label}</option>)}</select></label>
    <span className="sc-sub">then Layer 4</span>
    <ReasonAction label="Set the order" testid="set-chain" disabled={!ok||same} onDo={r=>act('set_chain',{models:order,reason:r},'Order set. AI admission is unchanged.')}/>
    {order.length>0&&!order.every(qualified)&&<small className="sc-sub">Qualify each model with the current instructions first.</small>}
  </div>
}

function Sample({d,can,act}){
  const rows=d.sample||[],models=(d.models||[]).filter(m=>m.status!=='retired'),[show,setShow]=useState('all')
  const exp=x=>x.expected?.is_scholarship===false?'Not a scholarship':x.expected?.single===false?'Lists several':'Scholarship'
  const right=(x,a)=>{if(!a||a.error)return null;const xs=x.expected?.is_scholarship!==false&&x.expected?.single!==false;const as=!!a.answer?.is_scholarship&&!!a.answer?.single_scholarship;return xs===as}
  const list=rows.filter(x=>show==='all'||models.some(m=>right(x,x.answers?.[m.code])===false))
  return <section className="m-panel" data-sx-sample>
    <h3>Qualification sample</h3>
    <p className="sc-sub">Pages with known answers: scholarships a person checked and published, and pages a person marked as not scholarships. Correct a label here when a model is right and the label is wrong.</p>
    <div className="ar-tabs" role="tablist" aria-label="Which sample pages"><button role="tab" aria-selected={show==='all'} className={show==='all'?'active':''} onClick={()=>setShow('all')}>All ({fmtNumber(rows.length)})</button><button role="tab" aria-selected={show==='wrong'} className={show==='wrong'?'active':''} onClick={()=>setShow('wrong')}>Where a model disagrees</button></div>
    <div className="cf-table-wrap"><table className="cf-table">
      <thead><tr><th>Page</th><th>Expected</th>{models.map(m=><th key={m.code}>{m.label}</th>)}{can&&<th/>}</tr></thead>
      <tbody>{list.length===0?<tr><td colSpan={3+models.length}>Nothing to show.</td></tr>:list.map(x=><tr key={x.id} data-sx-sample-row={x.id} className={x.active?'':'is-muted'}>
        <td><a className="cf-link" href={x.url} target="_blank" rel="noreferrer">{host(x.url)} <ExternalLink size={11}/></a><small className="sc-sub"> {x.provider||''}{x.note?` · ${x.note}`:''}</small></td>
        <td>{exp(x)}{x.expected?.international===true&&<small className="sc-sub"> · international</small>}<small className="sc-sub"> · {x.label_source}</small></td>
        {models.map(m=>{const a=x.answers?.[m.code],ok=right(x,a);return <td key={m.code} data-sx-answer={m.code}>{a?<>{aiVerdict(a)} {ok===false&&<b className="sc-bad">differs</b>}{a.answer?.name&&<small className="sc-sub"> {a.answer.name}</small>}{a.answer?.audience&&<small className="sc-sub"> · {AUD[a.answer.audience]||a.answer.audience}</small>}{a.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${a.evidence_id}`}> <FileText size={11}/></a>}</>:<span className="sc-sub">—</span>}</td>})}
        {can&&<td className="sx-actions">{x.expected?.is_scholarship===false
          ?<Button compact onClick={()=>act('label',{sample_id:x.id,expected:{is_scholarship:true,single:true}},'Label changed.')}>Mark scholarship</Button>
          :<Button compact onClick={()=>act('label',{sample_id:x.id,expected:{is_scholarship:false}},'Label changed.')}>Mark not a scholarship</Button>}
          <Button compact onClick={()=>act('label',{sample_id:x.id,active:!x.active},x.active?'Left out of qualification.':'Back in the sample.')}>{x.active?'Leave out':'Include'}</Button></td>}
      </tr>)}</tbody>
    </table></div>
  </section>
}

function Instructions({d,can,act}){
  const cur=(d.prompts||[]).find(p=>p.active),[text,setText]=useState(cur?.text||''),[edit,setEdit]=useState(false)
  useEffect(()=>{if(!edit)setText(cur?.text||'')},[cur?.text,edit])
  return <details className="m-panel" data-sx-instructions><summary>Instructions to the model (v{cur?.version||'—'})</summary>
    <p className="sc-sub">Saving new instructions makes a new version. The active model must then be qualified again, and AI admission switches off until it is.</p>
    <textarea className="sx-prompt" value={text} readOnly={!edit} onChange={e=>setText(e.target.value)} rows={16} aria-label="Instructions to the model"/>
    {can&&<div className="sx-row">{edit?<><ReasonAction label="Save as a new version" variant="primary" testid="set-prompt" disabled={text.trim().length<200||text===cur?.text} onDo={async r=>{await act('set_prompt',{text,reason:r},'Saved. Qualify again before switching AI admission on.');setEdit(false)}}/><Button compact onClick={()=>{setEdit(false);setText(cur?.text||'')}}>Cancel</Button></>:<Button compact onClick={()=>setEdit(true)}>Edit</Button>}</div>}
    <ul className="sx-versions">{(d.prompts||[]).map(p=><li key={p.version}>v{p.version}{p.active?' (current)':''} · {fmtDateTime(p.at)} · {p.reason||''}</li>)}</ul>
  </details>
}

function TestPage({d,can,act,models}){
  const[url,setUrl]=useState(''),[model,setModel]=useState(''),[busy,setBusy]=useState(false)
  if(!can)return null
  return <section className="m-panel" data-sx-test>
    <h3>Try a page</h3>
    <p className="sc-sub">Reads one page with a model and shows the answer under Recent answers within a minute or two. Nothing is admitted or changed.</p>
    <div className="sx-row"><input className="sx-url" value={url} onChange={e=>setUrl(e.target.value)} placeholder="https://… scholarship page" aria-label="Page address"/>
      <select value={model} onChange={e=>setModel(e.target.value)} aria-label="Model"><option value="">{d.active_model?'Active model':'Choose a model'}</option>{models.filter(m=>m.status!=='retired').map(m=><option key={m.code} value={m.code}>{m.label}</option>)}</select>
      <Button compact variant="primary" disabled={busy||!/^https?:\/\//.test(url.trim())||(!model&&!d.active_model)} onClick={async()=>{setBusy(true);try{await act('test',{url:url.trim(),model_code:model},'Queued. The answer appears under Recent answers.');setUrl('')}catch{}finally{setBusy(false)}}} data-sx-test-run><Play size={13}/>Read with AI</Button></div>
  </section>
}

function Recent({rows}){
  const[open,setOpen]=useState(null)
  return <section className="m-panel" data-sx-recent>
    <h3>Recent answers</h3>
    <div className="cf-table-wrap"><table className="cf-table">
      <thead><tr><th>When</th><th>Page</th><th>Model</th><th>Why</th><th>Answer</th><th>Proven</th><th>Applied</th></tr></thead>
      <tbody>{rows.length===0?<tr><td colSpan={7}>No answers yet.</td></tr>:rows.map(e=>{const a=e.answer||{},k=e.checks||{};return <React.Fragment key={e.id}><tr data-sx-recent-row={e.id} onClick={()=>setOpen(open===e.id?null:e.id)} style={{cursor:'pointer'}}>
        <td>{fmtDateTime(e.at)}</td>
        <td><a className="cf-link" href={e.url} target="_blank" rel="noreferrer" onClick={x=>x.stopPropagation()}>{host(e.url)}</a><small className="sc-sub"> {e.provider||''}</small></td>
        <td>{e.model_code}</td><td>{({admit:'New page',reread:'Re-read',test:'Try a page',qualify:'Qualification'})[e.run_kind]||e.run_kind}</td>
        <td>{aiVerdict(e)}{a.name&&<small className="sc-sub"> {a.name}</small>}</td>
        <td>{e.error?'—':<span className="sx-proofs"><Proof ok={k.name} label="Name"/><Proof ok={k.audience} label="Who"/><Proof ok={k.offered} label="Offered"/><Proof ok={k.value} label="Value"/></span>}</td>
        <td>{e.applied?<StatusChip value="done" tone="success" label={e.applied.admitted?'Admitted':e.applied.action||'Applied'}/>:<span className="sc-sub">Recorded only</span>}</td></tr>
        {open===e.id&&<tr className="sx-detail"><td colSpan={7}>{e.error?<p className="sc-bad">{e.error}</p>:<dl>
          <dt>Who it is for</dt><dd>{AUD[a.audience]||'—'}{a.audience_quote&&<q>{a.audience_quote}</q>}</dd>
          <dt>Offered</dt><dd>{a.offered||'—'}{a.offered_quote&&<q>{a.offered_quote}</q>}</dd>
          <dt>Value</dt><dd>{aiValue(a.value)}{a.value?.quote&&<q>{a.value.quote}</q>}</dd>
          <dt>Levels</dt><dd>{(a.levels||[]).join(', ')||'—'}</dd>
          <dt>Courses</dt><dd>{(k.courses_found||[]).length?`${(k.courses_found||[]).join('; ')}`:'—'}{(k.courses_not_found||[]).length?<small className="sc-sub"> · not found on the page: {(k.courses_not_found||[]).join('; ')}</small>:null}</dd>
          <dt>Dates</dt><dd>{[a.open_date&&`opens ${a.open_date}`,a.close_date&&`closes ${a.close_date}`].filter(Boolean).join(', ')||'—'}</dd>
          {a.not_scholarship_reason&&<><dt>Why not</dt><dd>{a.not_scholarship_reason}</dd></>}
          {e.evidence_id&&<><dt>Stored copy</dt><dd><a className="cf-link" href={`#evidence?evidence_id=${e.evidence_id}`}><FileText size={12}/> Open</a></dd></>}
        </dl>}</td></tr>}
      </React.Fragment>})}</tbody>
    </table></div>
  </section>
}
