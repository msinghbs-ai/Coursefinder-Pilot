// CF-247 F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): the Data Delivery summary at the TOP of Layer 2/3 > Operations. "I should not have to rely on your chat messages
// to know whether StudySearch is processing, admitting or publishing data."
// One row per data stream: coverage (n of N), net admission gain over the short and long windows (admitted minus withdrawn, from each stream's own ledger
// timestamps), Website and Zoho state, queue, holds with the largest exact reasons, processing speed, last and next run, and the automatic recovery status.
// It reuses the lane funnels below it (queue and hold stages, the reason breakdown), the Provider Catalogue and the Course Catalogue for drill-down; it
// is not another dashboard. Server: public.admin_layer23('data_delivery') (rank 3 and above, the same gate as Operations; SELECT only, counted by job
// data-delivery). It reloads itself at the interval in Pipeline settings > Data delivery (stops while the tab is hidden), and has a Refresh button.
// Unknown is never 0: a measure that is not counted, not built or failed shows "Not measured" or "Unknown" with the reason. A green job that admitted nothing
// in the window carries a visible flag that links to the reason breakdown. Times are Melbourne time, to the second where the page was read.
import React,{useCallback,useEffect,useRef,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber,fmtRelative,fmtTimeSeconds}from'./ui-kit'
import{fmtMoney}from'./lib/format'
import{plainError}from'./lib/errors'
import'./data-delivery.css'

const READ_TIMEOUT_MS=20000 // fixed: an API time-out for one read, so a hung request cannot halt the reload loop
const stampOf=v=>fmtTimeSeconds(v,null)
const num=x=>x==null?'':fmtNumber(Number(x))
const hoursText=h=>{const n=Number(h);return n===168?'7 d':n%24===0&&n>=48?`${n/24} d`:`${fmtNumber(n)} h`}
const ago=(iso,now)=>iso?fmtRelative(iso,'',now):''
function until(iso,now){if(!iso)return'';const s=Math.round((new Date(iso).getTime()-now)/1000);if(!(s>-60))return'due now';if(s<60)return'in under a minute';if(s<3600)return`in ${Math.round(s/60)} min`;if(s<86400)return`in ${Math.round(s/3600)} h`;return`in ${Math.round(s/86400)} days`}
const RECOVERY={healthy:['success','Retrying on schedule'],recovering:['info','Recovering'],needs_attention:['warning','Needs attention'],failing:['danger','Last run failed'],off:['warning','Off'],paused:['warning','Paused'],stalled:['warning','Stalled'],unknown:['neutral','Unknown']}
const FLAG_TONE={warn:'warning',bad:'danger',info:'neutral'}

/** The word shown when a figure is not counted: never 0, never blank, with the reason beside it. */
function Unknown({reason,word='Not measured'}){return <span className="dd-unknown" data-dd-unknown><em>{word}</em>{reason&&<small title={reason}>{reason}</small>}</span>}
function Stale({m}){
  if(!m)return null
  // a failed recount keeps the last good figures: they are shown, marked Stale, with the error beside them (never replaced by 0 or blank)
  if(m.count_error)return <><StatusChip tone="warning" label="Stale" title={`Last good count ${m.age_minutes??'?'} min ago`}/><small data-dd-count-error title={m.count_error}>The latest count failed ({m.count_error}); these are the last good figures.</small></>
  return m.stale?<StatusChip tone="warning" label="Stale" title={`Counted ${m.age_minutes??'?'} min ago`}/>:null
}

function href(screen,filters,extra){return hrefFor(screen,'',Object.fromEntries([...Object.entries(filters||{}).map(([k,v])=>[`f_${k}`,v]),...Object.entries(extra||{}).map(([k,v])=>[`f_${k}`,v])]))}

