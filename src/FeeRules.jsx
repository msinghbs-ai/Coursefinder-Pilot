// Layer 4 › Batch rules (v2.15.116): fee wording rules. Most unsettled tuition at a university is one wording, not a
// per-course question ("2026 Indicative First Year Fee $56,500"). A rule says: at this university, the amount after these
// words is the international tuition for this period. Preview shows every course it would settle; a draft is approved
// by a PIM Operator or above, runs at once and then hourly on newly read pages. Values entered by hand are never changed.
// Read: public.admin_fee_rules_read(), public.admin_fee_rule_preview(provider, phrase, url_pattern);
// write: public.admin_fee_rule_control(action, args) (migration 20260930140000_cf247_fee_wording_rules).
import React,{useEffect,useRef,useState}from'react'
import{Check,Pause,Play,Plus,RefreshCw,Scale,Search,Sparkles,Trash2,Zap}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'

export const PERIOD={annual:'Per year',per_semester:'Per semester',per_trimester:'Per trimester',total_indicative:'Whole course'}
const STATUS={draft:['warning','Draft · waiting for approval'],active:['success','Active'],paused:['neutral','Paused']}
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')

export default function FeeRules({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[draft,setDraft]=useState(null),[done,setDone]=useState(''),[err,setErr]=useState(''),[preview,setPreview]=useState(null)
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_fee_rules_read');if(error)throw error;setData(d||{})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const act=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);setDone('');setErr('');try{const{data:d,error}=await supabase.rpc('admin_fee_rule_control',{p_action:action,p_args:args});if(error)throw error;setData(d||{});const r=d?.result;if(action==='create')setDraft(null);setDone(r?`${action==='approve'?'Approved and run':'Run'}: ${fmtNumber(r.admitted||0)} fee${Number(r.admitted)===1?'':'s'} admitted${r.ambiguous?`, ${fmtNumber(r.ambiguous)} skipped (more than one amount)`:''}${r.already_had_fee?`, ${fmtNumber(r.already_had_fee)} already had a fee`:''}${r.entered_by_hand?`, ${fmtNumber(r.entered_by_hand)} entered by hand`:''}.`:action==='create'?'Saved as a draft. A PIM Operator or above can approve it.':'Saved.')}catch(e){setErr(`That did not work: ${errText(e)}`)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!data)return <section className="m-panel"><Loading label="Loading batch rules…"/></section>
  const rules=data.rules||[],sug=data.suggestions||[],recent=data.recent||[]
  const admitted=rules.reduce((n,r)=>n+Number(r.admitted||0),0)
  return <>
    <div className="cf-metric-grid">
      <Metric label="Active rules" value={fmtNumber(rules.filter(r=>r.status==='active').length)} detail={`${fmtNumber(rules.filter(r=>r.status==='draft').length)} waiting for approval`} icon={Scale}/>
      <Metric label="Fees admitted by rules" value={fmtNumber(admitted)} icon={Check} tone={admitted?'success':'neutral'}/>
      <Metric label="Wordings found" value={fmtNumber(sug.filter(s=>!s.has_rule).length)} detail="Repeated on 10 or more pages with no fee yet" icon={Sparkles}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Scale} title="Fee rules" subtitle="When a university words its international fee the same way on every course page, one rule settles all of them. Preview first, then approve. Values entered by hand are never changed." action={<div className="l3c-actions">
        {data.can_create&&<Button compact variant="primary" onClick={()=>setDraft({provider_id:'',provider:'',phrase:'',basis:'annual'})}><Plus size={14}/>New rule</Button>}
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {!data.can_create&&<p className="l3v-note">You can view these. A Pipeline Operator or above can prepare a rule; a PIM Operator or above approves it.</p>}
      {done&&<p className="sb-done" role="status">{done}</p>}
      {err&&<p className="fr-error" role="alert">{err}</p>}
    </section>
    {draft&&<RuleBuilder key={draft.provider_id+draft.phrase} init={draft} busy={busy} onCancel={()=>setDraft(null)} onSave={a=>act('create',a)} onError={onError}/>}
    <section className="m-panel">
      <SectionTitle title="Rules" subtitle={rules.length?`${rules.length} rule${rules.length===1?'':'s'}`:'No rules yet.'}/>
      {rules.length>0&&<div className="cf-table-wrap"><table className="cf-table fr-rules"><thead><tr><th>University</th><th>Words before the fee</th><th>Period</th><th>Status</th><th className="num">Admitted</th><th>Change</th></tr></thead><tbody>
        {rules.map(r=>{const st=STATUS[r.status]||['neutral',r.status];return <React.Fragment key={r.id}><tr data-rule={r.id}>
          <td><strong>{r.provider}</strong>{r.note&&<span className="l3v-code">{r.note}</span>}</td>
          <td><q className="fr-phrase">{r.phrase}</q><span className="l3v-code">{[r.created_by&&`Prepared by ${r.created_by}`,fmtDateTime(r.created_at)].filter(Boolean).join(' · ')}</span></td>
          <td>{PERIOD[r.basis]||r.basis}</td>
          <td><StatusChip value={r.status} tone={st[0]} label={st[1]}/>{r.approved_at&&<span className="l3v-code">Approved {[r.approved_by,fmtDateTime(r.approved_at)].filter(Boolean).join(' · ')}</span>}{r.last_run_at&&<span className="l3v-code">Last run {fmtDateTime(r.last_run_at)}</span>}</td>
          <td className="num">{fmtNumber(r.admitted||0)}</td>
          <td><div className="l3c-row-actions">
            <Button compact onClick={()=>setPreview(preview?.id===r.id?null:r)} aria-label={`Preview rule ${r.id}`} aria-pressed={preview?.id===r.id}><Search size={13}/>{preview?.id===r.id?'Hide preview':'Preview'}</Button>
            {r.status==='draft'&&data.can_approve&&<Button compact variant="primary" onClick={()=>act('approve',{id:r.id},`Approve this rule for ${r.provider} and admit the fees it finds now?`)} disabled={busy} aria-label={`Approve rule ${r.id}`}><Check size={13}/>Approve & run</Button>}
            {r.status==='active'&&data.can_approve&&<><Button compact onClick={()=>act('run',{id:r.id})} disabled={busy} aria-label={`Run rule ${r.id}`}><Zap size={13}/>Run now</Button><Button compact onClick={()=>act('pause',{id:r.id})} disabled={busy} aria-label={`Pause rule ${r.id}`}><Pause size={13}/>Pause</Button></>}
            {r.status==='paused'&&data.can_approve&&<Button compact onClick={()=>act('resume',{id:r.id})} disabled={busy} aria-label={`Resume rule ${r.id}`}><Play size={13}/>Resume</Button>}
            {r.status==='draft'&&data.can_create&&<Button compact variant="danger" onClick={()=>act('delete',{id:r.id},'Delete this draft rule?')} disabled={busy} aria-label={`Delete rule ${r.id}`}><Trash2 size={13}/></Button>}
          </div></td></tr>
          {preview?.id===r.id&&<tr className="fr-preview-row"><td colSpan={6}><div className="fr-preview-panel" data-preview-rule={r.id}><Preview providerId={r.provider_id} phrase={r.phrase} urlPattern={r.url_pattern} onError={onError}/></div></td></tr>}
          </React.Fragment>})}
      </tbody></table></div>}
    </section>
    <section className="m-panel">
      <SectionTitle icon={Sparkles} title="Wordings found on pages with no fee yet" subtitle="The words just before an amount, repeated on many course pages of the same university. Not every wording is a tuition fee: preview before making a rule."/>
      {sug.length?<div className="cf-table-wrap"><table className="cf-table fr-sug"><thead><tr><th>University</th><th>Words before the amount</th><th className="num">Pages</th>{data.can_create&&<th></th>}</tr></thead><tbody>
        {sug.map((s,i)=><tr key={i}><td>{s.provider}</td><td><q className="fr-phrase">{s.phrase}</q><span className="fr-example">{s.example}</span></td><td className="num">{fmtNumber(s.pages)}</td>
          {data.can_create&&<td>{s.has_rule?<span className="l3v-code">Rule exists</span>:<Button compact onClick={()=>setDraft({provider_id:s.provider_id,provider:s.provider,phrase:s.phrase,basis:'annual'})} aria-label={`Make a rule from ${s.phrase}`}><Plus size={13}/>Make a rule</Button>}</td>}</tr>)}
      </tbody></table></div>:<Empty text="No repeated wording found."/>}
    </section>
    {recent.length>0&&<section className="m-panel"><SectionTitle title="Recently admitted by rules"/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>When</th><th>Course</th><th className="num">Fee</th><th>Matched text</th></tr></thead><tbody>
        {recent.map((a,i)=><tr key={i}><td>{fmtDateTime(a.at)}</td><td>{a.course}<span className="l3v-code">{a.code} · rule {a.rule_id}</span></td><td className="num">{fmtMoney(a.amount,'AUD')}<span className="l3v-code">{[PERIOD[a.basis],a.fee_year].filter(Boolean).join(' · ')}</span></td><td className="fr-example">{a.text}</td></tr>)}
      </tbody></table></div></section>}
  </>
}

function Preview({providerId,phrase,urlPattern,onError}){
  const[p,setP]=useState(null),[busy,setBusy]=useState(false),t=useRef(null)
  useEffect(()=>{clearTimeout(t.current);if(!providerId||String(phrase||'').trim().length<6){setP(null);return}
    t.current=setTimeout(async()=>{setBusy(true);try{const{data,error}=await supabase.rpc('admin_fee_rule_preview',{p_provider_id:providerId,p_phrase:phrase,p_url_pattern:urlPattern||null});if(error)throw error;setP(data)}catch(e){onError?.(errText(e))}finally{setBusy(false)}},350)
    return()=>clearTimeout(t.current)},[providerId,phrase,urlPattern])
  if(!providerId||String(phrase||'').trim().length<6)return <p className="l3v-note">Choose the university and type at least 6 characters of the words that come just before the fee.</p>
  if(!p)return <Loading label="Checking the saved pages…"/>
  return <div className="fr-preview" data-preview>
    <p><strong>{fmtNumber(p.would_admit||0)} course{Number(p.would_admit)===1?'':'s'} would get a fee.</strong>{p.ambiguous?` ${fmtNumber(p.ambiguous)} skipped: the words appear with more than one amount.`:''}{p.already_had_fee?` ${fmtNumber(p.already_had_fee)} already have a fee and are left as they are.`:''}{p.amount_range?.min!=null?` Amounts from ${fmtMoney(p.amount_range.min,'AUD')} to ${fmtMoney(p.amount_range.max,'AUD')}.`:''}{busy?' Updating…':''}</p>
    {(p.samples||[]).length>0&&<div className="cf-table-wrap fr-sample-wrap"><table className="cf-table fr-samples"><thead><tr><th>Course</th><th className="num">Fee</th><th>Year</th><th>Words on the page</th></tr></thead><tbody>{p.samples.map(s=><tr key={s.course_id}><td className="fr-trunc" title={s.course}>{s.course}<span className="l3v-code">{s.code}</span></td><td className="num">{fmtMoney(s.amount,'AUD')}{s.has_fee?<span className="l3v-code">has a fee</span>:null}{s.amounts>1?<span className="l3v-code">more than one amount</span>:null}</td><td>{s.fee_year||'—'}</td><td className="fr-quote" title={s.text}><Quote text={s.text} phrase={phrase}/></td></tr>)}</tbody></table></div>}
  </div>
}

function RuleBuilder({init,busy,onCancel,onSave,onError}){
  const[v,setV]=useState(init),[q,setQ]=useState(''),[hits,setHits]=useState([]),t=useRef(null)
  useEffect(()=>{clearTimeout(t.current);if(v.provider_id||q.trim().length<2){setHits([]);return}t.current=setTimeout(async()=>{try{const{data,error}=await supabase.rpc('admin_priority_search',{p_kind:'provider',p_q:q.trim()});if(error)throw error;setHits(data||[])}catch(e){onError?.(errText(e))}},300);return()=>clearTimeout(t.current)},[q,v.provider_id])
  const set=(k,x)=>setV(s=>({...s,[k]:x}))
  return <section className="m-panel fr-builder" data-builder>
    <SectionTitle title="New fee wording rule" subtitle="Type the words exactly as they appear on the page just before the international fee. A year and ': A$' between the words and the amount are allowed."/>
    <div className="re-form">
      <div className="re-field"><small>University</small>{v.provider_id?<div className="re-picked"><strong>{v.provider}</strong><Button compact onClick={()=>setV(s=>({...s,provider_id:'',provider:''}))}>Change</Button></div>
        :<div><input className="fv-input" type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Type the university name" aria-label="Find the university"/>
          {hits.length>0&&<ul className="pq-hits">{hits.map(h=><li key={h.id}><div><strong>{h.label}</strong><span className="l3v-code">{h.detail}</span></div><Button compact variant="primary" onClick={()=>setV(s=>({...s,provider_id:h.id,provider:h.label}))}><Plus size={13}/>Choose</Button></li>)}</ul>}</div>}</div>
      <label><small>Words just before the fee</small><input className="fv-input" value={v.phrase} onChange={e=>set('phrase',e.target.value)} placeholder="e.g. Indicative First Year Fee"/></label>
      <div className="re-line"><label><small>The fee is</small><select className="fv-input" value={v.basis} onChange={e=>set('basis',e.target.value)} aria-label="Fee period">{Object.entries(PERIOD).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
        <label className="fr-grow"><small>Only pages whose address contains (optional)</small><input className="fv-input" value={v.url_pattern||''} onChange={e=>set('url_pattern',e.target.value)} placeholder="e.g. /study/undergraduate/"/></label></div>
      <label><small>Note (optional)</small><input className="fv-input" value={v.note||''} onChange={e=>set('note',e.target.value)} placeholder="e.g. International fee block; the domestic block says First Year Full Fee"/></label>
    </div>
    <Preview providerId={v.provider_id} phrase={v.phrase} urlPattern={v.url_pattern} onError={onError}/>
    <div className="re-foot"><Button compact variant="primary" onClick={()=>onSave({provider_id:v.provider_id,phrase:v.phrase,basis:v.basis,url_pattern:v.url_pattern||'',note:v.note||'',label:`${v.provider}: ${v.phrase}`})} disabled={busy||!v.provider_id||v.phrase.trim().length<6}><Check size={13}/>Save as draft</Button><Button compact onClick={onCancel} disabled={busy}>Cancel</Button></div>
  </section>
}

// The words on the page, centred on the rule's wording with the wording highlighted (full text on hover).
function Quote({text,phrase}){
  const t=String(text||''),w=String(phrase||'').trim(),i=w?t.toLowerCase().indexOf(w.toLowerCase()):-1
  if(i<0)return <span className="fr-trunc-inline">{t.length>140?t.slice(0,140)+'…':t}</span>
  const a=Math.max(0,i-40),b=Math.min(t.length,i+w.length+70)
  return <span>{a>0?'…':''}{t.slice(a,i)}<mark>{t.slice(i,i+w.length)}</mark>{t.slice(i+w.length,b)}{b<t.length?'…':''}</span>
}
