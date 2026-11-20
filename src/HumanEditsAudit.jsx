// CF-247 s804/s805 (Platform Admin 20 Nov 2026 05:52, chat S1-Build): Data & Governance › Human Edits & Periodic Audit.
// Every University or Course description a person edited before admitting it (pipeline.human_edit_audit, admission_source human_input).
// My Human Edits: the signed-in Pipeline Operator's own edits, which they acknowledge or re-verify. All Human Edits (Admin Governance): every
// edit, for the Platform Admin, with the Unacknowledged and Due for 6-Month Re-Review counts (due when next_review_due_at has passed: six
// months, a setting, after the edit or the last acknowledgement). Tick rows and choose one governed action:
//   Acknowledge & Keep Lock (bulk or single): records who and when, and the next review is due in six months again. No spend.
//   Re-Verify by Machine (bulk or single): a read-only comparison of the human text with the stored page quotes and the latest machine
//     candidate, shown side by side. Nothing is read again (no Firecrawl, no AI) and nothing is overwritten.
//   Edit & Re-Lock (single): a new revision of the text, checked and locked again.
//   Release Lock to Machine (bulk or single, Platform Admin): the hand lock is cleared so later readings may change the description.
//   Accept machine text (single, Platform Admin, after a re-verify): the machine candidate replaces the human text and the lock is cleared.
// All through public.admin_layer4_inbox (actions human_edits*); the server checks the role and ownership of every row.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import{CheckLine,descriptionRules}from'./DescriptionEditAdmit'
import{checkDescription,ruleCandidates}from'./lib/description-check.js'
import'./human-edits.css'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
export const HE_FILTERS=[['open','Open'],['unacknowledged','Unacknowledged'],['due','Due for 6-month re-review'],['all','All, including released']]
export const HE_STATUS={pending_ack:'Unacknowledged',acknowledged:'Acknowledged',rechecked:'Re-verified',lock_released:'Lock released',machine_accepted:'Machine text accepted',superseded:'Superseded'}
const PAGE=50

