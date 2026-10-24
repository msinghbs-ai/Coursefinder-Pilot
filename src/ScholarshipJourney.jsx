// v2.15.248 (Platform Admin bugs 11/10-5, 11 Oct 2026: "Manually ran 4 unis scholarship, job completed and scholarship didn't show
// up. This is exactly the gap I need in UI with the journey that platform admin should know what is happening and how long it's
// going to take to bring it up as admitted scholarship ... this is not complete auditing").
// The journey of one scholarship task, per university: what was found (site map, listing page, search), what was read and what it
// cost, what was decided for each page (became a scholarship, refused and why, too thin, skipped by a rule), the records made or
// changed, and where each scholarship stands for publishing (published, goes live at the next hourly publish, or what blocks it).
// Each page links to its stored copy (evidence) and each scholarship to its record. Read from the task's item record
// (pipeline.admin_job_items, public.admin_scholarship_job_journey), so it stays as it was when the task ran.
import React,{useEffect,useState}from'react'
import{CheckCircle2,Clock3,ExternalLink,FileText}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Loading,fmtDateTime,fmtNumber}from'./ui-kit'
import{fmtTime}from'./lib/format.js'
import{ExpandList,Pill}from'./ExpandList'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const OUTCOME={became_scholarship:['Became a scholarship','success'],new_record:['New record','success'],updated:['Updated','info'],unchanged:['Unchanged','neutral'],already_held:['Already held','neutral'],
  refused:['Refused','danger'],too_thin:['Too thin to read','warning'],skipped:['Skipped by a rule','neutral'],waiting:['Waiting','info'],not_read:['Not read','warning'],
  mapped:['Site mapped','info'],read:['Read','info'],failed:['Failed','danger']}
const KIND={site_map:'Site map',listing:'Listing page',candidate:'New page',page:'Known scholarship page'}
const hm=v=>fmtTime(v,'')
const plural=(n,one,many)=>`${fmtNumber(n)} ${Number(n)===1?one:(many||one+'s')}`

// One plain sentence per university: what happened and why nothing (or something) went live
export function journeySentence(p,next){
  const f=p.found||{},d=p.decided||{},r=p.records||{},pub=p.publish||{},sm=f.site_map
  const parts=[]
  if(sm)parts.push(sm.outcome==='waiting'?'Its site is being mapped':`Its site map kept ${(sm.note||[])[0]||'its scholarship pages'}`)
  parts.push(f.candidates?`${plural(f.candidates,'new page')} to check`:'no new pages to check')
  const out=[]
  if(d.became)out.push(`${fmtNumber(d.became)} became scholarships`)
  if(d.refused)out.push(`${fmtNumber(d.refused)} refused`)
  if(d.too_thin)out.push(`${fmtNumber(d.too_thin)} too thin to read`)
  if(d.skipped)out.push(`${fmtNumber(d.skipped)} skipped by a rule`)
  if(d.waiting)out.push(`${fmtNumber(d.waiting)} still waiting`)
  let s=parts.join('; ')+(out.length?` (${out.join(', ')})`:'')+'.'
  const kp=p.read?.known_pages||0
  if(kp)s+=` ${plural(kp,'known scholarship page')} read again: ${fmtNumber(r.updated||0)} updated, ${fmtNumber(r.unchanged||0)} unchanged.`
  const nx=(pub.next_publish||[]).length,bl=(pub.blocked||[]).length,fl=(pub.failing||[]).length
  if(nx)s+=` ${plural(nx,'scholarship')} ${nx===1?'goes':'go'} live at the next automatic publish${next?` (${hm(next)})`:''}.`
  if(bl)s+=` ${plural(bl,'scholarship')} cannot be published yet (see why below).`
  if(fl)s+=` ${plural(fl,'published scholarship')} now ${fl===1?'fails':'fail'} a check.`
  if(!nx&&!bl&&!fl&&!d.became)s+=' Nothing new to publish.'
  return s
}

function Stage({n,label,children,tone}){return <li className={`sj-stage tone-${tone||'neutral'}`}><span className="sj-num">{n}</span><div><b>{label}</b><div>{children}</div></div></li>}

