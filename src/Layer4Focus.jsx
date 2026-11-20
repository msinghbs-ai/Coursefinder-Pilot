// CF-247 s837 (Platform Admin 20 Nov 2026 14:40, S1-UI-Parity; mockup s820-s827): Layer 4 Review's default view. Left: "Waiting, grouped by rule",
// every waiting item of the chosen queue (kind) grouped by the rule that holds it, across the whole queue (public.admin_layer4_inbox rule_groups,
// security.layer4_rule_groups_v1, migration 20261120145000), largest first. Right: one focused review card at a time, read by key
// (rule_group_items); a decision moves to the next card of the group. Preview the batch shows the exact records of the chosen group (at most
// layer4.rule_batch_max) in one keyed read. Only a description group held for a banned word may then be admitted as one batch: each record with
// the words removed, one decide call per record with its own reason, after the confirmation. Every other group is worked card by card (AER has no
// bulk approval, S1-AER s831). The older views (By university, By kind, Grid, Decided) are behind the Other views toggle in src/Layer4Inbox.jsx.
import React,{useEffect,useMemo,useRef,useState}from'react'
import{ChevronLeft,ChevronRight,Eye,Layers,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber}from'./ui-kit'
import{descriptionRules}from'./DescriptionEditAdmit'
import{isCourseDescription}from'./CourseDescriptionPanel'
import{checkDescription,markBanned,stripBanned}from'./lib/description-check.js'
import{REREAD_SKIP,batchAdmits,batchRereads,firstSentence,groupLabel,isRecoveryGroup,refsOf,rereadAction}from'./lib/l4-rules.js'
import'./ops-pulse.css'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
const FOCUS_WINDOW=8 // fixed: cards read ahead of the focused one (screen comfort, not an operational limit)
const now=()=>typeof performance!=='undefined'?performance.now():Date.now()

/** The cleaned record of one banned-word description: what would be admitted, or why it is left for a person. */
export function cleanedOf(it,rules){const d=it?.detail||{},original=String(d.proposed?.description||''),r=rules?.[isCourseDescription(d)?'course':'provider']
  if(!r||!original.trim())return{ok:false,original,why:'No machine text to clean'}
  const s=stripBanned(original,r.words),c=s.changed?checkDescription(s.text,r):null
  return{ok:!!(s.changed&&c?.ok),original,text:s.text,removed:s.removed,words:r.words,why:!s.changed?'No word from the lists was found':c?.ok?'':`The cleaned text fails a check: ${c.problems.join('; ')||'a word from the lists remains'}`}}

