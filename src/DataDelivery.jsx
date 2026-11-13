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
    </ol>
    <Flow fl={st.flow}/></div>
}
/** The course description flow (CF-247 F-CDESC decline throughput, Platform Admin 10 Nov 2026): the eligible denominator, the retained net gain, what is declined or held and why, the day's reads against the cap, the last and next run and the blocker, counted live by security.data_delivery_cdesc_flow_v1.
 *  An additive block: a server that does not send it (an older server), or one that could not count it, shows Not measured as a whole; a figure the server did not send is Not measured, never 0. */
function Flow({fl}){
  if(fl==null)return <div className="dd-flow" data-dd-flow="unknown"><h5>Flow of eligible courses</h5><Unknown reason="This count is not available from the server yet" word="Not measured"/></div>
  if(!fl.known)return <div className="dd-flow" data-dd-flow="unknown"><h5>Flow of eligible courses</h5><Unknown reason={fl.reason} word="Not measured"/></div>
  const el=fl.eligible||{},ga=fl.gain||{},rd=fl.reads||{},ru=fl.run||{}
  const cause=(list,k)=>(list||[]).length>0&&<ul className="dd-reasons" data-dd-flow-causes={k}>{list.map(r=><li key={r.code}><span>{String(r.code).replaceAll('_',' ')}</span> <strong>{fmtNumber(Number(r.n))}</strong></li>)}</ul>
  return <div className="dd-flow" data-dd-flow="known">
    <h5>Flow of eligible courses</h5>
    <p className="sl-sub">Eligible means the course has no description and holds a stored page whose identity is proved. Counted live; each figure is exact.</p>
    <ul>
      <Row k="flow_eligible" label="Eligible courses (no description, identity-proved stored page)" v={el.without_description}/>
      <Row k="flow_never_read" label="Not read yet" v={el.never_read}/>
      <Row k="flow_waiting" label="Waiting in Layer 4" v={el.waiting_in_layer4}/>
      <Row k="flow_held_cap" label="Held behind a university's first waiting descriptions" v={el.held_behind_provider_cap}/>
      <Row k="flow_held_check" label="Held by a check" v={el.held_by_a_check}>{cause(fl.held_by_cause,'held')}</Row>
      <Row k="flow_read_other" label="Read, other outcome" v={el.read_other}/>
      <Row k="flow_declined" label="Declined by the machine rule, by cause" v={fl.declined_by_cause==null||fl.declined_by_cause.some(r=>!Number.isFinite(Number(r.n)))?null:fl.declined_by_cause.reduce((a,r)=>a+Number(r.n),0)} actor="machine">{cause(fl.declined_by_cause,'declined')}</Row>
      <Row k="flow_admitted_24h" label="Admitted by the machine rule, last 24 hours (kept)" v={ga.admitted_24h} actor="machine"/>
      <Row k="flow_admitted_7d" label="Admitted by the machine rule, last 7 days (kept)" v={ga.admitted_7d} actor="machine"/>
      <Row k="flow_withdrawn_7d" label="Withdrawn, last 7 days" v={ga.withdrawn_7d} actor="machine"/>
      <Row k="flow_retained" label="Machine admissions kept in total (net gain)" v={ga.retained_total} actor="machine"/>
      <Row k="flow_reads_today" label="Course readings today" v={rd.today}><small>of a daily limit of {rd.daily_cap==null?<em data-dd-unknown>Not measured</em>:num(rd.daily_cap)}</small></Row>
      <Row k="flow_full" label="Universities with every place taken by waiting descriptions" v={rd.universities_with_all_places_taken}/>
      <Row k="flow_parked" label="Waiting for a person (declined for good by the machine rule)" v={rd.parked_for_a_person}/>
    </ul>
    <p className="sl-sub" data-dd-flow-run>Automatic admission {ru.automatic_admission_on==null?'not measured':ru.automatic_admission_on?'on':'off'}{' · '}last admission {ru.last_admission_at?fmtDateTime(ru.last_admission_at):'none yet'}{' · '}last decline {ru.last_decline_at?fmtDateTime(ru.last_decline_at):'none yet'}{' · '}schedule {ru.schedule||'not measured'}</p>
    {fl.blocker&&<p className="sl-sub" data-dd-flow-blocker><strong>Blocker:</strong> {fl.blocker}</p>}
  </div>
}