function Coverage({c,unit,note}){
  if(!c?.known)return <Unknown reason={c?.reason} word="Unknown"/>
  const pct=c.pct==null?null:`${fmtNumber(Number(c.pct),{maxDecimals:1})}%`
  return <span data-dd-value={c.n}><strong>{num(c.n)}</strong>{c.total!=null&&<> of {num(c.total)}</>} <small>{unit}</small>
    {pct&&<span className="dd-bar" role="img" aria-label={`${pct} covered`}><i style={{width:`${Math.min(100,Number(c.pct))}%`}}/></span>}
    <small>{pct?`${pct} covered. `:''}{note&&<span data-dd-coverage-note>{note} </span>}{c.total==null&&<span data-dd-total-unknown title={c.total_reason}>Total not measured: {c.total_reason}. </span>}<Stale m={c}/></small></span>
}
function Net({n,hours,unit}){
  if(!n?.known)return <Unknown reason={n?.reason} word="Unknown"/>
  // a stream whose ledger holds no dated admission cannot say how many it admitted: Unknown, never a bold 0
  if(n.admitted_known===false)return <span data-dd-net="unknown" data-dd-admitted-unknown><Unknown reason={n.admitted_reason} word="Unknown"/><Stale m={n}/></span>
  const net=n.net,added=Number(n.added),removed=n.removed==null?null:Number(n.removed)
  const sign=v=>v>0?`+${fmtNumber(v)}`:v<0?`−${fmtNumber(Math.abs(v))}`:'0'
  const what=unit||'items'
  return <span data-dd-net={net==null?'unknown':net} data-dd-added={added}>
    {net==null?<><strong>{sign(added)}</strong> <small>{what} created</small></>:<strong>{sign(Number(net))}</strong>}
    <small>{fmtNumber(added)} {what} in{removed==null?'':` · ${fmtNumber(removed)} out`}{removed==null&&<span data-dd-removed-unknown title={n.removed_reason}>; no net: {n.removed_reason}</span>}</small>
    {n.partial&&<small data-dd-partial>{n.since?`Ledger starts ${fmtDateTime(n.since)}`:'No ledger events yet'}, shorter than {hoursText(hours)}</small>}
    <Stale m={n}/></span>
}
function Feed({f,drillLinks,unit}){
  if(!f?.known)return <Unknown reason={f?.reason}/>
  return <span data-dd-value={f.matched}><strong>{num(f.matched)}</strong> <small>of {num(f.expected)} {unit||'items'} matched</small>
    <small>{f.pending==null?<span data-dd-pending-unknown title={f.pending_reason}>pending: not measured</span>:drillLinks.pending?<a href={drillLinks.pending} data-dd-drill="pending">{num(f.pending)} pending</a>:<>{num(f.pending)} pending</>}{' · '}{drillLinks.missing?<a href={drillLinks.missing} data-dd-drill="missing">{num(f.missing)} missing</a>:<>{num(f.missing)} missing</>}{' · '}{num(f.not_applicable)} not applicable</small>
    <Stale m={f}/></span>
}
/** The age of one lane-funnel stage figure: a stalled lane-funnel job must not look current, so a stale or failed stage shows Stale with when it was counted and the error. */
function PartAge({x}){
  if(!x||!(x.stale||x.error))return null
  return <><StatusChip tone="warning" label="Stale" title={x.error||'The stage was not counted recently'}/><small data-dd-part-stale>{x.measured_at?`counted ${fmtDateTime(x.measured_at)} (${ago(x.measured_at,Date.now())})`:'not counted recently'}{x.error?`; the latest count failed (${x.error})`:''}</small></>
}
function Parts({p,label}){
  if(!p?.known)return <Unknown reason={p?.reason}/>
  return <span data-dd-value={p.n}><strong>{p.partial?'≥ ':''}{num(p.n)}</strong>
    {p.partial&&<small data-dd-partial>Some stages are not counted</small>}
    {(p.parts||[]).map(x=><small key={x.stage+x.title} data-dd-part={x.stage}>{x.title} {x.n==null?<em title={x.error||'not counted'}>unknown</em>:num(x.n)}<PartAge x={x}/></small>)}
    {p.causes_reason&&<small data-dd-causes-unknown>By cause: {p.causes_reason}</small>}</span>
}
function Holds({h}){
  if(!h?.known)return <Unknown reason={h?.reason}/>
  return <span data-dd-value={h.n}><strong>{h.partial?'≥ ':''}{num(h.n)}</strong>
    {h.partial&&<small data-dd-partial>Some stages are not counted</small>}
    {(h.parts||[]).map(x=><small key={x.stage+x.title} data-dd-part={x.stage}>{x.title} {x.n==null?<em title={x.error||'not counted'}>unknown</em>:num(x.n)}<PartAge x={x}/></small>)}
    {(h.reasons||[]).length>0&&<ul className="dd-reasons" data-dd-reasons>{h.reasons.map((r,i)=><li key={i}><span title={r.reason}>{r.reason}</span> <strong>{num(r.n)}</strong></li>)}</ul>}
    {h.causes_reason&&<small data-dd-causes-unknown>By cause: {h.causes_reason}</small>}</span>
}
function Speed({s}){
  if(!s?.known)return <Unknown reason={s?.reason}/>
  return <span data-dd-value={s.per_hour}><strong>{fmtNumber(Number(s.per_hour),{maxDecimals:1})}</strong> <small>per hour</small><small>{num(s.processed)} {s.basis||'items'} in {fmtNumber(Number(s.window_hours),{maxDecimals:1})} h</small></span>
}
function Runs({j,now}){
  if(!j?.known)return <Unknown reason={j?.reason} word="Unknown"/>
  const bad=j.last_status==='failed'
  return <span data-dd-last={j.last_run_at||''}>
    {j.history_stale&&<><StatusChip tone="warning" label="Stale" title={j.history_error||'The run history was not summarised recently'}/><small data-dd-history-stale>{j.history_measured_at?`run history counted ${fmtDateTime(j.history_measured_at)}`:'run history not counted yet'}{j.history_error?`; the latest summary failed (${j.history_error})`:''}</small></>}
    <small>Last</small> <strong>{fmtDateTime(j.last_run_at)}</strong> <small>{ago(j.last_run_at,now)}</small> <StatusChip tone={bad?'danger':j.last_status==='succeeded'?'success':'neutral'} label={bad?'Failed':j.last_status==='succeeded'?'OK':String(j.last_status||'').replaceAll('_',' ')||'Unknown'} title={j.last_message||undefined}/>
    <small>Next</small> {j.next_run_at?<><strong data-dd-next={j.next_run_at}>{fmtDateTime(j.next_run_at)}</strong> <small>{until(j.next_run_at,now)}</small></>:<em data-dd-unknown>{Number(j.active)>0?'Unknown':'Not scheduled (paused or off)'}</em>}</span>
}
function Recovery({r}){
  const[tone,label]=RECOVERY[r?.state]||RECOVERY.unknown
  return <span data-dd-recovery={r?.state||'unknown'}><StatusChip tone={tone} label={label}/><small>{r?.text}</small>{(r?.issue_refs||[]).length>0&&<small>Open: {r.issue_refs.join(', ')}</small>}</span>
}

