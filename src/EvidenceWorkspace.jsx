import React,{useEffect,useMemo,useState}from'react'
import{
  AlertTriangle,ArrowLeft,BookOpen,CheckCircle2,ChevronDown,Clock3,Database,Download,
  ExternalLink,FileCheck2,FileSearch,Filter,GitBranch,Hash,History,Layers3,Link2,
  RefreshCw,Search,ShieldCheck,Workflow,X
}from'lucide-react'
import{api}from'./lib/supabase'
import'./evidence-workspace.css'

const PAGE_SIZE=50
const ENTITY_PAGE={provider:'Providers',course:'Courses',campus:'Campuses',scholarship:'Scholarships'}
const EMPTY_FILTERS={country:'',sourceId:'',layer:'',entityType:'',entityId:'',providerId:'',jobId:'',evidenceType:'',mime:'',jobStatus:'',status:'',extractionState:'',freshness:'',verifiedFrom:'',verifiedTo:'',hash:'',unresolvedConflicts:''}

export default function EvidenceWorkspace({onError,navigate,routeParams}){
  const initial=useMemo(()=>filtersFromRoute(routeParams),[routeParams?.toString?.()])
  const[query,setQuery]=useState(routeParams?.get?.('q')||'')
  const[filters,setFilters]=useState(initial)
  const[opts,setOpts]=useState({})
  const[data,setData]=useState(null)
  const[offset,setOffset]=useState(0)
  const[busy,setBusy]=useState(false)
  const[advanced,setAdvanced]=useState(Boolean(initial.entityId||initial.providerId||initial.jobId||initial.hash||initial.verifiedFrom||initial.verifiedTo))
  const[selected,setSelected]=useState(routeParams?.get?.('evidence_id')||null)
  const[detail,setDetail]=useState(null)
  const[detailBusy,setDetailBusy]=useState(false)
  const debounced=useDebounce(query,260)

  useEffect(()=>{api.evidenceFilterOptions().then(setOpts).catch(e=>onError(e.message))},[])
  useEffect(()=>{setFilters(initial);setOffset(0);if(routeParams?.get?.('evidence_id'))setSelected(routeParams.get('evidence_id'))},[JSON.stringify(initial),routeParams?.get?.('evidence_id')])
  const args=useMemo(()=>({...filters,limit:PAGE_SIZE,offset,query:debounced,sort:'captured',direction:'desc'}),[offset,debounced,JSON.stringify(filters)])
  useEffect(()=>{let live=true;setBusy(true);api.evidencePage(args).then(x=>live&&setData(x)).catch(e=>onError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[JSON.stringify(args)])
  useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters)])
  useEffect(()=>{if(!selected){setDetail(null);return}let live=true;setDetailBusy(true);Promise.all([
    api.evidenceDetail(selected),api.evidenceObservations(selected,{limit:100}),api.evidenceEntities(selected,{limit:100})
  ]).then(([base,observations,entities])=>{if(live)setDetail({...base,observations,entities})}).catch(e=>onError(e.message)).finally(()=>live&&setDetailBusy(false));return()=>{live=false}},[selected])

  const rows=rowsOf(data),total=Number(data?.total??rows.length),active=activeFilters(filters)
  const setFilter=(k,v)=>setFilters(f=>({...f,[k]:v}))
  const clear=()=>{setQuery('');setFilters({...EMPTY_FILTERS});setOffset(0)}
  const deepContext=filters.entityId||filters.providerId||filters.jobId

  return <div className="evidence-page">
    <section className="m-panel evidence-hero">
      <div><span className="evidence-private"><ShieldCheck size={14}/>Private governed evidence</span><h2>Evidence, provenance & change history</h2><p>Trace source → acquisition job → artifact → observation/claim → canonical entity → review → current Search/publication state without collapsing authority layers.</p></div>
      <div className="evidence-hero-actions"><button className="m-secondary" onClick={()=>{setBusy(true);api.evidencePage(args).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))}}><RefreshCw size={14}/>Refresh</button><div className="evidence-count"><strong>{fmt(total)}</strong><span>matching artifacts</span></div></div>
    </section>

    <section className="m-panel evidence-workbench">
      <div className="evidence-search-row">
        <label className="evidence-search"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search source, authority URL, job, hash, artifact metadata or evidence ID…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label>
        <button className={`m-filter-toggle ${advanced?'active':''}`} onClick={()=>setAdvanced(x=>!x)}><Filter size={14}/>Advanced{active.length?` · ${active.length}`:''}</button>
        <button className="m-secondary compact" disabled={!query&&!active.length} onClick={clear}><RefreshCw size={14}/>Clear</button>
      </div>

      <div className="evidence-filter-grid">
        <Select label="Country" value={filters.country} onChange={v=>setFilter('country',v)} options={normalise(opts.countries)}/>
        <Select label="Source" value={filters.sourceId} onChange={v=>setFilter('sourceId',v)} options={normalise(opts.sources)}/>
        <Select label="Layer" value={filters.layer} onChange={v=>setFilter('layer',v)} options={normalise(opts.layers)}/>
        <Select label="Entity type" value={filters.entityType} onChange={v=>setFilter('entityType',v)} options={normalise(opts.entity_types)}/>
        <Select label="Evidence type" value={filters.evidenceType} onChange={v=>setFilter('evidenceType',v)} options={normalise(opts.evidence_types)}/>
        <Select label="Status" value={filters.status} onChange={v=>setFilter('status',v)} options={normalise(opts.statuses)}/>
        <Select label="Freshness" value={filters.freshness} onChange={v=>setFilter('freshness',v)} options={normalise(opts.freshness_states)}/>
        <Select label="MIME" value={filters.mime} onChange={v=>setFilter('mime',v)} options={normalise(opts.mimes)}/>
        {advanced&&<>
          <Select label="Extraction" value={filters.extractionState} onChange={v=>setFilter('extractionState',v)} options={normalise(opts.extraction_states)}/>
          <Select label="Job status" value={filters.jobStatus} onChange={v=>setFilter('jobStatus',v)} options={normalise(opts.job_statuses)}/>
          <Select label="Unresolved conflict" value={filters.unresolvedConflicts} onChange={v=>setFilter('unresolvedConflicts',v)} options={[o('true','Yes'),o('false','No')]}/>
          <TextFilter label="Entity UUID" value={filters.entityId} onChange={v=>setFilter('entityId',v)} placeholder="Provider / Course / Campus / Scholarship"/>
          <TextFilter label="Provider UUID" value={filters.providerId} onChange={v=>setFilter('providerId',v)} placeholder="Provider scope"/>
          <TextFilter label="Job UUID" value={filters.jobId} onChange={v=>setFilter('jobId',v)} placeholder="Acquisition job"/>
          <TextFilter label="Hash prefix" value={filters.hash} onChange={v=>setFilter('hash',v)} placeholder="SHA-256 prefix"/>
          <DateFilter label="Verified from" value={filters.verifiedFrom} onChange={v=>setFilter('verifiedFrom',v)}/>
          <DateFilter label="Verified to" value={filters.verifiedTo} onChange={v=>setFilter('verifiedTo',v)}/>
        </>}
      </div>

      {(query||active.length>0)&&<div className="evidence-chips">{query&&<Chip label={`Search: ${query}`} onRemove={()=>setQuery('')}/>} {active.map(([k,v])=><Chip key={k} label={`${labelFor(k)}: ${optionLabel(k,v,opts)}`} onRemove={()=>setFilter(k,'')}/>)}</div>}
      {deepContext&&<div className="evidence-context"><Link2 size={14}/><span>Scoped from a governed operational/canonical deep link.</span><button onClick={()=>{setFilter('entityId','');setFilter('providerId','');setFilter('jobId','')}}>Remove scope</button></div>}

      <EvidenceTable rows={rows} loading={busy} selected={selected} onSelect={setSelected}/>
      <Pager offset={offset} total={total} onOffset={setOffset}/>
    </section>

    {selected&&<EvidenceDrawer id={selected} data={detail} busy={detailBusy} onClose={()=>setSelected(null)} onError={onError} navigate={navigate}/>} 
  </div>
}