/** Why an intake outcome is skipped, kept apart: what is legitimately unresolvable (the page or calendar gives a month or season, no day: never invented), what a run can still take, and what waits for another fix or a decision. */
const INTAKE_SKIP={
  month_only:['Month or season only: no day (or no year) is printed','unresolvable'],
  page_date_waiting:['The stored page prints a full date and the intake has no date yet (the next hourly run checks it against the calendar)','recoverable'],
  page_only_unproven:['The page prints one date that no approved calendar start shares, and the audience is not shown (the Platform Admin decides the audience rule)','held'],
  identity:['The page is not proved to be the course’s own (E16)','held'],
  no_page_reading:['No stored reading of the course page','held'],
  waiting_for_period:['Waiting for the next academic year, or the date is past','held'],
  calendar_source:['The provider’s calendar is set aside or does not start the period that month','held'],
  person_decision:['Held for a person (locked, withdrawn or a course-level exception)','held'],
  other:['Another reason, as recorded','held']}
/** The intake stream's eligible denominator, new and retained admissions, skipped outcomes by cause, consumer publication and blockers (CF-247 F-INT, Platform Admin 10 Nov 2026 14:02): counted live and exactly by security.data_delivery_intake_v1
 *  when the page was read. Legitimately unresolvable (month or season only) is kept apart from what a run can still take and from what waits for another fix. A figure the server did not send is Not measured, never 0; a missing block (an older server) is Not measured as a whole. */