function ProviderBody({p,next}){
  const f=p.found||{},rd=p.read||{},d=p.decided||{},r=p.records||{},pub=p.publish||{},items=p.items||[]
  const[show,setShow]=useState('all')
  const shown=items.filter(i=>show==='all'||(show==='new'?i.kind==='candidate':show==='known'?i.kind==='page':i.kind==='site_map'||i.kind==='listing'))
  return <div className="sj-body" data-journey-provider={p.provider_id}>
    <p className="sj-sentence">{journeySentence(p,next)}</p>
    <ol className="sj-stages">
      <Stage n="1" label="Found" tone="info">{f.site_map?<>Site map {OUTCOME[f.site_map.outcome]?.[0].toLowerCase()||f.site_map.outcome}: {(f.site_map.note||[]).join('; ')} · </>:null}{plural(f.candidates||0,'new page')}{Object.entries(f.by||{}).length?` (${Object.entries(f.by).map(([k,v])=>`${fmtNumber(v)} by ${k}`).join(', ')})`:''}{(f.listing||[]).length?` · listing page ${f.listing.map(l=>OUTCOME[l.outcome]?.[0].toLowerCase()||l.outcome).join(', ')}`:''}</Stage>
      <Stage n="2" label="Read" tone="info">{plural(rd.candidates||0,'new page')} and {plural(rd.known_pages||0,'known scholarship page')} read through the scraper · {plural(rd.credits||0,'credit')}</Stage>
      <Stage n="3" label="Decided" tone={d.became?'success':(d.refused||d.too_thin)?'warning':'neutral'}>
        <span className="sj-pills">{d.became>0&&<Pill tone="success">{fmtNumber(d.became)} became scholarships</Pill>}{d.refused>0&&<Pill tone="danger">{fmtNumber(d.refused)} refused</Pill>}{d.too_thin>0&&<Pill tone="warning">{fmtNumber(d.too_thin)} too thin</Pill>}{d.skipped>0&&<Pill>{fmtNumber(d.skipped)} skipped</Pill>}{d.already_held>0&&<Pill>{fmtNumber(d.already_held)} already held</Pill>}{d.waiting>0&&<Pill tone="info">{fmtNumber(d.waiting)} waiting</Pill>}{!f.candidates&&<span className="sl-sub">No new pages</span>}</span>
        {(p.reasons||[]).length>0&&<span className="sj-reasons">Why: {(p.reasons||[]).slice(0,5).map(x=>`${x.reason} (${fmtNumber(x.n)})`).join(' · ')}</span>}
      </Stage>
      <Stage n="4" label="Records" tone={r.new?'success':'neutral'}>{fmtNumber(r.new||0)} new · {fmtNumber(r.updated||0)} updated · {fmtNumber(r.unchanged||0)} unchanged</Stage>
      <Stage n="5" label="Published" tone={(pub.next_publish||[]).length?'info':(pub.blocked||[]).length||(pub.failing||[]).length?'warning':'success'}>
        <span className="sj-pills"><Pill tone="success">{fmtNumber(pub.published||0)} published</Pill>{(pub.next_publish||[]).length>0&&<Pill tone="info">{fmtNumber(pub.next_publish.length)} live at {next?hm(next):'the next publish'}</Pill>}{(pub.blocked||[]).length>0&&<Pill tone="warning">{fmtNumber(pub.blocked.length)} not publishable yet</Pill>}{(pub.failing||[]).length>0&&<Pill tone="danger">{fmtNumber(pub.failing.length)} published but failing a check</Pill>}</span>
      </Stage>
    </ol>
    {[...(pub.next_publish||[]).map(x=>({...x,kind:'next'})),...(pub.blocked||[]).map(x=>({...x,kind:'blocked'})),...(pub.failing||[]).map(x=>({...x,kind:'failing'}))].length>0&&<div className="sj-pub" data-journey-publish>
      <h4>Where each scholarship stands</h4>
      <ul>{(pub.next_publish||[]).map(x=><li key={x.id}><Pill tone="info">Goes live {next?`at ${hm(next)}`:'at the next publish'}</Pill> <a className="cf-link" href={`#scholarships?id=${x.id}`}>{x.name}</a></li>)}
        {(pub.blocked||[]).map(x=><li key={x.id}><Pill tone="warning">{x.held?'Held':'Not publishable'}</Pill> <a className="cf-link" href={`#scholarships?id=${x.id}`}>{x.name}</a> <small className="sl-sub">— {(x.missing||[]).join('; ')}</small></li>)}
        {(pub.failing||[]).map(x=><li key={x.id}><Pill tone="danger">Published, now failing</Pill> <a className="cf-link" href={`#scholarships?id=${x.id}`}>{x.name}</a> <small className="sl-sub">— {(x.missing||[]).join('; ')}. Held automatically at the next hourly publish if it was published automatically.</small></li>)}</ul>
    </div>}
    <div className="sj-items" data-journey-items>
      <div className="sj-items-head"><h4>Every page ({fmtNumber(items.length)})</h4>
        <div className="ar-tabs" role="tablist" aria-label="Which pages">{[['all','All'],['new','New pages'],['known','Known pages'],['site','Site map and listing']].map(([k,l])=><button key={k} role="tab" aria-selected={show===k} className={show===k?'active':''} onClick={()=>setShow(k)}>{l}</button>)}</div></div>
      <div className="cf-table-wrap"><table className="cf-table sj-table"><thead><tr><th>Page</th><th>Kind</th><th>Outcome</th><th>Why</th><th>Copy kept</th><th>When</th></tr></thead><tbody>
        {shown.length===0&&<tr><td colSpan={6} className="sl-sub">No pages.</td></tr>}
        {shown.map((i,k)=>{const[ol,ot]=OUTCOME[i.outcome]||[i.outcome||'—','neutral'];return <tr key={k} data-journey-item={i.outcome}>
          <td className="sj-page"><b>{i.title||'—'}</b>{i.url&&<a className="cf-link" href={i.url} target="_blank" rel="noreferrer">{i.url.replace(/^https?:\/\/(www\.)?/,'').slice(0,90)} <ExternalLink size={11}/></a>}</td>
          <td>{KIND[i.kind]||i.kind}{i.found_via&&i.kind==='candidate'?<small className="sl-sub"> · {i.found_via}</small>:null}</td>
          <td><Pill tone={ot}>{ol}</Pill>{i.scholarship_id&&<> <a className="cf-link" href={`#scholarships?id=${i.scholarship_id}`}>record</a></>}</td>
          <td>{(i.reasons||[]).join('; ')||'—'}</td>
          <td>{i.evidence_id?<a className="cf-link" href={`#evidence?evidence_id=${i.evidence_id}`} data-journey-evidence><FileText size={12}/> Stored copy</a>:i.stored?'Stored':<span className="sl-sub">{i.kind==='site_map'?'—':'No copy'}</span>}</td>
          <td>{i.at?fmtDateTime(i.at):'—'}</td></tr>})}
      </tbody></table></div>
    </div>
  </div>
}