function EvidenceTable({rows,loading,selected,onSelect}){
  const cols=10
  return <div className="evidence-table-wrap"><table className="evidence-table"><thead><tr><th>Artifact</th><th>Source</th><th>Layer</th><th>Evidence type</th><th>Captured</th><th>Extraction</th><th>Freshness</th><th>Status</th><th>Job</th><th>Integrity</th></tr></thead><tbody>
    {loading&&!rows.length?Array.from({length:8}).map((_,i)=><tr key={i}>{Array.from({length:cols}).map((__,j)=><td key={j}><span className="evidence-skeleton"/></td>)}</tr>):rows.length?rows.map(r=><tr key={r.id} className={String(selected)===String(r.id)?'selected':''} onClick={()=>onSelect(r.id)}>
      <td><span className="evidence-artifact"><FileCheck2 size={15}/><span><strong>{shortId(r.id)}</strong><small>{r.country_code?`${flag(r.country_code)} ${r.country_code}`:'No country'} · {r.mime_type||'Unknown MIME'}</small></span></span></td>
      <td><strong>{r.source_label||'Unlinked source'}</strong><small>{r.source_type||r.source_status||'—'}</small></td>
      <td><Badge value={r.layer}/></td><td>{human(r.evidence_type)}</td><td><strong>{dateTime(r.captured_at)}</strong><small>{relative(r.captured_at)}</small></td>
      <td><State value={r.extraction_state}/><small>{fmt(r.observation_count)} observation{Number(r.observation_count)===1?'':'s'}{r.has_source_null?' · source-null':''}</small></td>
      <td><State value={r.freshness_state}/><small>{r.history_state?human(r.history_state):'—'}</small></td><td><State value={r.status}/>{r.unresolved_conflict&&<small className="danger-text">Unresolved conflict</small>}</td>
      <td><strong>{r.job_type||'No job'}</strong><small>{r.job_status?human(r.job_status):r.job_id?shortId(r.job_id):'—'}</small></td>
      <td><code>{r.content_hash?`${r.content_hash.slice(0,12)}…`:'—'}</code><small>{r.storage_available?'Private object present':'Metadata only'}</small></td>
    </tr>):<tr><td colSpan={cols}><Empty icon={Database} text="No evidence artifacts match the current governed filters."/></td></tr>}
  </tbody></table></div>
}