export default function HumanEditsAudit({tab,rank,onError}){
  const scope=tab==='all'?'all':'mine'
  const[filter,setFilter]=useState('open'),[entity,setEntity]=useState(''),[country,setCountry]=useState(''),[off,setOff]=useState(0)
  const[data,setData]=useState(null),[sel,setSel]=useState([]),[busy,setBusy]=useState(''),[note,setNote]=useState(''),[err,setErr]=useState(''),[confirm,setConfirm]=useState(null),[openId,setOpenId]=useState('')
  const load=(o=off)=>{setData(null);setErr('');rpc('human_edits',{scope,filter,entity_type:entity,country,limit:PAGE,offset:o}).then(d=>{setData(d);setSel(s=>s.filter(id=>(d.items||[]).some(x=>x.id===id)))}).catch(e=>{setErr(e.message);onError?.(e.message)})}
  useEffect(()=>{setOff(0);setSel([]);load(0)},[scope,filter,entity,country])
  const act=async(action,ids,extra)=>{setBusy(action);setErr('');setNote('')
    try{const r=await rpc(action,{ids,...(extra||{})});setNote(`${LABEL[action]}: ${fmtNumber(r.rows)} edit${r.rows===1?'':'s'}.`);setConfirm(null);load(off)}catch(e){setErr(e.message)}finally{setBusy('')}}
  if(rank<4)return <Empty text="Human Edits & Periodic Audit is for a Pipeline Operator or above."/>
  const items=data?.items||[],all=items.length>0&&items.every(x=>sel.includes(x.id)),c=data?.counts||{}
  const toggle=id=>setSel(s=>s.includes(id)?s.filter(x=>x!==id):[...s,id])
  const admin=rank>=6,chosen=items.filter(x=>sel.includes(x.id))
  return <div className="he" data-he={scope}>
    <p className="he-intro"><small>{scope==='all'?'Every description a person edited before admitting it, by anyone. ':'The descriptions you edited before admitting them. '}
      Each is locked by hand and due for review six months after it was edited or last acknowledged. Re-Verify by Machine compares the text with the stored page and the latest machine text; it reads nothing again and changes nothing.</small></p>
    <section className="he-tiles">
      <Metric label="Open human edits" value={fmtNumber(c.open??0)} detail={scope==='all'?'all reviewers':'yours'}/>
      <Metric label="Unacknowledged" value={fmtNumber(c.unacknowledged??0)} tone={Number(c.unacknowledged)?'warning':'success'} detail="not yet acknowledged"/>
      <Metric label="Due for 6-month re-review" value={fmtNumber(c.due??0)} tone={Number(c.due)?'warning':'success'} detail="180 days or more since the edit or acknowledgement"/>
    </section>
    <RuleTuning items={items}/>
    <div className="he-bar">
      <div className="he-pills" role="group" aria-label="Show">{HE_FILTERS.map(([k,l])=><button key={k} type="button" className={filter===k?'on':''} aria-pressed={filter===k} onClick={()=>setFilter(k)} data-he-filter={k}>{l}{k==='unacknowledged'&&Number(c.unacknowledged)?<span className="he-badge" data-he-badge="unacknowledged">{fmtNumber(c.unacknowledged)}</span>:null}{k==='due'&&Number(c.due)?<span className="he-badge" data-he-badge="due">{fmtNumber(c.due)}</span>:null}</button>)}</div>
      <select value={entity} onChange={e=>setEntity(e.target.value)} aria-label="Description" data-he-entity><option value="">University and course</option><option value="provider">University descriptions</option><option value="course">Course descriptions</option></select>
      <select value={country} onChange={e=>setCountry(e.target.value)} aria-label="Country" data-he-country><option value="">Every country</option>{['AU','NZ','CA'].map(k=><option key={k} value={k}>{k}</option>)}</select>
      <Button compact onClick={()=>load(off)}>Refresh</Button>
    </div>
    <div className="he-actions" role="toolbar" aria-label="Actions on the ticked edits" data-he-actions>
      <small>{sel.length?`${fmtNumber(sel.length)} ticked`:'Tick edits to act on them'}</small>
      <Button compact variant="primary" disabled={!sel.length||!!busy} onClick={()=>act('human_edits_ack',sel)} data-he-act="ack">{busy==='human_edits_ack'?'Saving…':'Acknowledge & Keep Lock'}</Button>
      <Button compact disabled={!sel.length||!!busy} onClick={()=>act('human_edits_recheck',sel)} data-he-act="recheck">{busy==='human_edits_recheck'?'Comparing…':'Re-Verify by Machine'}</Button>
      {admin&&<Button compact disabled={!sel.length||!!busy} onClick={()=>setConfirm('release')} data-he-act="release">Release Lock to Machine</Button>}
    </div>
    {confirm==='release'&&<div className="he-confirm" role="alertdialog" aria-label="Release the locks" data-he-confirm="release"><p><small>Release the hand lock on {fmtNumber(sel.length)} description{sel.length===1?'':'s'}: {chosen.slice(0,5).map(x=>x.name).join('; ')}{chosen.length>5?` and ${chosen.length-5} more`:''}. The human text stays until a later reading changes it; nothing is read now.</small></p>
      <Button compact variant="primary" disabled={!!busy} onClick={()=>act('human_edits_release',sel)} data-he-confirm-go>{busy?'Releasing…':'Release the locks'}</Button><Button compact onClick={()=>setConfirm(null)}>Cancel</Button></div>}
    {note&&<p className="he-note" role="status" data-he-note>{note}</p>}
    {err&&<p className="he-err" role="alert" data-he-error>{err}</p>}
    {!data?<Loading compact/>:items.length===0?<Empty text={filter==='open'?'No open human edits.':'Nothing to show for this choice.'}/>:<>
      <div className="he-table-wrap"><table className="he-table" data-he-table>
        <thead><tr><th><input type="checkbox" checked={all} onChange={()=>setSel(all?[]:items.map(x=>x.id))} aria-label="Tick every edit on this page" data-he-all/></th><th>Description</th><th>Country · type</th>{scope==='all'&&<th>Edited by</th>}<th>Edited</th><th>Review due</th><th>Status</th><th></th></tr></thead>
        <tbody>{items.map(x=><React.Fragment key={x.id}><tr className={`${x.due?'due':''}${!x.acknowledged_at?' unack':''}`} data-he-row={x.id} data-he-name={x.name}>
          <td><input type="checkbox" checked={sel.includes(x.id)} onChange={()=>toggle(x.id)} aria-label={`Tick ${x.name}`} data-he-tick/></td>
          <td><strong>{x.name||'—'}</strong><br/><small>{x.entity_type==='provider'?'University description':`Course description · ${x.provider_name||''}`}{x.revision>1?` · revision ${x.revision}`:''}</small></td>
          <td><small>{x.country||'—'}{x.provider_type?` · ${String(x.provider_type).replace(/_/g,' ')}`:''}</small></td>
          {scope==='all'&&<td><small>{x.mine?'You':(x.edited_by_name||'—')}</small></td>}
          <td><small>{fmtDate(x.edited_at)}<br/>{fmtNumber(x.age_days)} days ago</small></td>
          <td><small>{x.next_review_due_at?fmtDate(x.next_review_due_at):'—'}</small></td>
          <td className="he-chips">{!x.acknowledged_at&&!['lock_released','machine_accepted'].includes(x.status)&&<StatusChip value="unacknowledged" tone="warning" label="Unacknowledged"/>}{x.due&&!['lock_released','machine_accepted'].includes(x.status)&&<StatusChip value="due" tone="danger" label="Due for re-review"/>}
            {x.status==='rechecked'&&<StatusChip value="rechecked" tone="info" label={x.recheck_support_share!=null?`Re-verified: ${Math.round(Number(x.recheck_support_share)*100)}% of sentences on the page`:'Re-verified'}/>}
            {['acknowledged','lock_released','machine_accepted'].includes(x.status)&&<StatusChip value={x.status} tone={x.status==='acknowledged'?'success':'neutral'} label={HE_STATUS[x.status]}/>}
            {x.locked?<StatusChip value="locked" tone="neutral" label="Locked"/>:null}</td>
          <td><Button compact onClick={()=>setOpenId(openId===x.id?'':x.id)} aria-expanded={openId===x.id} data-he-open>{openId===x.id?'Close':'Open'}</Button></td></tr>
          {openId===x.id&&<tr className="he-detail-row"><td colSpan={scope==='all'?8:7}><EditDetail x={x} rank={rank} busy={busy} act={act}/></td></tr>}</React.Fragment>)}</tbody>
      </table></div>
      {Number(data.total)>PAGE&&<div className="he-pager"><Button compact disabled={off===0} onClick={()=>{const o=Math.max(0,off-PAGE);setOff(o);load(o)}}>Previous</Button><small>{fmtNumber(off+1)}–{fmtNumber(Math.min(off+PAGE,data.total))} of {fmtNumber(data.total)}</small><Button compact disabled={off+PAGE>=Number(data.total)} onClick={()=>{const o=off+PAGE;setOff(o);load(o)}}>Next</Button></div>}
    </>}
  </div>
}
const LABEL={human_edits_ack:'Acknowledged and kept locked',human_edits_recheck:'Re-verified by machine (nothing changed)',human_edits_edit:'Edited and re-locked',human_edits_release:'Lock released to the machine',human_edits_accept_machine:'Machine text accepted'}