/** One counted figure: a number from the server, or "Not measured" when the server did not send it. Never 0 for a figure that was not counted. */
function N({v,k,actor}){return v==null?<em data-dd-unknown data-dd-stage-n={k}>Not measured</em>:<strong data-dd-stage-n={k} data-dd-actor={actor||undefined}>{fmtNumber(Number(v))}</strong>}
function Row({k,label,v,actor,children}){return <li data-dd-stage-row={k}><span>{label}{actor&&<StatusChip tone={actor==='machine'?'info':'neutral'} label={actor==='machine'?'Machine rule':'Person'}/>}</span> <N v={v} k={k} actor={actor}/>{children}</li>}
/** The course description stages (CF-247 F-CDESC, Platform Admin 10 Nov 2026): counted live and exactly by the server when the page was read (no estimate, no forecast).
 *  Machine counts and person counts are labelled apart. A course that is not served to the Website (its provider is hidden, or Layer 4 blocks it) is shown on its own line; the course's own publication flag is not what the Website reads. Zoho is Not counted with the reason, never 0. */
function Stages({st}){
  if(!st)return null
  if(!st.known)return <div className="dd-stages-box" data-dd-stages="unknown"><h4 className="sl-h4">Course description stages</h4><Unknown reason={st.reason} word="Not counted"/></div>
  const src=st.source||{},pr=st.proposal||{},va=st.validation||{},ad=st.admitted||{},co=st.consumers||{},rb=co.machine_readback||{},zo=co.zoho||{}
  const reasons=va.top_decline_reasons||[]
  return <div className="dd-stages-box" data-dd-stages="known">
    <h4 className="sl-h4">Course description stages</h4>
    <p className="sl-sub" data-dd-stages-stamp>Counted live at {stampOf(st.counted_at)} (Melbourne), in {st.unit||'courses'}. Exact counts, no estimate. Machine-rule counts are kept apart from person counts.</p>
    <ol className="dd-stages">
      <li data-dd-stage="source"><h5>1. Source</h5><ul>
        <Row k="proposals_from_a_stored_page" label="Proposals read from a stored official page" v={src.proposals_from_a_stored_page}/></ul></li>
      <li data-dd-stage="proposal"><h5>2. AI proposal</h5><ul>
        <Row k="waiting_in_layer4" label="Waiting in Layer 4 for a decision" v={pr.waiting_in_layer4}/>
        <Row k="held_behind_provider_cap" label="Readings held behind a university's first waiting descriptions" v={pr.held_behind_provider_cap}/>
        <Row k="held_by_a_check" label="Readings held by a check (not proposed)" v={pr.held_by_a_check}/></ul></li>
      <li data-dd-stage="validation"><h5>3. Validation by the machine rule</h5><ul>
        <Row k="not_yet_checked_by_machine" label="Waiting, not yet looked at by the machine rule" v={va.not_yet_checked_by_machine} actor="machine"/>
        <Row k="declined_by_machine" label="Declined, left for a person" v={va.declined_by_machine} actor="machine">
          {reasons.length>0&&<ul className="dd-reasons" data-dd-decline-reasons>{reasons.map(r=><li key={r.code}><span title={r.example||undefined}>{String(r.code).replaceAll('_',' ')}</span> <strong>{fmtNumber(Number(r.n))}</strong></li>)}</ul>}</Row></ul></li>
      <li data-dd-stage="admitted"><h5>4. Admitted</h5><ul>
        <Row k="by_machine" label="Admitted by the machine rule" v={ad.by_machine} actor="machine"/>
        <Row k="by_person" label="Admitted by a person in Layer 4" v={ad.by_person} actor="person"/>
        <Row k="withdrawn" label="Machine admissions withdrawn" v={ad.withdrawn} actor="machine"/>
        <Row k="described_courses" label="Courses with a description in the catalogue" v={ad.described_courses}/>
        <Row k="described_other_route" label="of which by another route (neither of the above)" v={ad.described_other_route}/></ul></li>
      <li data-dd-stage="consumers"><h5>5. Website and Zoho</h5><ul>
        <Row k="website_published" label="Described courses served to the Website" v={co.website_published}/>
        <Row k="unpublished_course" label="Described courses not served to the Website (provider hidden or blocked in Layer 4)" v={co.unpublished_course}/>
        <li data-dd-stage-row="machine_readback"><span>Website read-back of machine admissions at admission <StatusChip tone="info" label="Machine rule"/></span>
          <small data-dd-readback>matched {num(rb.matched)} · lag {num(rb.lag)} · not in the feed {num(rb.not_in_feed)} · error {num(rb.error)}{Number(rb.not_checked)>0?` · not checked ${num(rb.not_checked)}`:''}. The detail function answered by identifier; that is not the same as listed and published.</small></li>
        <li data-dd-stage-row="zoho"><span>Zoho</span> {zo.known?<N v={zo.with_description} k="zoho"/>:<Unknown reason={zo.reason} word="Not counted"/>}</li></ul></li>
    </ol></div>
}

