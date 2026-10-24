import React,{useEffect,useMemo,useRef,useState}from'react'
import{Empty,FilterChip as Chip,Badge as KitBadge,LayerBadge,StatusChip}from'./ui-kit'
import{Pager}from'./ui-kit'
import{
  ChevronDown,Database,Download,ExternalLink,FileCheck2,FileSearch,
  Filter,Link2,RefreshCw,Search,X
}from'lucide-react'
import{fmtNumber,fmtDate,fmtDateTime,fmtBytes as formatBytes}from'./lib/format.js'
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
  const[sourceLabel,setSourceLabel]=useState('')
  const[data,setData]=useState(null)
  const[offset,setOffset]=useState(0)
  const[busy,setBusy]=useState(false)
  const[advanced,setAdvanced]=useState(Boolean(initial.entityId||initial.providerId||initial.jobId||initial.hash||initial.verifiedFrom||initial.verifiedTo))
  const[selected,setSelected]=useState(routeParams?.get?.('evidence_id')||null)
  const debounced=useDebounce(query,260)

  useEffect(()=>{api.evidenceFilterOptions().then(setOpts).catch(e=>onError(e.message))},[])
  useEffect(()=>{setFilters(initial);setOffset(0);if(routeParams?.get?.('evidence_id'))setSelected(routeParams.get('evidence_id'))},[JSON.stringify(initial),routeParams?.get?.('evidence_id')])
  const args=useMemo(()=>({...filters,limit:PAGE_SIZE,offset,query:debounced,sort:'captured',direction:'desc'}),[offset,debounced,JSON.stringify(filters)])
  useEffect(()=>{let live=true;setBusy(true);api.evidencePage(args).then(x=>live&&setData(x)).catch(e=>onError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[JSON.stringify(args)])
  useEffect(()=>setOffset(0),[debounced,JSON.stringify(filters)])

  const rows=rowsOf(data),total=Number(data?.total??rows.length),active=activeFilters(filters)
  const[roles,setRoles]=useState({})
  useEffect(()=>{let live=true;const ids=rows.map(r=>r.id).filter(Boolean);setRoles({});if(ids.length)api.evidenceCopyRoles(ids).then(x=>live&&setRoles(x||{})).catch(()=>{});return()=>{live=false}},[rows.map(r=>r.id).join(',')])
  const setFilter=(k,v)=>setFilters(f=>({...f,[k]:v}))
  const setCountry=v=>{setSourceLabel('');setFilters(f=>({...f,country:v,sourceId:''}))}
  const clear=()=>{setQuery('');setFilters({...EMPTY_FILTERS});setOffset(0)}
  const deepContext=filters.entityId||filters.providerId||filters.jobId

  return <div className="evidence-page">
    <section className="m-panel evidence-hero slim">
      {/* v2.15.227: the page header already names the page; this strip keeps only the count and Refresh */}
      <div className="evidence-count"><strong>{fmt(total)}</strong><span>matching saved pages and files</span></div>
      <div className="evidence-hero-actions"><button className="m-secondary" onClick={()=>{setBusy(true);api.evidencePage(args).then(setData).catch(e=>onError(e.message)).finally(()=>setBusy(false))}}><RefreshCw size={14}/>Refresh</button></div>
    </section>

    <section className="m-panel evidence-workbench">
      <div className="evidence-search-row">
        <label className="evidence-search"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search source, authority URL, job, hash, artifact metadata or evidence ID…"/>{query&&<button onClick={()=>setQuery('')}><X size={14}/></button>}</label>
        <button className={`m-filter-toggle ${advanced?'active':''}`} onClick={()=>setAdvanced(x=>!x)}><Filter size={14}/>Advanced{active.length?` · ${active.length}`:''}</button>
        <button className="m-secondary compact" disabled={!query&&!active.length} onClick={clear}><RefreshCw size={14}/>Clear</button>
      </div>

      <div className="evidence-filter-grid">
        <Select label="Country" value={filters.country} onChange={setCountry} options={normalise(opts.countries)}/>
        <PagedEvidenceSelect label="Source" value={filters.sourceId} valueLabel={sourceLabel} country={filters.country} onChange={(v,l)=>{setSourceLabel(l||'');setFilter('sourceId',v)}}/>
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

      {(query||active.length>0)&&<div className="evidence-chips">{query&&<Chip label={`Search: ${query}`} onRemove={()=>setQuery('')}/>} {active.map(([k,v])=><Chip key={k} label={`${labelFor(k)}: ${k==='sourceId'?(sourceLabel||String(v)):optionLabel(k,v,opts)}`} onRemove={()=>{if(k==='sourceId')setSourceLabel('');setFilter(k,'')}}/>)}</div>}
      {deepContext&&<div className="evidence-context"><Link2 size={14}/><span>Opened from a link on another screen.</span><button onClick={()=>{setFilter('entityId','');setFilter('providerId','');setFilter('jobId','')}}>Remove scope</button></div>}

      <EvidenceTable rows={rows} roles={roles} loading={busy} selected={selected} onSelect={setSelected}/>
      <Pager offset={offset} limit={PAGE_SIZE} total={total} onOffset={setOffset} className="evidence-pager"/>
    </section>

    {selected&&<EvidenceDrawer id={selected} onClose={()=>setSelected(null)} onOpen={setSelected} onError={onError} navigate={navigate}/>}
  </div>
}

function EvidenceTable({rows,roles={},loading,selected,onSelect}){
  const cols=10
  return <div className="evidence-table-wrap"><table className="evidence-table"><thead><tr><th>Artifact</th><th>Source</th><th>Layer</th><th>Evidence type</th><th>Captured</th><th>Extraction</th><th>Freshness</th><th>Status</th><th>Job</th><th>Integrity</th></tr></thead><tbody>
    {loading&&!rows.length?Array.from({length:8}).map((_,i)=><tr key={i}>{Array.from({length:cols}).map((__,j)=><td key={j}><span className="evidence-skeleton"/></td>)}</tr>):rows.length?rows.map(r=><tr key={r.id} className={String(selected)===String(r.id)?'selected':''} onClick={()=>onSelect(r.id)}>
      <td data-evidence-id={r.id}><span className="evidence-artifact"><FileCheck2 size={15}/><span><strong>{evidenceKind(r.evidence_type)}</strong><small>{r.country_code?`${flag(r.country_code)} ${r.country_code}`:'No country'} · {r.mime_type||'Unknown MIME'}</small></span></span></td>
      <td><strong>{r.source_label||'Unlinked source'}</strong><small>{r.source_type||r.source_status||'—'}</small><CopyRole role={roles[r.id]}/></td>
      <td><Badge value={r.layer}/></td><td><span className="evidence-type-cell"><strong>{human(r.evidence_type)}</strong><span className="evidence-format-badge">{formatOf(r.mime_type,r.evidence_type)}</span></span></td><td><strong>{dateTime(r.captured_at)}</strong><small>{relative(r.captured_at)}</small></td>
      <td><State value={r.extraction_state}/><small>{fmt(r.observation_count)} observation{Number(r.observation_count)===1?'':'s'}{r.has_source_null?' · source gave no value':''}</small></td>
      <td><State value={r.freshness_state}/><small>{r.history_state?human(r.history_state):'—'}</small></td><td><State value={r.status}/>{r.unresolved_conflict&&<small className="danger-text">Unresolved conflict</small>}</td>
      <td data-job-id={r.job_id||undefined}><strong>{r.job_type?jobWords(r.job_type):'No job'}</strong><small>{r.job_status?human(r.job_status):'—'}</small></td>
      <td data-content-hash={r.content_hash||undefined}><strong>{r.storage_available?'File is stored':'Details only'}</strong><small>{r.content_hash?'Checksum recorded':'No checksum'}</small></td>
    </tr>):<tr><td colSpan={cols}><Empty icon={Database} text="No stored pages match these filters."/></td></tr>}
  </tbody></table></div>
}

// v2.15.293 (Platform Admin, 19 Oct 2026: "explain why the evidence details panel is so bloated and hard to read ... simplify ... readability"):
// one screen from public.admin_evidence_summary: what the saved page is, its course, whether it was accepted and is in use, what it
// supplied, and its copies. The technical details sit in a closed part at the bottom. Sections with nothing to show are not drawn.
function EvidenceDrawer({id,onClose,onOpen,onError,navigate}){
  const[data,setData]=useState(null)
  const[busy,setBusy]=useState(true)
  const[accessBusy,setAccessBusy]=useState('')
  useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose])
  useEffect(()=>{let live=true;setData(null);setBusy(true);api.evidenceSummary(id).then(x=>{if(live)setData(x||{})}).catch(e=>onError(e.message)).finally(()=>live&&setBusy(false));return()=>{live=false}},[id])
  const[viewer,setViewer]=useState(null)
  // v2.15.294 (Platform Admin, 19 Oct 2026 22:13: "tried opening view page and error Preview_not_allowed"): saved web pages come back
  // unpacked as text and open in a sandboxed frame here (no scripts, no forms); Download saves the unpacked file.
  async function access(mode){setAccessBusy(mode);try{const x=await api.evidenceAccess(id,mode);if(typeof x?.content==='string'){if(mode==='download'){const b=new Blob([x.content],{type:`${x.mime_type||'text/plain'};charset=utf-8`}),u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download=x.file_name||'page.html';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),1000)}else setViewer(x);return}if(!x?.url)throw new Error('The link to the saved file was not returned.');window.open(x.url,'_blank','noopener,noreferrer')}catch(e){onError(e.message)}finally{setAccessBusy('')}}
  const d=data||{},course=d.course||null,accepted=d.accepted||null,supplied=d.supplied||{},items=rowsOf(supplied),suppliedTotal=Number(supplied.total||0),copies=d.copies||null,file=d.file||{},job=d.job||null
  const pageUrl=safeUrl(d.page_url),earlier=Number(copies?.earlier||0),later=Number(copies?.later||0),reviews=Number(d.reviews_open||0),how=fetchedVia(d.fetched_via)
  const newest=copies?.newest_id&&onOpen?<button className="ev-sum-link" onClick={()=>onOpen(copies.newest_id)}>Open the newest copy →</button>:null
  const counts=[reviews>0&&`${fmt(reviews)} open review item${reviews===1?'':'s'}`,earlier>0&&`${fmt(earlier)} earlier cop${earlier===1?'y':'ies'}`,later>0&&`${fmt(later)} later cop${later===1?'y':'ies'}`].filter(Boolean)
  const tech=[['Content hash',file.content_hash,'mono'],['File size',file.size_bytes!=null?fmtBytes(file.size_bytes):null],['MIME type',file.mime_type],['Storage path',file.storage_path,'mono'],['Source',d.source?.label],['Job',job?[human(job.type),human(job.status),job.id].filter(Boolean).join(' · '):null],['Worker',d.worker],['Evidence id',d.id||id,'mono']].filter(([,v])=>v!=null&&v!=='')
  return <><button className="evidence-drawer-backdrop" aria-label="Close panel" onClick={onClose}/><aside className="evidence-drawer" aria-label="Evidence">
    <div className="evidence-drawer-head"><div><small>Evidence</small><h2>{evidenceKind(d.evidence_type)}</h2>{d.captured_at&&<span className="ev-sum-read">Read {dateOnly(d.captured_at)}</span>}</div><button onClick={onClose} aria-label="Close"><X size={18}/></button></div>
    {busy?<div className="evidence-drawer-loading"><span className="evidence-spinner"/>Loading…</div>:d.error?<div className="evidence-drawer-body"><p className="ev-sum-line">This saved page was not found.</p></div>:<div className="evidence-drawer-body ev-sum">
      <section className="ev-sum-card">
        <h3>{course?.title||d.source?.label||'Saved page'}</h3>
        {course&&<p className="ev-sum-meta">{[course.code,course.provider].filter(Boolean).join(' · ')}{course.id&&navigate&&<button className="ev-sum-link" onClick={()=>openCanonical({entity_type:'course',entity_id:course.id},navigate)}>Open course →</button>}</p>}
        {pageUrl&&<a className="ev-sum-url" href={pageUrl} target="_blank" rel="noreferrer"><ExternalLink size={13}/><span>{pageUrl}</span></a>}
        {d.captured_at&&<p className="ev-sum-meta">Read on {dateOnly(d.captured_at)}{how?`, ${how}`:''}</p>}
      </section>

      {!course?<div className="ev-sum-result" data-ev-result="unlinked"><span>Not linked to a course</span></div>
        :accepted?.basis?<div className="ev-sum-result" data-ev-result="accepted"><span>Accepted as this course's page ({basisLabel(accepted.basis)})</span>{accepted.in_use?<StatusChip value="active" label="In use now"/>:suppliedTotal>0?<><StatusChip value="active" label="Older copy · its values are in use"/>{newest}</>:<><StatusChip value="superseded" label="Replaced by a newer copy"/>{newest}</>}</div>
        :accepted&&!accepted.in_use&&copies?.newest_id?<div className="ev-sum-result" data-ev-result="replaced"><StatusChip value="superseded" label="Replaced by a newer copy"/>{newest}</div>:null}

      {suppliedTotal>0?<section className="ev-sum-supplied"><h4>What this page supplied</h4><ul>{items.map((x,i)=><li key={`${x.field}-${i}`}><span>{x.field}</span><strong>{x.value||'—'}</strong>{x.status&&x.status!=='active'&&<State value={x.status}/>}</li>)}</ul>{suppliedTotal>items.length&&<p className="ev-sum-more">and {fmt(suppliedTotal-items.length)} more</p>}</section>
        :<p className="ev-sum-line" data-ev-supplied="none">No live value comes from this copy.</p>}

      {counts.length>0&&<p className="ev-sum-line" data-ev-counts>{counts.join(' · ')}</p>}

      <div className="ev-sum-actions"><button className="m-secondary" disabled={!file.available||Boolean(accessBusy)} onClick={()=>access('preview')}><FileSearch size={14}/>{accessBusy==='preview'?'Opening…':'View page'}</button><button className="m-secondary" disabled={!file.available||Boolean(accessBusy)} onClick={()=>access('download')}><Download size={14}/>{accessBusy==='download'?'Opening…':'Download'}</button>{!file.available&&<small>The saved file is no longer held.</small>}</div>

      {!accepted?.in_use&&suppliedTotal>0&&later>0&&<p className="ev-sum-line" data-ev-values-here>The page was read again later; the values in use still come from this copy, so it is kept.</p>}

      {tech.length>0&&<details className="ev-sum-tech"><summary>Technical details</summary><dl>{tech.map(([k,v,c])=><div key={k}><dt>{k}</dt><dd className={c||''}>{String(v)}</dd></div>)}</dl></details>}
    </div>}
  </aside>{viewer&&<PageViewer page={viewer} pageUrl={pageUrl} onClose={()=>setViewer(null)}/>}</>
}

