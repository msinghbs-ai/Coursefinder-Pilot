// Layer 4 › AI could not decide (v2.15.250, CF-247; Platform Admin 11 Oct 2026: "Qwen 3 then GPT-4.1 mini then to Layer 4").
// A scholarship page goes here only when every model in the chain failed to settle it: a reply failed, the name was not on the page,
// or a fact a model stated was not proven by its quote. Each page shows every model's answer with its quotes and the stored copy.
// Admit (the chosen answer, confirmed by a person, then the usual publish checks) or Refuse (with a reason). The decision is kept as an
// exception: the same page copy coming back later is decided the same way without asking again.
// Also shows the Layer 4 items rerouted to university adapters and to the scholarship AI. Read and write: admin_scholarship_ai.
import React,{useEffect,useState}from'react'
import{CheckCircle2,ExternalLink,FileText,RefreshCw,XCircle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{aiValue,aiVerdict}from'./ScholarshipExtraction'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const AUD={international:'International',both:'International and domestic',domestic:'Domestic only',not_stated:'Not stated'}
const FIELD={course_intake:'Intakes',course_english:'English requirements',provider_current_tuition_validation:'Tuition fees',scope_resolution:'Scholarship course scope'}
const host=u=>{try{const x=new URL(u);return x.hostname.replace(/^www\./,'')+x.pathname.replace(/\/$/,'')}catch{return u}}
const Proof=({ok,label})=><span className={`sx-proof ${ok?'ok':'no'}`}>{ok?<CheckCircle2 size={12}/>:<XCircle size={12}/>}{label}</span>

export default function ScholarshipAiReview({onError}){
  const[status,setStatus]=useState('pending'),[d,setD]=useState(null),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[fail,setFail]=useState('')
  const load=async()=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_scholarship_ai',{p_action:'reviews',p_args:{status}});if(error)throw error;setD(data)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[status])
  const decide=async(review,decision,extraction,reason)=>{setFail('');setMsg('');try{const{error}=await supabase.rpc('admin_scholarship_ai',{p_action:'review_decide',p_args:{review_id:review.id,decision,extraction_id:extraction||null,reason:reason||''}});if(error)throw error;setMsg(decision==='admit'?'Admitted. It goes through the publish checks at the next hourly publish.':'Refused. The same page copy will be refused again without asking.');await load()}catch(e){setFail(errText(e))}}
  // v2.15.256: read every waiting page again from the first model in the order (Platform Admin, with a reason; stored copy, no scraper credit)
  const[again,setAgain]=useState(false),[why,setWhy]=useState('')
  const reread=async()=>{setFail('');setMsg('');try{const{data,error}=await supabase.rpc('admin_scholarship_ai',{p_action:'reviews_reread',p_args:{reason:why.trim()}});if(error)throw error;setMsg(`${fmtNumber(data?.applied?.queued||0)} page(s) will be read again from the first model; each stays here only if no model settles it.`);setAgain(false);setWhy('');await load()}catch(e){setFail(errText(e))}}
  const rr=d?.reroutes||{},rows=d?.reviews||[]
  const rerouted=Object.entries(rr).filter(([k])=>k.startsWith('adapter:')).reduce((a,[,n])=>a+Number(n),0),toAi=Object.entries(rr).filter(([k])=>k.startsWith('scholarship_ai:')).reduce((a,[,n])=>a+Number(n),0)
  return <div className="m-page-stack sx" data-ai-review>
    <section className="m-panel">
      <div className="m-workspace-head"><div><h2>AI could not decide</h2><p>Scholarship pages that no model in the chain could settle: a reply failed, the name was not on the page, or a fact was not proven by a quote. Admit or refuse each one; the decision is kept for the same page copy.</p></div>
        <span className="sx-row">{again?<span className="sx-reason"><input value={why} onChange={e=>setWhy(e.target.value)} placeholder="Reason (kept in the log)" aria-label="Reason: read the waiting pages again" autoFocus/><Button compact variant="primary" disabled={why.trim().length<4} onClick={reread} data-ai-review-reread-confirm>Read again</Button><Button compact onClick={()=>{setAgain(false);setWhy('')}}>Cancel</Button></span>
          :<Button compact disabled={!Number(d?.pending)} onClick={()=>setAgain(true)} data-ai-review-reread>Read the waiting pages again</Button>}
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></span></div>
      <div className="sc-tiles">
        <div><small>Waiting for a person</small><strong>{fmtNumber(d?.pending||0)}</strong><span>{d?.ai_admission?'AI admission is on':'AI admission is off: nothing new arrives'}</span></div>
        <div><small>Models, in order</small><strong>{(d?.chain||[]).join(' → ')||'None'}</strong><span>then this list</span></div>
        <div data-ai-review-adapter><small>Course items sent to adapters</small><strong>{fmtNumber(rerouted)}</strong><span>{fmtNumber(d?.layer4_course_pending||0)} course items still in the Review queue</span></div>
        <div><small>Scholarship items sent to the AI</small><strong>{fmtNumber(toAi)}</strong><span>from the Review queue</span></div>
      </div>
      {rerouted>0&&<p className="sc-sub" data-ai-review-reroutes>Rerouted to the university adapter: {Object.entries(rr).filter(([k])=>k.startsWith('adapter:')).map(([k,n])=>`${FIELD[k.split(':')[1]]||k.split(':')[1]} ${fmtNumber(n)}`).join(' · ')}. Each course page is read again and the adapter admits the value; the items are closed as superseded.</p>}
      <div className="ar-tabs" role="tablist" aria-label="Which pages"><button role="tab" aria-selected={status==='pending'} className={status==='pending'?'active':''} onClick={()=>setStatus('pending')}>Waiting</button><button role="tab" aria-selected={status==='decided'} className={status==='decided'?'active':''} onClick={()=>setStatus('decided')}>Decided</button></div>
      {msg&&<p role="status" className="sc-note" data-ai-review-note>{msg}</p>}
      {fail&&<p role="alert" className="sc-note sc-bad" data-ai-review-fail>{fail}</p>}
      {busy&&!d?<Loading label="Loading…"/>:rows.length===0?<p className="sc-sub">{status==='pending'?'Nothing is waiting.':'No decisions yet.'}</p>:rows.map(v=><Review key={v.id} v={v} decide={decide}/>)}
    </section>
  </div>
}

function Review({v,decide}){
  const answers=v.answers||[],best=[...answers].reverse().find(a=>a.answer?.is_scholarship)||answers[answers.length-1],[pick,setPick]=useState(best?.id||null),[refusing,setRefusing]=useState(false),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const go=async(decision)=>{setBusy(true);try{await decide(v,decision,pick,reason)}finally{setBusy(false)}}
  return <article className="sx-review" data-ai-review-row={v.id}>
    <header><div><strong>{v.scholarship||answers.find(a=>a.answer?.name)?.answer?.name||host(v.url)}</strong><small className="sc-sub"> {v.provider||''}</small></div>
      <a className="cf-link" href={v.url} target="_blank" rel="noreferrer">{host(v.url)} <ExternalLink size={11}/></a></header>
    <p className="sc-note">Why: {v.reason}{v.status!=='pending'&&<> · <StatusChip value={v.status} tone={v.status==='admitted'?'success':'neutral'} label={v.status==='admitted'?'Admitted':'Refused'}/> {fmtDateTime(v.decided_at)}{v.note?` · ${v.note}`:''}</>}</p>
    <div className="sx-answers">{answers.map(a=>{const x=a.answer||{},k=a.checks||{};return <label key={a.id} className={`sx-answer${pick===a.id?' is-picked':''}`} data-ai-review-answer={a.model_code}>
      {v.status==='pending'&&<input type="radio" name={`pick-${v.id}`} checked={pick===a.id} onChange={()=>setPick(a.id)} disabled={!a.answer}/>}
      <div><b>{a.model_code}</b> {aiVerdict(a)}{x.name&&<small className="sc-sub"> {x.name}</small>}
        {a.error?<p className="sc-bad">{a.error}</p>:<dl>
          <dt>Who</dt><dd>{AUD[x.audience]||'—'} <Proof ok={k.audience} label="quote"/>{x.audience_quote&&<q>{x.audience_quote}</q>}</dd>
          <dt>Value</dt><dd>{aiValue(x.value)} <Proof ok={k.value} label="quote"/>{x.value?.quote&&<q>{x.value.quote}</q>}</dd>
          <dt>Offered</dt><dd>{x.offered||'—'}{x.offered_quote&&<q>{x.offered_quote}</q>}</dd>
          {x.not_scholarship_reason&&<><dt>Why not</dt><dd>{x.not_scholarship_reason}</dd></>}
          {a.evidence_id&&<><dt>Stored copy</dt><dd><a className="cf-link" href={`#evidence?evidence_id=${a.evidence_id}`}><FileText size={12}/> Open</a></dd></>}
        </dl>}</div></label>})}</div>
    {v.status==='pending'&&<div className="sx-row">
      <Button compact variant="primary" disabled={busy||!pick} onClick={()=>go('admit')} data-ai-review-admit>Admit the chosen answer</Button>
      {refusing?<span className="sx-reason"><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why it is not a scholarship for international students" aria-label="Reason for refusing" autoFocus/><Button compact disabled={busy||reason.trim().length<4} onClick={()=>go('refuse')} data-ai-review-refuse-confirm>Refuse</Button><Button compact onClick={()=>{setRefusing(false);setReason('')}}>Cancel</Button></span>
        :<Button compact onClick={()=>setRefusing(true)} data-ai-review-refuse>Refuse</Button>}
      <small className="sc-sub">Admit takes the chosen answer as confirmed for international students and currently offered; the hourly publish checks still apply.</small>
    </div>}
  </article>
}