/** A counted US dollar figure from the server, or "Not measured" when the server did not send it. Cents, or four decimals under one cent (one provider read costs less than a cent), never rounded to 0. */
function Usd({v,k}){return v==null?<em data-dd-unknown data-dd-money={k}>Not measured</em>:<strong data-dd-money={k} data-dd-value={v}>{fmtMoney(Number(v),'USD',{decimals:Number(v)>0&&Number(v)<0.01?4:2})}</strong>}
/** The provider-description AI cost, remaining allowance and Basic to Enriched outcome (CF-247 F-PDESC, Platform Admin 10 Nov 2026 12:07): counted live and exactly by security.data_delivery_pdesc_v1 when the page was read.
 *  Machine-rule counts and person counts are labelled apart. Spend settled as an estimate is labelled estimated. A figure the server did not send is Not measured, never 0; a missing block (an older server) is Not measured as a whole. */
function ProviderAi({pa}){
  if(pa==null||pa.known===false)return <div className="dd-stages-box" data-dd-provider-ai="unknown"><h4 className="sl-h4">AI cost, admissions and Basic to Enriched upgrade</h4><Unknown reason={pa?.reason||'This count is not available from the server yet'} word="Not measured"/></div>
  const ai=pa.ai||{},ad=pa.admitted||{},up=pa.upgrade||{}
  const tops=up.top_hold_rules||[]
  return <div className="dd-stages-box" data-dd-provider-ai="known">
    <h4 className="sl-h4">AI cost, admissions and Basic to Enriched upgrade</h4>
    <p className="sl-sub" data-dd-provider-ai-stamp>Counted live at {stampOf(pa.counted_at)} (Melbourne), in {pa.unit||'providers'}. Exact counts, no estimate except where a line says estimated. Machine-rule counts are kept apart from person counts.</p>
    <ol className="dd-stages dd-stages-3">
      <li data-dd-pdesc-stage="ai_cost"><h5>1. AI cost and remaining allowance</h5><ul>
        <li data-dd-stage-row="ai_spent"><span>Spent on provider descriptions</span> <Usd v={ai.spent_usd} k="spent"/><small>{ai.calls==null?'calls not measured':`${fmtNumber(Number(ai.calls))} paid calls`}</small></li>
        <li data-dd-stage-row="ai_reserved"><span>Reserved by reads in progress or unsettled</span> <Usd v={ai.reserved_usd} k="reserved"/><small>{ai.reserved_reads==null?'reads not measured':`${fmtNumber(Number(ai.reserved_reads))} reads`}</small></li>
        <li data-dd-stage-row="ai_ceiling"><span>Ceiling set for the lane</span> <Usd v={ai.ceiling_usd} k="ceiling"/></li>
        <li data-dd-stage-row="ai_remaining"><span>Remaining allowance (ceiling less spent less reserved)</span> <Usd v={ai.remaining_usd} k="remaining"/></li>
        <li data-dd-stage-row="ai_today"><span>Spent today (UTC day) against the daily guard</span> <Usd v={ai.today_usd} k="today"/><small data-dd-daily>{ai.daily_guard_usd==null?'Daily guard: Not measured':<>Daily guard <Usd v={ai.daily_guard_usd} k="guard"/>, left today <Usd v={ai.daily_remaining_usd} k="daily_remaining"/></>}</small></li>
        <li data-dd-stage-row="ai_settled"><span>Reservations settled as an estimate <StatusChip tone="warning" label="Estimated"/></span> <N v={ai.settled_estimated_reads} k="settled_reads"/><small data-dd-settled>{ai.settled_estimated_usd==null?'Amount: Not measured':<>summed <Usd v={ai.settled_estimated_usd} k="settled_usd"/> estimated. The call was assumed made; the provider never reported its cost.</>}</small></li></ul></li>
      <li data-dd-pdesc-stage="admitted"><h5>2. Admitted, by route</h5><ul>
        <Row k="ai_first_description" label="Descriptions written by the AI from an official page (first descriptions)" v={ad.ai_first_description} actor="machine"/>
        <Row k="ai_upgrade" label="Descriptions written by the AI from an official page (upgrades of a Basic profile)" v={ad.ai_upgrade} actor="machine"/>
        <Row k="registry_fact" label="Basic profiles built from the register (registry-fact route)" v={ad.registry_fact} actor="machine"/>
        <Row k="by_person" label="Admitted by a person in Layer 4" v={ad.by_person} actor="person"/>
        <Row k="withdrawn" label="Machine admissions withdrawn (not replaced by an upgrade)" v={ad.withdrawn} actor="machine"/></ul></li>
      <li data-dd-pdesc-stage="upgrade"><h5>3. Basic to Enriched upgrade</h5><ul>
        <Row k="upgrade_admitted" label="Upgraded to an Enriched description" v={up.admitted} actor="machine"/>
        <Row k="basic_profiles_held" label="Basic profiles still held (not upgraded yet)" v={up.basic_profiles_held}/>
        <Row k="upgrade_queued" label="Upgrade reads waiting for the reader" v={up.queued_reads}>
          {up.lane_on===false&&<small data-dd-upgrade-off>The upgrade lane is switched off, so no upgrade read is queued.</small>}</Row>
        <Row k="upgrade_held" label="Upgrade reads held, and why" v={up.held_reads}>
          {tops.length>0&&<ul className="dd-reasons" data-dd-upgrade-holds>{tops.map(r=><li key={r.rule}><span title={r.example||undefined}>{String(r.rule).replaceAll('_',' ')}</span> <strong>{fmtNumber(Number(r.n))}</strong></li>)}</ul>}</Row></ul></li>
    </ol></div>
}