// The saved page as it was read. HTML is shown in a frame with every sandbox restriction on (no scripts, forms, pop-ups or same-origin
// access) and a content policy that blocks scripts and connections; pictures and styles load from the university's site.
const VIEW_POLICY="default-src 'none'; img-src https: data:; style-src https: 'unsafe-inline'; font-src https: data:"
// The policy and base go first (after any doctype, so the page keeps its own layout mode).
function viewDoc(content,pageUrl){const head=`<meta http-equiv="Content-Security-Policy" content="${VIEW_POLICY}">${pageUrl?`<base href="${pageUrl.replace(/"/g,'&quot;')}">`:''}`;const m=/^\s*<!doctype[^>]*>/i.exec(content);return m?m[0]+head+content.slice(m[0].length):head+content}
function PageViewer({page,pageUrl,onClose}){
  useEffect(()=>{const k=e=>{if(e.key==='Escape'){e.stopPropagation();onClose()}};addEventListener('keydown',k,true);return()=>removeEventListener('keydown',k,true)},[onClose])
  const html=page.kind==='html'
  const doc=html?viewDoc(page.content,pageUrl):''
  return <div className="ev-viewer" role="dialog" aria-label="Saved page"><div className="ev-viewer-head"><strong>Saved page{page.file_name?` · ${page.file_name}`:''}</strong>{page.truncated&&<small>Shown in part (the file is very large).</small>}<button onClick={onClose} aria-label="Close saved page"><X size={18}/></button></div>
    {html?<iframe className="ev-viewer-frame" title="Saved page" sandbox="" referrerPolicy="no-referrer" srcDoc={doc}/>:<pre className="ev-viewer-text">{page.content}</pre>}
  </div>
}