export function ScholarshipJourney({jobId,data:given,live=false,single=false}){
  const[d,setD]=useState(given||null),[err,setErr]=useState(''),[open,setOpen]=useState(null)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_scholarship_job_journey',{p_job:jobId});if(error)throw error;setD(data);setErr('')}catch(e){setErr(errText(e))}}
  useEffect(()=>{if(given){setD(given);return}load()},[jobId,given])
  const running=['queued','running'].includes(d?.job?.state)
  useEffect(()=>{if(given||!(running||live))return;const t=setInterval(()=>{if(document.visibilityState==='visible')load()},8000);return()=>clearInterval(t)},[running,live,given,jobId])
  if(err)return <p className="m-alert compact" role="alert">The journey could not be read: {err}</p>
  if(!d)return <Loading label="Loading what the task did…" compact/>
  const j=d.job||{},provs=d.providers||[],next=d.next_publish_at
  const cols=[
    {key:'p',label:'University',width:'minmax(200px,2fr)',render:p=><span className="xl-title"><b>{p.name}</b><small>{p.code?`CRICOS ${p.code}`:''}</small></span>},
    {key:'f',label:'Found',width:'minmax(110px,1fr)',render:p=><Pill tone="info">{plural(p.found?.candidates||0,'new page')}</Pill>},
    {key:'r',label:'Read',width:'minmax(110px,1fr)',render:p=><span className="xl-stack"><span>{fmtNumber((p.read?.candidates||0)+(p.read?.known_pages||0))} pages</span><small>{plural(p.read?.credits||0,'credit')}</small></span>},
    {key:'d',label:'Decided',width:'minmax(150px,1.3fr)',render:p=>{const x=p.decided||{};return <span className="sj-pills">{x.became>0&&<Pill tone="success">{fmtNumber(x.became)} new</Pill>}{x.refused>0&&<Pill tone="danger">{fmtNumber(x.refused)} refused</Pill>}{x.too_thin>0&&<Pill tone="warning">{fmtNumber(x.too_thin)} thin</Pill>}{x.skipped>0&&<Pill>{fmtNumber(x.skipped)} skipped</Pill>}{x.waiting>0&&<Pill tone="info">{fmtNumber(x.waiting)} waiting</Pill>}{!x.became&&!x.refused&&!x.too_thin&&!x.skipped&&!x.waiting&&<small className="sl-sub">nothing new</small>}</span>}},
    {key:'pub',label:'Published',width:'minmax(160px,1.4fr)',render:p=>{const x=p.publish||{};return <span className="sj-pills"><Pill tone="success">{fmtNumber(x.published||0)} live</Pill>{(x.next_publish||[]).length>0&&<Pill tone="info">{fmtNumber(x.next_publish.length)} at {next?hm(next):'next'}</Pill>}{(x.blocked||[]).length>0&&<Pill tone="warning">{fmtNumber(x.blocked.length)} blocked</Pill>}{(x.failing||[]).length>0&&<Pill tone="danger">{fmtNumber(x.failing.length)} failing</Pill>}</span>}},
  ]
  return <div className="sj" data-scholarship-journey={j.id}>
    {!single&&<div className="sj-head">
      <span><b>{j.title}</b> · started by {j.requested_by||'—'} · {j.reason}</span>
      <span className="sj-pills"><Pill tone={running?'info':j.state==='done'?'success':j.state==='failed'?'danger':'neutral'}>{running?'Running':j.state==='done'?'Finished':j.state}</Pill>
        <small className="sl-sub">{j.started_at?`started ${fmtDateTime(j.started_at)}`:'waiting to start'}{j.finished_at?` · finished ${fmtDateTime(j.finished_at)}`:''}</small>
        {running&&d.eta_minutes!=null&&<Pill tone="info"><Clock3 size={12}/> about {d.eta_minutes} min left ({fmtNumber(d.left)} pages to go)</Pill>}
        {d.auto_publish&&next&&<Pill tone="neutral"><CheckCircle2 size={12}/> next automatic publish {hm(next)}</Pill>}</span>
    </div>}
    {single?provs.map(p=><ProviderBody key={p.provider_id} p={p} next={next}/>)
      :<ExpandList columns={cols} rows={provs.map(p=>({...p,__label:p.name}))} rowKey={p=>p.provider_id} openKey={open??(provs.length===1?provs[0].provider_id:null)} onOpen={setOpen} dataAttr="data-journey-row" renderBody={p=><ProviderBody p={p} next={next}/>} empty="No university in this task."/>}
  </div>
}