export default function Layer4Focus({kinds,kind,rank,onError,onDecided,renderItem,onOtherView}){
  const[g,setG]=useState(null),[key,setKey]=useState(''),[idx,setIdx]=useState(0),[cards,setCards]=useState({}),[gone,setGone]=useState(()=>new Set())
  const[pv,setPv]=useState(null),[rules,setRules]=useState(null),[run,setRun]=useState(null)
  const label=kinds?.[kind]?.label||kind
  const load=(keep)=>{if(!keep)setG(null);rpc('rule_groups',{kind}).then(setG).catch(e=>{setG({error:e.message});onError?.(e.message)})}
  useEffect(()=>{setKey('');setIdx(0);setCards({});setGone(new Set());setPv(null);setRun(null);if(kind)load()},[kind])
  const groups=g?.groups||[]
  const left=x=>(x.refs||[]).filter(r=>gone.has(r)).length
  const refs=useMemo(()=>refsOf(groups,key).filter(r=>!gone.has(r)),[g,key,gone])
  const groupOf=useMemo(()=>{const m={};for(const x of groups)for(const r of x.refs||[])m[r]=x;return m},[g])
  const at=Math.min(idx,Math.max(0,refs.length-1)),cur=refs[at]
  useEffect(()=>{if(!cur||cards[cur]!==undefined)return;const want=refs.slice(at,at+FOCUS_WINDOW).filter(r=>cards[r]===undefined);if(!want.length)return
    rpc('rule_group_items',{kind,refs:want}).then(d=>{const m={};for(const it of d.items||[])m[it.ref]=it;for(const r of want)if(!m[r])m[r]=false;setCards(c=>({...c,...m}))}).catch(e=>onError?.(e.message))},[cur,kind])
  useEffect(()=>{if(cur&&cards[cur]===false)setGone(s=>new Set([...s,cur]))},[cur,cards]) // decided elsewhere since the groups were read
  const done=r=>{setGone(s=>new Set([...s,cur]));onDecided?.(r)}
  const total=Math.max(0,(Number(g?.total)||0)-gone.size),sel=groups.find(x=>x.key===key)
  // s839 (20 Nov 2026): the batch is read as soon as a rule is chosen, so Preview the batch opens at once from what is already read
  const pre=useRef(null)
  const batchRead=x=>{const want=(x.refs||[]).filter(r=>!gone.has(r)).slice(0,Number(g?.batch_max)||50),sig=`${x.key}|${want.join(',')}`
    if(pre.current?.sig!==sig)pre.current={sig,want,p:Promise.all([rpc('rule_group_items',{kind,refs:want}),batchAdmits(x)?descriptionRules():Promise.resolve(null)])}
    pre.current.p.catch(()=>{if(pre.current?.sig===sig)pre.current=null});return pre.current}
  const rerunBatch=async(action,list)=>{setRun({done:0,failed:[],total:list.length,busy:true})  // s870: one server call for the whole batch
    try{const r=await rpc(action,{refs:list.map(x=>x.ref),reason:action==='aer_det_reread'?'Stale partial read: re-read from the stored copy by the deterministic reader ($0), from Layer 4 Review (batch)':'No stored page: queue a stored-page fetch, from Layer 4 Review (batch)'})
      const n=Number(action==='aer_det_reread'?r.superseded:r.fetch_queued)||0
      if(action==='aer_det_reread')setGone(s=>new Set([...s,...list.map(x=>x.ref)]))
      setRun({done:n,failed:[],total:list.length,busy:false,result:r});onDecided?.({batch:true,admitted:n,failed:list.length-n,action});load(true)}
    catch(e){setRun({done:0,failed:[{ref:'',subject:'batch',error:e.message}],total:list.length,busy:false})}}
  useEffect(()=>{if(sel)batchRead(sel)},[key,g])
  const openPreview=async()=>{if(!sel)return;const t0=now();setPv({key:sel.key,items:null});setRun(null)
    try{const b=batchRead(sel),[d,ru]=await b.p
      setRules(ru);setPv({key:sel.key,items:d.items||[],ms:Math.round(now()-t0),server_ms:d.ms,asked:b.want.length})}
    catch(e){pre.current=null;setPv(null);onError?.(e.message)}}
  const admitBatch=async list=>{setRun({done:0,failed:[],total:list.length,busy:true})
    let ok=0;const failed=[]
    for(const x of list){try{await rpc('decide',{kind:x.it.kind,ref:x.it.ref,choice:'edit_approve',value:x.c.text,set_manual_lock:true,
        reason:`Batch (rule group "Contains a banned word"): removed ${x.c.removed.join(', ')}`});ok++;setGone(s=>new Set([...s,x.it.ref]))}
      catch(e){failed.push({ref:x.it.ref,subject:x.it.subject,error:e.message})}
      setRun({done:ok,failed:[...failed],total:list.length,busy:true})}
    setRun({done:ok,failed,total:list.length,busy:false});onDecided?.({batch:true,admitted:ok,failed:failed.length});load(true)}

  if(!kind)return <Empty text="Nothing waits for a person."/>
  if(!g)return <Loading label="Grouping every waiting item by rule…"/>
  if(g.error)return <p className="l4i-err" role="alert">{g.error}</p>
  if(g.built_in===false)return <div className="l4f-other" data-l4-focus-hook><Empty text={`${label} is listed in By kind, with its own reader.`}/><Button compact onClick={()=>onOtherView?.('kind')}>Open {label} in By kind</Button></div>
  const curItem=cur?cards[cur]:null,curGroup=cur?groupOf[cur]:null
  const Grp=x=>{const n=Number(x.n)-left(x);return <button key={x.key} type="button" className={`l4r-grp${key===x.key?' on':''}`} aria-pressed={key===x.key}
    onClick={()=>{setKey(x.key);setIdx(0);setPv(null)}} data-l4-focus-group={x.key}><span>{groupLabel(x)}{Number(x.late)>0&&<small className="l4f-late"> · {fmtNumber(x.late)} late</small>}</span><span className="l4r-n">{fmtNumber(n)}</span></button>}
  return <div className="l4f" data-l4-focus={kind}>
    <aside className="l4f-rail" aria-label="Waiting, grouped by rule" data-l4-focus-rail={groups.length}>
      <p className="l4r-head"><Layers size={15} aria-hidden="true"/> <strong>Waiting, grouped by rule</strong></p>
      <p className="l4r-sub">Every waiting {label.toLowerCase()} item, by the check that holds it. Choose a rule, preview its batch, then work through it card by card.</p>
      <button type="button" className={`l4r-grp${!key?' on':''}`} aria-pressed={!key} onClick={()=>{setKey('');setIdx(0);setPv(null)}} data-l4-focus-group="all"><span>All in this queue</span><span className="l4r-n">{fmtNumber(total)}</span></button>
      {[['reviewer','Waiting for a reviewer',groups.filter(x=>!isRecoveryGroup(x))],['recovery','System recovery / Re-read available',groups.filter(isRecoveryGroup)]].map(([sec,title,gs])=>{
        const shown=gs.filter(x=>Number(x.n)-left(x)>0)
        if(!shown.length||(sec==='reviewer'&&!groups.some(isRecoveryGroup)))return <React.Fragment key={sec}>{shown.map(x=>Grp(x))}</React.Fragment>
        return <div key={sec} className={`l4f-sec l4f-sec-${sec}`} data-l4-focus-section={sec}><p className="l4f-sec-head">{title} <span className="l4r-n">{fmtNumber(shown.reduce((a,x)=>a+Number(x.n)-left(x),0))}</span></p>{shown.map(x=>Grp(x))}</div>})}
      <div className="l4r-actions l4f-batch">
        <Button compact disabled={!sel} onClick={openPreview} title={sel?'':'Choose a rule first'} data-l4-batch-open><Eye size={13}/>Preview the batch</Button>
        {Number(g.ms)>=0&&<small className="l4r-sub" data-l4-focus-ms>Grouped {fmtNumber(Number(g.total)||0)} items in {fmtNumber(g.ms)} ms</small>}
      </div>
    </aside>
    <section className="l4f-main" aria-label="Focused review card">
      {pv&&<BatchPreview pv={pv} group={groups.find(x=>x.key===pv.key)} rules={rules} rank={rank} run={run} onAdmit={admitBatch} onRerun={rerunBatch}
        onWork={()=>{setKey(pv.key);setIdx(0);setPv(null)}} onClose={()=>{setPv(null);setRun(null)}}/>}
      {!refs.length?<Empty text={key?'Nothing left in this rule group.':'Nothing left in this queue.'}/>:<>
        <header className="l4f-head" data-l4-focus-head>
          <span><strong>{groupLabel(curGroup||sel||{})}</strong> <small data-l4-focus-pos>Card {fmtNumber(at+1)} of {fmtNumber(refs.length)}{key?'':' in this queue'}{Number(curGroup?.n)>(curGroup?.refs||[]).length?` (oldest ${fmtNumber((curGroup.refs||[]).length)} of ${fmtNumber(curGroup.n)} listed)`:''}</small></span>
          <span className="l4f-nav"><Button compact disabled={at===0} onClick={()=>setIdx(at-1)} aria-label="Previous card" data-l4-focus-prev><ChevronLeft size={14}/>Previous</Button>
            <Button compact disabled={at>=refs.length-1} onClick={()=>setIdx(at+1)} aria-label="Next card" data-l4-focus-next>Next<ChevronRight size={14}/></Button></span>
        </header>
        {curItem?<div key={cur} data-l4-focus-card={cur}>{renderItem(curItem,done,groupLabel(curGroup||{}))}</div>:<Loading compact label="Reading the card…"/>}
      </>}
    </section>
  </div>
}

