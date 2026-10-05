// Coverage & completeness › Universities (CF-247 Decision 254, Platform Admin 5 Oct 07:36).
// One row per target university: adapter state and admitted fields, exclusions, central English rule and calendar,
// and how many courses hold intakes, English and fees, with where each value came from. Open a university to see its
// courses in a table (5 Oct 15:36: with location, delivery and entry requirement). A Platform Admin can attach a central English or key-dates page (read through Firecrawl, then
// approved in Layer 4 Review › Attributes).
// 5 Oct 17:04/18:04: indicative whole-course fees for each university (lowest and highest, in the country's currency).
// Current fees first (printed whole-course total, else annual fee x full-time years), the CRICOS registered total as
// the fallback, award courses only. Worked out every hour (public.admin_provider_fee_range). A Platform Admin
// publishes each university's range on its own, can set it by hand (never overwritten) and controls the settings.
// 5 Oct 19:18: hosted courses. An award inside or at the exit of a longer course takes its page, fee, intakes and
// delivery from its single-degree parent once the register check passes (public.admin_exit_awards). A page that
// carries several courses hosts them (public.admin_host_pages, admitted as 'host_pages'). Double degrees on an
// unconfirmed page and pages that are gone are proposals a Platform Admin confirms by hand.
import React,{useEffect,useMemo,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{fmtDate,fmtMoney,fmtShare}from'./lib/format'
import{Button,Empty,Loading,Pager,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const COUNTRY_NAME={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
const ADAPTER={admitting:['Admitting','success'],testing:['Testing','warning'],off:['Switched off','neutral']}
const FIELD={intakes:'Intakes',english:'English',fee:'Fees',delivery:'Delivery',exit_awards:'Exit awards',host_pages:'Host pages'}
const HOST_KIND={exit_award:'Exit award of',nested_award:'Award within',shared_page:'Shares the page of',double_degree:'Double degree page',no_public_page:'Page gone'}
const CHECK={pass:['Register check passed','success'],fail:['Register check failed','danger'],none:['No register to check','neutral']}
// Delivery as held in the catalogue (security.delivery_mode_from_text)
const DELIVERY={on_campus:'On campus',online:'Online',on_campus_and_online:'On campus and online',blended:'Blended'}
const POLICY={approved:['Approved','success'],proposed:['Waiting for approval','warning'],no_values:['Read, no rule found','neutral']}
// Where a held value came from
const SOURCE={adapter:['Course page (adapter)','success'],central:['Central rule','info'],reader:['Course page (general reader)','neutral'],hand:['Entered by hand','violet'],other:['Other source','neutral'],missing:['Missing','danger'],catalogue:['Registered campus','info']}
const SHOW=[['all','All courses'],['missing','Something missing'],['excluded','Excluded'],['adapter','Read by the adapter'],['central','From a central rule']]
const errText=e=>e?.message||String(e)
// How a course's whole-course fee was worked out, and why a course was left out of the range
const HOW={current_total:['Whole-course fee on the course page','success'],current_annual_x_years:['Annual fee x years','info'],register_total:['CRICOS registered total','neutral']}
const LEFT_OUT={no_course_length:'No course length',other_currency:'Other currency (not converted)',under_one_year:'Under one year',below_floor:'Below the floor'}
const money0=(v,c)=>fmtMoney(v,c,{decimals:0})

function Pill({tone='neutral',children,title}){return <span className={`cf-chip tone-${tone}`} title={title}>{children}</span>}
function SourcePill({source}){const[l,t]=SOURCE[source]||[source,'neutral'];return <Pill tone={t}>{l}</Pill>}

function Coverage({part,courses}){
  if(!part)return '—'
  const held=Number(part.held||0)
  const tone=!courses||held===0?'danger':held>=courses?'success':'warning'
  return <div className="uc-cov"><Pill tone={tone}>{fmtShare(part.held||0,courses)}</Pill><small className="sl-sub">{fmtNumber(part.held||0)} of {fmtNumber(courses)}</small>
    <span className="uc-src">{part.adapter>0&&<Pill tone="success" title="From the course page, read by the adapter">adapter {fmtNumber(part.adapter)}</Pill>}
      {part.central>0&&<Pill tone="info" title="From the university's central rule">central {fmtNumber(part.central)}</Pill>}
      {part.reader>0&&<Pill title="From the course page, general reader">reader {fmtNumber(part.reader)}</Pill>}
      {part.excluded>0&&<Pill tone="warning" title="Course readings excluded from admission">excluded {fmtNumber(part.excluded)}</Pill>}</span></div>
}

function PolicyCell({p,pages,kind}){
  const own=(pages||[]).filter(x=>x.kind===kind)
  const[l,t]=p?(POLICY[p.status]||[p.status,'neutral']):['None','neutral']
  return <div className="uc-policy"><Pill tone={t}>{l}</Pill>{p?.url&&<a className="cf-link" href={p.url} target="_blank" rel="noreferrer" title={p.url}>page</a>}
    {own.length>0&&<small className="sl-sub">{fmtNumber(own.length)} attached{own.some(x=>x.status==='found')?' · waiting to be read':''}</small>}</div>
}

function AttachPage({u,onDone,onError}){
  const[kind,setKind]=useState('english_policy'),[url,setUrl]=useState(''),[busy,setBusy]=useState(false)
  const add=async()=>{const reason=window.prompt(`Attach this ${kind==='english_policy'?'central English requirements':'key-dates'} page to ${u.name}? It is read through Firecrawl (evidence kept) and parsed into a proposal for approval in Layer 4 Review › Attributes. Give the reason (kept in the log).`,'');if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_central_page',{p_action:'add',p_args:{provider_id:u.provider_id,kind,url:url.trim(),reason}});if(error)throw error;setUrl('');onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <div className="uc-attach" data-central-attach={u.provider_id}>
    <select className="fv-filter" aria-label="Central page kind" value={kind} onChange={e=>setKind(e.target.value)}><option value="english_policy">Central English requirements</option><option value="intake_calendar">Key dates (term months)</option></select>
    <input className="au-search" type="url" aria-label="Central page address" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)}/>
    <Button compact disabled={busy||!/^https?:\/\/\S+$/.test(url.trim())} onClick={add}>Attach page</Button></div>
}

function CourseTable({u,onError}){
  const[show,setShow]=useState('all'),[offset,setOffset]=useState(0),[d,setD]=useState(null),[busy,setBusy]=useState(false)
  const LIMIT=100
  useEffect(()=>{setBusy(true);supabase.rpc('admin_university_courses_read',{p_provider_id:u.provider_id,p_args:{show,limit:LIMIT,offset}})
    .then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))},[u.provider_id,show,offset])
  return <div className="uc-courses" data-university-courses={u.provider_id}>
    <div className="cf-filterbar" role="group" aria-label="Show courses">{SHOW.map(([k,l])=><button key={k} className={show===k?'active':''} onClick={()=>{setOffset(0);setShow(k)}}>{l}</button>)}</div>
    {busy&&!d?<Loading/>:(d?.courses||[]).length===0?<Empty text="No courses match."/>:<>
    <div className="cf-table-wrap"><table className="cf-table uc-course-table"><thead><tr><th>Course</th><th>Location (campus)</th><th>Delivery</th><th>Intakes</th><th>English (IELTS)</th><th>Requirement</th><th>Fee (international, annual)</th></tr></thead><tbody>
      {d.courses.map(c=><tr key={c.course_id}>
        <td><strong>{c.course}</strong><small className="sl-sub">{c.code||'—'}{c.level?` · ${String(c.level).replace(/_/g,' ')}`:''}</small>
          <span className="uc-links">{c.url&&<a className="cf-link" href={c.url} target="_blank" rel="noreferrer">course page</a>}{c.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(c.evidence_id)}`}>evidence</a>}
            {c.read_status&&c.read_status!=='read'&&<Pill tone="warning">{String(c.read_status).replace(/_/g,' ')}</Pill>}
            {c.host&&<Pill tone={c.host.register_check==='fail'?'danger':c.host.applied?'info':'neutral'} title={c.host.url||''}>{HOST_KIND[c.host.kind]||c.host.kind}{c.host.host?` ${c.host.host}`:''}{c.host.years?` · ${fmtNumber(c.host.years)} yr`:''}{c.host.register_check==='fail'?' · check failed':c.host.applied?'':' · proposed'}</Pill>}</span></td>
        <td><span className="uc-val">{c.location?.value||c.location?.read||'—'}</span>{c.location&&<SourcePill source={c.location.source}/>}{c.location?.value&&c.location?.read&&<small className="sl-sub" title="Read on the course page">page: {c.location.read}</small>}</td>
        <td><span className="uc-val">{c.delivery?.value?(DELIVERY[c.delivery.value]||String(c.delivery.value).replace(/_/g,' ')):'—'}</span>{c.delivery&&<SourcePill source={c.delivery.source}/>}{c.delivery?.excluded&&<Pill tone="warning">excluded</Pill>}
          {c.delivery?.read&&<small className="sl-sub" title={c.delivery.read}>page: {String(c.delivery.read).slice(0,60)}</small>}</td>
        <td><span className="uc-val">{(c.intakes?.value||[]).join(', ')||'—'}</span><SourcePill source={c.intakes?.source}/>{c.intakes?.excluded&&<Pill tone="warning">excluded</Pill>}</td>
        <td><span className="uc-val">{c.english?.value??'—'}</span><SourcePill source={c.english?.source}/>{c.english?.excluded&&<Pill tone="warning">excluded</Pill>}</td>
        <td><span className="uc-val uc-req" title={c.requirement?.read||''}>{c.requirement?.read?String(c.requirement.read).slice(0,90):'—'}</span>{c.requirement?.other&&<small className="sl-sub" title={c.requirement.other}>Other: {String(c.requirement.other).slice(0,90)}</small>}{c.requirement&&<SourcePill source={c.requirement.source}/>}{(c.requirement?.read||c.requirement?.other)&&<small className="sl-sub">for review, not admitted</small>}</td>
        <td><span className="uc-val">{c.fee?.value!=null?fmtMoney(c.fee.value,c.fee.currency||'AUD'):'—'}{c.fee?.year?` (${c.fee.year})`:''}</span><SourcePill source={c.fee?.source}/>{c.fee?.excluded&&<Pill tone="warning">excluded</Pill>}</td></tr>)}
    </tbody></table></div>
    <Pager offset={offset} limit={LIMIT} total={Number(d.total||0)} onOffset={setOffset}/></>}
  </div>
}

function rangeText(r){return r&&r.low!=null&&r.high!=null?(Number(r.low)===Number(r.high)?money0(r.low,r.currency):`${money0(r.low,r.currency)}–${money0(r.high,r.currency)}`):'—'}

function FeeRangeCell({r}){
  if(!r)return '—'
  const c=r.computed||{}
  return <div className="uc-cov" data-fee-range-cell={r.provider_id}><span className="uc-val">{rangeText(r)}</span>
    <span className="uc-src">{r.published?<Pill tone="success">Published</Pill>:<Pill>Not published</Pill>}{r.by_hand&&<Pill tone="violet">Set by hand</Pill>}
      {!r.by_hand&&c.courses>0&&!c.meets_minimum&&<Pill tone="warning" title="Fewer courses than the minimum in the settings">few courses</Pill>}</span>
    <small className="sl-sub">{fmtNumber(c.courses||0)} courses</small></div>
}

function FeeRangeSettings({d,can,onDone,onError}){
  const s=d?.settings||{}
  const[v,setV]=useState(null),[busy,setBusy]=useState(false)
  useEffect(()=>{if(d?.settings)setV({include_under_one_year:!!s.include_under_one_year,min_courses:s.min_courses,min_fee_year:s.min_fee_year,min_whole_fee:s.min_whole_fee,excluded_level_codes:s.excluded_level_codes||[]})},[d])
  if(!v)return null
  const flip=code=>setV({...v,excluded_level_codes:v.excluded_level_codes.includes(code)?v.excluded_level_codes.filter(x=>x!==code):[...v.excluded_level_codes,code]})
  const save=async()=>{const reason=window.prompt('Save the whole-course fee settings? Every range is worked out again. Give the reason (kept in the log).','');if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_fee_range',{p_action:'settings',p_args:{...v,min_courses:Number(v.min_courses),min_fee_year:Number(v.min_fee_year),min_whole_fee:Number(v.min_whole_fee),reason}});if(error)throw error;onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  return <details className="uc-fr-settings" data-fee-range-settings><summary>Whole-course fee settings</summary>
    <p className="sl-sub">Each course's whole-course fee: the whole-course fee printed on the course page, else the current annual fee x full-time years, else the CRICOS registered total. Award courses only: the study levels ticked below are left out. Fees in another currency are never converted.</p>
    <div className="uc-fr-grid">
      <label><input type="checkbox" disabled={!can} checked={v.include_under_one_year} onChange={e=>setV({...v,include_under_one_year:e.target.checked})}/> Include courses under one year</label>
      <label><span>Fewest courses before a range can be published</span><input className="au-search" type="number" min="1" max="500" disabled={!can} value={v.min_courses} onChange={e=>setV({...v,min_courses:e.target.value})}/></label>
      <label><span>Oldest fee year counted as current</span><input className="au-search" type="number" min="2020" max="2100" disabled={!can} value={v.min_fee_year} onChange={e=>setV({...v,min_fee_year:e.target.value})}/></label>
      <label><span>Floor: whole-course fees below this are left out</span><input className="au-search" type="number" min="0" disabled={!can} value={v.min_whole_fee} onChange={e=>setV({...v,min_whole_fee:e.target.value})}/></label>
    </div>
    <fieldset className="uc-fr-levels"><legend>Study levels left out (not award courses)</legend>
      {(d.levels||[]).map(l=><label key={l.code}><input type="checkbox" disabled={!can} checked={v.excluded_level_codes.includes(l.code)} onChange={()=>flip(l.code)}/> {l.name}</label>)}</fieldset>
    {can&&<Button compact disabled={busy} onClick={save}>Save settings</Button>}
    {s.updated_at&&<small className="sl-sub">Last changed {fmtDateTime(s.updated_at)}{s.reason?` · ${s.reason}`:''}</small>}
  </details>
}

function HostedPanel({u,can,onError}){
  const[aw,setAw]=useState(null),[hp,setHp]=useState(null),[busy,setBusy]=useState(false),[show,setShow]=useState('')
  const load=()=>{setBusy(true);Promise.all([supabase.rpc('admin_exit_awards',{p_action:'read',p_args:{provider_id:u.provider_id}}),supabase.rpc('admin_host_pages',{p_action:'read',p_args:{provider_id:u.provider_id}})])
    .then(([a,h])=>{if(a.error)throw a.error;if(h.error)throw h.error;setAw(a.data||[]);setHp(h.data||[])}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{load()},[u.provider_id])
  const act=async(rpc,action,ask,extra={})=>{const reason=window.prompt(ask,'');if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc(rpc,{p_action:action,p_args:{provider_id:u.provider_id,reason,...extra}});if(error)throw error;load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!aw||!hp)return busy?<Loading/>:null
  const awards=aw.filter(x=>x.active),pages=hp.filter(x=>x.active)
  const n={pass:awards.filter(x=>x.register_check==='pass').length,fail:awards.filter(x=>x.register_check==='fail').length,shared:pages.filter(x=>x.link_type==='shared_page').length,dbl:pages.filter(x=>x.link_type==='double_degree').length,gone:pages.filter(x=>x.link_type==='no_public_page').length}
  if(awards.length+pages.length===0)return null
  const rows=show==='awards'?awards:show==='pages'?pages:[]
  return <div className="uc-fee-range uc-hosted" data-hosted={u.provider_id}>
    <div className="uc-fr-head"><strong>Hosted courses</strong>
      <Pill tone="success">{fmtNumber(n.pass)} awards checked</Pill>{n.fail>0&&<Pill tone="danger">{fmtNumber(n.fail)} awards failed the register check</Pill>}
      {n.shared>0&&<Pill tone="info">{fmtNumber(n.shared)} on a shared page</Pill>}{n.dbl>0&&<Pill tone="warning">{fmtNumber(n.dbl)} double degrees to confirm</Pill>}{n.gone>0&&<Pill tone="warning">{fmtNumber(n.gone)} pages gone</Pill>}</div>
    <small className="sl-sub">An award takes its page, fee, intakes and delivery from its single-degree parent once the register check passes and the university admits exit awards. A shared page is confirmed for the courses it carries when the university admits host pages. Double degrees and pages that are gone are confirmed by hand.</small>
    <div className="uc-attach">
      <Button compact onClick={()=>setShow(show==='awards'?'':'awards')} aria-expanded={show==='awards'}>{show==='awards'?'Hide awards':`Awards (${fmtNumber(awards.length)})`}</Button>
      <Button compact onClick={()=>setShow(show==='pages'?'':'pages')} aria-expanded={show==='pages'}>{show==='pages'?'Hide pages':`Pages (${fmtNumber(pages.length)})`}</Button>
      {can&&<><Button compact disabled={busy} onClick={()=>act('admin_exit_awards','detect',`Look for exit and nested awards at ${u.name} again? Give the reason (kept in the log).`)}>Find awards again</Button>
        <Button compact disabled={busy} onClick={()=>act('admin_host_pages','detect',`Look for shared pages, double degrees and pages that are gone at ${u.name} again? Give the reason (kept in the log).`)}>Find pages again</Button></>}
    </div>
    {show==='awards'&&<div className="cf-table-wrap"><table className="cf-table uc-fr-table"><thead><tr><th>Award</th><th>Parent course</th><th>Years</th><th>Register check</th><th>Fee</th><th></th></tr></thead><tbody>
      {rows.map(x=>{const[cl,ct]=CHECK[x.register_check]||['Not checked','neutral'];return <tr key={x.child_course_id}><td><strong>{x.child}</strong><small className="sl-sub">{x.child_code||''} · {HOST_KIND[x.link_type]||x.link_type}{x.set_by==='hand'?' · set by hand':''}</small></td>
        <td>{x.parent}<small className="sl-sub" title={x.printed||''}>{String(x.printed||'').slice(0,80)}</small></td><td>{fmtNumber(x.years)}</td>
        <td><Pill tone={ct}>{cl}</Pill><small className="sl-sub" title={x.check_detail||''}>{String(x.check_detail||'').slice(0,90)}</small></td>
        <td>{x.annual_fee!=null?<>{fmtMoney(x.annual_fee)}{x.fee_year?` (${x.fee_year})`:''}<small className="sl-sub">whole {fmtMoney(x.total_fee)}</small></>:'—'}</td>
        <td>{can&&<Button compact disabled={busy} onClick={()=>act('admin_exit_awards','off',`Switch this award link off for ${x.child}? Give the reason (kept in the log).`,{child_course_id:x.child_course_id})}>Switch off</Button>}</td></tr>})}
    </tbody></table></div>}
    {show==='pages'&&<div className="cf-table-wrap"><table className="cf-table uc-fr-table"><thead><tr><th>Course</th><th>Page</th><th>Register check</th><th></th></tr></thead><tbody>
      {rows.map(x=>{const[cl,ct]=CHECK[x.register_check]||['—','neutral'];return <tr key={x.course_id}><td><strong>{x.course}</strong><small className="sl-sub">{x.code||''} · {HOST_KIND[x.link_type]||x.link_type}{x.host?` ${x.host}`:''}{x.applied_at?' · confirmed':''}</small></td>
        <td><a className="cf-link" href={x.host_url} target="_blank" rel="noreferrer">{String(x.host_url||'').replace(/^https?:\/\/(www\.)?/,'').slice(0,70)}</a></td>
        <td>{x.link_type==='shared_page'?<><Pill tone={ct}>{cl}</Pill><small className="sl-sub" title={x.check_detail||''}>{String(x.check_detail||'').slice(0,90)}</small></>:'—'}</td>
        <td>{can&&!x.applied_at&&x.link_type!=='no_public_page'&&<Button compact disabled={busy} onClick={()=>act('admin_host_pages','confirm_page',`Confirm this page as the page of ${x.course}? Its values then come from it as admitted. Give the reason (kept in the log).`,{course_id:x.course_id})}>Confirm page</Button>}
          {can&&!x.applied_at&&x.link_type==='no_public_page'&&<Button compact disabled={busy} onClick={()=>act('admin_host_pages','no_page',`Record that ${x.course} has no public page? The page search stops for it. Give the reason (kept in the log).`,{course_id:x.course_id})}>No public page</Button>}
          {can&&<Button compact disabled={busy} onClick={()=>act('admin_host_pages','off',`Set this proposal aside for ${x.course}? Give the reason (kept in the log).`,{course_id:x.course_id})}>Set aside</Button>}</td></tr>})}
    </tbody></table></div>}
  </div>
}

function FeeRangePanel({u,can,onDone,onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[showCourses,setShowCourses]=useState(false)
  const load=()=>{setBusy(true);supabase.rpc('admin_provider_fee_range',{p_action:'read',p_args:{provider_id:u.provider_id}})
    .then(({data,error})=>{if(error)throw error;setD(data)}).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
  useEffect(()=>{load()},[u.provider_id])
  const act=async(action,ask,extra={})=>{const reason=window.prompt(ask,'');if(!reason)return
    setBusy(true);try{const{error}=await supabase.rpc('admin_provider_fee_range',{p_action:action,p_args:{provider_id:u.provider_id,reason,...extra}});if(error)throw error;load();onDone?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const setByHand=()=>{const r=d?.range,cur=r?.currency||'';const low=window.prompt(`Lowest whole-course fee for ${u.name} (${cur}, numbers only)`,r?.low??'');if(!low)return
    const high=window.prompt(`Highest whole-course fee for ${u.name} (${cur}, numbers only)`,r?.high??'');if(!high)return
    act('set',`Set the range by hand to ${low}–${high} ${cur}? It is never changed by the hourly refresh. Give the reason (kept in the log).`,{low,high})}
  if(busy&&!d)return <Loading/>
  const r=d?.range,c=r?.computed||{},src=c.sources||{},sk=c.skipped||{},rows=d?.courses||[]
  return <div className="uc-fee-range" data-fee-range={u.provider_id}>
    <div className="uc-fr-head"><strong>Indicative whole-course fees, where listed</strong><span className="uc-val">{rangeText(r)}</span>
      {r?.published?<Pill tone="success">Published</Pill>:<Pill>Not published</Pill>}{r?.by_hand&&<Pill tone="violet" title={r.manual?.note||''}>Set by hand</Pill>}
      {r&&!r.by_hand&&c.courses>0&&!c.meets_minimum&&<Pill tone="warning">Fewer courses than the minimum</Pill>}</div>
    {r?<>
      <small className="sl-sub">{fmtNumber(c.courses||0)} award courses · {Object.entries(HOW).map(([k,[l]])=>`${l}: ${fmtNumber(src[k]||0)}`).join(' · ')}
        {c.fee_year_from?` · fee year ${c.fee_year_from===c.fee_year_to?c.fee_year_from:`${c.fee_year_from}–${c.fee_year_to}`}`:''}{c.register_as_of?` · CRICOS as at ${fmtDate(c.register_as_of)}`:''}{c.computed_at?` · worked out ${fmtDateTime(c.computed_at)}`:''}</small>
      {Object.keys(sk).length>0&&<small className="sl-sub">Left out: {Object.entries(sk).map(([k,n])=>`${LEFT_OUT[k]||k} ${fmtNumber(n)}`).join(' · ')}</small>}
      {c.low!=null&&<small className="sl-sub">Lowest: {c.low_course||'—'} ({money0(c.low,r.currency)}, {(HOW[c.low_source]||[c.low_source])[0]}) · Highest: {c.high_course||'—'} ({money0(c.high,r.currency)}, {(HOW[c.high_source]||[c.high_source])[0]})</small>}
      {r.by_hand&&<small className="sl-sub">Worked out: {rangeText({...c,currency:r.currency})}{r.manual?.note?` · note: ${r.manual.note}`:''}</small>}
    </>:<small className="sl-sub">No award course with a qualifying fee yet.</small>}
    {can&&<div className="uc-attach">
      <Button compact disabled={busy} onClick={()=>act('refresh',`Work out the range for ${u.name} again now? Give the reason (kept in the log).`)}>Work out again</Button>
      {r&&(r.published?<Button compact disabled={busy} onClick={()=>act('unpublish',`Stop publishing the whole-course fee range for ${u.name}? Give the reason (kept in the log).`)}>Stop publishing</Button>
        :<Button compact disabled={busy||r.low==null} onClick={()=>act('publish',`Publish ${rangeText(r)} as the indicative whole-course fees for ${u.name}? Give the reason (kept in the log).`)}>Publish</Button>)}
      <Button compact disabled={busy} onClick={setByHand}>Set by hand</Button>
      {r?.by_hand&&<Button compact disabled={busy} onClick={()=>act('release',`Go back to the worked-out range for ${u.name}? Give the reason (kept in the log).`)}>Use the worked-out range</Button>}
    </div>}
    {rows.length>0&&<Button compact onClick={()=>setShowCourses(!showCourses)} aria-expanded={showCourses}>{showCourses?'Hide courses':`Show the ${fmtNumber(rows.length)} courses`}</Button>}
    {showCourses&&<div className="cf-table-wrap"><table className="cf-table uc-fr-table"><thead><tr><th>Course</th><th>Whole-course fee</th><th>How</th><th>Fee used</th><th>Years</th><th>Left out</th></tr></thead><tbody>
      {rows.map(x=><tr key={x.course_id} className={x.skip?'uc-fr-skip':''}><td><strong>{x.title}</strong><small className="sl-sub">{String(x.level_code||'').replace(/_/g,' ')}</small></td>
        <td>{x.whole_fee!=null?money0(x.whole_fee,x.currency_code):'—'}</td>
        <td>{x.source?<Pill tone={(HOW[x.source]||[])[1]||'neutral'}>{(HOW[x.source]||[x.source])[0]}</Pill>:'—'}</td>
        <td>{x.fee_amount!=null?fmtMoney(x.fee_amount,x.currency_code):'—'}<small className="sl-sub">{String(x.fee_basis||'').replace(/_/g,' ')}{x.fee_year?` · ${x.fee_year}`:''}{x.register_as_of?` · as at ${fmtDate(x.register_as_of)}`:''}</small></td>
        <td>{x.years!=null?fmtNumber(x.years):'—'}{x.years_from&&<small className="sl-sub">{x.years_from}</small>}</td>
        <td>{x.skip?<Pill tone="warning">{LEFT_OUT[x.skip]||x.skip}</Pill>:''}</td></tr>)}
    </tbody></table></div>}
  </div>
}

export function UniversitiesCoverage({rank=0}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState(''),[country,setCountry]=useState(''),[q,setQ]=useState(''),[state,setState]=useState(''),[open,setOpen]=useState(null),[fr,setFr]=useState(null)
  const loadRanges=()=>supabase.rpc('admin_provider_fee_range',{p_action:'read',p_args:{}}).then(({data,error})=>{if(error)throw error;setFr(data)}).catch(e=>setError(errText(e)))
  const load=()=>{setBusy(true);setError('');loadRanges();supabase.rpc('admin_universities_read',{p_args:country?{country}:{}})
    .then(({data,error})=>{if(error)throw error;setData(data)}).catch(e=>setError(errText(e))).finally(()=>setBusy(false))}
  const rangeOf=useMemo(()=>Object.fromEntries((fr?.ranges||[]).map(r=>[r.provider_id,r])),[fr])
  useEffect(()=>{load()},[country])
  const rows=useMemo(()=>(data?.universities||[]).filter(u=>(!q.trim()||u.name.toLowerCase().includes(q.trim().toLowerCase()))&&(!state||(state==='none'?!u.adapter:u.adapter?.state===state))),[data,q,state])
  const tally=useMemo(()=>{const t={admitting:0,testing:0,none:0};for(const u of data?.universities||[])t[u.adapter?.state==='admitting'?'admitting':u.adapter?'testing':'none']++;return t},[data])
  const can=rank>=6
  return <section className="m-panel uc-wrap" data-universities-coverage>
    <SectionTitle title="Universities" subtitle="Each target university: its adapter, its central English rule and calendar, and how many courses hold intakes, English and fees, with where each value came from. Open a university to see its courses."
      action={<Button compact className="cf-icon-btn" title="Refresh" aria-label="Refresh" onClick={load} disabled={busy}><RefreshCw size={14}/></Button>}/>
    <section className="cf-filterbar cc-where uc-filters" aria-label="Country and university">
      <label><span>Country</span><select className="fv-filter" aria-label="Universities country" value={country} onChange={e=>setCountry(e.target.value)}><option value="">All countries</option>{Object.entries(COUNTRY_NAME).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
      <label><span>University</span><input className="au-search" type="search" aria-label="Find a university" placeholder="Find a university…" value={q} onChange={e=>setQ(e.target.value)}/></label>
    </section>
    <section className="cf-filterbar" aria-label="Adapter state"><span>Adapter</span>
      {[['','All'],['admitting',`Admitting (${fmtNumber(tally.admitting)})`],['testing',`Testing (${fmtNumber(tally.testing)})`],['none',`No adapter (${fmtNumber(tally.none)})`]].map(([k,l])=><button key={k||'all'} className={state===k?'active':''} onClick={()=>setState(k)}>{l}</button>)}
    </section>
    {error&&<div className="dq-alert"><span>{error}</span></div>}
    <FeeRangeSettings d={fr} can={can} onDone={load} onError={setError}/>
    {busy&&!data?<Loading/>:<div className="cf-table-wrap"><table className="cf-table uc-table"><thead><tr><th>University</th><th>Adapter</th><th>Central English rule</th><th>Calendar</th><th>Intakes</th><th>English</th><th>Fees</th><th>Whole-course fees</th><th></th></tr></thead><tbody>
      {rows.map(u=>{const[al,at]=u.adapter?(ADAPTER[u.adapter.state]||[u.adapter.state,'neutral']):['No adapter','neutral'];const isOpen=open===u.provider_id
        return <React.Fragment key={u.provider_id}><tr data-university-row={u.provider_id} className={isOpen?'uc-open':''}>
          <td><strong>{u.name}</strong><span className="uc-meta"><Pill>{u.country}</Pill><small className="sl-sub">{fmtNumber(u.courses)} courses · {fmtNumber(u.pages_read)} pages read</small></span></td>
          <td><Pill tone={at}>{al}</Pill>{u.adapter?.state==='admitting'&&<span className="uc-fields">{(u.adapter.fields||[]).map(f=><Pill key={f} tone="success">{FIELD[f]||f}</Pill>)}</span>}
            {Number(u.adapter?.exclusions||0)>0&&<Pill tone="warning" title="Course readings excluded from admission">{fmtNumber(u.adapter.exclusions)} excluded</Pill>}
            {u.adapter?.admit_changed_at&&<small className="sl-sub">since {fmtDateTime(u.adapter.admit_changed_at)}</small>}</td>
          <td><PolicyCell p={u.english_policy} pages={u.central_pages} kind="english_policy"/></td>
          <td><PolicyCell p={u.calendar} pages={u.central_pages} kind="intake_calendar"/></td>
          <td><Coverage part={u.intakes} courses={u.courses}/></td>
          <td><Coverage part={u.english} courses={u.courses}/></td>
          <td><Coverage part={u.fee} courses={u.courses}/></td>
          <td><FeeRangeCell r={rangeOf[u.provider_id]}/></td>
          <td><Button compact aria-expanded={isOpen} onClick={()=>setOpen(isOpen?null:u.provider_id)}>{isOpen?'Close':'Open'}</Button></td></tr>
          {isOpen&&<tr className="uc-detail"><td colSpan={9}>
            {can&&<AttachPage u={u} onDone={load} onError={setError}/>}
            {(u.central_pages||[]).length>0&&<ul className="tn-list uc-pages">{u.central_pages.map((p,i)=><li key={i}><Pill tone={p.status==='read'||p.status==='parsed'?'success':p.status==='found'?'warning':'neutral'}>{p.kind==='english_policy'?'English':'Key dates'} · {String(p.status).replace(/_/g,' ')}</Pill> <a className="cf-link" href={p.url} target="_blank" rel="noreferrer">{p.url}</a>{p.read_at&&<small className="sl-sub"> read {fmtDateTime(p.read_at)}</small>}{p.evidence_id&&<a className="cf-link" href={`#evidence?evidence_id=${encodeURIComponent(p.evidence_id)}`}> evidence</a>}</li>)}</ul>}
            <FeeRangePanel u={u} can={can} onDone={loadRanges} onError={setError}/>
            <HostedPanel u={u} can={can} onError={setError}/>
            <CourseTable u={u} onError={setError}/></td></tr>}
        </React.Fragment>})}
      {rows.length===0&&<tr><td colSpan={9}><Empty text="No university matches."/></td></tr>}
    </tbody></table></div>}
    <p className="sl-sub uc-legend">Where a value came from: <SourcePill source="adapter"/> <SourcePill source="central"/> <SourcePill source="reader"/> <SourcePill source="hand"/> <SourcePill source="missing"/>. A course page reading comes first, the central rule fills courses with no English requirement, and a value entered by hand is never changed. Approve central rules in <a className="cf-link" href="#layer-4-review?tab=attributes">Layer 4 Review › Attributes</a>; set adapters in Models & services › University adapters.</p>
  </section>
}