// Scholarships › Coverage, one university: its last five on-demand runs, newest first
export function ProviderRuns({providerId}){
  const[runs,setRuns]=useState(null),[err,setErr]=useState(''),[open,setOpen]=useState(null)
  useEffect(()=>{let live=true;setRuns(null);supabase.rpc('admin_scholarship_provider_runs',{p_provider_id:providerId}).then(({data,error})=>{if(!live)return;if(error)setErr(errText(error));else setRuns(data||[])});return()=>{live=false}},[providerId])
  if(err)return <p className="sl-sub" role="alert">Runs could not be read: {err}</p>
  if(!runs)return <Loading label="Loading runs…" compact/>
  return <div className="sj-runs" data-provider-runs={providerId}><h3>Find scholarships runs</h3>
    {runs.length===0?<p className="sl-sub">No on-demand run yet. Use Find scholarships now above; what it finds, reads and decides shows here.</p>:
    <ul>{runs.map(r=>{const j=r.job||{},p=(r.providers||[])[0];return <li key={j.id} data-provider-run={j.id}>
      <button type="button" className="sj-run-toggle" aria-expanded={open===j.id} onClick={()=>setOpen(open===j.id?null:j.id)}>
        <b>{fmtDateTime(j.created_at)}</b> <span>{j.title}</span> <Pill tone={j.state==='done'?'success':['queued','running'].includes(j.state)?'info':'neutral'}>{j.state==='done'?'Finished':j.state}</Pill></button>
      {p&&<p className="sj-sentence">{journeySentence(p,r.next_publish_at)}</p>}
      {open===j.id&&p&&<ScholarshipJourney jobId={j.id} data={{...r}} single/>}
    </li>})}</ul>}
  </div>
}
