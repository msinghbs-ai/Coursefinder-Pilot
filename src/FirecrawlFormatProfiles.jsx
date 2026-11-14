// CF-247 v2.16.2 Firecrawl format profiles (Platform Admin 14 Nov 2026 19:19; mock-up accepted 20:13). A card of Models & services ›
// Toolsets and limits, under the Firecrawl card (F-OPS.08: no new dashboard or second settings editor). What every Firecrawl page read asks
// for, by profile: formats (markdown, rawHtml, html, links, screenshot), main content only, tags left out or kept, the Firecrawl copy age,
// wait and time allowed, optional actions, and crawl options (checked only; no lane crawls). Each worker lane is mapped to a profile, or to
// its own request (AER v1 lanes, Decision 276; adapter capture; the probe); a university can have its own profile for one lane.
// Reads: admin_fc_profiles_read_v1 (Curator and above). Writes: admin_fc_profiles_set_v1 (Platform Admin, a reason, the version it was
// opened at), and the screenshot size limit through admin_toolsets_write('setting'). Course pages stay whole page (onlyMainContent false)
// until a test read shows rawHtml keeps the side-panel entry bands (Platform Admin 14 Nov 2026 20:13).
import React,{useEffect,useMemo,useState}from'react'
import{Plus,RefreshCw,Trash2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtDateTime,fmtNumber}from'./ui-kit'
import Card from'./Card'
import ProviderListPicker,{useProviderNames}from'./ProviderListPicker'
import{plainError}from'./lib/errors'
import{FORMATS,NEVER_SENT,ACTION_TYPES,LANE_OWN,LANES,LANE_NAME,FROZEN_LANES,HOUR,checkAll,keptText,preview,listText,textList,numOrNull,keyFor}from'./lib/fc-profiles.js'
import'./fc-format-profiles.css'

const clone=v=>JSON.parse(JSON.stringify(v??null))
const FORMAT_NOTE={markdown:'the page as text, already cleaned',rawHtml:'the whole page as sent, for the readers and the audit trail',html:'the cleaned page as HTML',links:'every link on the page',screenshot:'a picture of the page (kept as received)'}
const profileLabel=(P,k)=>k===LANE_OWN?'The lane’s own request':(P?.[k]?.name||k)

export default function FirecrawlFormatProfiles({onError}){
  const[d,setD]=useState(null)
  const meta=d?<>{d.version!=null&&<span className="cf-chip tone-neutral" data-fcp-version>Version {fmtNumber(d.version)}</span>}{(d.problems||[]).length>0&&<span className="cf-chip tone-danger">Not in use: a problem</span>}</>:null
  return <Card id="services.toolset.firecrawl.formats" title="Firecrawl › Format profiles" subtitle="What every Firecrawl page read asks for. One request per page, 1 credit: rawHtml and markdown together by default, kept with the same evidence." meta={meta} data-fc-profiles>
    <Profiles onError={onError} onLoaded={setD}/>
  </Card>
}