function EditDetail({x,rank,busy,act}){
  const[edit,setEdit]=useState(false),[text,setText]=useState(x.current||x.edited||''),[reason,setReason]=useState(''),[rules,setRules]=useState(null)
  useEffect(()=>{descriptionRules().then(setRules).catch(()=>{})},[])
  const r=rules?.[x.entity_type==='course'?'course':'provider'],ok=r?checkDescription(text,r).ok:false,open=!['lock_released','machine_accepted','superseded'].includes(x.status)
  const rc=x.recheck_detail||{}
  return <div className="he-detail" data-he-detail={x.id}>
    <div className="he-sides">
      <section><h4>Original machine text</h4><p data-he-original>{x.original||<em>None (written by hand from a held reading)</em>}</p></section>
      <section><h4>Current human text</h4><p data-he-current>{x.current||x.edited}</p></section>
      {x.status==='rechecked'&&<section data-he-fresh><h4>Fresh machine candidate</h4><p>{x.recheck_candidate||<em>No machine text is held for this description.</em>}</p></section>}
    </div>
    {x.status==='rechecked'&&<div className="he-recheck" data-he-recheck><p><small>Re-verified {fmtDate(x.recheck_at)}: {rc.quotes_held?`each sentence of the human text against the stored page quotes (a sentence counts as on the page when ${Math.round(Number(rc.word_share||0.6)*100)}% of its longer words are there)`:'no page quotes are held for this description'}{rc.candidate_differs?'; the machine text differs from the human text':''}. Nothing was read again or changed.</small></p>
      {Array.isArray(rc.sentences)&&rc.sentences.length>0&&<ol>{rc.sentences.map((s,i)=><li key={i} className={s.supported?'ok':'miss'} data-he-sentence={s.supported?'on-page':'not-found'}>{s.sentence} <small>({Math.round(Number(s.share)*100)}% of words on the page)</small></li>)}</ol>}</div>}
    {x.reason&&<p><small>Reason given: {x.reason}</small></p>}
    {open&&<div className="he-detail-actions">
      <Button compact variant="primary" disabled={!!busy} onClick={()=>act('human_edits_ack',[x.id])} data-he-one="ack">Acknowledge &amp; Keep Lock</Button>
      <Button compact disabled={!!busy} onClick={()=>act('human_edits_recheck',[x.id])} data-he-one="recheck">Re-Verify by Machine</Button>
      <Button compact disabled={!!busy} onClick={()=>setEdit(e=>!e)} data-he-one="edit">Edit &amp; Re-Lock</Button>
      {rank>=6&&<Button compact disabled={!!busy} onClick={()=>act('human_edits_release',[x.id])} data-he-one="release">Release Lock to Machine</Button>}
      {rank>=6&&x.status==='rechecked'&&x.recheck_candidate&&<Button compact disabled={!!busy} onClick={()=>act('human_edits_accept_machine',[x.id])} data-he-one="accept">Accept machine text</Button>}
    </div>}
    {edit&&open&&<div className="he-edit" data-he-edit><textarea value={text} onChange={e=>setText(e.target.value)} rows={x.entity_type==='course'?3:6} aria-label="New text" data-he-edit-text/>
      <CheckLine text={text} rules={r}/>
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (at least 5 characters)" aria-label="Reason" data-he-edit-reason/>
      <Button compact variant="primary" disabled={!!busy||!ok||reason.trim().length<5} onClick={()=>act('human_edits_edit',[x.id],{text:text.trim(),reason:reason.trim()})} data-he-edit-save>{busy==='human_edits_edit'?'Saving…':'Save new revision and re-lock'}</Button></div>}
  </div>
}

