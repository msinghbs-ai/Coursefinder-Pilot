// Layer 2/3 › Course sources (v2.15.321, Platform Admin 22 Oct 2026 23:46 and 23:53): "Platform needs to independently read website ...
// let platform execute it using toolset. And leave all configurable and manageable from ui." The course source finder (job source-find)
// finds each university's own course source by itself: a Firecrawl map of its site first (1 credit), then its site maps, then its usual
// list pages, checked against the address pattern of the course pages already found. This screen shows what it found and why, every
// source a university has, and the controls: countries it works on, the list addresses it tries, find again, stop, add, approve.
// Server: public.admin_course_sources('list' | 'find_again' | 'stop_list' | 'stop_programme' | 'add_list' | 'add_programme' |
// 'approve_programme' | 'country' | 'path').
import React,{useEffect,useMemo,useState}from'react'
import{CheckCircle2,Compass,Globe2,ListChecks,RefreshCw,Search,XCircle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'

export const FINDER_STATES={
  found:{label:'Found',tone:'success',help:'The finder found a course source and added it.'},
  tested:{label:'Tested',tone:'info',help:'A test run found a source; nothing was added.'},
  none:{label:'Nothing found',tone:'warning',help:'No map, site map or list page gave enough course addresses. Tried again later, or add a source by hand.'},
  failed:{label:'Failed',tone:'danger',help:'The finder could not finish; it tries again later.'},
  leased:{label:'Looking now',tone:'info',help:'The finder is looking at this university now.'},
}
const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const finderOf=s=>FINDER_STATES[s]||{label:s||'Not looked at',tone:'neutral',help:''}
const viaLabel=v=>v==='map'?'Firecrawl map':v==='sitemap'?'Site map':v==='firecrawl'?'Scraper':v==='direct'?'Direct':v||'—'

export default function CourseSources({rank=3,onError}){
  const[d,setD]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(''),[msg,setMsg]=useState(''),[q,setQ]=useState(''),[country,setCountry]=useState('all'),[open,setOpen]=useState(''),[add,setAdd]=useState(null)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_course_sources',{p_action:'list',p_args:{}});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e));setD({providers:[],countries:[],paths:[]})}}
  useEffect(()=>{load()},[])
  const act=async(action,args,done)=>{if(!reason.trim()){setMsg('Write a reason first (it is kept with the change).');return}
    setBusy(action+(args.provider_id||args.id||args.value||args.country||''));setMsg('')
    try{const{error}=await supabase.rpc('admin_course_sources',{p_action:action,p_args:{...args,reason:reason.trim()}});if(error)throw error;setMsg(done);await load()}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  const rows=useMemo(()=>(d?.providers||[]).filter(p=>(country==='all'||p.country===country)&&(!q||String(p.name).toLowerCase().includes(q.toLowerCase()))),[d,q,country])
  if(!d)return <section className="m-panel"><Loading label="Reading course sources…"/></section>
  const all=d.providers||[],n=k=>all.filter(p=>p.finder?.state===k).length
  const waiting=all.filter(p=>(p.programmes||[]).some(s=>!s.approved_at&&s.status!=='stopped'&&Number(s.states?.created||0)+Number(s.states?.matched||0)>0)).length
  const canEdit=rank>=4
  return <div className="m-page-stack" data-course-sources>
    <section className="m-panel">
      <SectionTitle icon={Compass} title="Course sources" subtitle="Each university's own course list, found by the platform: a Firecrawl map of its site first, then its site maps, then its usual list pages, checked against the address pattern of the course pages already found. Course lists feed the page matchers; programme lists create courses that stay hidden until approved here."
        action={<Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>}/>
      <div className="cf-metric-grid">
        <Metric label="Found by the platform" value={n('found')} icon={CheckCircle2} tone="success" detail={`${fmtNumber(n('tested'))} in test runs`}/>
        <Metric label="Nothing found" value={n('none')} icon={XCircle} tone={n('none')?'warning':'neutral'} detail="Tried again later, or add a source"/>
        <Metric label="Universities with a source" value={all.filter(p=>(p.lists||[]).some(l=>l.status!=='stopped')||(p.programmes||[]).some(s=>s.status!=='stopped')).length} icon={ListChecks} tone="neutral"/>
        <Metric label="Programme lists to approve" value={waiting} icon={Globe2} tone={waiting?'warning':'neutral'} detail="Courses created, hidden until approved"/>
      </div>
      {canEdit&&<label className="cs-reason">Reason for changes<input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (kept with every change)" data-cs-reason/></label>}
      {msg&&<p className="qw-msg" role="status">{msg}</p>}
    </section>
    <section className="m-panel">
      <div className="cs-filters">
        <label className="cs-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a university"/></label>
        {['all',...(d.countries||[]).map(c=>c.country_code)].map(c=><button key={c} type="button" className={`cs-chip${country===c?' on':''}`} onClick={()=>setCountry(c)}>{c==='all'?'All':c}</button>)}
      </div>
      <div className="cf-table-wrap"><table className="cf-table qw-table" data-cs-table><thead><tr><th>University</th><th>Finder</th><th>Sources</th><th></th></tr></thead><tbody>
        {rows.length?rows.map(p=>{const f=p.finder||{},st=finderOf(f.state),isOpen=open===p.provider_id;return <React.Fragment key={p.provider_id}><tr data-cs-row={p.provider_id}>
          <td><strong>{p.name}</strong><small className="qw-sub">{p.country} · {p.website||'no website'}</small></td>
          <td><StatusChip value={f.state||'none'} tone={st.tone} label={st.label} title={st.help}/>{f.tried_at&&<small className="qw-sub">{fmtDateTime(f.tried_at)}</small>}{f.pattern_basis&&<small className="qw-sub">Pattern from {f.pattern_basis}</small>}{f.reason&&<small className="qw-sub">{f.reason}</small>}{f.added&&<small className="qw-sub">Added a {f.added==='programme_list'?'programme list':'course list'}</small>}</td>
          <td>{(p.lists||[]).map(l=><div key={l.id} className="cs-src"><span className="cs-kind">Course list</span> <a className="cf-link" href={l.url} target="_blank" rel="noreferrer">{l.url}</a><small className="qw-sub">{l.status} · {viaLabel(l.read_via||l.via)} · {fmtNumber(l.links||0)} links ({fmtNumber(l.new||0)} new){l.by_finder?' · found by the platform':' · added by a person'}{l.read_at?` · read ${fmtDateTime(l.read_at)}`:''}</small>
              {canEdit&&l.status!=='stopped'&&<Button compact disabled={!!busy} onClick={()=>act('stop_list',{id:l.id,provider_id:p.provider_id},'Course list stopped.')}>Stop</Button>}</div>)}
            {(p.programmes||[]).map(s=><div key={s.id} className="cs-src"><span className="cs-kind">Programme list</span> <a className="cf-link" href={s.url} target="_blank" rel="noreferrer">{s.url}</a><small className="qw-sub">{s.status} · {viaLabel(s.read_via||s.kind)} · {fmtNumber(s.found||0)} programmes · {Object.entries(s.states||{}).map(([k,v])=>`${k} ${fmtNumber(v)}`).join(', ')||'not read yet'} · {s.approved_at?`approved ${fmtDateTime(s.approved_at)}`:'courses hidden until approved'}</small>
              {canEdit&&s.status!=='stopped'&&<Button compact disabled={!!busy} onClick={()=>act('stop_programme',{id:s.id,provider_id:p.provider_id},'Programme list stopped.')}>Stop</Button>}
              {rank>=6&&!s.approved_at&&s.status!=='stopped'&&<Button compact disabled={!!busy} onClick={()=>act('approve_programme',{provider_id:p.provider_id},'Programme list approved: its courses show once their page is read and their level is in scope.')} data-cs-approve>Approve</Button>}</div>)}
            {!(p.lists||[]).length&&!(p.programmes||[]).length&&<span className="qw-sub">No source yet</span>}</td>
          <td className="cs-actions">{canEdit&&<Button compact disabled={!!busy} onClick={()=>act('find_again',{provider_id:p.provider_id},'The finder looks at this university on its next run.')}>Find again</Button>}
            <Button compact onClick={()=>setOpen(isOpen?'':p.provider_id)}>{isOpen?'Hide tries':'What was tried'}</Button>
            {canEdit&&<Button compact onClick={()=>setAdd(add?.provider_id===p.provider_id?null:{provider_id:p.provider_id,kind:'list',url:'',pattern:'',read_via:''})}>Add source</Button>}</td>
        </tr>
        {isOpen&&<tr className="cs-detail"><td colSpan={4}>{f.pattern&&<p className="qw-sub">Course address pattern: <code>{f.pattern}</code></p>}
          {(f.tried||[]).length?<ul className="qw-list">{f.tried.map((t,i)=><li key={i}><strong>{t.kind==='map'?'Firecrawl map':t.kind==='sitemap'?'Site map':t.kind==='list'?'List page':'Home page'}</strong> {t.url||t.host}<small>{[t.result,t.addresses!=null&&`${fmtNumber(t.addresses)} addresses`,t.matches!=null&&`${fmtNumber(t.matches)} course addresses`,t.known?`${fmtNumber(t.known_found||0)} of ${fmtNumber(t.known)} known pages`:null,t.http&&`HTTP ${t.http}`,t.via&&viaLabel(t.via),t.sibling_sites&&`study sites: ${t.sibling_sites.map(x=>x[0]).join(', ')}`].filter(Boolean).join(' · ')}</small></li>)}</ul>:<Empty text="The finder has not looked at this university yet."/>}</td></tr>}
        {add?.provider_id===p.provider_id&&<tr className="cs-detail"><td colSpan={4}><div className="cs-add" data-cs-add>
          <select value={add.kind} onChange={e=>setAdd({...add,kind:e.target.value})}><option value="list">Course list (feeds the page matchers)</option><option value="programme">Programme list (creates hidden courses)</option></select>
          <select value={add.read_via} onChange={e=>setAdd({...add,read_via:e.target.value})}><option value="">Read as a page or site map</option><option value="map">Read by Firecrawl map</option></select>
          <input value={add.url} onChange={e=>setAdd({...add,url:e.target.value})} placeholder="Address (list page, site map or site)"/>
          <input value={add.pattern} onChange={e=>setAdd({...add,pattern:e.target.value})} placeholder={add.kind==='programme'?'Programme page address pattern (required)':'Course address pattern (site map or map)'}/>
          <Button compact disabled={!!busy||!add.url||(add.kind==='programme'&&!add.pattern)} onClick={()=>act(add.kind==='programme'?'add_programme':'add_list',add.kind==='programme'?{provider_id:p.provider_id,url:add.url,url_pattern:add.pattern,read_via:add.read_via,kind:'sitemap'}:{provider_id:p.provider_id,url:add.url,link_pattern:add.pattern,read_via:add.read_via},'Source added; it is read on the next run.').then(()=>setAdd(null))}>Add</Button>
        </div></td></tr>}
        </React.Fragment>}):<tr><td colSpan={4} className="cf-empty-cell">No university here yet. The finder adds them as it looks.</td></tr>}
      </tbody></table></div>
    </section>
    <div className="qw-grid">
      <section className="m-panel">
        <SectionTitle title="Countries" subtitle="The finder looks only at universities in these countries."/>
        <ul className="qw-list">{(d.countries||[]).map(c=><li key={c.country_code}><strong>{c.country_code}</strong> {c.enabled?'on':'off'}<small>{c.reason}</small>
          {canEdit&&<Button compact disabled={!!busy} onClick={()=>act('country',{country:c.country_code,enabled:!c.enabled},`${c.country_code} switched ${c.enabled?'off':'on'}.`)}>{c.enabled?'Switch off':'Switch on'}</Button>}</li>)}</ul>
        {canEdit&&<AddCountry busy={!!busy} onAdd={cc=>act('country',{country:cc,enabled:true},`${cc} added.`)}/>}
      </section>
      <section className="m-panel">
        <SectionTitle title="What the finder tries" subtitle="List addresses tried on a university's site, and the words a course folder is named with (used when too few course pages are known)."/>
        <ul className="qw-list">{(d.paths||[]).map(x=><li key={x.id}><strong>{x.kind==='list_path'?'List address':'Folder word'}</strong> <code>{x.value}</code> {x.enabled?'':'(off)'}
          {canEdit&&<Button compact disabled={!!busy} onClick={()=>act('path',{kind:x.kind,value:x.value,sort:x.sort,enabled:!x.enabled},'Saved.')}>{x.enabled?'Switch off':'Switch on'}</Button>}</li>)}</ul>
        {canEdit&&<AddPath busy={!!busy} onAdd={(kind,value)=>act('path',{kind,value,enabled:true},'Added.')}/>}
      </section>
    </div>
  </div>
}
function AddCountry({busy,onAdd}){const[v,setV]=useState('');return <div className="cs-add"><input value={v} maxLength={2} onChange={e=>setV(e.target.value.toUpperCase())} placeholder="Country code (e.g. UK)"/><Button compact disabled={busy||v.length!==2} onClick={()=>onAdd(v)}>Add country</Button></div>}
function AddPath({busy,onAdd}){const[k,setK]=useState('list_path'),[v,setV]=useState('');return <div className="cs-add"><select value={k} onChange={e=>setK(e.target.value)}><option value="list_path">List address</option><option value="folder_word">Folder word</option></select><input value={v} onChange={e=>setV(e.target.value)} placeholder={k==='list_path'?'/study/programmes':'courses?'}/><Button compact disabled={busy||!v} onClick={()=>onAdd(k,v)}>Add</Button></div>}
