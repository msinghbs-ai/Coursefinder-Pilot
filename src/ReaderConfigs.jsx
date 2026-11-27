// Layer 2/3 › Adapter builder › 5 Reader configurations (CF-247 s1310, SS-Programme-Control 27 Nov 2026 13:39 and 13:43 AEDT; Platform Admin direction
// 27 Nov 2026, coursefinder-admin PR 1293). One provider's academic entry (AER) and scholarship reader configurations: the stored sources, each
// configuration's versions and what changed between them, its samples and their qualification results, the activation authority, what it read
// and admitted, and the next requalification. A configuration is data from a closed list (registered reading.entry_* settings within their ranges,
// an address pattern, country from the address; scholarship listing hosts of the provider's own site): no code, SQL or prompt.
// Reads and writes: admin_reader_configs_v1 (PIM Admin drafts and qualifies; Platform Admin activates, pauses, resumes and rolls back; each with a reason).
import React,{useEffect,useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber,fmtDate,fmtDateTime}from'./ui-kit'
import{plainError}from'./lib/errors'

const reasonOf=t=>`Adapter builder › Reader configurations: ${String(t).slice(0,200)}`
const DOMAIN={academic_entry:'Academic entry (AER)',scholarship:'Scholarships'}
const TEMPLATE={country_page_generic_heading:'Country pages: country taken from the page address',provider_settings:'Reader settings for this provider',link_hosts:'Listing award links on other hosts of the provider'}
const OUTCOME={deterministic_read:['Read by a proven reader','tone-success'],guard_passed:['Passed the guard (model read after activation)','tone-info'],guard_held:['Held (as a negative must be)','tone-neutral'],read_incomplete:['Read, incomplete','tone-warning'],not_read:['Not read','tone-warning'],items_gained:['Gained awards','tone-success'],no_gain:['No awards gained','tone-warning']}
const short=u=>String(u||'').replace(/^https?:\/\/(www\.)?/,'').slice(0,90)
// the state of one configuration, from its current and newest versions
export function configState(c){
  const vs=c?.versions||[],cur=vs.find(v=>v.id===c.current_version_id)||vs[0],top=vs[0]
  if(top?.status==='pending'&&top?.draft)return['Draft','tone-neutral']
  if(top?.status==='pending')return['Qualifying on stored copies','tone-info']
  if(c.enabled&&c.paused)return[cur?.requalify_failed_at?'Paused: requalification failed':'Paused','tone-warning']
  if(c.enabled&&cur?.activated_at)return['Active','tone-success']
  if(top?.status==='valid'&&top?.held)return[`Qualified · ${String(top.held).replace('HELD:','held: ').replace(/_/g,' ').toLowerCase()}`,'tone-warning']
  if(top?.status==='valid')return['Qualified, activation next','tone-info']
  if(top?.status==='invalid')return['Did not qualify','tone-warning']
  return['Off','tone-neutral']
}
// what changed from the previous version (settings, address pattern, country, hosts)
export function versionDiff(v,prev){
  if(!prev)return[]
  const a=v.configuration||{},b=prev.configuration||{},out=[]
  for(const k of['template','url_like','country_from'])if((a[k]??null)!==(b[k]??null))out.push(`${k}: ${b[k]??'—'} → ${a[k]??'—'}`)
  const sa=a.settings||{},sb=b.settings||{}
  for(const k of new Set([...Object.keys(sa),...Object.keys(sb)]))if(JSON.stringify(sa[k])!==JSON.stringify(sb[k]))out.push(`${k}: ${sb[k]===undefined?'—':JSON.stringify(sb[k])} → ${sa[k]===undefined?'—':JSON.stringify(sa[k])}`)
  if(JSON.stringify(a.hosts_add||[])!==JSON.stringify(b.hosts_add||[]))out.push(`hosts: ${(b.hosts_add||[]).join(', ')||'—'} → ${(a.hosts_add||[]).join(', ')||'—'}`)
  return out
}
const nextRequalify=(v,days)=>v?.activated_at?new Date(new Date(v.activated_at).getTime()+days*86400000):null