// v2.15.294 (Platform Admin, 19 Oct 2026 22:13: "evidence still duplicated"): each row says what it is. Copies of one course page are
// numbered, with the one in use marked; an older copy whose values are still in use says so; other pages say what kind of page they are.
const COPY_KIND={provider_facts:"Provider's facts page (not this course's page)",register_file:'Register or catalogue file',screenshot:'Page screenshot'}
function CopyRole({role}){if(!role)return null;if(role.kind==='course_page'){const n=Number(role.copies||0),of=n>1?` · copy ${fmt(role.copy)} of ${fmt(n)}`:'';const label=role.role==='in_use'?'Course page in use':role.role==='older_values_live'?'Older copy · its values are in use':'Older copy';return <span className="ev-copy-role" data-ev-role={role.role||'none'}>{label}{of}</span>}const label=COPY_KIND[role.kind];return label?<span className="ev-copy-role" data-ev-role={role.kind}>{label}</span>:null}

const EVIDENCE_KIND={source_snapshot:'Course page',layer2_raw_html:'Saved web page',layer2_raw_json:'Saved data file',website_screenshot:'Page screenshot',screenshot:'Page screenshot',regulatory_snapshot:'Register snapshot'}
const BASIS={exact_title:'exact title',cricos_code:'CRICOS code',cricos_code_on_page:'CRICOS code on the page',title_level:'title and level',field_award:'field and award',adapter_title:"title found by the university's reader",adapter_code:"course code found by the university's reader",manual:'chosen by a person'}
function evidenceKind(t){return t?EVIDENCE_KIND[String(t).toLowerCase()]||human(t):'Saved page'}
function basisLabel(b){return BASIS[String(b).toLowerCase()]||String(b).replace(/[_-]+/g,' ')}
function fetchedVia(v){const x=String(v||'').toLowerCase();if(!x)return'';if(x==='firecrawl')return'through Firecrawl';if(x==='direct')return'fetched directly';return`through ${human(x)}`}
function dateOnly(v){return fmtDate(v)}


