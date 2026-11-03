// Toolsets and limits (v2.15.177, Decision 252). Platform Admin, 4 Oct 2026 13:37: OpenRouter is not capped by the
// platform (observe, collect logs, top up when required); each layer shows a notice when a toolset it depends on hits a
// limit or times out; Serper and ScrapingBee run on a key whose plan limits are settings (a free key now, a production
// key later), with sample runs across every country before scheduled use; and every
// variable is a setting the Platform Admin changes here — nothing fixed in code.
// SS-020 step 1 (Decision 269, 3 Nov 2026): the Serper, ScrapingBee, Search pass and Sample runs cards retired (Firecrawl only, 4 Oct);
// their rows and history stay (src/retired-services.js).
// Reads: admin_toolsets_read(), admin_platform_notices_read(layer).
// CF-247 W35 (Platform Admin 30 Oct 2026 06:53): notices come from a cached snapshot; its time, age and Stale marker are shown (SnapshotStamp).
// Writes: admin_toolsets_write(action,args) — Platform Admin with a reason.
// v2.15.180 (Decision 253): Firecrawl settings by section (Target universities, Read pages, Find pages, Runs) and the
// Firecrawl work panel (FirecrawlWork.jsx): runs by use case, target universities and the report for Firecrawl support.
// v2.15.200 (Decision 254, Platform Admin 6 Oct 15:38 "Services, keys and limits only, every card collapsed"): every
// panel here is a collapsed card (Card.jsx). Firecrawl runs, targets and university adapters moved to Layer 2 › Adapters.
import React,{useEffect,useState}from'react'
import{RefreshCw,BellRing,Check,ArrowRight}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtDateTime,fmtNumber}from'./ui-kit'
import FirecrawlWork from'./FirecrawlWork'
import FirecrawlCredits from'./FirecrawlCredits'
import Card,{rememberOpen}from'./Card'
import{hrefFor}from'./nav-map'
import{plainError}from'./lib/errors'
import{useIsPlatformAdmin,balanceWords}from'./lib/viewer'
import SnapshotStamp from'./SnapshotStamp'
import{gateFor}from'./guide/operatingWords'
import{RETIRED_TOOLSETS}from'./retired-services'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const LAYER={0:'Platform',1:'Layer 1',2:'Layer 2',3:'Layer 3',4:'Layer 4'}
const SEV={high:'danger',warning:'warning',info:'neutral'}
const money=v=>v==null?'—':`US$${Number(v).toFixed(2)}`