function BatchPreview({pv,group,rules,rank,run,onAdmit,onRerun,onWork,onClose}){
  const name=groupLabel(group||{key:pv.key}),admits=batchAdmits({key:pv.key}),reruns=batchRereads({key:pv.key})
  const list=(pv.items||[]).map(it=>({it,c:admits?cleanedOf(it,rules):null})),ready=list.filter(x=>x.c?.ok)
  // s870: a recovery group's records, by what the server says each one can do
  const rr=reruns?list.filter(x=>x.it.reread?.verdict==='rereadable').map(x=>x.it):[],ff=reruns?list.filter(x=>x.it.reread?.verdict==='no_stored_page').map(x=>x.it):[]
  const[confirm,setConfirm]=useState(false)
  return <div className="l4f-preview" role="dialog" aria-label={`Preview the batch: ${name}`} data-l4-batch-preview={pv.key}>
    <header><strong>Preview the batch: {name}</strong><button type="button" className="hd-x" onClick={onClose} aria-label="Close the preview" data-l4-batch-close><X size={15}/></button></header>
    {!pv.items?<Loading compact label="Reading the records…"/>:<>
      <p className="l4r-sub" data-l4-batch-ms>{fmtNumber(list.length)} record{list.length===1?'':'s'}{Number(group?.n)>list.length?` (the oldest ${fmtNumber(list.length)} of ${fmtNumber(group.n)})`:''}, shown in {fmtNumber(pv.ms)} ms{pv.server_ms!=null?` (database ${fmtNumber(pv.server_ms)} ms)`:''}.
        {admits?' Each is admitted with the marked words removed, one decision each with its reason, and locked by hand. A record whose cleaned text fails a check is left for a person.':
          reruns?` System recovery: ${fmtNumber(rr.length)} can be re-read from their stored copy by the deterministic reader ($0: no AI, no Firecrawl)${ff.length?`, and ${fmtNumber(ff.length)} have no stored page and can be queued for a stored-page fetch`:''}. Nothing is approved here: each new read goes through the same machine rule and Layer 4.`:
          pv.key.startsWith('aer:')?' Entry requirement items are decided one card at a time: there is no batch approval.':' These are decided one card at a time.'}</p>
      <ol className="l4f-recs">{list.map(({it,c})=><li key={it.ref} data-l4-batch-rec={it.ref} data-l4-batch-ok={c?String(c.ok):undefined}>
        <span className="l4f-rec-name"><strong>{it.subject||String(it.ref).slice(0,8)}</strong>{it.provider&&<small> · {it.provider}</small>}</span>
        {c?<>{c.original&&<p className="l4f-rec-text">{markBanned(c.original,c.words).map((x,i)=>x.word?<mark key={i} className="dea-ban">{x.text}</mark>:<React.Fragment key={i}>{x.text}</React.Fragment>)}</p>}
            {c.ok?<p className="l4f-rec-clean" data-l4-batch-clean><small>Admitted as:</small> {c.text}</p>:<p className="l4f-rec-hold"><small>Left for a person: {c.why}</small></p>}</>
          :<small className="l4f-rec-why">{firstSentence(it.why)}{reruns&&it.reread?<> · <b data-l4-batch-rr={it.reread.verdict}>{it.reread.verdict==='rereadable'?'re-read from stored copy':it.reread.verdict==='no_stored_page'?'stored-page fetch':`left as it is: ${REREAD_SKIP[it.reread.verdict]||it.reread.verdict}`}</b></>:null}</small>}</li>)}</ol>
      {run&&<p className="l4f-run" role="status" data-l4-batch-run={run.busy?'running':'done'}>{run.busy?`Working on ${fmtNumber(run.total)}…`:run.result?(run.result.action==='apply'?`Re-read asked for ${fmtNumber(run.done)} of ${fmtNumber(run.total)}: the stale reads are superseded and the deterministic reader reads the stored copies within the next sweeps.`:`Queued ${fmtNumber(run.done)} of ${fmtNumber(run.total)} for a stored-page fetch.`):`Admitted ${fmtNumber(run.done)} of ${fmtNumber(run.total)}.`}{run.failed.length?` ${fmtNumber(run.failed.length)} not admitted: ${run.failed.map(f=>`${f.subject||f.ref} (${f.error})`).join('; ')}`:''}</p>}
      <div className="l4r-actions">
        {reruns&&!run&&(!confirm?<>{rr.length>0&&<Button compact variant="primary" disabled={rank<6} onClick={()=>setConfirm('rr')} title={rank<6?'Needs the Platform Admin (AER decisions, A3)':''} data-l4-batch-reread>Re-read {fmtNumber(rr.length)} from stored copy ($0)</Button>}
            {ff.length>0&&<Button compact disabled={rank<6} onClick={()=>setConfirm('ff')} data-l4-batch-fetch>Queue stored-page fetch for {fmtNumber(ff.length)}</Button>}</>
          :<><Button compact variant="primary" onClick={()=>onRerun(confirm==='rr'?'aer_det_reread':'aer_page_fetch',confirm==='rr'?rr:ff)} data-l4-batch-reread-confirm>{confirm==='rr'?`Confirm: re-read these ${fmtNumber(rr.length)} ($0)`:`Confirm: queue ${fmtNumber(ff.length)} fetches`}</Button><Button compact onClick={()=>setConfirm(false)}>Not now</Button></>)}
        {admits&&!run&&(!confirm?<Button compact variant="primary" disabled={rank<4||!ready.length} onClick={()=>setConfirm(true)} title={rank<4?'Needs a Pipeline Operator or above':''} data-l4-batch-admit>Remove the words &amp; admit {fmtNumber(ready.length)}</Button>
          :<><Button compact variant="primary" onClick={()=>onAdmit(ready)} data-l4-batch-confirm>Confirm: admit these {fmtNumber(ready.length)}</Button><Button compact onClick={()=>setConfirm(false)}>Not now</Button></>)}
        <Button compact onClick={onWork} data-l4-batch-work>Work through these card by card</Button>
      </div></>}
  </div>
}