function EvidenceDrawer({id,data,busy,onClose,onError,navigate}){
  const[accessBusy,setAccessBusy]=useState('')
  useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose])
  async function access(mode){setAccessBusy(mode);try{const x=await api.evidenceAccess(id,mode);if(!x?.url)throw new Error('Signed evidence URL was not returned.');window.open(x.url,'_blank','noopener,noreferrer')}catch(e){onError(e.message)}finally{setAccessBusy('')}}
  const a=data?.artifact||{},s=data?.source||{},j=data?.job||{},storage=data?.storage||{},obs=rowsOf(data?.observations),entities=rowsOf(data?.entities),claims=data?.claims||[],reviews=data?.reviews||[],actions=data?.review_actions||[]
  return <><button className="evidence-drawer-backdrop" onClick={onClose}/><aside className="evidence-drawer">
    <div className="evidence-drawer-head"><div><small>Evidence artifact</small><h2>{a.evidence_type?human(a.evidence_type):shortId(id)}</h2><span>{id}</span></div><button onClick={onClose} aria-label="Close"><X size={18}/></button></div>
    {busy?<div className="evidence-drawer-loading"><span className="evidence-spinner"/>Loading governed lineage…</div>:<div className="evidence-drawer-body">
      <LineageStrip source={s} job={j} artifact={a} observationCount={obs.length} entityCount={entities.length} reviewCount={reviews.length}/>
      <section className="evidence-detail-hero">
        <div><span className="evidence-private"><ShieldCheck size={13}/>Private evidence boundary</span><h3>{s.label||'Evidence artifact'}</h3><p>{safeUrl(a.source_url)||safeUrl(s.authority_url)||'No public source URL recorded.'}</p><div className="evidence-state-row"><State value={a.status}/><State value={a.extraction_state}/><State value={a.freshness_state}/>{data?.unresolved_conflict&&<State value="conflict"/>}</div></div>
        <div className="evidence-access-actions"><button className="m-secondary" disabled={!storage.preview_allowed||accessBusy} onClick={()=>access('preview')}><FileSearch size={14}/>{accessBusy==='preview'?'Signing…':'Preview'}</button><button className="m-secondary" disabled={!storage.download_allowed||accessBusy} onClick={()=>access('download')}><Download size={14}/>{accessBusy==='download'?'Signing…':'Download'}</button></div>
      </section>

      <DetailGrid items={[
        ['Acquired',dateTime(a.captured_at)],['Verified',a.verification_at?dateTime(a.verification_at):'Not verified'],['Snapshot / version',a.snapshot_version||'Not versioned'],['Content hash',a.content_hash||'—'],
        ['MIME',a.mime_type||storage.content_type||'—'],['Validity',range(a.valid_from,a.valid_to)],['Storage',storage.available?`${fmtBytes(storage.size_bytes)} · private object`:'No private object'],['Change Control',(data?.change_control_ids||[]).join(', ')||'Not linked']
      ]}/>

      <Section icon={BookOpen} title="Source authority & acquisition" subtitle="Public authority metadata only; no raw private Storage URL is exposed.">
        <KeyRows rows={[
          ['Source',s.label],['Type',s.source_type],['Country',s.country_code],['Trust rank',s.trust_rank],['Authority URL',safeUrl(s.authority_url)],['Artifact source URL',safeUrl(a.source_url)],['Source last success',s.last_success_at?dateTime(s.last_success_at):null],['Source last failure',s.last_failure_at?dateTime(s.last_failure_at):null]
        ]}/>
        <External url={a.source_url||s.authority_url} label="Open source authority"/>
      </Section>

      <Section icon={Workflow} title="Acquisition job" subtitle="The execution that captured or associated this artifact.">
        {j.id?<div className="evidence-job-card"><div><strong>{human(j.job_type||j.domain||'Acquisition job')}</strong><span>{j.id}</span></div><State value={j.status}/><KeyRows rows={[["Domain",j.domain],["Started",j.started_at?dateTime(j.started_at):null],["Completed",j.completed_at?dateTime(j.completed_at):null],["Attempts",j.attempt_count]]}/></div>:<Empty icon={Workflow} text="No acquisition job is linked to this artifact."/>}
      </Section>

      <Section icon={FileCheck2} title={`Extracted observations · ${fmt(data?.observations?.total??obs.length)}`} subtitle="Source-null, rejected and superseded values remain explicit and are not silently treated as missing.">
        {obs.length?<div className="evidence-observation-list">{obs.map(x=><Observation key={x.observation_id} value={x} onCanonical={()=>openCanonical(x,navigate)}/>)}</div>:<Empty icon={FileSearch} text="No extracted canonical observation is linked. This is classified as missing extraction unless the artifact is rejected by an explicit claim/review state."/>}
      </Section>

      <Section icon={Link2} title={`Affected canonical entities · ${fmt(data?.entities?.total??entities.length)}`} subtitle={data?.entities?.consequence_note||'Current downstream state is context, not an assertion of causal publication admission.'}>
        {entities.length?<div className="evidence-entity-list">{entities.map(x=><EntityCard key={`${x.entity_type}:${x.entity_id}`} value={x} onOpen={()=>openCanonical(x,navigate)}/>)}</div>:<Empty icon={Link2} text="No canonical entity link is materialised for this artifact."/>}
      </Section>

      <Section icon={GitBranch} title="Snapshot & change history" subtitle="Predecessor/successor state is shown without rewriting historical evidence.">
        <Supersession value={data?.supersession}/>
      </Section>

      <Section icon={History} title="Claims, review & decisions" subtitle="Layer 3 suggestions and Layer 4 human resolution remain distinct from source authority.">
        {!claims.length&&!reviews.length&&!actions.length?<Empty icon={History} text="No claims, review cases or review actions are currently linked to this artifact."/>:<><RecordList title="Claims" rows={claims}/><RecordList title="Review cases" rows={reviews}/><RecordList title="Review actions" rows={actions}/></>}
      </Section>

      <Section icon={ShieldCheck} title="Storage controls" subtitle="Access is issued only by the authorised signed-access service and expires after 60 seconds.">
        <KeyRows rows={[["Private object available",yesNo(storage.available)],["Preview allowed",yesNo(storage.preview_allowed)],["Download allowed",yesNo(storage.download_allowed)],["Object created",storage.object_created_at?dateTime(storage.object_created_at):null],["Object updated",storage.object_updated_at?dateTime(storage.object_updated_at):null],["Content type",storage.content_type]]}/>
      </Section>
    </div>}
  </aside></>
}