function Stream({s,now,providerFilters,open,onToggle}){
  const dr=s.drill||{}
  const lanes=hrefFor('layer2','operations',{lane:s.lane})
  const filtersOk=dr.needs_provider_filters?providerFilters:true
  const link=(f,extra)=>dr.screen&&f&&filtersOk?href(dr.screen,f,extra):null
  const feedLink=(side,state)=>dr.screen==='providers'&&dr[side]&&providerFilters?href('providers',{[dr[side].key]:state}):null
  const flags=s.flags||[]
  const cells=[
    ['coverage','Coverage',<Coverage c={s.coverage} unit={s.unit} note={dr.coverage_note}/>],
    ['net_short',`Net ${hoursText(s.net_short?.window_hours)}`,<Net n={s.net_short} hours={s.net_short?.window_hours} unit={s.net_unit}/>],
    ['net_long',`Net ${hoursText(s.net_long?.window_hours)}`,<Net n={s.net_long} hours={s.net_long?.window_hours} unit={s.net_unit}/>],
    ['website','Website',<Feed f={s.website} unit={s.consumer_unit} drillLinks={{pending:feedLink('website','pending'),missing:feedLink('website','missing')}}/>],
    ['zoho','Zoho',<Feed f={s.zoho} unit={s.consumer_unit} drillLinks={{pending:feedLink('zoho','pending'),missing:feedLink('zoho','missing')}}/>],
    ['queue','Queue',<Parts p={s.queue}/>],
    ['holds','Holds and reasons',<Holds h={s.holds}/>],
    ['speed','Speed',<Speed s={s.speed}/>],
    ['runs','Last and next run',<Runs j={s.jobs} now={now}/>],
    ['recovery','Automatic recovery',<Recovery r={s.recovery}/>],
  ]
  const filled=link(dr.filled,{}),missing=link(dr.missing,{})
  return <details className="dd-stream" data-dd-stream={s.stream} data-dd-stale={s.stale?'true':'false'} open={open} onToggle={e=>onToggle(e.currentTarget.open)}>
    <summary>
      <div className="dd-name" data-dd-cell="name"><strong>{s.title}</strong>
        {flags.map(f=><span key={f.code} className={`dd-flag tone-${FLAG_TONE[f.severity]||'neutral'}`} data-dd-flag={f.code} data-dd-queue-empty={f.queue_empty?'true':undefined} role="status"><span>{f.text}</span>{f.code.startsWith('green')&&<> <a href={lanes} onClick={e=>e.stopPropagation()} data-dd-reasons-link>See reasons</a></>}</span>)}
      </div>
      {cells.map(([k,label,node])=><div className="dd-cell" key={k} data-label={label} data-dd-cell={k}>{node}</div>)}
    </summary>
    <div className="dd-body">
      <Stages st={s.stages}/>
      {s.stream==='pdesc'&&<ProviderAi pa={s.provider_ai}/>}
      <p><strong>What this stream is.</strong> {s.what}</p>
      <p><strong>How the gain is counted.</strong> {s.net_basis||'Not stated.'}{s.net_short?.removed_known?' Net = admitted minus withdrawn, from the ledger timestamps in the window.':''}</p>
      {(s.coverage?.by_country||[]).length>0&&<table className="cf-table dd-countries"><thead><tr><th>Country</th><th>Covered</th><th>Of</th></tr></thead><tbody>
        {s.coverage.by_country.map(c=><tr key={c.cc}><td data-label="Country">{c.cc}</td><td data-label="Covered">{num(c.n)}</td><td data-label="Of">{c.total==null?'Not measured':num(c.total)}</td></tr>)}</tbody></table>}
      <div className="dd-drill" data-dd-drill-box>
        <strong>Open in the catalogue</strong>
        {filled&&<a href={filled} data-dd-drill="filled">{dr.filled_label||'Filled'}</a>}{missing&&<a href={missing} data-dd-drill="missing">{dr.missing_label||'Missing'}</a>}
        {dr.screen&&!filled&&!missing&&dr.screen!=='providers'&&<a href={hrefFor(dr.screen)} data-dd-drill="open">Open the list</a>}
        <a href={lanes} data-dd-drill="lane">Reason breakdown</a>
        {dr.needs_provider_filters&&!providerFilters&&<small data-dd-degraded>Provider Catalogue filters (Filled, Missing, Website and Zoho state) arrive when the Provider Catalogue columns release is live; these links appear then.</small>}
        {dr.note&&<small data-dd-drill-note>{dr.note}</small>}
      </div>
      <h4 className="sl-h4">Primary jobs</h4>
      <div className="lf-frame"><table className="cf-table"><thead><tr><th>Job</th><th>Last run</th><th>Result</th><th>Next run</th><th>Runs ({hoursText(s.net_short?.window_hours)})</th></tr></thead><tbody>
        {(s.jobs?.list||[]).map(j=><tr key={j.job}><td data-label="Job">{j.job}{!j.scheduled&&<small> not scheduled</small>}</td><td data-label="Last run">{j.last_start?fmtDateTime(j.last_start):'Unknown'}</td>
          <td data-label="Result">{j.last_status?`${String(j.last_status).replaceAll('_',' ')}${j.last_message?`: ${j.last_message}`:''}`:'Unknown'}</td><td data-label="Next run">{j.next_run?fmtDateTime(j.next_run):j.scheduled?'Paused':'Unknown'}</td>
          <td data-label="Runs">{j.scheduled?`${num(j.succeeded)} ok, ${num(j.failed)} failed`:'Unknown'}</td></tr>)}</tbody></table></div>
    </div>
  </details>
}

