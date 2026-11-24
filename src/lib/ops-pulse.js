// CF-247 S1-UX s824 to s827 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24, chat S1-UX): pure helpers (no React) for the Dashboard KPI cards
// (s824), the 4-stage pipeline board on Platform Health (s825), the Layer 4 rule groups (s826) and the contextual ? help drawer (s827). The Layer 4
// hold banner and banned-word removal are S1-RM-Design's (s819-s821, Pilot PR 1411: src/lib/description-check.js).
// Shared by src/OpsPulse.jsx, src/HelpDrawer.jsx, src/Layer4RuleGroups.jsx, src/PlatformHealth.jsx and the s823-s827 spec.
// Every figure comes from the stored ops pulse (pipeline.ops_pulse_snapshot, migration 20261120140000, read inside admin_read 'platform_health'):
// nothing here starts another database read. An unknown figure stays unknown (shown as a dash), never 0.
import{fmtNumber}from'./format.js'
import{CD_HOLD,cdHoldKey}from'./cdesc-hold.js'

const num=v=>v===null||v===undefined||v===''||Number.isNaN(Number(v))?null:Number(v)

// the four stages, in the order data moves; each opens the existing screen where its controls already live (no new control is added here)
export const STAGES=[
  {n:1,key:'registers',name:'Official Registers',icon:'Landmark',href:'#layer-1-register',screen:'Layer 1 Register',queuedLabel:'waiting in the register checks',meter:'Register checks passing',
    action:'Re-check a register',actionHint:'Opens Layer 1 Register, where each register has Run now. A register whose file has not changed writes nothing.'},
  {n:2,key:'capture',name:'Page Capture',icon:'ScanLine',href:'#scheduled-jobs?tab=automations',screen:'Automations',queuedLabel:'pages and calls waiting',meter:'Capture checks passing',
    action:'Pause or resume capture',actionHint:'Opens Automations, where each capture job has its pause switch. Nothing is lost while capture is paused; the queue keeps its order.'},
  {n:3,key:'extraction',name:'AI Extraction & Auto-Clean',icon:'Sparkles',href:'#layer-2-discovery?tab=operations',screen:'Layer 2/3 › Operations',queuedLabel:'stored pages waiting to be read',meter:'Extraction checks passing',
    action:'Run a small bounded batch',actionHint:'Opens Layer 2/3 › Operations: preview, then Run now on a bounded batch inside the daily cap.'},
  {n:4,key:'catalogue',name:'Live Catalogue',icon:'LibraryBig',href:'#layer-4-review',screen:'Layer 4 Review',queuedLabel:'decisions waiting on you',meter:'Catalogue checks passing',
    action:'Open Layer 4 by rule',actionHint:'Opens Layer 4 Review, grouped by what a person must do.'}
]
export const STATUS_WORDS={ok:'Running normally',warning:'Slowed or due: needs attention',critical:'Stopped: fix first',unknown:'Not measured yet'}
export const toneOf=s=>s==='ok'?'ok':s==='warning'?'warn':s==='critical'?'crit':'unknown'

/** The pulse from a platform_health answer: null when the stored pulse is not there (older deployment, or the snapshot is stale and the read counted live). */
export function pulseOf(health){const p=health&&typeof health==='object'?health.pulse:null;return p&&typeof p==='object'&&Array.isArray(p.stages)?p:null}

/** One stage card: status, tone, queued count and its health meter (share of its checks passing), all from the stored row. */
export function stageCards(pulse){
  const by=new Map((pulse?.stages||[]).map(s=>[Number(s.stage),s]))
  return STAGES.map(m=>{const s=by.get(m.n)||{},checks=num(s.checks),bad=Array.isArray(s.attention)?s.attention.length:0
    const passing=checks==null?null:Math.max(0,checks-bad),pct=checks?Math.round(passing/checks*100):null
    const status=s.status||'unknown'
    return{...m,status,tone:toneOf(status),words:STATUS_WORDS[status]||STATUS_WORDS.unknown,queued:num(s.queued),checks,passing,meterPct:pct,
      meterText:checks?`${passing} of ${checks} checks passing`:'No checks report here yet',attention:Array.isArray(s.attention)?s.attention:[],rate:stageRate(pulse,m.n)}})
}

/** The connected track between stages: how far data flows before the first stage that needs attention (1 to 4; 4 when all are healthy). */
export function flowReach(cards){const i=cards.findIndex(c=>c.tone==='warn'||c.tone==='crit');return i===-1?cards.length:i+1}