// s819 (Platform Admin 20 Nov 2026 10:21): rule-tuning candidates. The words reviewers removed most often when they edited a description before admitting
// it. A word already on the readers' list is now removed automatically before Layer 4; a word that is not on it is a candidate to add (Settings › Pipeline
// settings, Platform Admin, with a reason). Worked out on this page from the edits shown; nothing is written.
function RuleTuning({items}){
  const[rules,setRules]=useState(null)
  useEffect(()=>{descriptionRules().then(setRules).catch(()=>{})},[])
  const words=[...(rules?.provider?.words||[]),...(rules?.course?.words||[])],rows=ruleCandidates(items,words).slice(0,12)
  if(!items.length)return null
  return <details className="he-tuning" data-he-tuning open={rows.some(r=>!r.on_list)||undefined}>
    <summary><strong>Rule-tuning candidates</strong> <small>{rows.length?`${rows.filter(r=>!r.on_list).length} word(s) reviewers removed that are not on the list yet`:'No word removed yet'}</small></summary>
    {rows.length>0&&<table className="he-tuning-table"><thead><tr><th>Word removed</th><th>Edits</th><th>On the readers' list?</th></tr></thead>
      <tbody>{rows.map(r=><tr key={r.word} data-he-tuning-word={r.word}><td><code>{r.word}</code></td><td>{fmtNumber(r.n)}</td><td>{r.on_list?'Yes: removed automatically before Layer 4':'No: a candidate to add (Settings › Pipeline settings)'}</td></tr>)}</tbody></table>}
    <p><small>Counted from the edits listed above. Adding a word changes what the readers refuse and remove; it is a Platform Admin decision with a reason.</small></p>
  </details>
}