function LineageStrip({source,job,artifact,observationCount,entityCount,reviewCount}){const steps=[['Source',source?.label||'Unlinked'],['Acquisition job',job?.job_type||'Unlinked'],['Artifact',artifact?.evidence_type||'Evidence'],['Observation / claim',`${observationCount} observation${observationCount===1?'':'s'}`],['Canonical entity',`${entityCount} linked`],['Review / decision',`${reviewCount} review${reviewCount===1?'':'s'}`],['Search / publication','Current consequence state']];return <div className="evidence-lineage">{steps.map(([a,b],i)=><React.Fragment key={a}><div><small>{a}</small><strong>{b}</strong></div>{i<steps.length-1&&<span>→</span>}</React.Fragment>)}</div>}
function Observation({value:x,onCanonical}){return <article className="evidence-observation"><div className="evidence-observation-head"><div><strong>{human(x.field_code||x.observation_type)}</strong><span>{human(x.observation_type)} · {x.entity_label||x.entity_code||'Unresolved entity'}</span></div><State value={x.value_state||x.status}/></div><pre>{pretty(x.value_json)}</pre><div className="evidence-observation-meta"><span>{x.verified_at?`Verified ${dateTime(x.verified_at)}`:x.observed_at?`Observed ${dateTime(x.observed_at)}`:'No observation timestamp'}</span>{x.entity_id&&<button onClick={onCanonical}><ArrowLeft size={12}/>Canonical {human(x.entity_type)}</button>}</div></article>}
function EntityCard({value:x,onOpen}){return <article className="evidence-entity-card"><div><small>{human(x.entity_type)}</small><strong>{x.entity_label||x.entity_code||shortId(x.entity_id)}</strong><span>{x.provider_label&&x.provider_label!==x.entity_label?x.provider_label:''}</span></div><div className="evidence-entity-state"><State value={x.canonical_publication_status}/>{x.entity_type==='course'&&<span>{x.search_projected?'Search projected':'Not in Search'}{x.search_projected?` · fee ${yesNo(x.search_has_fee)} · intake ${yesNo(x.search_has_intake)} · English ${yesNo(x.search_has_english)}`:''}</span>}</div><button className="m-secondary compact" onClick={onOpen}>Open canonical →</button></article>}
function Supersession({value}){const prev=value?.predecessor,next=value?.successors||[];if(!prev&&!next.length)return <Empty icon={GitBranch} text="This artifact has no explicit predecessor or successor link."/>;return <div className="evidence-history"><div><small>Predecessor</small><strong>{prev?shortId(prev.id):'None'}</strong>{prev?.captured_at&&<span>{dateTime(prev.captured_at)}</span>}</div><div><small>Successors</small><strong>{next.length}</strong>{next.map(x=><span key={x.id}>{shortId(x.id)} · {dateTime(x.captured_at)}</span>)}</div></div>}
function RecordList({title,rows}){return <div className="evidence-record-group"><h4>{title}</h4>{rows.map((x,i)=><div className="evidence-record" key={x.id||i}><strong>{human(x.action||x.field_code||x.domain||x.status||title)}</strong><span>{Object.entries(x).filter(([k,v])=>k!=='id'&&v!=null&&typeof v!=='object').slice(0,5).map(([k,v])=>`${human(k)}: ${String(v)}`).join(' · ')}</span></div>)}</div>}
function Section({icon:Icon,title,subtitle,children}){return <section className="evidence-section"><div className="evidence-section-title"><span><Icon size={15}/></span><div><h3>{title}</h3>{subtitle&&<p>{subtitle}</p>}</div></div>{children}</section>}
function DetailGrid({items}){return <div className="evidence-detail-grid">{items.map(([k,v])=><div key={k}><small>{k}</small><strong className={k==='Content hash'?'mono':''}>{v||'—'}</strong></div>)}</div>}
function KeyRows({rows}){return <div className="evidence-kv">{rows.filter(([,v])=>v!==undefined).map(([k,v])=><div key={k}><span>{k}</span><strong>{v==null||v===''?'—':String(v)}</strong></div>)}</div>}
function External({url,label}){const safe=safeUrl(url);return safe?<a className="evidence-external" href={safe} target="_blank" rel="noreferrer"><ExternalLink size={13}/>{label}</a>:null}
function Empty({icon:Icon,text}){return <div className="evidence-empty"><Icon size={17}/><span>{text}</span></div>}