function Samples({v}){
  const s=Object.entries(v?.samples||{})
  if(!s.length)return null
  return <div className="cf-table-wrap"><table className="cf-table" data-reader-samples><thead><tr><th>Sample page</th><th>Role</th><th>Result</th></tr></thead><tbody>
    {s.map(([id,x])=><tr key={id}><td>{x.url?<a href={x.url} target="_blank" rel="noreferrer">{short(x.url)}</a>:id}</td><td>{x.role||'positive'}</td>
      <td>{x.state==='done'?<><span className={`cf-chip ${OUTCOME[x.outcome]?.[1]||'tone-neutral'}`}>{OUTCOME[x.outcome]?.[0]||x.outcome}</span>{x.rows!=null?` · ${fmtNumber(x.rows)} rows`:''}{x.error?<small className="ab-muted"> {String(x.error).slice(0,140)}</small>:null}</>:<span className="cf-chip tone-neutral">{x.state==='draft'?'Not sent yet':x.state==='leased'?'Being read':'Waiting to be read'}</span>}</td></tr>)}
  </tbody></table></div>
}

function Configuration({c,d,act,busy}){
  const[st,tone]=configState(c),vs=c.versions||[],cur=vs.find(v=>v.id===c.current_version_id),top=vs[0]
  const due=nextRequalify(cur,d.requalify_days),auth=(d.authority||[]).find(a=>a.code===(c.domain==='scholarship'?'reader_config:sch_listing:link_hosts':`reader_config:aer_matrix:${top?.configuration?.template}`))
  const cfg=(cur||top)?.configuration||{}
  return <div className="ab-sub" data-reader-config={c.profile_key}>
    <div className="ab-sub-head"><strong>{TEMPLATE[cfg.template]||cfg.template}</strong> <span className={`cf-chip ${tone}`} data-reader-state>{st}</span></div>
    <div className="ab-sub-body">
      <ul className="ab-facts">
        {cfg.url_like&&<li><span>Pages</span><code>{cfg.url_like}</code></li>}
        {cfg.country_from&&<li><span>Country</span>from the page address</li>}
        {cfg.settings&&Object.keys(cfg.settings).length>0&&<li><span>Settings</span>{Object.entries(cfg.settings).map(([k,x])=>`${k} = ${JSON.stringify(x)}`).join(' · ')}</li>}
        {cfg.hosts_add&&<li><span>Award link hosts</span>{(cfg.hosts_add||[]).join(', ')||'found on the stored copies when qualified'}</li>}
        <li><span>Activation authority</span>{auth?`${auth.auto?'standing authority':'held for the Platform Admin'} — ${auth.why}`:'none recorded'}</li>
        {c.runs&&c.runs.reads>0&&<li><span>Read with it</span>{fmtNumber(c.runs.reads)} reads · {fmtNumber(c.runs.rows_admitted)} rows admitted · last {fmtDateTime(c.runs.last)}</li>}
        {cur?.reread_at&&<li><span>Read again after activation</span>{fmtDateTime(cur.reread_at)} · {fmtNumber(cur.reread_runs||0)} reads</li>}
        {due&&<li><span>Next requalification</span>{fmtDate(due)} (or sooner when a sample copy changes)</li>}
        <li><span>Configuration ID</span><code data-reader-profile-id>{c.profile_id}</code></li>
      </ul>
      <details data-reader-versions><summary>Versions ({fmtNumber(vs.length)})</summary>
        <ol className="tn-list">{vs.map((v,i)=>{const diff=versionDiff(v,vs[i+1]);return <li key={v.id} data-reader-version={v.version_no}>
          <strong>v{v.version_no}</strong> <span className="ab-muted">{v.draft?'draft':v.status}{v.id===c.current_version_id?' · current':''}{v.mode?` · ${v.mode}`:''}{v.held?` · ${v.held}`:''}{v.activated_at?` · active from ${fmtDateTime(v.activated_at)}`:''} · {fmtDateTime(v.created_at)}</span>
          {diff.length>0&&<small className="ab-muted"> · changed: {diff.join('; ')}</small>}
          {v.requalify_of&&<small className="ab-muted"> · requalification</small>}
          <Samples v={v}/>
          <div className="ab-actions">
            {v.draft&&d.can_draft&&<><Button compact disabled={busy} onClick={()=>act('qualify',{version_id:v.id},`qualify v${v.version_no} on its stored samples`)} data-reader-qualify>Qualify on stored copies</Button>
              <Button compact disabled={busy} onClick={()=>act('discard_draft',{version_id:v.id},`discard draft v${v.version_no}`)}>Discard draft</Button></>}
            {!v.draft&&v.status!=='pending'&&d.can_draft&&i===0&&<Button compact disabled={busy} onClick={()=>act('requalify',{version_id:v.id},`requalify v${v.version_no} on the current stored copies`)} data-reader-requalify>Requalify</Button>}
            {v.status==='valid'&&!v.activated_at&&d.can_activate&&<Button compact variant="primary" disabled={busy} onClick={()=>act('activate',{version_id:v.id},`activate v${v.version_no}`)} data-reader-activate>Activate</Button>}
            {v.activated_at&&v.id!==c.current_version_id&&['superseded','valid'].includes(v.status)&&d.can_activate&&<Button compact disabled={busy} onClick={()=>act('rollback',{version_id:v.id},`roll back to v${v.version_no}`)} data-reader-rollback>Roll back to v{v.version_no}</Button>}
          </div></li>})}</ol>
      </details>
      {d.can_activate&&cur&&c.enabled&&<div className="ab-actions">{c.paused?<Button compact disabled={busy} onClick={()=>act('resume',{version_id:cur.id},'resume')}>Resume</Button>:<Button compact disabled={busy} onClick={()=>act('pause',{version_id:cur.id},'pause')}>Pause</Button>}</div>}
    </div>
  </div>
}