/** s870 (Platform Admin 20 Nov 2026 16:28): the action on one AER card held as technical recovery, from the server's check (rule_group_items):
 * Re-read from stored copy ($0) or Queue stored-page fetch. One click, the Platform Admin's (A3); the reason is recorded with the action. */
export function AerRecoveryAction({it,rank,onDone,onError}){
  const a=rereadAction(it),[busy,setBusy]=useState(false),[done,setDone]=useState('')
  if(!a)return null
  const go=async()=>{setBusy(true)
    try{const r=await rpc(a.key,{refs:[it.ref],reason:a.key==='aer_det_reread'?'Stale partial read: re-read from the stored copy by the deterministic reader ($0), from Layer 4 Review':'No stored page: queue a stored-page fetch, from Layer 4 Review'})
      const ok=Number(a.key==='aer_det_reread'?r.superseded:r.fetch_queued)>0
      if(!ok){const why=Object.keys(r.skipped||{})[0];throw new Error(`Not done: ${REREAD_SKIP[why]||why||'the item changed'}`)}
      if(a.key==='aer_det_reread')onDone?.({kind:it.kind,ref:it.ref,outcome:'queued',headline:'Re-read asked: the deterministic reader reads the stored copy ($0)'})
      else setDone('Queued: the course is on the Course page needed list.')}
    catch(e){onError?.(e.message)}finally{setBusy(false)}}
  return <div className="l4f-recovery" data-l4-recovery={a.key}>
    <Button compact variant="primary" disabled={busy||rank<6||!!done} onClick={go} title={rank<6?'Needs the Platform Admin (AER decisions, A3)':a.why} data-l4-recovery-go>{busy?'Working…':a.label}</Button>
    <small>{done||a.why}</small></div>
}