// s930 (S1-Dynamic-Lookups): the countries come from the live lookups (target countries) or, without them, from the scores themselves
const regionName=(()=>{try{const d=new Intl.DisplayNames(['en-AU'],{type:'region'});return cc=>{try{return d.of(cc)||cc}catch{return cc}}}catch{return cc=>cc}})()
/** One bar a country from the stored completeness scores; a country with no score is shown as not measured. */
export function completenessBars(pulse,codes){const c=pulse?.completeness||{},list=Array.isArray(codes)&&codes.length?codes:Object.keys(c)
  return list.map(cc=>[cc,regionName(cc)]).map(([cc,label])=>{const pct=num(c?.[cc]?.completeness);return{cc,label,pct,courses:num(c?.[cc]?.courses),text:pct==null?'—':`${Math.round(pct)}%`}})}

/** Today's AI spend against the daily cap (as the budgets check last measured it). */
export function spendOf(pulse){const b=pulse?.budget||{},spend=num(b.spend_usd),cap=num(b.cap_usd)
  return{spend,cap,pct:spend!=null&&cap?Math.min(100,Math.round(spend/cap*100)):null,text:spend==null?'—':`US$${spend.toFixed(2)}`,capText:cap==null?'cap not set':`of the US$${cap.toFixed(2)} daily cap`}}

/** s836 (20 Nov 2026 14:40): the daily cap from the budgets check in the same Platform Health answer when the stored pulse has none (the check writes
 * ai_daily_ceiling_usd; the pulse before migration 20261120145000 read an older key). No extra read. */
export function withBudgetCap(pulse,health){if(!pulse)return pulse;const b=pulse.budget||{};if(num(b.cap_usd)!=null)return pulse
  const c=(Array.isArray(health?.checks)?health.checks:[]).find(x=>x?.key==='budgets'),d=c?.detail||{},cap=num(d.ai_daily_ceiling_usd??d.openrouter_daily_ceiling_usd)
  return cap==null?pulse:{...pulse,budget:{...b,cap_usd:cap,spend_usd:b.spend_usd??d.openrouter_spend_24h_usd}}}

/** s838 (20 Nov 2026 14:41): a stage's rate against its normal rate, from the stored pulse's rates (migration 20261120145000). Stage 2: pages captured
 * in the window against the average of the days before; stage 3: the auto-clean pass rate (machine admissions admitted of all decided). */
export function stageRate(pulse,n){const r=pulse?.rates;if(!r||typeof r!=='object')return null
  const h=num(r.window_hours),d=num(r.baseline_days),win=h?`last ${h} h`:'window',base=d?`the ${d} days before`:'before'
  if(n===2){const c=r.capture||{},w=num(c.window),norm=num(c.normal),ratio=num(c.ratio);if(w==null)return null
    const vs=ratio==null?'no normal rate yet':ratio>=1.15?`${ratio.toFixed(1)}× normal`:ratio<=0.85?`${Math.round(ratio*100)}% of normal`:'about normal'
    return{key:'capture',label:'Capture rate vs normal',pct:ratio==null?null:Math.min(100,Math.round(ratio/2*100)),tone:ratio!=null&&ratio<0.5?'warn':'ok',
      text:`${fmtNumber(w)} pages in the ${win} · ${vs}${norm!=null?` (normal ${fmtNumber(Math.round(norm))} per ${h||24} h, from ${base})`:''}`}}
  if(n===3){const a=r.autoclean||{},rate=num(a.rate),norm=num(a.normal_rate),dec=num(a.decided);if(rate==null)return null
    const diff=norm==null?null:Math.round((rate-norm)*10)/10
    return{key:'autoclean',label:'Auto-clean pass rate',pct:Math.round(rate),tone:diff!=null&&diff<=-10?'warn':'ok',
      text:`${rate}% admitted by the machine rules in the ${win} (${fmtNumber(dec)} decided)${norm!=null?` · normal ${norm}%${diff?` (${diff>0?'+':''}${diff} points)`:''}`:''}`}}
  return null}

/** The five KPI cards (Dashboard and Platform Health). */
export function kpiCards(pulse,codes){
  const st=pulse?.status||'unknown',bars=completenessBars(pulse,codes),sp=spendOf(pulse),wait=num(pulse?.layer4_waiting),block=num(pulse?.blockers)
  const kinds=pulse?.layer4_by_kind&&typeof pulse.layer4_by_kind==='object'?Object.keys(pulse.layer4_by_kind).length:null
  return[
    {key:'status',icon:'Activity',label:'System status',tone:toneOf(st),value:st==='ok'?'Healthy':st==='warning'?'Needs attention':st==='critical'?'Something is broken':'Not measured yet',
      detail:num(pulse?.warning)!=null?`${num(pulse.critical)||0} critical · ${num(pulse.warning)||0} warning`:''},
    {key:'completeness',icon:'Gauge',label:'Catalogue completeness',tone:'info',value:null,bars,detail:'Stored scores'},
    {key:'waiting',icon:'Inbox',label:'Decisions waiting on you',tone:wait?'warn':'ok',value:wait==null?'—':fmtNumber(wait),detail:kinds==null?'':`Layer 4, in ${kinds} kind${kinds===1?'':'s'}`},
    {key:'blockers',icon:'OctagonAlert',label:'Active blockers',tone:block?'crit':'ok',value:block==null?'—':String(block),detail:block?'critical issues open':'none open'},
    {key:'spend',icon:'Wallet',label:'AI & crawl spend today',tone:sp.pct!=null&&sp.pct>=80?'warn':'info',value:sp.text,detail:sp.capText,meterPct:sp.pct}
  ]
}