function PagedEvidenceSelect({label,value,valueLabel='',country='',onChange}){const[open,setOpen]=useState(false),[q,setQ]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[busy,setBusy]=useState(false),[selectedLabel,setSelectedLabel]=useState(valueLabel);const ref=useRef(null),inputRef=useRef(null),debounced=useDebounce(q,220);useEffect(()=>{const close=e=>{if(ref.current&&!ref.current.contains(e.target))setOpen(false)};addEventListener('mousedown',close);return()=>removeEventListener('mousedown',close)},[]);useEffect(()=>{setOffset(0)},[debounced,country]);useEffect(()=>{if(valueLabel)setSelectedLabel(valueLabel);if(!value)setSelectedLabel('')},[value,valueLabel]);useEffect(()=>{if(!open)return;let live=true;setBusy(true);api.filterOptionPage({kind:'evidence_source',country,query:debounced,limit:10,offset}).then(x=>{if(!live)return;setData(x||{items:[],total:0,has_more:false});const hit=(x?.items||[]).find(y=>String(y.value)===String(value));if(hit)setSelectedLabel(hit.label)}).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setBusy(false));return()=>{live=false}},[open,country,debounced,offset,value]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const items=data.items||[],page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <div className="evidence-select" ref={ref}><button className={value?'has-value':''} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selectedLabel||'All'}</strong></span><ChevronDown size={13}/></button>{open&&<div className="evidence-select-pop"><label><Search size={13}/><input ref={inputRef} value={q} onChange={e=>setQ(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></label><button onClick={()=>{onChange('','All');setSelectedLabel('');setOpen(false);setQ('');setOffset(0)}} className={!value?'selected':''}>All</button>{items.map(x=><button key={String(x.value)} onClick={()=>{setSelectedLabel(x.label);onChange(x.value,x.label);setOpen(false);setQ('');setOffset(0)}} className={String(value)===String(x.value)?'selected':''}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!items.length&&!busy&&<small>No matching options</small>}{Number(data.total||0)>10&&<div className="evidence-pager"><button disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</div>}
function Select({label,value,onChange,options=[]}){const[open,setOpen]=useState(false),[q,setQ]=useState(''),[page,setPage]=useState(0);const inputRef=useRef(null);useEffect(()=>setPage(0),[q,options.length]);useEffect(()=>{if(open&&typeof window!=='undefined'&&window.matchMedia?.('(pointer:fine)').matches)setTimeout(()=>inputRef.current?.focus(),0)},[open]);const selected=options.find(x=>String(x.value)===String(value));const filtered=options.filter(x=>`${x.label} ${x.meta||''}`.toLowerCase().includes(q.toLowerCase())),pages=Math.max(1,Math.ceil(filtered.length/10)),safePage=Math.min(page,pages-1),shown=filtered.slice(safePage*10,safePage*10+10);return <div className="evidence-select"><button className={value?'has-value':''} onClick={()=>setOpen(x=>!x)}><span><small>{label}</small><strong>{selected?.label||'All'}</strong></span><ChevronDown size={13}/></button>{open&&<div className="evidence-select-pop"><label><Search size={13}/><input ref={inputRef} value={q} onChange={e=>setQ(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/></label><button onClick={()=>{onChange('','All');setOpen(false);setQ('');setPage(0)}} className={!value?'selected':''}>All</button>{shown.map(x=><button key={String(x.value)} onClick={()=>{onChange(x.value,x.label);setOpen(false);setQ('');setPage(0)}} className={String(value)===String(x.value)?'selected':''}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!shown.length&&<small>No matching options</small>}{filtered.length>10&&<div className="evidence-pager"><button disabled={safePage===0} onClick={()=>setPage(p=>Math.max(0,p-1))}>Previous</button><span>{safePage+1} / {pages}</span><button disabled={safePage>=pages-1} onClick={()=>setPage(p=>Math.min(pages-1,p+1))}>Next</button></div>}</div>}</div>}
function TextFilter({label,value,onChange,placeholder}){return <label className="evidence-text-filter"><small>{label}</small><input value={value||''} onChange={e=>onChange(e.target.value.trim())} placeholder={placeholder}/></label>}
function DateFilter({label,value,onChange}){return <label className="evidence-text-filter"><small>{label}</small><input type="date" value={value||''} onChange={e=>onChange(e.target.value)}/></label>}

function Badge({value}){return /\d/.test(String(value??''))?<LayerBadge layer={value}/>:<KitBadge>{human(value||'unknown')}</KitBadge>}
// UI audit Phase 1 (24 Oct 2026): raw state strings read as what they mean; anything unmapped is humanised as before
const STATE_WORDS={missing_extraction:'Not yet read',has_extraction:'Read',extracted:'Read',no_policy:'No reading rule',current_or_unversioned:'Current copy',current:'Current copy',superseded:'Older copy',stale:'Needs re-reading',fresh:'Current',unversioned:'Current copy',versioned:'Versioned copy',unknown:'Unknown'}
export const stateWords=v=>{const k=String(v||'unknown').toLowerCase().replace(/[\s-]+/g,'_');return STATE_WORDS[k]||human(k)}
function State({value}){const k=String(value||'unknown').toLowerCase();return <StatusChip value={k} label={stateWords(k)} title={k!==stateWords(k).toLowerCase()?human(k):undefined}/>}
// Job slugs read as what the job does ("provider_course_page_sweep" → "Course page sweep")
const JOB_WORDS={provider_course_page_sweep:'Course page sweep',course_page_sweep:'Course page sweep',coverage_admit:'Coverage admit',coverage_read:'Coverage read',coverage_discover:'Coverage discover'}
export const jobWords=v=>{const k=String(v||'').toLowerCase().replace(/[\s-]+/g,'_');return JOB_WORDS[k]||human(k.replace(/^provider_/,''))}

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
function fmt(v){const n=Number(v);return Number.isFinite(n)?fmtNumber(n):'—'}
function dateTime(v){if(!v)return'—';const d=new Date(v);return Number.isNaN(+d)?String(v):fmtDateTime(d)}
function relative(v){const d=new Date(v);if(Number.isNaN(+d))return'Unknown time';const s=Math.max(0,Math.round((Date.now()-d.getTime())/1000));if(s<60)return'Just now';if(s<3600)return`${Math.round(s/60)}m ago`;if(s<86400)return`${Math.round(s/3600)}h ago`;if(s<604800)return`${Math.round(s/86400)}d ago`;return dateTime(v)}
function formatOf(mime,evidenceType=''){const m=String(mime||'').toLowerCase(),t=String(evidenceType||'').toLowerCase();if(m==='application/json'||m.endsWith('+json'))return'JSON';if(m==='text/html'||m==='application/xhtml+xml')return'HTML';if(m.startsWith('image/'))return t.includes('screenshot')?'SCREENSHOT':'IMAGE';if(m==='application/pdf')return'PDF';if(m==='text/csv')return'CSV';if(m.includes('spreadsheetml')||m.includes('ms-excel'))return'XLSX';if(m==='application/zip'||m.includes('zip'))return'ZIP';if(m==='text/plain')return'TEXT';return m?m.split('/').pop().toUpperCase():'UNKNOWN'}
function fmtBytes(v){return formatBytes(v,'Unknown size')}
function flag(code){const c=String(code||'').toUpperCase();return c.length===2?String.fromCodePoint(...[...c].map(x=>127397+x.charCodeAt())):''}
function safeUrl(v){try{const u=new URL(String(v||''));return['http:','https:'].includes(u.protocol)?u.toString():null}catch{return null}}