function IntakeDelivery({d}){
  if(d==null||d.known===false)return <div className="dd-stages-box" data-dd-intake-delivery="unknown"><h4 className="sl-h4">Eligible intakes, admissions, skipped causes and blockers</h4><Unknown reason={d?.reason||'This count is not available from the server yet'} word="Not measured"/></div>
  const dn=d.denominator||{},ad=d.admissions||{},wins=ad.windows||[],sk=d.skipped||{},now=sk.now||[],win=sk.window||[],pb=d.publication||{},bl=d.blockers||[],sw=d.switches||{}
  const nm=x=>x==null?'Not measured':fmtNumber(Number(x))
  const group=(kind)=>now.filter(r=>(INTAKE_SKIP[r.k]||INTAKE_SKIP.other)[1]===kind)
  const tech=bl.filter(b=>b.kind==='technical')
  const SkipList=({rows,k})=>rows.length>0?<ul className="dd-reasons" data-dd-intake-skips={k}>{rows.map(r=><li key={r.k}><span>{(INTAKE_SKIP[r.k]||INTAKE_SKIP.other)[0]}</span> <strong>{fmtNumber(Number(r.n))}</strong></li>)}</ul>:null
  const sum=(rows)=>rows.length?rows.reduce((a,r)=>a+Number(r.n),0):0
  return <div className="dd-stages-box" data-dd-intake-delivery="known">
    <h4 className="sl-h4">Eligible intakes, admissions, skipped causes and blockers</h4>
    <p className="sl-sub" data-dd-intake-delivery-stamp>Counted live at {stampOf(d.counted_at)} (Melbourne), in {d.unit||'intakes'}. Exact counts, no estimate. A month or season is never turned into a day.</p>
    <ol className="dd-stages dd-stages-3">
      <li data-dd-intake-stage="denominator"><h5>1. Eligible denominator</h5><ul>
        <Row k="active_intakes" label="Active intakes of active courses" v={dn.active_intakes}/>
        <Row k="exact_start" label="With an exact start date" v={dn.exact_start}/>
        <Row k="with_deadline" label="With an application deadline" v={dn.with_deadline}/>
        <Row k="eligible" label="Eligible: exact starts plus undated intakes at a provider whose approved calendar the plan reads" v={dn.eligible}/>
        <Row k="undated_eligible" label="Eligible and still undated" v={dn.undated_eligible}/>
        <Row k="undated_no_decision" label="Undated, not yet looked at: the provider has no approved calendar (a source gap, not a failure)" v={dn.undated_no_decision}/></ul></li>
      <li data-dd-intake-stage="admissions"><h5>2. New admissions and retained net gain</h5><ul>
        {wins.length===0?<li data-dd-stage-row="windows"><span>Admissions in the window</span> <N v={null} k="windows"/></li>:wins.map(w=><li key={w.hours} data-dd-stage-row={'window_'+w.hours}><span>Last {w.hours} hours: new start dates <StatusChip tone="info" label="Machine rule"/></span> <N v={w.new_start} k={'new_start_'+w.hours}/>
          <small data-dd-intake-window={w.hours}>retained now {nm(w.retained_start)} · gross fills {nm(w.gross)} · withdrawn {nm(w.withdrawn)} · net {nm(w.net)} · new deadlines {nm(w.new_deadline)} (retained {nm(w.retained_deadline)})</small></li>)}
        {(ad.by_rule||[]).length>0&&<li data-dd-stage-row="by_rule"><span>By rule, short window</span> <small>{(ad.by_rule||[]).map(r=>`${r.rule}: ${nm(r.filled)} filled${Number(r.withdrawn)>0?`, ${nm(r.withdrawn)} withdrawn`:''}`).join(' · ')}</small></li>}
        <li data-dd-stage-row="last_admitted"><span>Last admission / last processed</span> <small>{d.admissions?.last_admitted_at?stampOf(ad.last_admitted_at):'Not measured'} / {ad.last_processed_at?stampOf(ad.last_processed_at):'Not measured'}</small></li></ul></li>
      <li data-dd-intake-stage="skipped"><h5>3. Skipped, by cause</h5><ul>
        <Row k="skip_unresolvable" label="Legitimately unresolvable: month or season only" v={sum(group('unresolvable'))}><SkipList rows={group('unresolvable')} k="unresolvable"/></Row>
        <Row k="skip_recoverable" label="A run can still take: the stored page prints a date" v={sum(group('recoverable'))}><SkipList rows={group('recoverable')} k="recoverable"/>{sw.page_date_admit===false&&<small data-dd-route-off>The page-date route is switched off.</small>}</Row>
        <Row k="skip_held" label="Held for another fix or a decision" v={sum(group('held'))}><SkipList rows={group('held')} k="held"/></Row>
        <li data-dd-stage-row="skip_window"><span>Skipped events in the last {sk.window_hours==null?'?':sk.window_hours} hours (as recorded)</span> <N v={sk.window_events} k="skip_window"/><small>{sk.window_intakes==null?'':`${nm(sk.window_intakes)} intakes. `}{win.slice(0,6).map(r=>`${(INTAKE_SKIP[r.k]||INTAKE_SKIP.other)[0].split(':')[0]}: ${nm(r.n)}`).join(' · ')}</small></li></ul></li>
      <li data-dd-intake-stage="publication"><h5>4. Consumers and blockers</h5><ul>
        <li data-dd-stage-row="publication"><span>Decisions that hold a date, by publication check</span> {(pb.by_state||[]).length===0?<em data-dd-unknown>Not measured</em>:<small data-dd-intake-publication>{(pb.by_state||[]).map(r=>`${String(r.state).replaceAll('_',' ')}: ${nm(r.n)}`).join(' · ')}{pb.last_checked_at?` · last checked ${stampOf(pb.last_checked_at)}`:''}</small>}</li>
        <li data-dd-stage-row="technical_blocker"><span>Active technical blocker</span> {tech.length===0?<strong data-dd-blocker="none">None</strong>:<small data-dd-blocker="technical">{tech.map(b=>b.text).join(' ')}</small>}</li>
        {bl.filter(b=>b.kind!=='technical').length>0&&<li data-dd-stage-row="held_blockers"><span>What holds the rest</span><ul className="dd-reasons" data-dd-intake-blockers>{bl.filter(b=>b.kind!=='technical').map(b=><li key={b.code}><span title={b.text}>{b.kind==='decision'?'Decision: ':'Source: '}{b.text}</span> <strong>{b.n==null?'Not measured':fmtNumber(Number(b.n))}</strong></li>)}</ul></li>}</ul></li>
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

/** The academic entry requirements (AER) sources, gaps and holds (CF-247 AER source recovery, Platform Admin 10 Nov 2026 14:02): counted live by security.data_delivery_aer_v1 when the page was read, from the AER tables
 *  (the gaps by route come from the hourly findings). A figure the server did not send is Not measured, never 0; a missing block (an older server) or known false is Not measured as a whole. */
function AerSources({a}){
  if(a==null||a.known===false)return <div className="dd-stages-box" data-dd-aer-sources="unknown"><h4 className="sl-h4">Entry-requirement sources, gaps and holds</h4><Unknown reason={a?.reason||'This count is not available from the server yet'} word="Not measured"/></div>
  const c=a.coverage||{},src=a.sources||{},sf=src.stored_find||{},gaps=a.gaps||[],prk=a.parked||{},rule=prk.by_rule||[],oth=a.other_findings||[],lr=a.last_run||{},jobs=a.jobs||[],blk=a.blockers||[]
  const routeName=r=>String(r||'').replaceAll('_',' ')
  return <div className="dd-stages-box" data-dd-aer-sources="known">
    <h4 className="sl-h4">Entry-requirement sources, gaps and holds</h4>
    <p className="sl-sub" data-dd-aer-stamp>Counted live at {stampOf(a.counted_at)} (Melbourne), in {a.unit||'providers'}; provider coverage as cached by the hourly reconcile ({c.counted_at?stampOf(c.counted_at):'Not measured'}). Gaps are grouped by what the platform already holds for each provider.</p>
    {blk.length>0&&<ul className="dd-reasons" data-dd-aer-blockers>{blk.map((b,i)=><li key={i}><span>{b}</span></li>)}</ul>}
    <ol className="dd-stages dd-stages-3">
      <li data-dd-aer-stage="coverage"><h5>1. Eligible providers and sources</h5><ul>
        <Row k="aer_eligible" label="Eligible providers (AU and NZ, published, enrolling international students)" v={c.eligible}/>
        <Row k="aer_with_source" label="With an entry-requirements source" v={c.with_source}/>
        <Row k="aer_source_read" label="With a source read" v={c.source_read}/>
        <Row k="aer_with_active" label="With active entry-requirement rows" v={c.with_active_rows}/>
        <Row k="aer_waiting" label="With rows waiting for a Layer 4 decision" v={c.waiting_for_layer4}/>
        <Row k="aer_active_course_rows" label="Active course rows" v={c.active_course_rows}/>
        <Row k="aer_active_matrix_rows" label="Active provider matrix rows" v={c.active_matrix_rows}/>
        <Row k="aer_proposed_course_rows" label="Proposed course rows" v={c.proposed_course_rows}/>
        <Row k="aer_sources_total" label="Sources held" v={src.total}>
          <small data-dd-aer-stored-find>{sf.switch_on===true?'Entry pages from stored links: on':sf.switch_on===false?'Entry pages from stored links: off':'Entry pages from stored links: Not measured'}; {sf.sources_attached==null?'attached: Not measured':`${fmtNumber(Number(sf.sources_attached))} attached`}</small></Row></ul></li>
      <li data-dd-aer-stage="gaps"><h5>2. Remaining gaps, by route</h5>
        {gaps.length===0?<Unknown reason="No provider is waiting without a source in the latest findings" word="None found"/>:<ul>{gaps.map(g=><li key={g.route} data-dd-aer-gap={g.route}><span title={g.example_reason||undefined}>{routeName(g.route)}{g.parked&&<StatusChip tone="warning" label="Parked"/>}</span> <strong>{fmtNumber(Number(g.providers))}</strong>
          <small>{g.courses_waiting>0?`${fmtNumber(Number(g.courses_waiting))} courses. `:''}{g.next_action||'Next action: Not measured'}</small></li>)}</ul>}
        {oth.length>0&&<><h5>Other open findings</h5><ul className="dd-reasons" data-dd-aer-other>{oth.map(o=><li key={o.cause}><span>{routeName(o.cause)}</span> <strong>{fmtNumber(Number(o.findings))}</strong></li>)}</ul></>}</li>
      <li data-dd-aer-stage="holds"><h5>3. Parked holds, last and next run</h5>
        <ul><Row k="aer_parked" label="Layer 4 items parked by the technical lane (not counted against the Layer 4 limit)" v={prk.items}/></ul>
        {rule.length>0&&<ul className="dd-reasons" data-dd-aer-parked>{rule.map(r=><li key={r.class} title={r.next_action||undefined}><span>{routeName(r.class)}: {r.reason||'reason Not measured'}</span> <strong>{fmtNumber(Number(r.items))}</strong></li>)}</ul>}
        <p data-dd-aer-last-run>{lr.ran_at?<>Last scheduled read <strong>{fmtDateTime(lr.ran_at)}</strong>: {num(lr.course_reads)} course reads, {num(lr.corrections)} corrections, {num(lr.matrix_pages)} entry pages; Layer 4 waiting {num(lr.layer4_waiting)}{lr.back_pressure?' (full)':''}{lr.parked_not_counted==null?'':`; parked not counted ${num(lr.parked_not_counted)}`}.</>:<Unknown reason="No scheduled read is on record" word="Not measured"/>}</p>
        {jobs.length>0&&<ul className="dd-reasons" data-dd-aer-jobs>{jobs.map(j=><li key={j.job}><span>{j.job} <small>{j.schedule}</small></span> <strong>{j.active?(j.next_run?`next ${fmtDateTime(j.next_run)}`:'next run Not measured'):'paused'}</strong></li>)}</ul>}</li>
      <AerProgress/>
    </ol></div>
}

/** CF-247 F-AER.04 (decision delivery item 6, 11 Nov 2026): stage 4 of the AER panel, discovery and admission. Read on its own (public.admin_aer_delivery_progress, about
 *  0.3 s) beside the panel's existing read, so it shows even when that read is slow; a figure the server did not send is Not measured, never 0. */
function AerProgress(){
  const[p,setP]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{let live=true;supabase.rpc('admin_aer_delivery_progress').then(({data,error})=>{if(!live)return;if(error)setErr(error.message||'Not available');else setP(data)}).catch(e=>{if(live)setErr(String(e?.message||e))});return()=>{live=false}},[])
  if(err||p?.known===false)return <li data-dd-aer-stage="progress" data-dd-aer-progress="unknown"><h5>4. Discovery and admission</h5><Unknown reason={err||p?.reason||'Not available'} word="Not measured"/></li>
  if(!p)return <li data-dd-aer-stage="progress"><h5>4. Discovery and admission</h5><p className="sl-sub">Loading…</p></li>
  const c=p.campaign||{},mc=p.machine?.course||{},mm=p.machine?.matrix||{},cr=p.corrected_reads||{},g=p.gains_24h||{},f=p.failures||{}
  const nm=x=>x==null?'Not measured':fmtNumber(Number(x))
  const mode=m=>m==null?'Not measured':Number(m)>=2?'admitting':Number(m)>=1?'shadow (decides nothing)':'off'
  return <li data-dd-aer-stage="progress" data-dd-aer-progress="known"><h5>4. Discovery and admission</h5>
    <p className="sl-sub" data-dd-aer-progress-stamp>Counted live at {fmtDateTime(p.counted_at)}.</p>
    <ul>
      <Row k="aer_campaign_asked" label={`Discovery campaign (${c.state||'Not measured'}): providers asked`} v={c.providers_attempted}/>
      <Row k="aer_campaign_usable" label="Usable sources found (read)" v={c.usable_sources}/>
      <Row k="aer_campaign_not_found" label="No entry page on the provider's website" v={c.not_found}/>
      <Row k="aer_campaign_credits" label={`Firecrawl credits used (ceiling ${nm(c.credit_cap)}${c.cost_per_usable_source!=null?`; ${c.cost_per_usable_source} a usable source`:''})`} v={c.credits}/>
      <Row k="aer_campaign_spare" label={`Spare central credits taken today (room now ${nm(c.spare_room)}: ${c.spare_why||'Not measured'})`} v={c.spare_credits_today}/>
      <Row k="aer_machine_course" label={`Course reads admitted by the machine rule (${mode(mc.mode)}), last 24 hours`} v={mc.admitted_24h}/>
      <Row k="aer_machine_matrix" label={`Country tables and qualification rows admitted by the machine rule (${mode(mm.mode)}; ${nm(mm.providers)} providers)`} v={mm.admitted}/>
      <Row k="aer_machine_matrix_shadow" label={`Shadow results (would admit ${nm(mm.shadow_would_admit)}; last validation ${mm.validation?(mm.validation.passed?'passed':'not passed'):'none'})`} v={mm.shadow}/>
      <Row k="aer_corrected_open" label={`Corrected reads open (refused ${nm(cr.refused_24h)}, replaced ${nm(cr.replaced_24h)} in 24 hours)`} v={cr.open}/>
      <Row k="aer_gains" label={`Rows made active in 24 hours: course (matrix ${nm(g.matrix_rows)}, qualification ${nm(g.qualification_rows)})`} v={g.course_rows}/>
      <Row k="aer_failures" label={`Sources that cannot be fetched (reads held as unreadable ${nm(f.reads_held_unreadable)})`} v={f.sources_not_fetched}/>
    </ul>
    {(mm.declines||[]).length>0&&<ul className="dd-reasons" data-dd-aer-declines>{mm.declines.map((d,i)=><li key={i}><span>Kept with a person: {d.reason}</span> <strong>{fmtNumber(Number(d.n))}</strong></li>)}</ul>}
  </li>
}

