// CF-247 v2.15.298 (Platform Admin, 20 Oct 2026 07:02: "anything that needs attention or intervention should come to Layer 4, define its
// return path"; 07:40 choices: by university, all stopped onboarding cases, courses not on the site at the bottom, websites down after 30
// days). Layer 4 › Inbox: everything that needs a person, grouped by university, from public.admin_layer4_inbox. Each item says why it is
// here and what each choice does next; choices that open another screen link to it. Design: admin repo docs/platform/LAYER4-INBOX-DESIGN.md.
// v2.15.300 (Platform Admin, 20 Oct 2026, "Old Layer 4 tabs now", "Counsellor reports tab"): the Review queue, AI could not decide, Websites to
// find and Coverage › Counsellor reports retired; their addresses open this Inbox on their kind (?kind=), a university opens with ?provider=,
// counsellor reports are closed here (Fixed, Not changed), and Decided lists the decisions taken here (who, when, choice, reason).
// CF-247 A1-A3 (Platform Admin, 30 Oct 2026 06:53): an AER item (kind aer_review) shows its source, stored copy, completeness and rows with their
// quotes (public.layer4_aer_review_read). The Platform Admin approves it, rejects it, or approves it except the ticked rows, with one reason;
// one item at a time, never in bulk. Curators read it here and keep correcting active rows in Catalogue › Entry requirements.
import React,{useEffect,useMemo,useRef,useState}from'react'
import{AlertTriangle,ArrowRight,ExternalLink,Inbox,RefreshCw,Search}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor,roleName}from'./nav-map'
import{Button,Empty,Loading,Metric,StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import'./layer4-inbox.css'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
// SS-016 role simulation (1 Nov 2026): the rank a choice needs, as public.admin_layer4_inbox decides it: its own rank, else rank 4
// (coalesce((v_c->>'rank')::int, 4)); a choice that opens another screen decides nothing here. A Curator was offered choices the server refuses.
const needs=c=>c.link?0:Number(c.rank||4)
const days=t=>t?Math.max(0,Math.floor((Date.now()-new Date(t).getTime())/86400000)):0
const linkFor=(link,it)=>link==='builder'?hrefFor('layer2','builder',{provider:it.provider_id}):link==='course'?hrefFor('courses','',{id:it.detail?.course_id||(it.detail?.entity==='course'?it.detail?.key:'')}):'#'
const aerRead=id=>supabase.rpc('layer4_aer_review_read',{p_review_item_id:id}).then(({data,error})=>{if(error)throw new Error(error.message);return data||{}})
// UR-04 (1 Nov 2026): items are read page by page from a stable position (kind order, created, kind, ref), not by offset, so a decision or a
// new arrival never hides or repeats an item; the position is kept for this browser tab so returning from a destination screen resumes it
const POS='l4i-pos'
const readPos=()=>{try{return JSON.parse(sessionStorage.getItem(POS)||'null')}catch{return null}}
const keyOf=it=>it?{after_o:it.o,after_at:it.created_at,after_kind:it.kind,after_ref:it.ref}:null
const urlOf=v=>typeof v==='string'?v:Array.isArray(v)?urlOf(v[0]):v&&typeof v==='object'?(v.url||v.course_url||''):''

export default function Layer4Inbox({onError,routeParams}){
  const want=routeParams?.get?.('kind')||'',wantProvider=routeParams?.get?.('provider')||'',wantView=routeParams?.get?.('view')||'' // v2.15.343: the Dashboard opens the Inbox by kind (?view=kind)
  const[sum,setSum]=useState(null),[view,setView]=useState(want?'kind':wantView==='kind'?'kind':'university'),[kind,setKind]=useState(want),[q,setQ]=useState('')
  const[unis,setUnis]=useState(null),[offset,setOffset]=useState(0),[pick,setPick]=useState(null),[items,setItems]=useState(null),[note,setNote]=useState('')
  const[cur,setCur]=useState(null),[stack,setStack]=useState([]),restored=useRef(readPos()),hold=useRef(true)
  const posKey=`${view}|${kind}|${pick?.provider_id||''}`
  const kinds=sum?.kinds||{},order=useMemo(()=>Object.entries(kinds).sort((a,b)=>a[1].order-b[1].order).map(([k])=>k),[sum])
  const loadSum=()=>rpc('summary').then(setSum).catch(e=>onError?.(e.message))
  const loadUnis=(o=offset)=>{setUnis(null);rpc('universities',{kind,q,limit:50,offset:o}).then(d=>{setUnis(d);if(view==='university'&&!pick&&d.items?.[0])setPick(wantProvider?(d.items.find(u=>u.provider_id===wantProvider)||{provider_id:wantProvider,name:'University'}):d.items[0])}).catch(e=>onError?.(e.message))}
  const loadItems=(c=cur)=>{if(view==='decided'){setItems(null);rpc('decided',{limit:100}).then(setItems).catch(e=>onError?.(e.message));return}if(view==='kind'&&!kind){setItems(null);return}if(view==='university'&&!pick){setItems(null);return}setItems(null)
    rpc('items',{...(view==='kind'?{kind}:{provider_id:pick.provider_id,...(kind?{kind}:{})}),limit:200,...(c||{})}).then(setItems).catch(e=>onError?.(e.message))}
  useEffect(()=>{loadSum()},[])
  // UR-09 (1 Nov 2026): an address that names another kind or university on this screen opens it, without a reload
  const asked=useRef({want,wantProvider})
  useEffect(()=>{const was=asked.current;asked.current={want,wantProvider};if(was.want===want&&was.wantProvider===wantProvider)return
    // SS-016 acceptance (1 Nov 2026 21:20): Back to an address of the same kind left the university list on screen; the view follows the address too
    if(want&&(want!==kind||view!=='kind')){setView('kind');setKind(want);setNote('')}
    else if(wantProvider&&(wantProvider!==pick?.provider_id||view!=='university')){setView('university');setPick({provider_id:wantProvider,name:'University'});setNote('')}},[want,wantProvider])
  useEffect(()=>{setOffset(0);setPick(null);loadUnis(0)},[kind,q])
  useEffect(()=>{let c=null,s=[];const r=restored.current
    if(r&&r.key===posKey){c=r.cur||null;s=r.stack||[]}else if(r&&!(view==='university'&&!pick))restored.current=null  // kept while the same list is shown
    hold.current=true
    setCur(c);setStack(s);loadItems(c)},[pick?.provider_id,view,kind])
  // the position is saved only from the render after it was set, never from the render that is still restoring it
  useEffect(()=>{if(hold.current){hold.current=false;return}if(view==='university'&&!pick)return;try{sessionStorage.setItem(POS,JSON.stringify({key:posKey,cur,stack}))}catch{}},[posKey,cur,stack])
  const page=c=>{setCur(c);loadItems(c)}
  const next=()=>{restored.current=null;const l=items?.items||[];if(!l.length)return;setStack([...stack,cur]);page(keyOf(l[l.length-1]))}
  const prev=()=>{restored.current=null;const s=[...stack];const c=s.length?s.pop():null;setStack(s);page(c)}
  const decided=r=>{setNote(outcomeText(r));loadSum();loadItems(cur);if(view==='university')rpc('universities',{kind,q,limit:50,offset}).then(setUnis).catch(()=>{})}
  if(!sum)return <Loading label="Reading what needs a person…"/>
  const bk=sum.by_kind||{}
  return <div className="l4i" data-l4-inbox>
    <section className="l4i-tiles">
      <Metric label="Waiting for a person" value={fmtNumber(sum.total)} detail={`${fmtNumber(sum.universities)} universities`} icon={Inbox}/>
      <Metric label={`Older than ${sum.target_days} days`} value={fmtNumber(sum.late)} tone={Number(sum.late)?'warning':'success'} detail="Oldest first within each university" icon={AlertTriangle}/>
    </section>
    <div className="l4i-kinds" role="toolbar" aria-label="Kinds of decision">
      <button type="button" className={!kind?'on':''} onClick={()=>setKind('')}>All ({fmtNumber(sum.total)})</button>
      {order.filter(k=>bk[k]?.n).map(k=><button key={k} type="button" className={kind===k?'on':''} data-l4-kind={k} onClick={()=>setKind(k)}>{kinds[k].label} ({fmtNumber(bk[k].n)})</button>)}
    </div>
    <div className="l4i-bar">
      <div className="l4i-view">{[['university','By university'],['kind','By kind'],['decided','Decided']].map(([v,l])=><button key={v} type="button" className={view===v?'on':''} onClick={()=>{setView(v);setNote('')}}>{l}</button>)}</div>
      {view==='university'&&<label className="l4i-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a university…" aria-label="Find a university"/></label>}
      <Button compact onClick={()=>{loadSum();loadUnis(offset);loadItems(cur)}}><RefreshCw size={14}/>Refresh</Button>
    </div>
    {note&&<p className="l4i-note" role="status">{note}</p>}
    {view==='decided'?<Decided items={items} kinds={kinds}/>:view==='kind'&&!kind?<Empty text="Choose a kind above to see its items across every university."/>:
    <div className={view==='university'?'l4i-split':''}>
      {view==='university'&&<aside className="l4i-unis" aria-label="Universities">
        {!unis?<Loading compact/>:(unis.items||[]).length===0?<Empty text="Nothing waits for a person."/>:<>
          <ul>{unis.items.map(u=><li key={u.provider_id||'platform'}><button type="button" className={pick?.provider_id===u.provider_id?'on':''} onClick={()=>{setPick(u);setNote('')}} data-l4-uni={u.name}>
            <strong>{u.name}</strong><small>{u.country||''}{u.courses!=null?` · ${fmtNumber(u.courses)} courses`:''}</small>
            <span className="l4i-uni-kinds">{Object.entries(u.by_kind||{}).sort((a,b)=>(kinds[a[0]]?.order||99)-(kinds[b[0]]?.order||99)).map(([k,n])=><em key={k}>{kinds[k]?.label||k}{n>1?` ${n}`:''}</em>)}</span>
            {u.late&&<span className="l4i-late">{days(u.oldest)} d</span>}</button></li>)}</ul>
          {Number(unis.total)>50&&<div className="l4i-pager"><Button compact disabled={offset===0} onClick={()=>{const o=Math.max(0,offset-50);setOffset(o);loadUnis(o)}}>Previous</Button><small>{offset+1}–{Math.min(offset+50,unis.total)} of {fmtNumber(unis.total)}</small><Button compact disabled={offset+50>=unis.total} onClick={()=>{const o=offset+50;setOffset(o);loadUnis(o)}}>Next</Button></div>}
        </>}
      </aside>}
      <section className="l4i-items" aria-label="Items">
        {view==='university'&&pick&&<header className="l4i-items-head"><h3>{pick.name}</h3><small>{pick.country||''}{pick.courses!=null?` · ${fmtNumber(pick.courses)} active courses`:''}</small></header>}
        {!items?<Loading compact/>:(items.items||[]).length===0?<Empty text="Nothing left here."/>:
          items.items.map(it=><Item key={`${it.kind}:${it.ref}`} it={it} k={kinds[it.kind]||{label:it.kind,choices:[]}} showProvider={view==='kind'} rank={sum.rank} onDone={decided} onError={onError}/>)}
        {items&&view!=='decided'&&(cur||Number(items.total)>(items.items||[]).length)&&(()=>{const b=Number(items.before||0),n=(items.items||[]).length,t=Number(items.total||0)
          return <div className="l4i-pager" data-l4-pager><Button compact disabled={!cur} onClick={prev} data-l4-prev>Previous</Button>
            <small data-l4-range>{n?`${fmtNumber(b+1)}–${fmtNumber(b+n)}`:'0'} of {fmtNumber(t)}, oldest first</small>
            <Button compact disabled={b+n>=t} onClick={next} data-l4-next>Next</Button></div>})()}
      </section>
    </div>}
  </div>
}

function Item({it,k,showProvider,rank,onDone,onError}){
  const[open,setOpen]=useState(null),[reason,setReason]=useState(''),[value,setValue]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const d=it.detail||{}
  // hotfix D1 (24 Oct 2026): a course-link row that holds a fee (identity re-verification quarantine, fee floor) has no new page to use;
  // "Enter another address" binds a person's page (https:// on the provider's own site), which is read again and re-admits the fee
  const fee=isFeeItem(it)
  // SS-016 (1 Nov 2026): a fee check (provider_current_tuition_validation) shows the proposed fee and is admitted or not; an address is refused
  const feeCheck=isFeeCheck(it)
  const aerItem=it.kind==='aer_review',[aer,setAer]=useState(null)
  useEffect(()=>{if(aerItem)aerRead(it.ref).then(setAer).catch(e=>setAer({error:e.message}))},[it.ref])
  const aerWaiting=(aer?.rows||[]).filter(r=>r.status==='proposed')
  // E13 (Platform Admin 2 Nov 2026 05:18): a course entry read the completeness gate holds cannot be approved; when the only problem is rows
  // about another programme, Approve except is allowed once every one of them is ticked (the server checks the same)
  const gate=aer?.kind==='course_entry_first_read'?aer.completeness_gate:null,held=gate?.complete===false
  const otherIds=(gate?.other_programme||[]).map(o=>o.id),exceptOnly=held&&!(Number(gate.rows_cut)>0)&&!(gate.shared_page||[]).length
  const gated=c=>held&&(c.key==='approve'||(c.key==='approve_except'&&!exceptOnly))
  const choices=(k.choices||[]).filter(c=>!(fee&&c.key==='use')).filter(c=>!(feeCheck&&c.key==='enter')).map(c=>feeCheck&&FEE_CHECK[c.key]?{...c,...FEE_CHECK[c.key]}:c)
  const choose=c=>{setErr('');if(c.link){window.location.hash=linkFor(c.link,it).replace(/^#/,'');return}setOpen(c);setReason(c.reason||'');setValue(c.input==='url'&&it.kind==='course_link'&&!fee?urlOf(d.proposed):c.input==='url'&&it.kind==='conjoint_first_run'?(d.proposed?.parent_url||''):(c.input==='courses'||c.input==='rows')?'[]':'')}
  // hotfix 26 Oct 2026: a university's first run (no page published / conjoint rule) shows its sample; "has a page" ticks courses from it
  const firstRun=it.kind==='no_page_first_run'||it.kind==='conjoint_first_run'
  const sample=Array.isArray(d.proposed?.sample)?d.proposed.sample:[]
  const ticked=(()=>{try{return JSON.parse(value||'[]')}catch{return[]}})()
  const tick=id=>setValue(JSON.stringify(ticked.includes(id)?ticked.filter(x=>x!==id):[...ticked,id]))
  const go=async()=>{setBusy(true);setErr('');try{const r=await rpc('decide',{kind:it.kind,ref:it.ref,choice:open.key,reason,value});setOpen(null);onDone?.(r)}catch(e){setErr(e.message)}finally{setBusy(false)}}
  return <article className={`l4i-item${it.late?' late':''}`} data-l4-item={it.kind} data-l4-ref={it.ref}>
    <header><StatusChip value={it.kind} tone={it.late?'warning':'info'} label={k.label}/>{showProvider&&it.provider&&<strong className="l4i-prov">{it.provider}</strong>}{it.subject&&<span className="l4i-subj">{it.subject}</span>}{d.course_code&&<span className="l4i-code" title="CRICOS code" data-l4-code>CRICOS {d.course_code}</span>}<small>{fmtDate(it.created_at)} · {days(it.created_at)} d · <span data-l4-refshow title={it.ref}>Ref {String(it.ref).slice(0,8)}</span></small></header>
    <p className="l4i-why">{it.why}</p>
    {(d.evidence_id||d.course_id)&&!aerItem&&<p className="l4i-evid" data-l4-evidence><small>
      {d.evidence_id?<><a href={hrefFor('evidence','',{evidence_id:d.evidence_id})} data-l4-evidence-link>Stored copy</a>{d.captured_at?` captured ${fmtDate(d.captured_at)}`:''}{d.newer_copy?<em className="l4i-match warn" data-l4-newer> a newer copy of this page exists</em>:''}{d.source_url?<> · <a href={d.source_url} target="_blank" rel="noreferrer">source <ExternalLink size={11}/></a></>:null}</>:'No stored copy is linked to this item'}
      {d.course_id&&<> · <a href={hrefFor('courses','',{id:d.course_id})} data-l4-open-record>Open the course record</a></>}</small></p>}
    {(fee||feeCheck)&&<dl className="l4i-dl" data-l4-fee><dt>{fee?'Fee held back':'Proposed fee'}</dt><dd data-l4-fee-proposed>{feeText(d.proposed)}</dd>{feeText(d.before)!=='—'&&<><dt>Fee we hold</dt><dd data-l4-fee-held>{feeText(d.before)}</dd></>}</dl>}
    {it.kind==='course_link'&&!fee&&!feeCheck&&(urlOf(d.before)||urlOf(d.proposed))&&<dl className="l4i-dl"><dt>Page we hold</dt><dd data-l4-held><PageLink u={urlOf(d.before)} title={it.subject}/></dd><dt>New page</dt><dd data-l4-new><PageLink u={urlOf(d.proposed)} title={it.subject}/></dd></dl>}
    {fee&&<p className="l4i-why" data-l4-fee-item><small>A held fee: enter the course's own page (https://, on the university's website) and it is read again, or keep the page we hold.</small></p>}
    {it.kind==='counsellor_report'&&<dl className="l4i-dl" data-l4-report>{d.issue&&<><dt>Issue</dt><dd>{String(d.issue).replace(/_/g,' ')}</dd></>}{d.field&&<><dt>Field</dt><dd>{d.field}</dd></>}{d.suggested_value&&<><dt>Suggested</dt><dd>{d.suggested_value}</dd></>}{d.source_url&&<><dt>Source</dt><dd><a href={d.source_url} target="_blank" rel="noreferrer">{d.source_url} <ExternalLink size={11}/></a></dd></>}{d.reporter&&<><dt>Reported by</dt><dd>{[d.reporter.name,d.reporter.email].filter(Boolean).join(' · ')}</dd></>}</dl>}
    {firstRun&&<div className="l4i-dl" data-l4-first-run>
      <p><small>{it.kind==='no_page_first_run'?`${d.before?.courses_proposed??sample.length} course(s) found no page after the AI page match. Check the sample against the university's website.`:`${d.before?.conjoint_courses_without_page??sample.length} conjoint or double degree(s) without a page of their own.`}</small></p>
      {it.kind==='conjoint_first_run'&&d.proposed?.parent_url&&<p><small>Conjoint page found: <PageLink u={d.proposed.parent_url}/></small></p>}
      {sample.length>0&&<ul className="l4i-sample" data-l4-sample>{sample.map(x=><li key={x.course_id}>{open?.input==='courses'?<label><input type="checkbox" checked={ticked.includes(x.course_id)} onChange={()=>tick(x.course_id)} data-l4-sample-tick={x.course_code||x.code||x.course_id}/> {x.title}{x.code?` (${x.code})`:''} has its own page</label>:<>{x.title}{x.code?` (${x.code})`:''}</>}</li>)}</ul>}
    </div>}
    {aerItem&&<AerRows aer={aer} rank={rank} ticking={open?.input==='rows'} ticked={ticked} tick={tick}/>}
    {it.kind==='provider_departure'&&d.note&&<p className="l4i-why" data-l4-departure><small>{d.note}</small></p>}
    {it.kind==='held_scholarship'&&<dl className="l4i-dl">{d.url&&<><dt>Page</dt><dd><a href={d.url} target="_blank" rel="noreferrer">{d.url} <ExternalLink size={11}/></a></dd></>}{it.suggestion&&<><dt>AI re-check</dt><dd>{it.suggestion}</dd></>}{d.audience_quote&&<><dt>Who</dt><dd><q>{d.audience_quote}</q></dd></>}{d.value_quote&&<><dt>Value</dt><dd><q>{d.value_quote}</q></dd></>}</dl>}
    <div className="l4i-choices">{choices.map(c=>{const low=rank<needs(c),stop=gated(c);return <button key={c.key} type="button" className={`${open?.key===c.key?'on':''}${c.link?' link':''}`} disabled={low||stop} title={low?`Needs ${roleName(needs(c))} (rank ${needs(c)}) or above`:stop?'Held: this read is incomplete (see above)':c.returns} onClick={()=>choose(c)} data-l4-choice={c.key}>{c.label}{c.link&&<ArrowRight size={12}/>}</button>})}</div>
    {(()=>{const by={};for(const c of choices)if(rank<needs(c))(by[needs(c)]||=[]).push(c.label)
      return Object.keys(by).length?<p className="l4i-why" data-l4-handoff><small>{Object.entries(by).map(([n,l])=>`${l.join(', ')}: ${roleName(n)} (rank ${n}) or above decides; ask a ${roleName(n)}.`).join(' ')}</small></p>:null})()}
    {open&&<div className="l4i-confirm">
      <p className="l4i-next"><strong>What happens next:</strong> {open.returns}</p>
      {open.input==='url'&&<input value={value} onChange={e=>setValue(e.target.value)} placeholder="https://…" aria-label="Web address"/>}
      {open.input==='provider'&&<input value={value} onChange={e=>setValue(e.target.value)} placeholder="Successor: its exact name, or its CRICOS or NZQA code" aria-label="Successor provider"/>}
      {open.input==='rows'&&exceptOnly&&<p className="l4i-next" data-l4-aer-other-needed>{otherIds.every(id=>ticked.includes(id))?'Every row about another programme is ticked.':`Tick the ${otherIds.length===1?'row':`${otherIds.length} rows`} about another programme to leave ${otherIds.length===1?'it':'them'} out.`}</p>}
      {open.input==='rows'&&<p className="l4i-next" data-l4-aer-except-count>{ticked.length===0?'Tick the rows to leave out.':ticked.length>=aerWaiting.length?'Every row is ticked: use Reject the read instead.':`Leaving out ${ticked.length} of ${aerWaiting.length} rows; the other ${aerWaiting.length-ticked.length} become active once the checks pass.`}</p>}
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (kept with the decision)" aria-label="Reason"/>
      <Button compact variant="primary" disabled={busy||reason.trim().length<(aerItem?5:4)||(open.input==='rows'&&(ticked.length===0||ticked.length>=aerWaiting.length||(exceptOnly&&!otherIds.every(id=>ticked.includes(id)))))||(open.input==='url'&&!urlOk(value,fee))||(open.input==='provider'&&value.trim().length<3)||(open.input==='courses'&&ticked.length===0)} onClick={go} data-l4-confirm>{busy?'Saving…':open.label}</Button>
      <Button compact onClick={()=>setOpen(null)}>Cancel</Button>
      {err&&<p className="l4i-err" role="alert">{err}</p>}
    </div>}
  </article>
}

// CF-247 A1: the rows of an AER item, each with its quote; ticked rows are left out by "Approve except…" (Platform Admin, A3)
const ROW_STATUS={proposed:'Waiting',active:'Active',inactive:'Withdrawn',superseded:'Superseded',unverified:'Quarantined'}
export const isExcluded=r=>r?.status==='inactive'&&/^excluded by /.test(r?.status_reason||'')
function AerRows({aer,rank,ticking,ticked,tick}){
  if(!aer)return <Loading compact/>
  if(aer.error)return <p className="l4i-err" role="alert">{aer.error}</p>
  const L=aer.lineage||{},c=L.completeness||{},rows=aer.rows||[],course=aer.kind==='course_entry_first_read'
  const gate=course&&aer.status==='pending'?aer.completeness_gate:null,other=Object.fromEntries((gate?.other_programme||[]).map(o=>[o.id,o.names]))
  return <div className="l4i-aer" data-l4-aer>
    <dl className="l4i-dl" data-l4-aer-lineage>
      <dt>Source</dt><dd>{L.source_url?<a href={L.source_url} target="_blank" rel="noreferrer">{L.source_url} <ExternalLink size={11}/></a>:'—'}</dd>
      <dt>Stored copy</dt><dd>{aer.evidence_id?<a href={hrefFor('evidence','',{evidence_id:aer.evidence_id})} data-l4-aer-evidence>Open the stored copy</a>:'—'}{(L.content_hash||(L.row_content_hashes||[])[0])&&<small> · {String(L.content_hash||L.row_content_hashes[0]).slice(0,12)}</small>}</dd>
      {!course&&<><dt>Read</dt><dd data-l4-aer-read>{L.run_id?String(L.run_id).slice(0,8):'—'}{c.status?` · completeness ${c.status}${c.matched!=null?` (${c.matched} matched)`:''}`:''}{L.rows_dropped!=null?` · ${L.rows_dropped} not kept`:''}</dd></>}
    </dl>
    {gate&&(gate.complete===false?<div className="l4i-why" role="note" data-l4-aer-gate="held"><strong>Held: this read is incomplete, so it cannot be approved (E13)</strong>
      <ul>{(gate.reasons||[]).map((w,n)=><li key={n}>{w.charAt(0).toUpperCase()+w.slice(1)}.</li>)}</ul></div>
      :<p className="l4i-why" data-l4-aer-gate="complete"><small>Read whole: no requirement was cut and no row is about another programme.</small></p>)}
    {rank<6&&<p className="l4i-why" data-l4-aer-pa-only><small>AER items are admitted or rejected by the Platform Admin (decision A3). Curators correct active rows in Catalogue › Entry requirements.</small></p>}
    <ul className="l4i-sample l4i-aer-rows" data-l4-aer-rows>{rows.map(r=>{const label=course?[r.kind&&String(r.kind).replace(/_/g,' '),r.description].filter(Boolean).join(': '):[r.country,r.level,r.qualification].filter(Boolean).join(' · ')
      const min=[r.min_grade,r.scale&&r.scale!=='none'?r.scale:null,r.score!=null?`${r.score} (${r.basis||'no basis'})`:null,r.band?`band ${r.band}`:null].filter(Boolean).join(' · ')
      const body=<><strong>{label||'—'}</strong>{min&&<small> · {min}</small>}<span className="l4i-aer-status" data-l4-aer-status={isExcluded(r)?'excluded':r.status}>{isExcluded(r)?'Excluded in Layer 4':ROW_STATUS[r.status]||r.status}</span>{other[r.id]&&<span className="l4i-aer-status" data-l4-aer-other={r.id}>About another programme: {other[r.id]}</span>}{r.quote&&<q>{r.quote}</q>}</>
      return <li key={r.id} data-l4-aer-row={r.id} title={r.status_reason||undefined}>{ticking&&r.status==='proposed'?<label><input type="checkbox" checked={ticked.includes(r.id)} onChange={()=>tick(r.id)} data-l4-aer-tick={r.id} aria-label={`Leave out ${label}`}/> {body}</label>:body}</li>})}</ul>
    {aer.decision&&<p className="l4i-why" data-l4-aer-decision><small>Decided: {aer.decision.action==='edit_and_approve'?'approved except':aer.decision.action} · {aer.decision.reason}{Array.isArray(aer.decision.exclude_row_ids)?` · ${aer.decision.exclude_row_ids.length} row(s) left out`:''}</small></p>}
  </div>
}

// UR-06 (1 Nov 2026): the decision reply says what actually happened at the destination, with the audit event, not only the choice's text
const OUTCOME={admitted:'Admitted',applied:'Applied',reconciled:'Closed without admitting a value',downstream:'Queued: the result follows later',deferred:'Deferred: asked again later',pending_check:'Saved, but the destination does not show it yet: check before going on'}
export const outcomeText=r=>{const o=r?.outcome||{},rows=o.rows||{}
  if(!o.class)return`Done. ${r?.returns||''}`
  const parts=[`Done. ${OUTCOME[o.class]||o.class}`]
  const rc=['active','excluded','superseded','proposed','inactive'].filter(k=>rows[k]).map(k=>`${rows[k]} ${k==='proposed'?'waiting':k}`)
  if(rc.length)parts.push(`rows ${rc.join(', ')}`)
  if(o.fee)parts.push(`fee ${feeText(o.fee)}`)
  if(o.value)parts.push(o.verified?`now the course's link: ${o.value}`:`not yet the course's link: ${o.value}`)
  if(o.decision_id)parts.push(`decision ${String(o.decision_id).slice(0,8)}`)
  if(r?.event_id)parts.push(`audit #${r.event_id}`)
  return parts.join(' · ')}
export const isFeeCheck=it=>it?.kind==='course_link'&&it?.detail?.field_code==='provider_current_tuition_validation'
const FEE_CHECK={use:{label:'Admit this fee',returns:'The proposed fee becomes the course\'s international tuition fee (a person\'s decision, recorded with the stored copy)'},
  keep:{label:'Do not admit this fee',returns:'Closed; the proposed fee is not admitted and the course keeps what it holds'}}
const BASIS={annual:'a year',indicative_annual:'a year (indicative)',per_year_explicit:'a year'}
// the fee as the reader proposed it: amount, currency, basis, fee year and audience; a missing year is said, never guessed
export const feeText=v=>{if(!v||typeof v!=='object'||v.amount==null||v.amount==='')return'—'
  const cur=v.currency_code||v.currency||'',amt=Number(v.amount)
  return[`${cur} ${Number.isFinite(amt)?fmtNumber(amt,{decimals:Number.isInteger(amt)?0:2}):v.amount}`.trim(),BASIS[v.basis]||(v.basis?String(v.basis).replace(/_/g,' '):'basis not stated'),
    v.fee_year?`fee year ${v.fee_year}`:'no fee year printed',v.audience||null].filter(Boolean).join(' · ')}
export const isFeeItem=it=>it?.kind==='course_link'&&it?.detail?.field_code==='provider_current_tuition'
export const urlOk=(v,httpsOnly)=>(httpsOnly?/^https:\/\/[^\s/]+\.\S+/:/^https?:\/\/\S+\.\S+/).test(String(v||'').trim())

// v2.15.299 (Platform Admin, 20 Oct 2026 09:41: "the course name is align to course url, there should be no confusion"): each address says
// whether its last part is the course's own name, or the course name with more words (a major or specialisation)
const slug=t=>String(t||'').toLowerCase().replace(/&/g,' and ').replace(/\([^)]*\)/g,m=>' '+m.slice(1,-1)+' ').replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'')
function nameMatch(u,title){if(!u||!title)return null;const last=String(u).replace(/[?#].*$/,'').replace(/\/+$/,'').split('/').pop().toLowerCase(),t=slug(title);if(!t)return null;if(last===t)return'name';if(last.startsWith(t+'-'))return'major';return null}
function PageLink({u,title}){if(!u)return'none';const m=nameMatch(u,title);return <><a href={u} target="_blank" rel="noreferrer">{u} <ExternalLink size={11}/></a>{m==='name'&&<em className="l4i-match ok" data-l4-match="name">matches the course name</em>}{m==='major'&&<em className="l4i-match warn" data-l4-match="major">a major or specialisation of the course</em>}</>}

// v2.15.300: the decisions taken in the Inbox, newest first (public.admin_layer4_inbox('decided'))
function Decided({items,kinds}){
  if(!items)return <Loading compact/>
  const list=items.items||[]
  if(!list.length)return <Empty text="Nothing has been decided here yet."/>
  return <div className="cf-table-wrap"><table className="cf-table" data-l4-decided><thead><tr><th>When</th><th>Kind</th><th>University</th><th>Choice</th><th>Why</th><th>By</th></tr></thead><tbody>
    {list.map((x,i)=>{const k=kinds[x.kind]||{},c=(k.choices||[]).find(c=>c.key===x.choice);return <tr key={i}><td>{fmtDate(x.at)}</td><td>{k.label||x.kind}</td><td>{x.provider||'—'}</td><td>{c?.label||x.choice}{x.value?<small className="sl-sub"> {x.value}</small>:null}</td><td><small>{x.reason}</small></td><td><small>{x.by||'—'}</small></td></tr>})}
  </tbody></table></div>
}