function Select({label,value,onChange,options=[]}){const[open,setOpen]=useState(false),[q,setQ]=useState('');const selected=options.find(x=>String(x.value)===String(value));const shown=options.filter(x=>`${x.label} ${x.meta||''}`.toLowerCase().includes(q.toLowerCase())).slice(0,200);return <div className="evidence-select"><button className={value?'has-value':''} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selected?.label||'All'}</strong></span><ChevronDown size={13}/></button>{open&&<div className="evidence-select-pop"><label><Search size={13}/><input autoFocus value={q} onChange={e=>setQ(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></label><button onClick={()=>{onChange('');setOpen(false);setQ('')}} className={!value?'selected':''}>All</button>{shown.map(x=><button key={String(x.value)} onClick={()=>{onChange(x.value);setOpen(false);setQ('')}} className={String(value)===String(x.value)?'selected':''}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}</div>}</div>}
function TextFilter({label,value,onChange,placeholder}){return <label className="evidence-text-filter"><small>{label}</small><input value={value||''} onChange={e=>onChange(e.target.value.trim())} placeholder={placeholder}/></label>}
function DateFilter({label,value,onChange}){return <label className="evidence-text-filter"><small>{label}</small><input type="date" value={value||''} onChange={e=>onChange(e.target.value)}/></label>}
function Chip({label,onRemove}){return <span>{label}<button onClick={onRemove}><X size={11}/></button></span>}
function Badge({value}){return <span className="evidence-badge">{human(value||'unknown')}</span>}
function State({value}){const s=String(value||'unknown').toLowerCase(),tone=['rejected','failed','error','conflict','blocked'].includes(s)?'danger':['source_null','stale','expired','superseded','warning'].includes(s)?'warning':['missing_extraction','pending','queued','running','processing','in_review'].includes(s)?'info':['current','active','completed','succeeded','published','extracted','resolved','captured'].includes(s)?'success':'neutral';return <span className={`evidence-state ${tone}`}>{human(s)}</span>}
function Pager({offset,total,onOffset}){const pages=Math.max(1,Math.ceil(total/PAGE_SIZE)),page=Math.floor(offset/PAGE_SIZE)+1;return <div className="evidence-pager"><span>Page <strong>{page}</strong> of {pages} · {fmt(total)} records</span><div><button disabled={offset<=0} onClick={()=>onOffset(Math.max(0,offset-PAGE_SIZE))}>Previous</button><button disabled={offset+PAGE_SIZE>=total} onClick={()=>onOffset(offset+PAGE_SIZE)}>Next</button></div></div>}

function openCanonical(x,navigate){const page=ENTITY_PAGE[String(x.entity_type||'').toLowerCase()];if(!page||!navigate)return;const id=x.entity_id;if(id)navigate(page,{id})}
function filtersFromRoute(params){const f={...EMPTY_FILTERS};if(!params?.get)return f;for(const[k,p]of Object.entries({country:'country',sourceId:'source_id',layer:'layer',entityType:'entity_type',entityId:'entity_id',providerId:'provider_id',jobId:'job_id',evidenceType:'evidence_type',mime:'mime',jobStatus:'job_status',status:'status',extractionState:'extraction_state',freshness:'freshness',verifiedFrom:'verified_from',verifiedTo:'verified_to',hash:'hash',unresolvedConflicts:'unresolved_conflicts'})){const v=params.get(p);if(v)f[k]=v}return f}
function normalise(list){return(Array.isArray(list)?list:[]).map(x=>{if(typeof x!=='object')return o(String(x),human(x));const value=x.code??x.id??x.value??x.name,label=x.name??x.label??human(value);return o(String(value),label,x.source_type||'')})}
function o(value,label,meta=''){return{value,label,meta}}
function activeFilters(f){return Object.entries(f).filter(([,v])=>v!==''&&v!=null)}
function labelFor(k){return({sourceId:'Source',entityType:'Entity type',entityId:'Entity',providerId:'Provider',jobId:'Job',evidenceType:'Evidence type',jobStatus:'Job status',extractionState:'Extraction',verifiedFrom:'Verified from',verifiedTo:'Verified to',unresolvedConflicts:'Unresolved conflict'})[k]||human(k)}
function optionLabel(k,v,opts){const sets={country:opts.countries,sourceId:opts.sources,layer:opts.layers,entityType:opts.entity_types,evidenceType:opts.evidence_types,mime:opts.mimes,jobStatus:opts.job_statuses,status:opts.statuses,extractionState:opts.extraction_states,freshness:opts.freshness_states};const found=normalise(sets[k]).find(x=>String(x.value)===String(v));if(k==='unresolvedConflicts')return v==='true'?'Yes':'No';return found?.label||String(v)}
function rowsOf(v){if(Array.isArray(v))return v;return v?.items??v?.rows??v?.data??[]}
function useDebounce(value,delay){const[v,setV]=useState(value);useEffect(()=>{const t=setTimeout(()=>setV(value),delay);return()=>clearTimeout(t)},[value,delay]);return v}
function human(v){if(v==null||v==='')return'—';return String(v).replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())}
function fmt(v){const n=Number(v);return Number.isFinite(n)?n.toLocaleString():'—'}
function dateTime(v){if(!v)return'—';const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleString(undefined,{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})}
function relative(v){const d=new Date(v);if(Number.isNaN(+d))return'Unknown time';const s=Math.max(0,Math.round((Date.now()-d.getTime())/1000));if(s<60)return'Just now';if(s<3600)return`${Math.round(s/60)}m ago`;if(s<86400)return`${Math.round(s/3600)}h ago`;if(s<604800)return`${Math.round(s/86400)}d ago`;return dateTime(v)}
function range(a,b){if(!a&&!b)return'No explicit validity window';return`${a?dateTime(a):'Open'} → ${b?dateTime(b):'Open'}`}
function fmtBytes(v){const n=Number(v);if(!Number.isFinite(n))return'Unknown size';if(n<1024)return`${n} B`;if(n<1024**2)return`${(n/1024).toFixed(1)} KB`;return`${(n/1024**2).toFixed(1)} MB`}
function yesNo(v){return v?'Yes':'No'}
function shortId(v){return v?`${String(v).slice(0,8)}…`:'—'}
function flag(code){const c=String(code||'').toUpperCase();return c.length===2?String.fromCodePoint(...[...c].map(x=>127397+x.charCodeAt())):''}
function safeUrl(v){try{const u=new URL(String(v||''));return['http:','https:'].includes(u.protocol)?u.toString():null}catch{return null}}
function pretty(v){if(v==null)return'—';try{return JSON.stringify(v,null,2)}catch{return String(v)}}