/** CF-247 RM1A-1 (O29, Admin destination data design v1.1 §6): Course recognition on Website API v3 course detail. Read on its own
 *  (public.admin_course_recognition_delivery, about 0.2 s): searchable courses, courses served with a CRICOS recognition, and the courses held with the
 *  exact reason and next action. A figure the server did not send is Not measured, never 0. */
export function RecognitionDelivery({rpc}){
  const[p,setP]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{let live=true;Promise.resolve(rpc('admin_course_recognition_delivery',{})).then(({data,error})=>{if(!live)return;if(error)setErr(error.message||'Not available');else setP(data)}).catch(e=>{if(live)setErr(String(e?.message||e))});return()=>{live=false}},[])
  const head=<h4>Course recognition (Website API v3 course detail)</h4>
  if(err||p?.known===false)return <section className="dd-recognition" data-dd-recognition="unknown">{head}<Unknown reason={err||p?.reason||'Not available'} word="Not measured"/></section>
  if(!p)return <section className="dd-recognition" data-dd-recognition="loading">{head}<p className="sl-sub">Loading…</p></section>
  const au=p.au||{},nz=p.nz||{}
  return <section className="dd-recognition" data-dd-recognition="known">{head}
    <p className="sl-sub" data-dd-recognition-stamp>Counted live at {fmtDateTime(p.counted_at)}. Website v3 only; Zoho v3 follows after the Zoho developer is told. An empty list is never &ldquo;not recognised&rdquo;.</p>
    <ul>
      <Row k="rec_au_searchable" label="Australian courses in search" v={au.searchable}/>
      <Row k="rec_au_served" label="Served with a CRICOS registration" v={au.served} actor="machine"/>
      <Row k="rec_au_held_dates" label="Held: registration active but its end date has passed (F-DISC to reconcile)" v={au.held_dates_inconsistent}/>
      <Row k="rec_au_held_source" label="Held: no active public source for the registration" v={au.held_source_missing}/>
      <Row k="rec_nz_searchable" label={`New Zealand courses in search (held: ${nz.held_reason||'reason Not measured'})`} v={nz.searchable}/>
    </ul>
    {p.next_action&&<p className="sl-sub" data-dd-recognition-next>Next action: {p.next_action}</p>}
  </section>
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
      {s.stream==='aer'&&<AerSources a={s.aer_sources}/>}
      {s.stream==='int'&&<IntakeDelivery d={s.intake_delivery}/>}
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
    <div className="dd-streams">{streams.map(s=><Stream key={s.stream} s={s} now={now} providerFilters={Boolean(d.provider_filters_available)} open={open[s.stream]??Boolean(s.stages||s.provider_ai||s.aer_sources)} onToggle={o=>setOpen(x=>({...x,[s.stream]:o}))}/>)}</div>
    <RecognitionDelivery rpc={rpc}/>
    <p className="sl-sub">Net = admitted minus withdrawn, from each stream&rsquo;s own ledger timestamps. A job the scheduler reports as OK says nothing about data: the flag shows when it admitted nothing. Reload interval, windows and the number of reasons are settings (Settings &rsaquo; Pipeline settings &rsaquo; Data delivery).</p>
  </section>
}