// a new draft (or a new version of an existing configuration): only the closed list can be entered
function DraftForm({d,providerId,from,onSaved,onError}){
  const[domain,setDomain]=useState(from?.domain||'academic_entry'),[template,setTemplate]=useState(from?.template||'provider_settings'),[like,setLike]=useState(from?.url_like||'')
  const[country,setCountry]=useState(Boolean(from?.country_from)),[settings,setSettings]=useState(from?.settings||{}),[key,setKey]=useState(''),[val,setVal]=useState(''),[hosts,setHosts]=useState((from?.hosts_add||[]).join(', '))
  const[picks,setPicks]=useState({}),[note,setNote]=useState(''),[busy,setBusy]=useState(false)
  const reg=(d.settings||[]).find(s=>s.key===key)
  const sources=domain==='scholarship'?(d.listing_pages||[]).filter(l=>l.stored):(d.entry_sources||[]).filter(s=>s.stored)
  const addSetting=()=>{if(!reg)return;const v=Array.isArray(reg.value)?val.split(',').map(x=>x.trim()).filter(Boolean):Number(val);if(!Array.isArray(v)&&!Number.isFinite(v))return;setSettings({...settings,[key]:v});setKey('');setVal('')}
  const save=async()=>{setBusy(true);try{
      const configuration=domain==='scholarship'?{template:'link_hosts',hosts_add:hosts.split(',').map(h=>h.trim()).filter(Boolean)}:{template,url_like:like.trim(),country_from:country?'url_slug':null,settings}
      const samples=Object.entries(picks).filter(([,r])=>r).map(([id,role])=>({id,role}))
      const{data,error}=await supabase.rpc('admin_reader_configs_v1',{p_action:'save_draft',p_args:{provider_id:providerId,domain,configuration,samples,source_note:note.trim(),reason:reasonOf(`save a ${DOMAIN[domain]} draft`)}});if(error)throw error
      onSaved?.(data)}catch(e){onError?.(plainError(e))}finally{setBusy(false)}}
  return <div className="ab-add ab-reader-draft" data-reader-draft-form>
    <select aria-label="Reader" value={domain} onChange={e=>setDomain(e.target.value)}>{Object.entries(DOMAIN).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
    {domain==='academic_entry'?<>
      <select aria-label="Template" value={template} onChange={e=>setTemplate(e.target.value)}><option value="provider_settings">{TEMPLATE.provider_settings}</option><option value="country_page_generic_heading">{TEMPLATE.country_page_generic_heading}</option></select>
      <input aria-label="Pages (address pattern)" placeholder="https://www.provider.edu.au/…/% (% stands for any text)" value={like} onChange={e=>setLike(e.target.value)}/>
      <label className="ab-muted"><input type="checkbox" checked={country} onChange={e=>setCountry(e.target.checked)}/> The country is named by the page address (last part)</label>
      <div className="ab-add"><select aria-label="Reader setting" value={key} onChange={e=>setKey(e.target.value)}><option value="">Add a reader setting…</option>{(d.settings||[]).map(s=><option key={s.key} value={s.key}>{s.label||s.key}</option>)}</select>
        {reg&&<><input aria-label="Value" placeholder={Array.isArray(reg.value)?'comma-separated texts':`${reg.min??''} to ${reg.max??''}${reg.unit?` ${reg.unit}`:''} (now ${JSON.stringify(reg.value)})`} value={val} onChange={e=>setVal(e.target.value)}/><Button compact onClick={addSetting}>Add</Button></>}</div>
      {Object.keys(settings).length>0&&<small className="ab-muted">{Object.entries(settings).map(([k,x])=><span key={k}>{k} = {JSON.stringify(x)} <button type="button" className="cf-link" onClick={()=>{const n={...settings};delete n[k];setSettings(n)}}>remove</button> · </span>)}</small>}
    </>:<input aria-label="Award link hosts" placeholder="Hosts of the provider's own site the listing links awards to (optional, comma-separated)" value={hosts} onChange={e=>setHosts(e.target.value)}/>}
    <p className="ab-text">Samples (stored copies; at most {fmtNumber(d.samples_max)}, at least {fmtNumber(d.min_positive)} positive to qualify). A negative must stay unread: {domain==='scholarship'?'a page that is not a directory must gain no awards':'a page outside this template must not be read into rows'}.</p>
    <div className="cf-table-wrap"><table className="cf-table"><tbody>{sources.map(s=><tr key={s.id}><td><select aria-label={`Role of ${short(s.url)}`} value={picks[s.id]||''} onChange={e=>setPicks({...picks,[s.id]:e.target.value})}><option value="">—</option><option value="positive">positive</option><option value="negative">negative</option></select></td>
      <td><a href={s.url} target="_blank" rel="noreferrer">{short(s.url)}</a> <small className="ab-muted">{domain==='scholarship'?`${fmtNumber(s.items)} items · ${s.status}`:`${s.last_state||s.status}${s.rows_admitted!=null?` · ${fmtNumber(s.rows_admitted)} admitted`:''}${s.last_error?` · ${String(s.last_error).slice(0,80)}`:''}`}</small></td></tr>)}</tbody></table></div>
    <input aria-label="Source note" placeholder="Source note (edition, where the page is linked from)" value={note} onChange={e=>setNote(e.target.value)}/>
    <Button compact disabled={busy||!Object.values(picks).some(r=>r==='positive')||(domain==='academic_entry'&&!/^https?:\/\/\S+\//.test(like.trim()))} onClick={save} data-reader-save-draft>Save draft</Button>
    <small className="ab-muted">A draft changes nothing. Qualify reads its samples' stored copies with the proven readers ($0, no fetch, no model); a pass switches nothing on, and activation is its own step under the recorded authority.</small>
  </div>
}

export default function ReaderConfigs({providerId,name,onError}){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[form,setForm]=useState(null),[msg,setMsg]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_reader_configs_v1',{p_action:'list',p_args:{provider_id:providerId}});if(error)throw error;setD(data||{})}catch(e){onError?.(plainError(e))}}
  useEffect(()=>{setD(null);load()},[providerId])
  const qualifying=(d?.configurations||[]).some(c=>c.versions?.[0]?.status==='pending'&&!c.versions[0].draft)
  useEffect(()=>{if(!qualifying)return;const t=setTimeout(load,20000);return()=>clearTimeout(t)},[d])  // fixed: screen refresh while samples are read
  const act=async(action,args,what)=>{setBusy(true);setMsg('');try{const{data,error}=await supabase.rpc('admin_reader_configs_v1',{p_action:action,p_args:{...args,reason:reasonOf(`${what} (${name})`)}});if(error)throw error
      setMsg(action==='activate'?(data?.activated?'Activated: its pages are read again with it.':`Not activated: ${data?.why||'see the version'}.`):action==='qualify'?`Sent to qualification: ${fmtNumber(data?.samples||0)} stored copies are read within minutes.`:'Done.');await load()}catch(e){onError?.(plainError(e))}finally{setBusy(false)}}
  const groups=useMemo(()=>{const g={academic_entry:[],scholarship:[]};for(const c of d?.configurations||[])(g[c.domain]||(g[c.domain]=[])).push(c);return g},[d])
  if(!d)return <Loading label="Reading the reader configurations…"/>
  return <div className="ab-readers" data-reader-configs>
    <p className="ab-text">How this university's academic entry pages and scholarship listings are read. A configuration is data: which pages, the country from the address, registered reader settings within their ranges, or the hosts a listing links its awards to. It is qualified on the stored copies with positive and negative samples, switched on only under the recorded authority (scholarships wait for the Platform Admin), keeps every version, and is qualified again every {fmtNumber(d.requalify_days)} days or when a sample copy changes. {d.lifecycle_on?'':'The reader lifecycle is switched off on Pipeline settings: nothing is qualified until it is on.'}</p>
    <p className="ab-text" data-reader-results>Entry rows now: <strong>{fmtNumber(d.entry_rows?.active||0)}</strong> active, {fmtNumber(d.entry_rows?.other||0)} other · listing pages {fmtNumber((d.listing_pages||[]).length)} ({fmtNumber((d.listing_pages||[]).filter(l=>l.active&&l.items===0).length)} active with no awards read).</p>
    {Object.entries(DOMAIN).map(([k,label])=><section key={k} data-reader-domain={k}><h4 className="sl-h4">{label}</h4>
      {(groups[k]||[]).length?(groups[k]||[]).map(c=><Configuration key={c.profile_id} c={c} d={d} act={act} busy={busy}/>):<p className="sl-sub">No configuration yet.</p>}
      {d.can_draft&&(groups[k]||[]).length>0&&<Button compact onClick={()=>{const c=groups[k][0],cur=(c.versions||[]).find(v=>v.id===c.current_version_id)||c.versions?.[0];setForm({...(cur?.configuration||{}),domain:k})}}>Change as a new draft</Button>}
    </section>)}
    {d.can_draft&&(form?<><DraftForm d={d} providerId={providerId} from={form} onSaved={async r=>{setForm(null);setMsg(`Draft saved (configuration ${r?.profile_id}).`);await load()}} onError={onError}/><Button compact onClick={()=>setForm(null)}>Cancel</Button></>
      :<Button compact onClick={()=>setForm({domain:'academic_entry'})} data-reader-new>New configuration</Button>)}
    {msg&&<p className="cf-chip tone-info" role="status">{msg}</p>}
    <details data-reader-sources><summary>Stored sources ({fmtNumber((d.entry_sources||[]).length)} entry pages · {fmtNumber((d.listing_pages||[]).length)} listing pages)</summary>
      {(d.entry_sources||[]).length===0&&(d.listing_pages||[]).length===0?<Empty text="No stored source yet."/>:<ul className="tn-list">
        {(d.entry_sources||[]).map(s=><li key={s.id}><strong>AER</strong> <a href={s.url} target="_blank" rel="noreferrer">{short(s.url)}</a> <small className="ab-muted">{s.stored?'stored':'not stored'} · {s.last_state||s.status}{s.rows_admitted!=null?` · ${fmtNumber(s.rows_admitted)} admitted`:''}{s.last_read?` · ${fmtDateTime(s.last_read)}`:''}{s.reader_config?' · read with a configuration':''}{s.last_error?` · ${String(s.last_error).slice(0,120)}`:''}</small></li>)}
        {(d.listing_pages||[]).map(l=><li key={l.id}><strong>Scholarships</strong> <a href={l.url} target="_blank" rel="noreferrer">{short(l.url)}</a> <small className="ab-muted">{l.active?'active':'inactive'} · {l.status} · {fmtNumber(l.items)} items{l.total_stated?` of ${fmtNumber(l.total_stated)} stated`:''}{l.stored?' · stored':''}{l.read_at?` · ${fmtDateTime(l.read_at)}`:''}</small></li>)}
      </ul>}
    </details>
    {(d.events||[]).length>0&&<details data-reader-events><summary>History ({fmtNumber(d.events.length)})</summary><ul className="tn-list">{d.events.map((e,i)=><li key={i}><small className="ab-muted">{fmtDateTime(e.at)}</small> {String(e.action).replace(/_/g,' ')}{e.detail?.by?` · ${e.detail.by}`:''}{e.detail?.reason?` · ${String(e.detail.reason).slice(0,120)}`:''}</li>)}</ul></details>}
  </div>
}