/** Active failures: every stage check that is warning or critical, with the stage it belongs to. */
export function activeFailures(pulse){return stageCards(pulse).flatMap(c=>c.attention.map(a=>({stage:c.name,stageN:c.n,icon:c.icon,href:c.href,key:a.key,label:a.label||a.key,status:a.status,tone:toneOf(a.status)})))}

/** System internals: the checks list, attention first; only those needing attention unless Show all is ticked. */
export function internalsCounts(pulse,checks){const c=pulse?.checks
  if(c&&typeof c==='object')return{attention:num(c.attention)||0,healthy:num(c.healthy)||0,skipped:num(c.skipped)||0,total:num(c.total)||0}
  const l=Array.isArray(checks)?checks:[];return{attention:l.filter(x=>x.status==='warning'||x.status==='critical').length,healthy:l.filter(x=>x.status==='ok').length,skipped:l.filter(x=>x.status==='skipped').length,total:l.length}}
export const needsAttention=c=>c?.status==='warning'||c?.status==='critical'

// ---------- Layer 4: the cards on screen, grouped by the rule that holds them (s826; no server read, no decision) ----------
/** The rule that holds one Layer 4 item: the description hold code (course: machine.reason_code; university: proposed.held_rule), else the first clause of its reason. */
export function ruleOf(it){
  const d=it?.detail||{}
  if(it?.kind==='provider_description'){const key=cdHoldKey(d?.machine?.reason_code??d?.proposed?.held_rule,d);return{key:`cd:${key}`,label:(CD_HOLD[key]||CD_HOLD.other).title}}
  const why=String(it?.why||'').trim().split(/(?<=[.;:])\s+/)[0].replace(/[.;:]+$/,'').trim()
  return{key:`${it?.kind||'item'}:${why.toLowerCase()}`,label:why||'Held by a check'}
}
/** Groups, largest first (ties keep the order the cards arrive in, oldest first). */
export function ruleGroups(items){const m=new Map()
  for(const it of items||[]){const r=ruleOf(it);if(!m.has(r.key))m.set(r.key,{...r,items:[]});m.get(r.key).items.push(it)}
  return[...m.values()].map((g,i)=>({...g,n:g.items.length,i})).sort((a,b)=>b.n-a.n||a.i-b.i)}
/** The sidebar is worth showing only when it actually groups something. */
export const groupsWorthShowing=g=>g.length>1&&g.some(x=>x.n>1)

// ---------- Contextual ? help: three steps for each main screen, kept in step with Guides › Platform guide ----------
export const HELP_GUIDES={
  dashboard:{title:'Dashboard',what:'Start here each day',guide:'#platform-guide',
    steps:['Read the five cards: system status, completeness by country, decisions waiting, blockers and today’s spend.','Open the first item under Active failures or Decisions waiting on you.','Come back here when it is done; the figures are rebuilt every 5 minutes.'],
    who:'What you see depends on your role. A Counsellor or Viewer sees catalogue search only, and no pipeline figures are read for that role.'},
  health:{title:'Platform Health',what:'Find where data is stuck',guide:'#platform-guide',
    steps:['Find the stage that is not green in the 4-stage pipeline.','Select it to read what it is doing and why.','Use its action, which opens the screen where that stage’s controls live, or open System internals for the job-by-job view.'],
    who:'Curator and above can open this screen; pausing and running jobs needs a Pipeline Operator or above.'},
  layer4:{title:'Layer 4 Review',what:'Clear the decisions waiting on you',guide:'#platform-guide',
    steps:['Choose a queue, then a rule on the left (Waiting, grouped by rule); Preview the batch shows its records.','Read the main hold reason at the top of the card and check the page’s own words.','Decide with the one action bar: Save Edit & Admit, Approve As-Is or Reject. A banned word has Remove & Admit under its cleaned text, or one confirmed batch.'],
    who:'Admitting needs a Pipeline Operator or above. Every decision keeps your name and your reason.'},
  catalogue:{title:'Catalogue',what:'Check and correct catalogue data',guide:'#platform-guide',
    steps:['Filter by country and completeness to find what needs attention.','Page 50 at a time with Next 50; filters stay quick on 36,000+ courses.','Open a row to edit. A field locked by hand shows a Human Locked pill and automation never changes it.'],
    who:'Counsellors and Viewers can search and read; editing needs a Curator or above.'}
}
export const helpFor=k=>HELP_GUIDES[k]||HELP_GUIDES.dashboard