// ---- notices on each layer page -------------------------------------------------------------------------------------
// v2.15.268 (Platform Admin, 13 Oct 2026 14:56: "these notification are asking for cant be fixed and if followed the link its doesnt open
// the specific card to adjust the values if required"; chose all four). Each notice now says plainly whether a person needs to act
// (Action needed, Action outside StudySearch, Optional) or not (Nothing to do), its Go to button opens the exact card or setting
// (the card is opened and scrolled to; see focusTarget in mature-main.jsx), the universities it is about are listed in the notice with
// Search again or a website box, and information-only notices are kept to Toolsets and limits, not shown on the layer pages.
const LIMITS={page:'services',tab:'limits'}
const go=(label,page,tab,card,at)=>({label,page,tab,card,at})
const NEED={action:['Action needed','warning'],outside:['Action outside StudySearch','warning'],optional:['Optional','neutral'],info:['Nothing to do','success']}
export function noticePlan(n){
  const k=`${n.toolset}:${n.kind}`,key=n.key||'',used=/^Used up/.test(n.detail||'')
  // v2.15.327 (Platform Admin 23 Oct 2026 13:26: "go to openrouter settings doesn't open, check rest of the link"): every Go to names the
  // card it scrolls to (at); goToCard also opens the Toolsets and limits card the toolset cards sit in
  const fc=go('Firecrawl settings',LIMITS.page,LIMITS.tab,'services.toolset.firecrawl','services.toolset.firecrawl')
  const or=go('OpenRouter settings',LIMITS.page,LIMITS.tab,'services.toolset.openrouter','services.toolset.openrouter')
  switch(k){
    case'firecrawl:daily_budget':return{need:'info',say:used?'Nothing to do: this work carries on by itself after midnight, Melbourne time.':'Nothing to do yet: this work stops for the day only if the share is used up.',
      go:go('Daily budget settings',LIMITS.page,LIMITS.tab,'services.toolset.firecrawl','firecrawl:Daily budget')}
    case'firecrawl:search_stopped':return{need:'action',say:'Check each website below, then press Search again.',items:'resume',go:go('Credits by university',LIMITS.page,LIMITS.tab,'services.toolset.firecrawl.credits','services.toolset.firecrawl.credits')}
    case'firecrawl:search_held':return{need:'action',say:'Check the adapter and website below, then press Search again.',items:'resume',go:go('Credits by university',LIMITS.page,LIMITS.tab,'services.toolset.firecrawl.credits','services.toolset.firecrawl.credits')}
    case'firecrawl:no_official_site':return{need:'optional',say:'Enter a website below if you know it. Otherwise nothing to do.',items:'website',go:go('Layer 4 Inbox','layer4','inbox','','')}
    case'firecrawl:shared_site':return{need:'info',say:'Nothing to do, unless a college needs its own website (enter it on the provider).',go:go('Providers','providers','','','')}
    case'firecrawl:low_balance':return{need:'outside',say:'Top up the Firecrawl account. Work stops by itself at the reserve.',go:go('Firecrawl credits',LIMITS.page,LIMITS.tab,'services.firecrawl-credits','services.firecrawl-credits')}
    case'firecrawl:cap_reached':return key.startsWith('firecrawl:2:course_link_cap')
      ?{need:'optional',say:'Raise the monthly cap if the search should carry on this month. Otherwise it carries on next month.',go:go('Course-page search budget',LIMITS.page,LIMITS.tab,'','search-cap')}
      :{need:'optional',say:'Raise the scholarship cap if these pages should be read.',go:go('Scholarship credits','layer2','scholarships','','sch-credits')}
    case'openrouter:refused':return /:rate$/.test(key)?{need:'info',say:'Nothing to do: the pages are read again by themselves.',go:or}
      :{need:'outside',say:/:key_limit$/.test(key)?'Raise or clear the key’s limit at OpenRouter.':/:credit$/.test(key)?'Top up the OpenRouter balance.':'Check the key on Settings.',go:or}
    case'openrouter:low_balance':return{need:'outside',say:'Top up the OpenRouter account.',go:or}
    case'openrouter:not_observed':return{need:'action',say:'Check the job “Read the OpenRouter balance”.',go:go('Task manager','jobs','tasks','','')}
    // SS-016 UR-10 (1 Nov 2026): security.platform_notices_v1 raises this at severity info in Observe only (nothing stopped), warning in Stop at limits
    case'openrouter:over_guard':return{need:'info',say:n.severity==='info'?'Nothing to do: Observe only, so nothing has stopped; it is recorded for the top-up review.':'Nothing to do: it carries on when the UTC day changes. Raise the guard if it should carry on today.',go:go('Daily guards',LIMITS.page,LIMITS.tab,'services.toolset.openrouter','openrouter:Daily guards')}
    case'scheduled_jobs:timeout':return{need:'action',say:'Lower the job’s batch size so each run finishes inside the limit.',go:go('Jobs','jobs','jobs','','')}
    case'scheduled_jobs:failed':return{need:n.severity==='high'?'action':'info',say:n.severity==='high'?'It keeps failing: the job needs a fix.':'Nothing to do unless it repeats.',go:go('Jobs','jobs','jobs','','')}
    case'pipeline:hygiene':return{need:'action',say:'Retire what is unused, fix the security items, and run the drop paste file for what is ready (component register).',go:go('Jobs','jobs','jobs','','')}
    case'pipeline:waste_paused':return{need:'info',say:'Nothing to do: it switches on again by itself when work arrives.',go:go('Pipeline settings','environment','','','settings-register')}
    case'pipeline:waste_frozen':return{need:'action',say:'Check the frozen values and set the right one by hand.',go:go('Pipeline settings','environment','','','settings-register')}
    case'pipeline:fixed_value':return{need:'action',say:'Move the number into a setting so it can be changed on screen.',go:go('Pipeline settings','environment','','','settings-register')}
    case'edge_functions:timeout':return{need:'action',say:'Lower the worker’s per-run limit.',go:fc}
    default:return{need:'action',say:'',go:go('Toolsets and limits',LIMITS.page,LIMITS.tab,'services.toolsets','services.toolsets')}
  }
}
// Opens the card (and any card it sits in) for this session and goes to the page; mature-main scrolls to `at`.
export function goToCard(g){
  if(!g)return
  // v2.15.327: a toolset card sits inside Toolsets and limits, which is opened too; the card itself is scrolled to when no other place is named
  let cards=String(g.card||'').split(',').filter(Boolean)
  if(cards.some(c=>c.startsWith('services.toolset.'))&&!cards.includes('services.toolsets'))cards=['services.toolsets',...cards]
  for(const id of cards)rememberOpen(id)
  const params={};if(cards.length)params.card=cards.join(',');const at=g.at||cards[cards.length-1];if(at)params.at=at
  const next=hrefFor(g.page,g.tab,params).slice(1)
  // already on that address (the notice is on the same screen): the router is told again so it opens and scrolls
  if(window.location.hash.replace(/^#/,'')===next)window.dispatchEvent(new HashChangeEvent('hashchange'))
  else window.location.hash=next
}

export function LayerNotices({layer}){
  const[d,setD]=useState(null),[open,setOpen]=useState(false),[busy,setBusy]=useState(false)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_platform_notices_read',{p_layer:layer});if(!error)setD(data||{})}catch{/* notices are advisory */}}
  useEffect(()=>{setD(null);load()},[layer])
  if(!d)return null
  // information-only notices stay on Toolsets and limits
  const shown=(d.notices||[]).filter(n=>noticePlan(n).need!=='info'),infos=(d.notices||[]).length-shown.length
  const live=shown.filter(n=>!n.acknowledged),seen=shown.filter(n=>n.acknowledged)
  if(!shown.length&&!infos)return null
  const ack=async n=>{const reason=ask(`Acknowledge “${n.title}”? It comes back if it happens again.`);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:'ack',p_args:{notice_key:n.key,reason}});if(error)throw error;await load()}catch(e){window.alert(errText(e))}finally{setBusy(false)}}
  return <section className="tn-strip" data-layer-notices={layer} aria-label="Toolset notices">
    {live.map(n=><Notice key={n.key} n={n} can={d.can_manage&&!busy} onAck={()=>ack(n)} onDone={load}/>)}
    {seen.length>0&&<details className="tn-seen" open={open} onToggle={e=>setOpen(e.currentTarget.open)}><summary>{seen.length} acknowledged</summary>{seen.map(n=><Notice key={n.key} n={n} onDone={load}/>)}</details>}
    {infos>0&&<p className="tn-infos" data-layer-notice-infos><button type="button" className="cf-linkbtn" onClick={()=>goToCard(go('Toolsets and limits',LIMITS.page,LIMITS.tab,'services.toolsets','services.toolsets'))}>
      {infos} information-only notice{infos===1?'':'s'} (nothing to do) on Toolsets and limits</button></p>}
    <SnapshotStamp meta={d.snapshot} label="Notices checked" what="layer-notices"/>
  </section>
}
export function Notice({n,can,onAck,onDone}){
  const plan=noticePlan(n),[label,tone]=NEED[plan.need],gate=gateFor(n.toolset,n.kind) // SS-016 UR-10: which gate raised it
  const cls=plan.need==='info'?'info':n.severity||'info'
  return <div className={`tn-item tn-${cls}`} data-notice={n.key} data-notice-need={plan.need}>
    <BellRing size={15} aria-hidden/>
    <div className="tn-text"><strong>{n.title}</strong>{n.detail&&<span>{n.detail}</span>}
      <span className="tn-need"><span className={`cf-chip tone-${tone}`}>{label}</span>{plan.say||n.hint}</span>
      {plan.items&&(n.items||[]).length>0&&<NoticeItems n={n} mode={plan.items} onDone={onDone}/>}
      {gate&&<small className="tn-gate" data-notice-gate={gate.key}>Gate: {gate.gate}. Changed by: {gate.who}.</small>}
      <small className="tn-meta">{LAYER[n.layer]} · {n.toolset?.replace(/_/g,' ')} · last {fmtDateTime(n.last_at)}{n.acknowledged?` · acknowledged ${fmtDateTime(n.acknowledged_at)}`:''}</small></div>
    <div className="tn-acts">
      {plan.go&&<Button compact onClick={()=>goToCard(plan.go)} data-notice-go={plan.go.at||plan.go.card||plan.go.page}>Go to {plan.go.label}<ArrowRight size={13}/></Button>}
      {can&&!n.acknowledged&&<Button compact onClick={onAck}><Check size={13}/>Acknowledge</Button>}
    </div>
  </div>
}
// The universities a notice is about, with the fix in place: Search again (held or stopped course search) or a website box.
function NoticeItems({n,mode,onDone}){
  const items=n.items||[],[busy,setBusy]=useState(false),[val,setVal]=useState({}),[msg,setMsg]=useState('')
  const resume=async u=>{const reason=ask(`Search course pages again for ${u.name}? Check its website and adapter first.`);if(!reason)return;setBusy(true);setMsg('')
    try{const{error}=await supabase.rpc('admin_firecrawl_search_resume',{p_provider_id:u.provider_id,p_reason:reason});if(error)throw error;setMsg(`${u.name}: course-page search starts again.`);await onDone?.()}catch(e){setMsg(errText(e))}finally{setBusy(false)}}
  const save=async u=>{const url=String(val[u.provider_id]||'').trim();if(!url)return;setBusy(true);setMsg('')
    try{const{error}=await supabase.rpc('admin_provider_website_set',{p_provider_id:u.provider_id,p_url:url});if(error)throw error;setMsg(`${u.name}: website saved. The course-page search starts within minutes.`);setVal(v=>({...v,[u.provider_id]:''}));await onDone?.()}catch(e){setMsg(errText(e))}finally{setBusy(false)}}
  return <details className="tn-items" data-notice-items={n.key}><summary>Show the {fmtNumber(items.length)} {mode==='website'?'providers':'universities'}</summary>
    {msg&&<p className="sl-sub" role="status">{msg}</p>}
    <div className="cf-table-wrap"><table className="cf-table"><tbody>
      {items.map(u=><tr key={u.provider_id} data-notice-item={u.provider_id}>
        <td><strong>{u.name}</strong>{u.reason&&<small className="sl-sub">{u.reason}</small>}{u.searches>0&&<small className="sl-sub">{fmtNumber(u.searches)} searches with no correct course page</small>}</td>
        {mode==='resume'?<><td>{u.website?<a href={u.website} target="_blank" rel="noreferrer">{u.website.replace(/^https?:\/\//,'')}</a>:'No website on record'}</td>
          <td><Button compact disabled={busy} onClick={()=>resume(u)}>Search again</Button></td></>
        :<td><span className="tn-site"><input aria-label={`Website for ${u.name}`} placeholder="https://" value={val[u.provider_id]||''} disabled={busy} onChange={e=>setVal(v=>({...v,[u.provider_id]:e.target.value}))}/>
          <Button compact disabled={busy||!String(val[u.provider_id]||'').trim()} onClick={()=>save(u)}>Save website</Button></span></td>}
      </tr>)}
    </tbody></table></div>
  </details>
}

// ---- Models & services › Toolsets and limits ------------------------------------------------------------------------
export default function Toolsets({onError}){
  const[d,setD]=useState(null),[n,setN]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{setFailed('');try{const[a,b]=await Promise.all([supabase.rpc('admin_toolsets_read'),supabase.rpc('admin_platform_notices_read',{p_layer:null})]);if(a.error)throw a.error;setD(a.data||{});setN(b.data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{load()},[])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Toolsets could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading toolsets…"/></section>
  const can=Boolean(d.can_manage)&&!busy
  const notices=(n?.notices||[])
  return <div className="m-page-stack" data-toolsets>
    <Card id="services.toolsets" title="Toolsets and limits" subtitle="The outside services and platform limits each layer depends on. A notice appears on the layer’s page when one of them hits a limit or times out."
      meta={<span className={`cf-chip tone-${notices.length?'warning':'success'}`}>{notices.length?`${fmtNumber(notices.length)} notice${notices.length===1?'':'s'}`:'No notices'}</span>}>
      {!d.can_manage&&<p className="l3v-note">You can view this. Only a Platform Admin can change it.</p>}
      <SnapshotStamp meta={n?.snapshot} label="Notices checked" what="toolset-notices"/>
      <div className="tn-all" data-toolset-notices>{notices.length?notices.map(x=><Notice key={x.key} n={x} onDone={load}/>):<p className="sl-sub">No notices on any layer.</p>}</div>
    </Card>
    {(d.toolsets||[]).filter(t=>!RETIRED_TOOLSETS.has(t.key)).map(t=><React.Fragment key={t.key}><Toolset t={t} d={d} can={can} write={write}/>{t.key==='firecrawl'&&<><FirecrawlCredits onError={onError}/><FirecrawlWork onError={onError}/></>}</React.Fragment>)}
  </div>
}

const SECTION_ORDER=['Key and plan limits','How the service is used','Daily guards','Target universities','Read pages','Find pages','Runs','Daily budget','Search pass','Sample runs','Notices']
function Toolset({t,d,can,write}){
  const or=t.key==='openrouter'?d.openrouter||{}:null
  const sections=SECTION_ORDER.filter(x=>(t.settings||[]).some(s=>(s.section||'Notices')===x))
  return <Card id={`services.toolset.${t.key}`} title={t.label} subtitle={`${(t.layers||[]).map(l=>LAYER[l]).join(', ')}. ${t.help}`} data-toolset={t.key}
    meta={<>{t.enforcement&&<span className={`cf-chip tone-${t.enforcement==='observe'?'warning':'success'}`}>{t.enforcement==='observe'?'Observe only':'Stops at limits'}</span>}{t.plan?.at_reserve&&<span className="cf-chip tone-danger">At its reserve</span>}</>}>
    {t.key==='firecrawl'&&<p className="tn-jump"><a href="#layer-2-discovery?tab=universities">Firecrawl runs, targets and university adapters are on Layer 2 › Adapters</a></p>}
    {t.enforcement&&<div className="tn-mode" data-toolset-mode={t.key}>
      <span className={`cf-chip tone-${t.enforcement==='observe'?'warning':'success'}`}>{t.enforcement==='observe'?'Observe only — not stopped by the platform':'Stop at limits'}</span>
      {can&&<Button compact onClick={()=>write('enforcement',{toolset:t.key,enforcement:t.enforcement==='observe'?'stop':'observe'},t.enforcement==='observe'?`Make ${t.label} stop at its spend guards and credit floor?`:`Let ${t.label} run past its spend guards and credit floor (observe only)?`)}>{t.enforcement==='observe'?'Switch to stop at limits':'Switch to observe only'}</Button>}
      <small className="sl-sub">{t.reason}{t.updated_at?` · ${fmtDateTime(t.updated_at)}`:''}</small></div>}
    {or&&<OpenRouter or={or}/>}
    {sections.map(sec=><Settings key={sec} title={sec} t={t} rows={t.settings.filter(s=>(s.section||'Notices')===sec)} can={can} write={write}/>)}
  </Card>
}

function Settings({title,t,rows,can,write}){
  const[vals,setVals]=useState({})
  return <div className="tn-section" data-toolset-section={`${t.key}:${title}`}><h4 className="sl-h4">{title}</h4>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Setting</th><th>Value</th><th>Last change</th></tr></thead><tbody>
      {rows.map(s=>{const shown=s.kind==='list'?(s.value||[]).join(', '):String(s.value??'');const v=vals[s.key]??shown;const changed=String(v)!==shown
        const value=s.kind==='list'?v.split(',').map(x=>x.trim()).filter(Boolean):s.kind==='boolean'?v==='true':v
        return <tr key={s.key} data-toolset-setting={`${t.key}.${s.key}`}><td><strong>{s.label}</strong><small className="sl-sub">{s.help}</small></td>
          <td><span className="sl-val tn-val">{s.kind==='boolean'?<select aria-label={s.label} value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}><option value="true">Yes</option><option value="false">No</option></select>
            :<input aria-label={s.label} className={s.kind==='number'?'':'tn-wide'} inputMode={s.kind==='number'?'decimal':'text'} value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}/>}
            <small>{s.unit}{s.kind==='number'&&s.min!=null?` (${fmtNumber(s.min)} to ${fmtNumber(s.max)})`:''}</small>
            {can&&changed&&<Button compact variant="primary" onClick={()=>write('setting',{toolset:t.key,key:s.key,value},`Change "${s.label}" to ${v}?`)}>Save</Button>}</span></td>
          <td><small>{s.reason||'—'}{s.updated_at?` · ${fmtDateTime(s.updated_at)}`:''}</small></td></tr>})}
    </tbody></table></div></div>
}

// v2.15.258 (bug 12/10-01): the AI uses that run now (Layer 3 retired), spend today against each daily guard, and the credit floor.
// Guards and the floor are edited in "Daily guards" below; the mode (Observe only / Stop at limits) is the switch above.
function OpenRouter({or}){
  const admin=useIsPlatformAdmin()
  const b=or.balance||{},floor=Number(or.credit_floor_usd||0),low=b.remaining_usd!=null&&Number(b.remaining_usd)<floor
  return <div className="tn-or" data-openrouter>
    <p data-balance={admin?'figure':'words'}>{admin?<><strong>Balance {money(b.remaining_usd)}</strong> of {money(b.total_credits)} bought · </>:<><strong>Credit: {balanceWords(b.remaining_usd,floor)}</strong> · </>}read {b.observed_at?fmtDateTime(b.observed_at):'never'} (every 15 minutes){admin?<> · credit floor {money(floor)}</>:null}{low&&<span className="cf-chip tone-danger"> Below the floor</span>}</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>AI use</th><th className="num">Calls today (UTC)</th><th className="num">Spent today</th><th className="num">Daily guard</th><th>State</th></tr></thead><tbody>
      {(or.uses||[]).map(g=>{const over=Number(g.guard)>0&&Number(g.spent_today)>=Number(g.guard)
        return <tr key={g.use} data-or-use={g.use}><td>{g.label}</td><td className="num">{fmtNumber(g.calls||0)}</td><td className="num">{money(g.spent_today)}</td><td className="num">{money(g.guard)}</td>
          <td>{g.allowed===false?<span className="cf-chip tone-danger">Stopped (stop at limits)</span>:over?<span className="cf-chip tone-warning">Past its guard (observed)</span>:<span className="cf-chip tone-success">Running</span>}</td></tr>})}
    </tbody></table></div>
    <small className="sl-sub">Change the guards and the floor under Daily guards below. Spend by day (UTC, last 14 days): {(or.spend_by_day||[]).map(x=>`${x.day} ${money(x.usd)} (${fmtNumber(x.calls)} calls)`).join(' · ')||'none'}</small>
  </div>
}

// SS-020 step 1 (Decision 269, 3 Nov 2026): the Sample runs and Search pass cards retired with the Serper and ScrapingBee cards (Firecrawl
// only, 4 Oct 2026). Their history stays in pipeline.toolset_sample_runs, toolset_sample_items and search_pass_links; the functions and the
// toolset-runner edge function are marked retiring in pipeline.component_register (migration 20261104340000).