export default function DataDelivery({rank=0,onError,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState(null),[busy,setBusy]=useState(false),[now,setNow]=useState(()=>Date.now()),[open,setOpen]=useState({})
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const last=useRef(0),inflight=useRef(false)
  const load=useCallback(async()=>{
    if(inflight.current)return
    inflight.current=true;setBusy(true)
    let timer=null
    // one hung request must not stop the polling: the read is abandoned after the time-out and the next tick asks again (fixed: an API time-out, not an operating value)
    const timeout=new Promise((_,no)=>{timer=setTimeout(()=>no(new Error('The read took too long and was stopped; it will be asked again')),READ_TIMEOUT_MS)})
    try{const{data,error}=await Promise.race([rpc('admin_layer23',{p_action:'data_delivery',p_args:{}}),timeout]);if(error)throw error
      if(!data||!Array.isArray(data.streams))throw new Error('The Data Delivery read returned no streams')
      setD(data);setErr(null);last.current=Date.now()}
    catch(e){const m=plainError(e);setErr({message:m,at:new Date().toISOString()});onError?.(m)}
    finally{clearTimeout(timer);inflight.current=false;setBusy(false);setNow(Date.now())}
  },[])
  useEffect(()=>{load()},[])
  const every=Math.max(15,Number(d?.ui_refresh_seconds||60))*1000
  useEffect(()=>{
    // reload on the setting's interval while the tab is visible; nothing runs while it is hidden, and a hidden tab reloads when shown if it is overdue
    const t=setInterval(()=>{if(document.visibilityState==='visible')load();else setNow(Date.now())},every)
    const tick=setInterval(()=>{if(document.visibilityState==='visible')setNow(Date.now())},15000)
    const vis=()=>{if(document.visibilityState==='visible'&&Date.now()-last.current>=every)load()}
    document.addEventListener('visibilitychange',vis)
    return()=>{clearInterval(t);clearInterval(tick);document.removeEventListener('visibilitychange',vis)}
  },[every,load])
  if(rank<3)return null
  if(!d)return <section className="m-panel dd" data-data-delivery aria-label="Data delivery">{err?<div role="alert" data-dd-error><p>Data delivery could not be read: {err.message}</p><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></div>:<Loading label="Reading data delivery…"/>}</section>
  const streams=d.streams||[]
  const flagged=streams.filter(s=>(s.flags||[]).some(f=>f.code==='green_no_admission'))
  const unknownAdm=streams.filter(s=>(s.flags||[]).some(f=>f.code==='green_admission_unknown'))
  const failing=streams.filter(s=>(s.flags||[]).some(f=>f.code==='job_failing'))
  const snap=d.snapshot||{}
  const age=snap.oldest_measured_at?Math.round((Date.now()-new Date(snap.oldest_measured_at).getTime())/60000):null
  return <section className="m-panel dd" data-data-delivery aria-label="Data delivery">
    <div className="cf-section-title"><div className="cf-section-heading"><h3>Data delivery</h3>
      <small>Is StudySearch processing, admitting and publishing data? Live from the database, by stream. &ldquo;Not measured&rdquo; and &ldquo;Unknown&rdquo; mean the figure is not counted here, never zero.</small></div>
      <Button compact onClick={load} disabled={busy} data-dd-refresh><RefreshCw size={14}/>Refresh</Button></div>
    <p className="sl-sub" data-dd-stamp>Updated <strong data-dd-updated>{stampOf(d.at)}</strong> (Melbourne). Reloads every {fmtNumber(every/1000)} s while this tab is open.
      {' '}Counts were taken {snap.newest_measured_at?`as recently as ${stampOf(snap.newest_measured_at)}`:'at an unknown time'}{age!=null?`, the oldest ${age} min ago`:''}.
      {Number(snap.failed_measures)>0&&<> <strong>{fmtNumber(snap.failed_measures)} measure(s) could not be counted.</strong></>}</p>
    {err&&<p role="alert" className="dd-stale" data-dd-stale-banner>The last refresh failed at {stampOf(err.at)} (Melbourne): {err.message}. These are the figures read at {stampOf(d.at)}; they may be out of date.</p>}
    {(flagged.length>0||failing.length>0||unknownAdm.length>0)&&<p className="dd-summary" data-dd-summary>{flagged.length>0&&<><strong>{flagged.length}</strong> stream{flagged.length===1?'':'s'} ran green but admitted nothing in {hoursText(d.windows?.short_hours)} ({flagged.map(s=>s.title).join(', ')}). </>}{unknownAdm.length>0&&<><strong>{unknownAdm.length}</strong> ran green with what they admitted unknown ({unknownAdm.map(s=>s.title).join(', ')}). </>}{failing.length>0&&<><strong>{failing.length}</strong> with a failed run ({failing.map(s=>s.title).join(', ')}).</>}</p>}
    <div className="dd-head" aria-hidden="true"><span>Stream</span><span>Coverage</span><span>Net {hoursText(d.windows?.short_hours)}</span><span>Net {hoursText(d.windows?.long_hours)}</span><span>Website</span><span>Zoho</span><span>Queue</span><span>Holds and reasons</span><span>Speed</span><span>Last and next run</span><span>Automatic recovery</span></div>
    <div className="dd-streams">{streams.map(s=><Stream key={s.stream} s={s} now={now} providerFilters={Boolean(d.provider_filters_available)} open={open[s.stream]??Boolean(s.stages||s.provider_ai)} onToggle={o=>setOpen(x=>({...x,[s.stream]:o}))}/>)}</div>
    <p className="sl-sub">Net = admitted minus withdrawn, from each stream&rsquo;s own ledger timestamps. A job the scheduler reports as OK says nothing about data: the flag shows when it admitted nothing. Reload interval, windows and the number of reasons are settings (Settings &rsaquo; Pipeline settings &rsaquo; Data delivery).</p>
  </section>
}
