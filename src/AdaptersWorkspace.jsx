// Layer 2 › Adapters (v2.15.200, CF-247 Decision 254). Platform Admin, 6 Oct 2026 15:25: "Adapters Lifecycle needs to
// managed in better UI experience. Where they are created, should have qualify and admit and then toggle on/off for
// editing and reruns, if they are switched off what are the consequences. they should have schedule to run - which is
// read pages from Evidence or Fire crawler if the page hash changes? Adapter can be visually created as well. Try to
// combine then in a single UI experience." 15:31 "Under Layer2 ... anything cascading action or information produces like
// English fees would be bounded at same place." 15:38: Coverage › Universities retired into this screen.
//
// One collapsed row per university with an adapter or in the Firecrawl targets (public.admin_adapters 'list'). Opening a
// row reads that university in full (admin_adapters 'detail') and holds everything about it: coverage, the switch and its
// consequences, Qualify and Admit as tasks, the adapter builder and editor, the read schedule, central pages, the fee
// range, hosted courses, the Firecrawl target, history and the course table. Tick rows (or tick every row the filters
// show) to Qualify, Admit, read pages again, switch on or off, or set the read cycle for many at once.
// Rules kept: Qualify only measures. Admit is its own deliberate step (Platform Admin, with a reason) and admits only the
// fields an adapter passed in its latest Qualify. Values entered or locked by hand are never changed. Thresholds and the
// read-cycle bounds come from the database, not from this file.
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw,ChevronRight,CheckCircle2,XCircle,Power,CalendarClock}from'lucide-react'
import{supabase}from'./lib/supabase'
import JobButton from'./JobButton'
import Card,{useCardOpen,rememberOpen}from'./Card'
import{Button,Empty,Loading,SectionTitle,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{Pill,Coverage,PolicyCell,AttachPage,CourseTable,FeeRangeCell,FeeRangeSettings,HostedPanel,AwardLinkSettings,RereadPanel,FeeRangePanel,ADAPTER,FIELD,SourcePill}from'./UniversitiesCoverage'
import{AdapterEditor,AdapterEvaluation,FirecrawlRuns,FirecrawlTargets}from'./FirecrawlWork'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const QFIELDS=['intakes','english','fee','delivery']
const PAGE=50
const KIND_LABEL={qualify_adapters:'Qualify',admit_qualified:'Admit',reread_pages:'Read pages again',firecrawl_run:'Firecrawl run',adapter_apply:'Apply the adapter',central_page_read:'Central page'}
const STATE_TONE={queued:'neutral',running:'info',paused:'warning',done:'success',failed:'danger',cancelled:'neutral'}
const ACTION_LABEL={uni_adapter_admit:'Admission changed',uni_adapter_exclude:'Course excluded',uni_adapter_request:'Improvement asked',uni_adapter_request_answer:'Request answered',uni_adapter_switch:'Switched',uni_adapter_read_cycle:'Read cycle set',
  uni_adapter_save:'Adapter saved',uni_adapter_apply:'Adapter applied',uni_adapter_preview:'Adapter previewed',job_start:'Task started'}
const COUNTRY={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const share=v=>`${Math.round(Number(v||0)*100)}%`

// What switching off does, in plain words. Shown next to the switch and in the bulk bar.
const OFF_EFFECT='Switched off, the adapter is not applied to pages read from now on: the general reader reads them instead, and nothing the adapter reads is admitted. Values it already admitted stay in the catalogue. Values entered or locked by hand are never changed. Its settings are kept, so it can be edited, tested and switched on again.'
const ON_EFFECT='Switched on, the adapter is applied to every page of this university read from now on (and when you press Apply or Read pages again). What it reads is admitted only for the fields admitted below, and only after a deliberate Admit.'

// A block inside an open row. Closed by default; whether a kind of block is open is remembered for the browser session
// (the same for every university), and its content is read only while it is open.
function Block({id,title,meta,children,...rest}){
  const[open,setOpen]=useCardOpen(`adapters.block.${id}`)
  return <section className={`ad-block${open?' is-open':''}`} data-ad-block={id} {...rest}>
    <button type="button" className="ad-row-name" aria-expanded={open} onClick={()=>setOpen(!open)}><ChevronRight size={14} className="cf-card-chev" style={{transform:open?'rotate(90deg)':undefined}} aria-hidden/><strong>{title}</strong>{meta&&<small className="sl-sub">{meta}</small>}</button>
    {open&&<div className="cf-card-body">{children}</div>}
  </section>
}

function AdapterPill({a}){const[l,t]=a?(ADAPTER[a.state]||[a.state,'neutral']):['No adapter','neutral'];return <Pill tone={t}>{l}</Pill>}
function Fields({list,tone='success'}){return (list||[]).length?<span className="ad-chips">{list.map(f=><Pill key={f} tone={tone}>{FIELD[f]||f}</Pill>)}</span>:null}

// ---- one university, open --------------------------------------------------------------------------------------------
function Row({row,settings,can,canQualify,picked,onPick,open,onOpen,onChanged,onError,rangeOf}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false)
  const pid=row.provider_id
  const load=()=>supabase.rpc('admin_adapters',{p_action:'detail',p_args:{provider_id:pid}}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e)))
  useEffect(()=>{if(open)load()},[open,pid])
  const a=row.adapter,q=row.qualify,passing=q?.passing||[]
  const refresh=()=>{load();onChanged?.()}
  const switchOn=async on=>{const reason=ask(`${on?'Switch on':'Switch off'} the adapter for ${row.name}?\n\n${on?ON_EFFECT:OFF_EFFECT}`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_adapters',{p_action:'set_on',p_args:{provider_ids:[pid],on,reason}});if(error)throw error;refresh()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const setCycle=async()=>{const cur=d?.schedule?.read_cycle_days
    const v=window.prompt(`Read the pages of ${row.name} again every how many days? ${settings.read_cycle_min} to ${settings.read_cycle_max}. Leave empty for the platform default (${settings.read_cycle_default} days).`,cur??'')
    if(v===null)return;const days=v.trim()===''?null:Number(v);if(days!==null&&!(Number.isInteger(days)&&days>=settings.read_cycle_min&&days<=settings.read_cycle_max)){onError?.(`The read cycle is ${settings.read_cycle_min} to ${settings.read_cycle_max} days, or empty for the default.`);return}
    const reason=ask(`Set the read cycle of ${row.name} to ${days??`the default (${settings.read_cycle_default})`} days? The next read of each page already read moves to its last read plus this cycle.`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_adapters',{p_action:'set_cycle',p_args:{provider_ids:[pid],days,reason}});if(error)throw error;refresh()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const target=async inc=>{const reason=ask(inc?`Add ${row.name} to the Firecrawl targets? Firecrawl may then be used for its pages (Read pages and Find pages runs).`:`Take ${row.name} out of the Firecrawl targets? Firecrawl will not be used for it. Pages are still read plainly where they can be.`);if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_firecrawl_write',{p_action:'target',p_args:{provider_id:pid,included:inc,reason}});if(error)throw error;refresh()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const u=d?{...d,provider_id:pid,name:row.name}:null
  const last=d?.qualifications?.[0]
  return <article className={`ad-row${open?' is-open':''}`} data-adapter-row={pid}>
    <div className="ad-row-head">
      <input type="checkbox" aria-label={`Tick ${row.name}`} checked={picked} onChange={()=>onPick(pid)}/>
      <button type="button" className="ad-row-name" aria-expanded={open} onClick={()=>onOpen(open?null:pid)}>
        <ChevronRight size={15} className="cf-card-chev" style={{transform:open?'rotate(90deg)':undefined}} aria-hidden/>
        <span><strong>{row.name}</strong><small className="sl-sub">{[row.country,row.state].filter(Boolean).join(' · ')}{row.university?'':' · not a university'}</small></span></button>
      <span className="ad-chips"><AdapterPill a={a}/>{a?.state==='admitting'&&<Fields list={a.fields}/>}</span>
      <span className="ad-chips ad-hide-sm" title="Fields that passed in the latest Qualify">{q?(passing.length?<><small className="sl-sub">Passed:</small><Fields list={passing} tone="info"/></>:<small className="sl-sub">Qualify: nothing passed</small>):<small className="sl-sub">Not qualified yet</small>}{q&&<small className="sl-sub">{fmtDate(q.at)}</small>}</span>
      <span className="ad-hide-sm"><small className="sl-sub">{fmtNumber(row.pages_read)} of {fmtNumber(row.pages)} pages read{row.next_read?` · next read ${fmtDate(row.next_read)}`:''}</small>
        {row.target&&<Pill tone={row.target.included?'info':'neutral'}>{row.target.included?'Firecrawl target':'Not a Firecrawl target'}</Pill>}</span>
      <Button compact onClick={()=>onOpen(open?null:pid)} aria-label={`${open?'Close':'Open'} ${row.name}`}>{open?'Close':'Open'}</Button>
    </div>
    {open&&<div className="ad-row-body" data-adapter-detail={pid}>
      {!d?<Loading label={`Loading ${row.name}…`}/>:<>
      <div className="ad-grid" data-adapter-coverage>
        <div><small className="sl-sub">Intakes</small><Coverage part={d.intakes} courses={d.courses}/></div>
        <div><small className="sl-sub">English</small><Coverage part={d.english} courses={d.courses}/></div>
        <div><small className="sl-sub">Fees</small><Coverage part={d.fee} courses={d.courses}/></div>
        <div><small className="sl-sub">Central English rule</small><PolicyCell p={d.english_policy} pages={d.central_pages} kind="english_policy"/></div>
        <div><small className="sl-sub">Key dates</small><PolicyCell p={d.calendar} pages={d.central_pages} kind="intake_calendar"/></div>
        <div><small className="sl-sub">Whole-course fees</small><FeeRangeCell r={rangeOf[pid]}/></div>
      </div>

      <Block id="switch" title="Switch, Qualify and Admit" meta={a?`${(ADAPTER[a.state]||[a.state])[0]}${a.state==='admitting'?`: ${(a.fields||[]).map(f=>FIELD[f]||f).join(', ')}`:''}`:'No adapter yet: build one below'} data-adapter-lifecycle={pid}>
        {!a?<p className="ad-note">This university has no adapter. Build one under <strong>Build and test the adapter</strong>, save it switched on, then Qualify it here.</p>:<>
          <div className="ad-actions">
            <AdapterPill a={a}/>
            {can&&(a.state==='off'?<Button compact variant="primary" disabled={busy} onClick={()=>switchOn(true)} data-adapter-switch="on"><Power size={13}/> Switch on</Button>
              :<Button compact disabled={busy} onClick={()=>switchOn(false)} data-adapter-switch="off"><Power size={13}/> Switch off</Button>)}
          </div>
          <p className="ad-note" data-adapter-consequence>{a.state==='off'?OFF_EFFECT:ON_EFFECT}</p>
          <h4 className="sl-h4">1. Qualify (measures only, admits nothing)</h4>
          <p className="ad-note">A field passes when the adapter reads it on at least {share(settings.min_read_share)} of the pages read and agrees with the catalogue on at least {share(settings.min_agree_share)} of the values both hold (settings on Models &amp; services › Firecrawl).</p>
          <JobButton kind="qualify_adapters" scope={pid} args={{provider_ids:[pid],adapter_state:'any'}} label="Qualify this adapter" disabled={!canQualify||a.state==='off'}
            question={`Qualify the adapter for ${row.name}? It measures what the adapter reads on the stored pages against the admission rules. Nothing is admitted.`} onFinished={refresh}/>
          {a.state==='off'&&<small className="sl-sub">Switch the adapter on to Qualify it.</small>}
          {last?<div className="cf-table-wrap"><table className="cf-table tm-table" data-adapter-qualify><thead><tr><th>Field</th><th>Result</th><th className="num">Read on</th><th className="num">Agrees</th><th>Why</th></tr></thead><tbody>
            {QFIELDS.map(f=>{const x=(last.fields||{})[f];if(!x)return null;return <tr key={f}><td>{FIELD[f]||f}</td><td><span className={`ad-field ${x.pass?'ad-pass':'ad-fail'}`}>{x.pass?<CheckCircle2 size={13}/>:<XCircle size={13}/>}{x.pass?'Passes':'Does not pass'}</span></td>
              <td className="num">{fmtNumber(x.read)} ({share(x.read_share)})</td><td className="num">{x.agree_share==null?'—':share(x.agree_share)}</td><td><small className="sl-sub">{x.why}</small></td></tr>})}
          </tbody></table><small className="sl-sub">Latest Qualify {fmtDateTime(last.at)} · {fmtNumber(last.pages_read)} pages read · {last.title}</small></div>:<p className="ad-note">Not qualified yet.</p>}
          <h4 className="sl-h4">2. Admit (the deliberate step)</h4>
          <p className="ad-note">Admits only the fields that passed in the latest Qualify{passing.length?` (${passing.map(f=>FIELD[f]||f).join(', ')})`:''}. Fields already admitted stay. Values entered or locked by hand are never changed.</p>
          <JobButton kind="admit_qualified" scope={pid} args={{provider_ids:[pid]}} label="Admit the passing fields" disabled={!can||a.state==='off'||!passing.some(f=>!(a.fields||[]).includes(f))}
            question={`Admit ${passing.filter(f=>!(a.fields||[]).includes(f)).map(f=>FIELD[f]||f).join(', ')} from the adapter for ${row.name}? Values entered or locked by hand are never changed.`} onFinished={refresh}/>
          {!can&&<small className="sl-sub">A Platform Admin admits.</small>}
          {can&&a.state!=='off'&&passing.length>0&&!passing.some(f=>!(a.fields||[]).includes(f))&&<small className="sl-sub">Every passing field is already admitted.</small>}
        </>}
      </Block>

      <Block id="build" title="Build and test the adapter" meta="Visual builder, settings, preview, Apply, what it read, exclusions">
        <AdapterEditor providerId={pid} onError={onError}/>
      </Block>

      <Block id="schedule" title="Read schedule" meta={`Every ${d.schedule?.read_cycle_days??settings.read_cycle_default} days${d.schedule?.read_cycle_days?'':' (default)'}${d.schedule?.next_read?` · next ${fmtDate(d.schedule.next_read)}`:''}`} data-adapter-schedule={pid}>
        <p className="ad-note">Each course page that has been read is read again on its cycle. A page whose content (hash) has not changed keeps its evidence. A changed page is stored as new evidence and the adapter, when switched on, reads it. Pages a plain read cannot open go to Firecrawl only if the university is a Firecrawl target.</p>
        <div className="ad-grid">
          <div><small className="sl-sub">Read cycle</small><strong>{d.schedule?.read_cycle_days??settings.read_cycle_default} days</strong>{!d.schedule?.read_cycle_days&&<small className="sl-sub"> platform default</small>}</div>
          <div><small className="sl-sub">Next read</small><strong>{fmtDateTime(d.schedule?.next_read)}</strong></div>
          <div><small className="sl-sub">Last read</small><strong>{fmtDateTime(d.schedule?.last_read)}</strong></div>
          <div><small className="sl-sub">Due within 7 / 30 days</small><strong>{fmtNumber(d.schedule?.due_7_days)} / {fmtNumber(d.schedule?.due_30_days)}</strong></div>
        </div>
        <p className="ad-note">Pages by state: {Object.entries(d.schedule?.by_status||{}).map(([k,n])=>`${k.replace(/_/g,' ')} ${fmtNumber(n)}`).join(' · ')||'none'}</p>
        {can&&a&&<div className="ad-actions"><Button compact disabled={busy} onClick={setCycle}><CalendarClock size={13}/> Set the read cycle</Button></div>}
        <RereadPanel ids={[pid]} names={[row.name]} can={can} onDone={refresh} onError={onError}/>
      </Block>

      <Block id="central" title="Central pages (English, key dates)" meta={`${fmtNumber((d.central_pages||[]).length)} attached`}>
        {can&&<AttachPage u={u} onDone={refresh} onError={onError}/>}
        {(d.central_pages||[]).length>0?<ul className="tn-list uc-pages">{d.central_pages.map((p,i)=><li key={i}><Pill tone={p.status==='read'||p.status==='parsed'?'success':p.status==='found'?'warning':'neutral'}>{p.kind==='english_policy'?'English':'Key dates'} · {String(p.status).replace(/_/g,' ')}</Pill> <a className="cf-link" href={p.url} target="_blank" rel="noreferrer">{p.url}</a>{p.read_at&&<small className="sl-sub"> read {fmtDateTime(p.read_at)}</small>}{p.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(p.evidence_id)}`}> evidence</a>}</li>)}</ul>:<p className="ad-note">No central page attached.</p>}
        <p className="ad-note">A central page is read through Firecrawl and parsed into a proposal. Approve it in <a className="cf-link" href="#layer-4-review?tab=attributes">Layer 4 Review › Attributes</a>. The central rule fills courses whose own page gives no value.</p>
      </Block>

      <Block id="fees" title="Fee range and rules" meta="Indicative whole-course fees">
        <FeeRangePanel u={u} can={can} onDone={onChanged} onError={onError}/>
      </Block>

      <Block id="hosted" title="Hosted courses" meta="Exit and nested awards, shared pages, double degrees">
        <HostedPanel u={u} can={can} onError={onError}/>
      </Block>

      <Block id="firecrawl" title="Firecrawl target" meta={row.target?(row.target.included?'In the targets':'Out of the targets'):'Not in the target list'}>
        <p className="ad-note">{row.target?.included?'Firecrawl may be used for this university: pages that refuse a plain read, and searching its site for missing course pages.':'Firecrawl is not used for this university. Its pages are read plainly where they can be.'}{row.target?.override_reason?` Set by hand: ${row.target.override_reason}.`:row.target?.rule_match?' Matched by the targets rule.':''}</p>
        {can&&<Button compact disabled={busy} onClick={()=>target(!row.target?.included)}>{row.target?.included?'Take out of the targets':'Add to the targets'}</Button>}
      </Block>

      <Block id="history" title="History" meta={`${fmtNumber((d.tasks||[]).length)} tasks · ${fmtNumber((d.log||[]).length)} changes`} data-adapter-history={pid}>
        {(d.tasks||[]).length>0?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Task</th><th>State</th><th>When</th></tr></thead><tbody>
          {d.tasks.map(j=><tr key={j.id}><td>{j.title}<small className="sl-sub">{KIND_LABEL[j.kind]||j.kind}</small></td><td><Pill tone={STATE_TONE[j.state]||'neutral'}>{j.state}</Pill></td><td>{fmtDateTime(j.finished_at||j.created_at)}</td></tr>)}
        </tbody></table></div>:<p className="ad-note">No tasks yet.</p>}
        {(d.log||[]).length>0&&<ul className="tm-events">{d.log.map((e,i)=><li key={i}><small className="sl-sub">{fmtDateTime(e.at)}{e.by?` · ${e.by}`:''}</small> {ACTION_LABEL[e.action]||e.action.replace(/_/g,' ')}{e.detail?.on!=null?` ${e.detail.on?'on':'off'}`:''}{e.detail?.days!==undefined?` ${e.detail.days??'default'}`:''}{e.detail?.fields?`: ${(e.detail.fields||[]).join(', ')}`:''}{e.detail?.reason?` · ${e.detail.reason}`:''}</li>)}</ul>}
        <p className="ad-note">Every task, with its full result, is also under <a className="cf-link" href="#scheduled-jobs?tab=jobs">Scheduled jobs › Jobs</a>. Running tasks are in the Task manager.</p>
      </Block>

      <Block id="courses" title="Courses" meta={`${fmtNumber(d.courses)} courses · ${fmtNumber(d.pages_read)} pages read`}>
        <CourseTable u={u} onError={onError}/>
        <p className="sl-sub uc-legend">Where a value came from: <SourcePill source="adapter"/> <SourcePill source="central"/> <SourcePill source="reader"/> <SourcePill source="hand"/> <SourcePill source="missing"/></p>
      </Block>
      </>}
    </div>}
  </article>
}

// ---- the many ticked -------------------------------------------------------------------------------------------------
function Bulk({ids,rows,settings,can,canQualify,onClear,onChanged,onError}){
  const[busy,setBusy]=useState(false),[reread,setReread]=useState(false)
  const withAdapter=rows.filter(r=>r.adapter).map(r=>r.provider_id)
  const on=rows.filter(r=>r.adapter&&r.adapter.state!=='off').map(r=>r.provider_id)
  const passing=rows.filter(r=>r.adapter&&r.adapter.state!=='off'&&(r.qualify?.passing||[]).some(f=>!(r.adapter.fields||[]).includes(f))).map(r=>r.provider_id)
  const call=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_adapters',{p_action:action,p_args:{...args,reason}});if(error)throw error;onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const cycle=()=>{const v=window.prompt(`Read the pages of the ${fmtNumber(withAdapter.length)} ticked universities with an adapter again every how many days? ${settings.read_cycle_min} to ${settings.read_cycle_max}. Leave empty for the platform default (${settings.read_cycle_default} days).`,'')
    if(v===null)return;const days=v.trim()===''?null:Number(v);if(days!==null&&!(Number.isInteger(days)&&days>=settings.read_cycle_min&&days<=settings.read_cycle_max)){onError?.(`The read cycle is ${settings.read_cycle_min} to ${settings.read_cycle_max} days, or empty for the default.`);return}
    call('set_cycle',{provider_ids:withAdapter,days},`Set the read cycle of ${fmtNumber(withAdapter.length)} universities to ${days??`the default (${settings.read_cycle_default})`} days?`)}
  return <div className="ad-bulk" data-adapters-bulk>
    <strong>{fmtNumber(ids.length)} ticked</strong><small className="sl-sub">{fmtNumber(withAdapter.length)} with an adapter · {fmtNumber(on.length)} switched on · {fmtNumber(passing.length)} with a passing field not yet admitted</small>
    <JobButton kind="qualify_adapters" scope="adapters" args={{provider_ids:on,adapter_state:'any'}} label={`Qualify ${fmtNumber(on.length)}`} disabled={!canQualify||on.length===0}
      question={`Qualify the ${fmtNumber(on.length)} ticked adapters that are switched on? It measures only. Nothing is admitted.`} onFinished={onChanged}/>
    <JobButton kind="admit_qualified" scope="adapters" args={{provider_ids:passing}} label={`Admit ${fmtNumber(passing.length)}`} disabled={!can||passing.length===0} variant={undefined}
      question={`Admit the fields that passed in each adapter's latest Qualify, for ${fmtNumber(passing.length)} adapters? Fields already admitted stay. Values entered or locked by hand are never changed.`} onFinished={onChanged}/>
    {can&&<Button compact disabled={busy||withAdapter.length===0} onClick={()=>call('set_on',{provider_ids:withAdapter,on:true},`Switch on ${fmtNumber(withAdapter.length)} adapters?\n\n${ON_EFFECT}`)}><Power size={13}/> Switch on</Button>}
    {can&&<Button compact disabled={busy||on.length===0} onClick={()=>call('set_on',{provider_ids:on,on:false},`Switch off ${fmtNumber(on.length)} adapters?\n\n${OFF_EFFECT}`)}><Power size={13}/> Switch off</Button>}
    {can&&<Button compact disabled={busy||withAdapter.length===0} onClick={cycle}><CalendarClock size={13}/> Read cycle</Button>}
    <Button compact onClick={()=>setReread(!reread)} aria-expanded={reread}>Read pages again…</Button>
    <Button compact onClick={onClear}>Clear</Button>
    {reread&&<div style={{flexBasis:'100%'}}><RereadPanel ids={ids} names={rows.map(r=>r.name)} can={can} onClose={()=>setReread(false)} onDone={onChanged} onError={onError}/></div>}
  </div>
}

// ---- the screen ------------------------------------------------------------------------------------------------------
// Decision 255 (6 Oct 2026), Rule 2 (8 Oct 2026): a read-only measure of the page-fee rule. It changes nothing; a card that is closed reads nothing.
function FeeRulesReport({onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false)
  const run=()=>{setBusy(true);supabase.rpc('admin_fee_rules_report',{p_args:{}}).then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{run()},[])
  if(!d)return <p className="ad-note">{busy?'Measuring…':'No report yet.'}</p>
  const row=(k,v,t)=><tr key={k}><th scope="row">{k}</th><td>{fmtNumber(v)}</td><td>{t}</td></tr>
  return <div data-fee-rules-report>
    <p className="ad-note">Rule 2 (8 Oct 2026): the CRICOS registered fee is held until the provider's own course page gives an annual international fee with captured evidence; the page fee then wins with no review, whatever year it names. A page's fee is compared here with the CRICOS registered total divided by the course's duration; "Differs" means more than {share(d.tolerance)} apart. Nothing is written: both fees stay stored and the course uses the page fee. A fee entered or locked by hand keeps the earlier rule.</p>
    <table className="m-table"><tbody>
      {row('Compared',d.compared,'Courses with a page fee and a CRICOS total')}
      {row('Agree',d.agree,'Nothing to decide')}
      {row('Differ',d.differ,'')}
      {row('Page fee used',d.would_change,`${fmtNumber(d.page_higher)} higher, ${fmtNumber(d.page_lower)} lower than CRICOS; ${fmtNumber(d.gap_over_20)} differ by more than 20%`)}
      {row('Of which: possible half-year fee',d.suspected_half,'The page fee is about half of CRICOS a year (sometimes a per-semester fee). Shown for information; the page fee is used')}
      {row('CRICOS held: no captured evidence',d.kept_no_evidence,'The page fee has no evidence on record')}
      {row('CRICOS held: not the provider\'s own site',d.kept_other_site,'Read from a site shared by several providers (Rule 1)')}
      {row('Protected: entered or locked by hand',d.protected_by_hand,'Never overwritten')}
    </tbody></table>
    <h4>By university (most changes first)</h4>
    <table className="m-table"><thead><tr><th>University</th><th>Compared</th><th>Page fee used</th></tr></thead><tbody>
      {(d.by_provider||[]).map(r=><tr key={r.provider_id}><td>{r.provider}</td><td>{fmtNumber(r.compared)}</td><td>{fmtNumber(r.would_change)}</td></tr>)}
    </tbody></table>
    {(d.suspected_half_sample||[]).length>0&&<div data-fee-suspected-half>
      <h4>Suspected half-year fees</h4>
      <table className="m-table"><thead><tr><th>Course</th><th>University</th><th>Page fee</th><th>CRICOS a year</th></tr></thead><tbody>
        {d.suspected_half_sample.map(r=><tr key={r.course_id}><td>{r.title}</td><td>{r.provider}</td><td>{fmtNumber(r.page_fee)}</td><td>{fmtNumber(r.cricos_per_year)}</td></tr>)}
      </tbody></table>
    </div>}
    <h4>Largest gaps</h4>
    <table className="m-table"><thead><tr><th>Course</th><th>University</th><th>Page fee</th><th>Page year</th><th>CRICOS a year</th><th>Gap</th></tr></thead><tbody>
      {(d.sample||[]).map(r=><tr key={r.course_id}><td>{r.title}</td><td>{r.provider}</td><td>{fmtNumber(r.page_fee)}</td><td>{r.page_year}</td><td>{fmtNumber(r.cricos_per_year)}</td><td>{share(r.gap)}</td></tr>)}
    </tbody></table>
    <Button compact onClick={run} disabled={busy}>Measure again</Button>
  </div>
}

const FILTERS={country:'',state:'',kind:'university',adapter:'',qualify:'',target:'',q:''}
function readFilters(){try{return{...FILTERS,...JSON.parse(window.sessionStorage.getItem('cf.adapters.filters')||'{}')}}catch{return FILTERS}}

export default function AdaptersWorkspace({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[f,setF]=useState(readFilters),[picked,setPicked]=useState([]),[open,setOpen]=useState(null),[shown,setShown]=useState(PAGE),[fr,setFr]=useState(null)
  const fail=e=>{setErr(e);onError?.(e)}
  const load=()=>{setBusy(true);supabase.rpc('admin_adapters',{p_action:'list',p_args:{}}).then(({data,error})=>{if(error)throw error;setData(data);setErr('')}).catch(e=>fail(errText(e))).finally(()=>setBusy(false))
    supabase.rpc('admin_provider_fee_range',{p_action:'read',p_args:{}}).then(({data,error})=>{if(error)throw error;setFr(data)}).catch(()=>{})}
  useEffect(()=>{load()},[])
  useEffect(()=>{try{window.sessionStorage.setItem('cf.adapters.filters',JSON.stringify(f))}catch{}setShown(PAGE)},[f])
  const set=(k,v)=>setF(x=>({...x,[k]:v,...(k==='country'?{state:''}:{})}))
  const all=data?.adapters||[]
  const settings=data?.settings||{}
  const can=Boolean(data?.can_manage),canQualify=Boolean(data?.can_qualify)
  const rangeOf=useMemo(()=>Object.fromEntries((fr?.ranges||[]).map(r=>[r.provider_id,r])),[fr])
  const countries=useMemo(()=>[...new Set(all.map(r=>r.country).filter(Boolean))].sort(),[all])
  const states=useMemo(()=>[...new Set(all.filter(r=>!f.country||r.country===f.country).map(r=>r.state).filter(Boolean))].sort(),[all,f.country])
  const rows=useMemo(()=>{const q=f.q.trim().toLowerCase();return all.filter(r=>(!f.country||r.country===f.country)&&(!f.state||r.state===f.state)&&(f.kind!=='university'||r.university)
    &&(!f.adapter||(f.adapter==='none'?!r.adapter:r.adapter?.state===f.adapter))
    &&(!f.qualify||(f.qualify==='never'?!r.qualify:f.qualify==='passing'?(r.qualify?.passing||[]).length>0:f.qualify==='waiting'?r.adapter&&r.adapter.state!=='off'&&(r.qualify?.passing||[]).some(x=>!(r.adapter.fields||[]).includes(x)):r.qualify&&(r.qualify.passing||[]).length===0))
    &&(!f.target||(f.target==='in'?r.target?.included:!r.target?.included))&&(!q||r.name.toLowerCase().includes(q)))},[all,f])
  const tally=useMemo(()=>{const t={admitting:0,testing:0,off:0,none:0};for(const r of rows)t[r.adapter?.state||'none']++;return t},[rows])
  const pick=id=>setPicked(p=>p.includes(id)?p.filter(x=>x!==id):[...p,id])
  const allTicked=rows.length>0&&rows.every(r=>picked.includes(r.provider_id))
  const tickAll=()=>setPicked(allTicked?picked.filter(id=>!rows.some(r=>r.provider_id===id)):[...new Set([...picked,...rows.map(r=>r.provider_id)])])
  const pickedRows=useMemo(()=>all.filter(r=>picked.includes(r.provider_id)),[all,picked])
  // From a link elsewhere on this screen (the Firecrawl targets, what each university needs next): show that one row, open, with its builder.
  const openRow=(id,block='build')=>{const r=all.find(x=>x.provider_id===id);if(r){if(block)rememberOpen(`adapters.block.${block}`);setF({...FILTERS,kind:'any',q:r.name});setOpen(id)}}

  return <div className="m-page-stack" data-adapters-workspace>
    <section className="m-panel" data-adapters-list>
      <SectionTitle title="Adapters" subtitle="One row per university with an adapter or in the Firecrawl targets. Open a row for everything about that university. Tick rows to act on many."
        action={<Button compact className="cf-icon-btn" title="Refresh" aria-label="Refresh" onClick={load} disabled={busy}><RefreshCw size={14}/></Button>}/>
      {err&&<div className="dq-alert"><span>{err}</span></div>}
      <div className="ad-filters" role="group" aria-label="Filter adapters">
        <label><span>Country</span><select aria-label="Adapters country" value={f.country} onChange={e=>set('country',e.target.value)}><option value="">All</option>{countries.map(c=><option key={c} value={c}>{COUNTRY[c]||c}</option>)}</select></label>
        <label><span>State or province</span><select aria-label="Adapters state" value={f.state} onChange={e=>set('state',e.target.value)}><option value="">All</option>{states.map(s=><option key={s} value={s}>{s}</option>)}</select></label>
        <label><span>Provider kind</span><select aria-label="Provider kind" value={f.kind} onChange={e=>set('kind',e.target.value)}><option value="university">Universities</option><option value="any">Any provider</option></select></label>
        <label><span>Adapter</span><select aria-label="Adapter state" value={f.adapter} onChange={e=>set('adapter',e.target.value)}><option value="">Any</option><option value="admitting">Admitting</option><option value="testing">Testing (on, not admitting)</option><option value="off">Switched off</option><option value="none">No adapter</option></select></label>
        <label><span>Latest Qualify</span><select aria-label="Latest Qualify" value={f.qualify} onChange={e=>set('qualify',e.target.value)}><option value="">Any</option><option value="waiting">Passed, not yet admitted</option><option value="passing">A field passed</option><option value="failing">Nothing passed</option><option value="never">Not qualified yet</option></select></label>
        <label><span>Firecrawl</span><select aria-label="Firecrawl target" value={f.target} onChange={e=>set('target',e.target.value)}><option value="">Any</option><option value="in">Target</option><option value="out">Not a target</option></select></label>
        <label><span>Find</span><input type="search" aria-label="Find a university" placeholder="Name…" value={f.q} onChange={e=>set('q',e.target.value)}/></label>
        <Button compact onClick={()=>setF(FILTERS)}>Reset</Button>
      </div>
      {!data?<Loading label="Loading adapters…"/>:<>
        <p className="ad-note" data-adapters-tally>{fmtNumber(rows.length)} shown of {fmtNumber(all.length)} · admitting {fmtNumber(tally.admitting)} · testing {fmtNumber(tally.testing)} · switched off {fmtNumber(tally.off)} · no adapter {fmtNumber(tally.none)}</p>
        <label className="tn-check"><input type="checkbox" checked={allTicked} onChange={tickAll} aria-label="Tick every row shown"/> Tick every row shown ({fmtNumber(rows.length)})</label>
        {picked.length>0&&<Bulk ids={picked} rows={pickedRows} settings={settings} can={can} canQualify={canQualify} onClear={()=>setPicked([])} onChanged={load} onError={fail}/>}
        <div className="ad-list">
          {rows.slice(0,shown).map(r=><Row key={r.provider_id} row={r} settings={settings} can={can} canQualify={canQualify} picked={picked.includes(r.provider_id)} onPick={pick} open={open===r.provider_id} onOpen={setOpen} onChanged={load} onError={fail} rangeOf={rangeOf}/>)}
          {rows.length===0&&<Empty text="No university matches these filters."/>}
        </div>
        {rows.length>shown&&<div className="ad-more"><Button compact onClick={()=>setShown(shown+PAGE*2)}>Show {fmtNumber(Math.min(PAGE*2,rows.length-shown))} more ({fmtNumber(rows.length-shown)} left)</Button></div>}
        {data.as_at&&<small className="sl-sub">As at {fmtDateTime(data.as_at)}.</small>}
      </>}
    </section>

    {/* v2.15.213: the university list comes first; the dry run and settings sit below it. */}
    <Card id="adapters.how" title="How an adapter goes from built to admitting" meta={<span>Build · Qualify · Admit · Schedule</span>} data-adapters-how>
      <ol className="tn-steps">
        <li><strong>Build</strong> the adapter in its row (Build and test the adapter): the visual builder picks each field on a stored page, Preview tries it on stored pages, Save keeps it, Apply reads the stored pages again with it.</li>
        <li><strong>Qualify</strong> it: a task that measures what it reads against the admission rules. It admits nothing.</li>
        <li><strong>Admit</strong> the fields that passed: a separate task, a Platform Admin with a reason. Values entered or locked by hand are never changed.</li>
        <li><strong>Schedule</strong>: every page read is read again on its cycle (platform default {fmtNumber(settings.read_cycle_default)} days, or the university's own). Only a changed page produces new evidence for the adapter to read.</li>
        <li><strong>Switch off</strong> to stop it: {OFF_EFFECT}</li>
      </ol>
    </Card>
    <Card id="adapters.firecrawl-runs" title="Firecrawl runs" subtitle="Read pages and Find pages for the Firecrawl targets, started as tasks." data-adapters-firecrawl-runs><FirecrawlRuns onError={fail}/></Card>
    <Card id="adapters.firecrawl-targets" title="Firecrawl targets and credits spent" subtitle="The universities Firecrawl is used for, and the credits spent this period." data-adapters-firecrawl-targets><FirecrawlTargets onError={fail} onOpen={openRow}/></Card>
    <Card id="adapters.next" title="What each university needs next" subtitle="Rules learnt from the first adapters: find pages first, an adapter for page data, start dates or English, or admitted as it is." data-adapters-next><AdapterEvaluation onPick={openRow} onError={fail}/></Card>
    <Card id="adapters.fee-rules" title="Page fees against CRICOS (dry run)" subtitle="What the page-fee rules would change. Read only; nothing is applied." data-adapters-fee-rules><FeeRulesReport onError={fail}/></Card>
    <Card id="adapters.settings" title="Fee range and award link settings" subtitle="Settings that apply to every university's fee range and hosted courses." data-adapters-settings>
      <FeeRangeSettings d={fr} can={can} onDone={load} onError={fail}/>
      <AwardLinkSettings can={can} onError={fail}/>
      <p className="ad-note">Qualify thresholds (read on {share(settings.min_read_share)} of pages, agree on {share(settings.min_agree_share)}) are Firecrawl settings on <a className="cf-link" href="#models-services">Platform settings › Models &amp; services</a>.</p>
    </Card>
  </div>
}