function Profiles({onError,onLoaded}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[draft,setDraft]=useState(null),[sel,setSel]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[mode,setMode]=useState('sched'),[gen,setGen]=useState(0)
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_fc_profiles_read_v1');if(error)throw error;const v=data||{};setD(v);onLoaded?.(v)
    setDraft({profiles:clone(v.profiles||{}),lanes:clone(v.lanes||{}),overrides:clone(v.overrides||[])});setSel(s=>s&&v.profiles?.[s]?s:Object.keys(v.profiles||{})[0]||'');setGen(g=>g+1)}catch(e){setFailed(plainError(e))}}
  useEffect(()=>{load()},[])// eslint-disable-line react-hooks/exhaustive-deps
  const changed=useMemo(()=>d&&draft?JSON.stringify(draft)!==JSON.stringify({profiles:d.profiles||{},lanes:d.lanes||{},overrides:d.overrides||[]}):false,[d,draft])
  const problems=useMemo(()=>draft?checkAll(draft):[],[draft])
  if(failed&&!d)return <div><Empty text={`Format profiles could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></div>
  if(!d||!draft)return <Loading label="Loading format profiles…"/>
  const can=Boolean(d.can_edit)&&!busy,P=draft.profiles,cur=P[sel]
  const setProf=fn=>{setMsg('');setDraft(x=>{const y=clone(x);fn(y.profiles[sel]);return y})}
  const setLane=(l,k)=>{setMsg('');setDraft(x=>({...x,lanes:{...x.lanes,[l]:k}}))}
  const addProfile=()=>{const name=`New profile ${Object.keys(P).length+1}`,k=keyFor(name,Object.keys(P));setDraft(x=>({...x,profiles:{...x.profiles,[k]:{name,about:'',formats:['rawHtml','markdown'],onlyMainContent:false,maxAgeMs:48*HOUR}}}));setSel(k)}
  const used=k=>Object.values(draft.lanes).filter(v=>v===k).length+draft.overrides.filter(o=>o.profile===k).length
  const removeProfile=()=>{if(used(sel))return;setDraft(x=>{const y=clone(x);delete y.profiles[sel];return y});setSel(Object.keys(P).find(k=>k!==sel)||'')}
  const discard=()=>{setDraft({profiles:clone(d.profiles||{}),lanes:clone(d.lanes||{}),overrides:clone(d.overrides||[])});setMsg('');setGen(g=>g+1)}
  const save=async()=>{setBusy(true);setMsg('')
    try{const{data,error}=await supabase.rpc('admin_fc_profiles_set_v1',{p_profiles:draft.profiles,p_lanes:draft.lanes,p_overrides:draft.overrides,p_reason:reason.trim(),p_expected_version:d.version??null})
      if(error)throw error;setReason('');await load();setMsg(`Saved as version ${fmtNumber(data?.version)}. The worker uses it from its next run.`)}
    catch(e){const t=plainError(e);setMsg(t);onError?.(t)}finally{setBusy(false)}}
  return <div className="fcp" data-fc-profiles-body>
    {!d.can_edit&&<p className="l3v-note">You can view this. Only a Platform Admin can change it.</p>}
    {(d.problems||[]).length>0&&<p className="fcp-alert" role="alert" data-fcp-server-problem>The saved set has a problem, so the worker is not using it: every lane sends its own request. {d.problems.join('; ')}</p>}
    <p className="fcp-never" data-fcp-never>Only {FORMATS.join(', ')} can be asked for. <strong>Never sent</strong>, refused here and by the server: {NEVER_SENT.map(f=><code key={f}>{f}</code>).reduce((a,b)=>[a,', ',b])} (each costs extra credits or runs an AI pass over the page).</p>

    <div className="fcp-grid">
      <nav className="fcp-list" aria-label="Profiles">
        {Object.entries(P).map(([k,p])=><button type="button" key={k} className={`fcp-tab${k===sel?' is-on':''}`} aria-pressed={k===sel} onClick={()=>setSel(k)} data-fcp-profile={k}>
          <strong>{p.name||k}</strong><small>{(p.formats||[]).join(' + ')} · {fmtNumber(used(k))} lane{used(k)===1?'':'s'}</small></button>)}
        {can&&<Button compact onClick={addProfile}><Plus size={14}/>Add profile</Button>}
      </nav>
      {cur?<ProfileEditor key={`${sel}:${gen}`} k={sel} p={cur} can={can} setProf={setProf} used={used(sel)} onRemove={removeProfile} mode={mode} setMode={setMode}/>:<Empty text="Choose a profile."/>}
    </div>

    <section className="fcp-section" data-fcp-lanes><h4 className="sl-h4">Which profile each lane uses</h4>
      <p className="sl-sub">A lane not listed, and a lane set to “The lane’s own request”, sends exactly what it sends today. Entry requirement lanes (AER v1) stay on their own request while AER v1 is frozen.</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Lane</th><th>Profile</th><th>Kept with the evidence</th></tr></thead><tbody>
        {LANES.map(([l])=>{const k=draft.lanes[l]??LANE_OWN,frozen=FROZEN_LANES.has(l)
          return <tr key={l} data-fcp-lane={l}><td><strong>{LANE_NAME[l]}</strong><small className="sl-sub"><code>{l}</code></small></td>
            <td>{frozen?<span title="AER v1 is frozen (Decision 276)">{profileLabel(P,k)}</span>
              :<select aria-label={`Profile for ${LANE_NAME[l]}`} value={k} disabled={!can} onChange={e=>setLane(l,e.target.value)}>
                <option value={LANE_OWN}>The lane’s own request</option>{Object.entries(P).map(([pk,p])=><option key={pk} value={pk}>{p.name||pk}</option>)}</select>}</td>
            <td><small>{keptText(l,k===LANE_OWN?null:P[k])}</small></td></tr>})}
      </tbody></table></div>
    </section>

    <Overrides key={gen} draft={draft} setDraft={x=>{setMsg('');setDraft(x)}} can={can}/>
    <ShotLimit d={d} can={can} onDone={load} onError={onError}/>

    <div className={`fcp-save${changed?' is-dirty':''}`} data-fcp-save>
      {problems.length>0&&<ul className="fcp-problems" role="alert" data-fcp-problems>{problems.map((p,i)=><li key={i}>{p}</li>)}</ul>}
      {can&&<><label className="fcp-reason"><span>Reason (kept in the log)</span><input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why this change" disabled={!changed}/></label>
        <div className="fcp-save-row"><span className="sl-sub">{changed?'Unsaved changes':'No changes'}{d.saved_at?` · version ${fmtNumber(d.version)} saved ${fmtDateTime(d.saved_at)}`:''}</span>
          <Button compact disabled={!changed||busy} onClick={discard}>Discard</Button>
          <Button compact variant="primary" disabled={!changed||busy||problems.length>0||reason.trim().length<4} onClick={save}>Save profiles</Button></div></>}
      {msg&&<p className="sl-sub" role="status" data-fcp-msg>{msg}</p>}
      {(d.history||[]).length>0&&<details className="fcp-history"><summary>Last changes</summary><ul>{d.history.map((h,i)=><li key={i}>Version {fmtNumber(h.version)} · {fmtDateTime(h.at)} · {h.reason}</li>)}</ul></details>}
    </div>
  </div>
}

function ProfileEditor({k,p,can,setProf,used,onRemove,mode,setMode}){
  const[acts,setActs]=useState(p.actions?.length?JSON.stringify(p.actions,null,1):''),[actErr,setActErr]=useState('')
  const num=(field,scale=1)=>e=>{const v=numOrNull(e.target.value);setProf(x=>{if(v==null||Number.isNaN(v))delete x[field];else x[field]=Math.round(v*scale)})}
  const toggle=f=>setProf(x=>{const has=x.formats.includes(f);x.formats=has?x.formats.filter(y=>y!==f):FORMATS.filter(y=>y===f||x.formats.includes(y))})
  const setActions=s=>{setActs(s);if(!s.trim()){setActErr('');setProf(x=>{delete x.actions});return}
    try{const a=JSON.parse(s);if(!Array.isArray(a))throw Error('a JSON list is needed');setActErr('');setProf(x=>{x.actions=a})}catch(e){setActErr(`Actions are not valid yet: ${e.message}`)}}
  const crawl=p.crawl||{}
  const setCrawl=(f,v)=>setProf(x=>{const c={...(x.crawl||{})};if(v===''||v==null)delete c[f];else c[f]=v;if(Object.keys(c).length)x.crawl=c;else delete x.crawl})
  const body=preview(p,mode==='now')
  return <div className="fcp-edit" data-fcp-editor={k}>
    <div className="fcp-row"><label className="fcp-field"><span>Name</span><input value={p.name||''} disabled={!can} onChange={e=>setProf(x=>{x.name=e.target.value})}/></label>
      <label className="fcp-field fcp-wide"><span>What it is for</span><input value={p.about||''} disabled={!can} onChange={e=>setProf(x=>{x.about=e.target.value})}/></label></div>
    <p className="sl-sub">Used by {fmtNumber(used)} lane{used===1?'':'s'} or override{used===1?'':'s'}. {can&&(used?'A profile in use cannot be removed.':<Button compact onClick={onRemove}><Trash2 size={13}/>Remove profile</Button>)}</p>

    <fieldset className="fcp-fs"><legend>Output formats</legend>
      {FORMATS.map(f=><label key={f} className="fcp-check"><input type="checkbox" checked={p.formats.includes(f)} disabled={!can} onChange={()=>toggle(f)} data-fcp-format={f}/><code>{f}</code><small>{FORMAT_NOTE[f]}</small></label>)}
      {p.formats.includes('screenshot')&&<label className="fcp-check"><input type="checkbox" checked={!!p.screenshotFullPage} disabled={!can} onChange={e=>setProf(x=>{x.screenshotFullPage=e.target.checked})}/>Whole page, not only the first screen</label>}
      <small className="sl-sub">A screenshot is saved as received beside the evidence before Firecrawl’s 24-hour link expires; WebP conversion waits for its own checks.</small></fieldset>

    <fieldset className="fcp-fs"><legend>Content filtering</legend>
      <label className="fcp-field"><span>Main content only</span><select value={p.onlyMainContent===undefined?'':String(p.onlyMainContent)} disabled={!can} onChange={e=>setProf(x=>{if(e.target.value==='')delete x.onlyMainContent;else x.onlyMainContent=e.target.value==='true'})}>
        <option value="false">No: the whole page (side panels, country tables)</option><option value="true">Yes: leave out menus, headers and footers</option><option value="">The lane’s own setting</option></select>
        <small>Shapes markdown and html. Course pages stay whole page until a test read shows rawHtml keeps the side-panel entry bands.</small></label>
      <div className="fcp-row"><label className="fcp-field fcp-wide"><span>Leave out tags</span><input value={listText(p.excludeTags)} placeholder="e.g. nav, footer, script, style" disabled={!can} onChange={e=>setProf(x=>{const v=textList(e.target.value);if(v.length)x.excludeTags=v;else delete x.excludeTags})}/></label>
        <label className="fcp-field fcp-wide"><span>Keep only tags</span><input value={listText(p.includeTags)} placeholder="Empty keeps everything not left out" disabled={!can} onChange={e=>setProf(x=>{const v=textList(e.target.value);if(v.length)x.includeTags=v;else delete x.includeTags})}/></label></div></fieldset>

    <fieldset className="fcp-fs"><legend>Cache, waiting and time allowed</legend><div className="fcp-row">
      <label className="fcp-field"><span>Firecrawl copy up to (hours)</span><input inputMode="decimal" defaultValue={p.maxAgeMs==null?'':p.maxAgeMs/HOUR} disabled={!can} onChange={num('maxAgeMs',HOUR)}/><small>Scheduled reads; 48 is Firecrawl’s own default. Run now always asks for a fresh page.</small></label>
      <label className="fcp-field"><span>Wait after load (ms)</span><input inputMode="numeric" defaultValue={p.waitFor??''} placeholder="The lane’s own" disabled={!can} onChange={num('waitFor')}/><small>0 to 60,000.</small></label>
      <label className="fcp-field"><span>Time allowed (ms)</span><input inputMode="numeric" defaultValue={p.timeout??''} placeholder="The lane’s own" disabled={!can} onChange={num('timeout')}/><small>1,000 to 300,000; never past the lane’s own time-out.</small></label></div></fieldset>

    <fieldset className="fcp-fs"><legend>Actions before the read (optional)</legend>
      <textarea rows={3} value={acts} disabled={!can} onChange={e=>setActions(e.target.value)} placeholder='[{"type":"click","selector":"#international-tab"},{"type":"wait","milliseconds":2000}]' aria-label="Actions"/>
      <small className="sl-sub">A JSON list. Allowed: {ACTION_TYPES.join(', ')}.</small>{actErr&&<small className="fcp-err" role="alert">{actErr}</small>}</fieldset>

    <details className="fcp-fs fcp-crawl" data-fcp-crawl><summary>Crawl options <span className="cf-chip tone-neutral">Saved and checked; no lane crawls yet</span></summary><div className="fcp-row">
      <label className="fcp-field"><span>Pages at most</span><input inputMode="numeric" defaultValue={crawl.limit??''} disabled={!can} onChange={e=>setCrawl('limit',numOrNull(e.target.value))}/></label>
      <label className="fcp-field"><span>Link depth</span><input inputMode="numeric" defaultValue={crawl.maxDiscoveryDepth??''} disabled={!can} onChange={e=>setCrawl('maxDiscoveryDepth',numOrNull(e.target.value))}/></label>
      <label className="fcp-field"><span>Site map</span><select value={crawl.sitemap||''} disabled={!can} onChange={e=>setCrawl('sitemap',e.target.value)}><option value="">Firecrawl’s default</option><option value="include">include</option><option value="skip">skip</option><option value="only">only</option></select></label>
      <label className="fcp-field fcp-wide"><span>Only paths matching</span><input defaultValue={listText(crawl.includePaths)} disabled={!can} onChange={e=>setCrawl('includePaths',textList(e.target.value).length?textList(e.target.value):'')}/></label>
      <label className="fcp-field fcp-wide"><span>Never paths matching</span><input defaultValue={listText(crawl.excludePaths)} disabled={!can} onChange={e=>setCrawl('excludePaths',textList(e.target.value).length?textList(e.target.value):'')}/></label></div>
      <small className="sl-sub">A crawl would send this profile’s formats and filters as its scrape options. Starting crawls is a separate feature with its own credit share.</small></details>

    <div className="fcp-fs" data-fcp-preview><div className="fcp-row fcp-between"><strong>What Firecrawl is sent</strong>
      <span className="fcp-seg" role="group" aria-label="Kind of read"><button type="button" aria-pressed={mode==='sched'} className={mode==='sched'?'is-on':''} onClick={()=>setMode('sched')}>Scheduled read</button><button type="button" aria-pressed={mode==='now'} className={mode==='now'?'is-on':''} onClick={()=>setMode('now')}>Run now</button></span></div>
      <pre className="fcp-pre">{JSON.stringify(body,null,2)}</pre>
      <small className="sl-sub">The lane adds its own proxy, location, and wait or time allowed where this profile leaves them blank. Kept with the evidence: profile and version, formats asked for, Firecrawl cache state, the page’s own status and credits used.</small></div>
  </div>
}

function Overrides({draft,setDraft,can}){
  const[pid,setPid]=useState(''),[lane,setLane]=useState(LANES[0][0]),[prof,setProf]=useState(Object.keys(draft.profiles)[0]||LANE_OWN),[why,setWhy]=useState('')
  const names=useProviderNames(draft.overrides.map(o=>o.provider_id))
  const add=()=>{if(!pid||draft.overrides.some(o=>o.provider_id===pid&&o.lane===lane))return;setDraft({...draft,overrides:[...draft.overrides,{provider_id:pid,lane,profile:prof,...(why.trim()?{why:why.trim()}:{})}]});setPid('');setWhy('')}
  const remove=i=>setDraft({...draft,overrides:draft.overrides.filter((_,j)=>j!==i)})
  const lanes=LANES.filter(l=>!FROZEN_LANES.has(l[0]))
  return <section className="fcp-section" data-fcp-overrides><h4 className="sl-h4">University overrides</h4>
    <p className="sl-sub">A university that needs another profile for one lane, for example a site that keeps its fees outside the main content.</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>University</th><th>Lane</th><th>Profile</th><th>Why</th>{can&&<th/>}</tr></thead><tbody>
      {draft.overrides.length?draft.overrides.map((o,i)=><tr key={`${o.provider_id}:${o.lane}`} data-fcp-override={`${o.provider_id}:${o.lane}`}><td>{names[o.provider_id]?.name||o.provider_id.slice(0,8)}</td><td>{LANE_NAME[o.lane]||o.lane}</td><td>{profileLabel(draft.profiles,o.profile)}</td><td><small>{o.why||'—'}</small></td>
        {can&&<td><Button compact onClick={()=>remove(i)}>Remove</Button></td>}</tr>):<tr><td colSpan={can?5:4} className="cf-empty-cell">No overrides: every university uses its lane’s profile.</td></tr>}
    </tbody></table></div>
    {can&&<div className="fcp-add" data-fcp-add-override>
      <div className="fcp-field fcp-wide"><span>University</span><ProviderListPicker value={pid} label="the override" emptyText="Type a university’s name" onChange={v=>{const ids=textList(v);setPid(ids[ids.length-1]||'')}}/></div>
      <label className="fcp-field"><span>Lane</span><select value={lane} onChange={e=>setLane(e.target.value)}>{lanes.map(([l,w])=><option key={l} value={l}>{w}</option>)}</select></label>
      <label className="fcp-field"><span>Profile</span><select value={prof} onChange={e=>setProf(e.target.value)}><option value={LANE_OWN}>The lane’s own request</option>{Object.entries(draft.profiles).map(([k,p])=><option key={k} value={k}>{p.name||k}</option>)}</select></label>
      <label className="fcp-field fcp-wide"><span>Why</span><input value={why} onChange={e=>setWhy(e.target.value)}/></label>
      <Button compact disabled={!pid} onClick={add}><Plus size={14}/>Add override</Button></div>}
  </section>
}

function ShotLimit({d,can,onDone,onError}){
  const[v,setV]=useState(String(d.screenshot_max_mb??'')),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const changed=v!==String(d.screenshot_max_mb??'')
  const save=async()=>{setBusy(true);try{const{error}=await supabase.rpc('admin_toolsets_write',{p_action:'setting',p_args:{toolset:'firecrawl',key:'screenshot_max_mb',value:Number(v),reason:reason.trim()}});if(error)throw error;setReason('');await onDone()}catch(e){onError?.(plainError(e))}finally{setBusy(false)}}
  return <div className="fcp-row fcp-shot" data-fcp-shot><label className="fcp-field"><span>Largest screenshot kept (MB)</span><input inputMode="decimal" value={v} disabled={!can} onChange={e=>setV(e.target.value)}/><small>1 to 50. A larger one is noted on the evidence and not kept. No profile asks for screenshots today.</small></label>
    {can&&changed&&<><label className="fcp-field fcp-wide"><span>Reason</span><input value={reason} onChange={e=>setReason(e.target.value)}/></label><Button compact variant="primary" disabled={busy||reason.trim().length<4} onClick={save}>Save</Button></>}</div>
}
