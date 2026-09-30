// Scholarship course links (v2.15.115): decide, once per scholarship, which of its proposed courses it applies to.
// 37,200 proposed links came from 87 scholarships whose pages name no course, so each was proposed for every course of
// its provider. A Pipeline Operator or above chooses: all courses, only matching courses (study level, field of study,
// words in the title), or no courses. Matching links are accepted, the rest rejected; the decision is saved, can be
// changed, and is applied to links proposed later. A suggestion from the scholarship's name is shown, never applied.
// Read: public.admin_scholarship_links_read(view, q), public.admin_scholarship_links_detail(id, decision, filter);
// write: public.admin_scholarship_links_decide(id, decision, filter, reason)
// (migrations 20260930130000 to 20260930133000, cf247_scholarship_course_links).
import React,{useEffect,useRef,useState}from'react'
import{Check,ExternalLink,Link2,RefreshCw,Search,Sparkles}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'

export const DECISION={all:'All proposed courses',filter:'Only matching courses',none:'No courses'}
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')

export default function ScholarshipLinks({onError}){
  const[view,setView]=useState('waiting'),[q,setQ]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(false),[pick,setPick]=useState(null)
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_scholarship_links_read',{p_view:view,p_q:q.trim()||null});if(error)throw error;setData(d||{})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{const t=setTimeout(load,q?300:0);return()=>clearTimeout(t)},[view,q])
  if(!data)return <section className="m-panel"><Loading label="Loading scholarship course links…"/></section>
  const s=data.summary||{},items=data.items||[]
  return <>
    <div className="cf-metric-grid">
      <Metric label="Links waiting" value={fmtNumber(s.waiting_links||0)} detail={`from ${fmtNumber(s.waiting_scholarships||0)} scholarships`} icon={Link2} tone={s.waiting_links?'warning':'success'}/>
      <Metric label="Scholarships decided" value={fmtNumber(s.decided_scholarships||0)} icon={Check}/>
      <Metric label="Links accepted / rejected" value={`${fmtNumber(s.accepted_links||0)} / ${fmtNumber(s.rejected_links||0)}`} icon={Link2}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={Link2} title="Scholarship course links" subtitle="These scholarships don't say which courses they are for, so they were proposed for every course at their university. Decide once per scholarship: all courses, only matching ones, or none." action={<div className="l3c-actions">
        <span className="pq-search sl-search"><Search size={14}/><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a scholarship or university" aria-label="Find a scholarship"/></span>
        <select className="fv-filter" value={view} onChange={e=>{setView(e.target.value);setPick(null)}} aria-label="Show"><option value="waiting">Waiting for a decision</option><option value="decided">Decided</option><option value="all">All</option></select>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {!data.can_decide&&<p className="l3v-note">You can view these. A Pipeline Operator or above can decide.</p>}
      {items.length?<div className="cf-table-wrap"><table className="cf-table sl-list"><thead><tr><th>Scholarship</th><th>Award</th><th className="num">Waiting</th><th>Suggested</th><th>Decision</th></tr></thead><tbody>
        {items.map(x=><tr key={x.scholarship_id} className={pick===x.scholarship_id?'sl-picked':''} onClick={()=>setPick(x.scholarship_id)} data-scholarship={x.scholarship_id}>
          <td><button type="button" className="sl-name" onClick={e=>{e.stopPropagation();setPick(x.scholarship_id)}}>{x.name}</button><span className="l3v-code">{x.provider}</span></td>
          <td>{x.award||'—'}</td>
          <td className="num">{fmtNumber(x.waiting||0)}<span className="l3v-code">of {fmtNumber(x.proposed||0)}</span></td>
          <td>{x.suggestion&&<StatusChip value={x.suggestion.decision} tone="violet" label={DECISION[x.suggestion.decision]}/>}</td>
          <td>{x.decision?<><StatusChip value={x.decision.decision} tone="success" label={DECISION[x.decision.decision]}/><span className="l3v-code">{fmtNumber(x.decision.accepted)} linked · {fmtDateTime(x.decision.at)}</span></>:<span className="l3v-code">Not decided</span>}</td>
        </tr>)}
      </tbody></table></div>:<Empty text={view==='waiting'?'No scholarship links are waiting for a decision.':'Nothing to show.'}/>}
    </section>
    {pick&&<Decide key={pick} id={pick} canDecide={Boolean(data.can_decide)} onDone={load} onError={onError}/>}
  </>
}

function Decide({id,canDecide,onDone,onError}){
  const[d,setD]=useState(null),[dec,setDec]=useState(''),[levels,setLevels]=useState([]),[fields,setFields]=useState([]),[title,setTitle]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState('')
  const first=useRef(true),t=useRef(null)
  const filter=()=>({...(levels.length?{levels}:{}),...(fields.length?{fields}:{}),...(title.trim()?{title:title.trim()}:{})})
  const read=async(decision,f)=>{try{const{data,error}=await supabase.rpc('admin_scholarship_links_detail',{p_scholarship_id:id,p_decision:decision??null,p_filter:f??null});if(error)throw error;return data}catch(e){onError?.(errText(e));return null}}
  useEffect(()=>{(async()=>{const x=await read();if(!x)return;setD(x);const p=x.preview||{};setDec(p.decision||'all');setLevels(p.filter?.levels||[]);setFields(p.filter?.fields||[]);setTitle(p.filter?.title||'');setReason(x.decision?.reason||'')})()},[id])
  useEffect(()=>{if(!d)return;if(first.current){first.current=false;return}clearTimeout(t.current);t.current=setTimeout(async()=>{const x=await read(dec,dec==='filter'?filter():{});if(x)setD(x)},300);return()=>clearTimeout(t.current)},[dec,JSON.stringify(levels),JSON.stringify(fields),title])
  if(!d)return <section className="m-panel"><Loading label="Loading the scholarship…"/></section>
  const s=d.scholarship||{},p=d.preview||{},sg=d.suggestion
  const toggle=(list,set,v)=>set(list.includes(v)?list.filter(x=>x!==v):[...list,v])
  const valid=dec!=='filter'||levels.length||fields.length||title.trim()
  const save=async()=>{if(!window.confirm(dec==='none'?`Link ${s.name} to no courses? All ${fmtNumber(d.proposed)} proposed links are rejected.`:`Link ${s.name} to ${fmtNumber(p.matched)} course${p.matched===1?'':'s'} and reject ${fmtNumber(p.not_matched)}?`))return
    setBusy(true);setSaved('');try{const{data,error}=await supabase.rpc('admin_scholarship_links_decide',{p_scholarship_id:id,p_decision:dec,p_filter:dec==='filter'?filter():{},p_reason:reason.trim()||null});if(error)throw error;setD(data);setSaved(`Saved: ${fmtNumber(data?.result?.accepted||0)} linked, ${fmtNumber(data?.result?.rejected||0)} rejected${data?.result?.sweep_removed?`, ${fmtNumber(data.result.sweep_removed)} automatic links removed`:''}.`);onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const useSuggestion=()=>{if(!sg)return;setDec(sg.decision);setLevels(sg.filter?.levels||[]);setFields(sg.filter?.fields||[]);setTitle(sg.filter?.title||'')}
  return <section className="m-panel sl-decide" data-decide={id}>
    <SectionTitle title={s.name} subtitle={[s.provider,s.award,s.academic_year&&`Year ${s.academic_year}`].filter(Boolean).join(' · ')} action={s.source_url&&<a className="cf-link" href={s.source_url} target="_blank" rel="noreferrer">Open the scholarship page <ExternalLink size={12}/></a>}/>
    {d.decision&&<p className="sl-current">Current decision: <strong>{DECISION[d.decision.decision]}</strong> · {fmtNumber(d.decision.accepted)} linked · {[d.decision.by,fmtDateTime(d.decision.at),d.decision.reason].filter(Boolean).join(' · ')}</p>}
    {sg&&<div className="sl-suggest"><Sparkles size={14}/><span><strong>Suggested: {DECISION[sg.decision]}</strong> — {sg.why}</span>{canDecide&&<Button compact onClick={useSuggestion}>Use suggestion</Button>}</div>}
    <fieldset className="sl-choice" disabled={!canDecide||busy}><legend>Which courses is it for?</legend>
      {Object.entries(DECISION).map(([k,l])=><label key={k}><input type="radio" name={`dec-${id}`} value={k} checked={dec===k} onChange={()=>setDec(k)}/>{l}{k==='all'&&` (${fmtNumber(d.proposed)})`}</label>)}
    </fieldset>
    {dec==='filter'&&<div className="sl-filter">
      <div><small>Study level</small><div className="sl-checks">{(d.levels||[]).map(l=><label key={l.id}><input type="checkbox" checked={levels.includes(l.id)} onChange={()=>toggle(levels,setLevels,l.id)} disabled={!canDecide}/>{l.name} <span>{fmtNumber(l.count)}</span></label>)}</div></div>
      <div><small>Field of study</small><div className="sl-checks">{(d.fields||[]).map(f=><label key={f.id}><input type="checkbox" checked={fields.includes(f.id)} onChange={()=>toggle(fields,setFields,f.id)} disabled={!canDecide}/>{f.name} <span>{fmtNumber(f.count)}</span></label>)}</div></div>
      <label className="sl-title"><small>Words in the course title (separate options with commas)</small><input className="fv-input" value={title} onChange={e=>setTitle(e.target.value)} placeholder="e.g. Master of Data Science, Information Technology" disabled={!canDecide}/></label>
      <p className="l3v-note">A course must match every part you set: one of the ticked levels, one of the ticked fields, and one of the title words.</p>
    </div>}
    <div className="sl-preview"><strong>{dec==='none'?'No courses will be linked.':`${fmtNumber(p.matched||0)} course${Number(p.matched)===1?'':'s'} will be linked, ${fmtNumber(p.not_matched||0)} rejected.`}</strong>
      {dec!=='none'&&(p.sample_matched||[]).length>0&&<ul>{p.sample_matched.map(c=><li key={c.id}>{c.title}<span className="l3v-code">{c.code}</span></li>)}{p.matched>p.sample_matched.length&&<li className="l3v-code">and {fmtNumber(p.matched-p.sample_matched.length)} more</li>}</ul>}
    </div>
    {canDecide&&<div className="sl-save"><label className="re-reason"><small>Reason (optional, kept with the decision)</small><input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="e.g. Scholarship page says postgraduate coursework only"/></label>
      <Button variant="primary" onClick={save} disabled={busy||!valid}><Check size={14}/>{busy?'Saving…':'Save decision'}</Button></div>}
    {saved&&<p className="sb-done" role="status">{saved}</p>}
  </section>
}
