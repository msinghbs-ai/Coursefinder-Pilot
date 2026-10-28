// CF-247 v2.15.363 AER operations workspace (Platform Admin mandate 29 Oct 2026 08:06; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md).
// Catalogue › Entry requirements: four views over the academic entry requirement data, in the catalogue's own patterns (W16):
//   Provider entry matrix · Course entry requirements · Sources, reads and holds · Resolution inspection.
// A summary of the current scope sits above every view. Lists are filtered, sorted and paged on the server (at most 100 rows a page);
// the table is the shared catalogue DataTable (fluid, resizable, sorting headers) with a Columns menu saved per browser. A row opens the
// right-hand drawer with its full quote, source, stored copy, reading run, Layer 4 item and the history of every change.
// Curator and above can switch the list to "Edit in list" (one cell at a time, Enter or leaving the cell saves, Esc cancels; a reason for
// the session is asked first and kept with every change), add a requirement from a stored official source, and withdraw, quarantine or
// restore a row with a reason. Proposed AI rows are never edited or activated here: they link to Layer 4 (W3). A Platform Admin can ask
// for one source to be read again through the existing governed mechanism. Every write goes through public.admin_aer; nothing here reads
// or writes a table directly.
import React,{useEffect,useMemo,useRef,useState}from'react'
import{Check,Columns3,ExternalLink,GraduationCap,Pencil,Plus,RefreshCw,Search,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,StatusChip,FilterChip,Pager,Loading,EmptyInline,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{DataTable,FilterSelect}from'./DataTable'
import{ReasonAction}from'./ProviderOnboarding'
import{hrefFor}from'./nav-map'
import{plainError}from'./lib/errors'
import'./aer-workspace.css'

export const aer=async(action,args={})=>{const{data,error}=await supabase.rpc('admin_aer',{p_action:action,p_args:args});if(error)throw error;return data}
const PAGE=50

// pills: the shared statusTone system, with plain words (never colour alone)
export const ROW_PILL={active:['success','Active'],proposed:['info','Waiting in Layer 4'],unverified:['danger','Quarantined'],inactive:['neutral','Withdrawn'],superseded:['neutral','Superseded']}
export const HOLD_PILL={read:['success','Read'],reading:['info','Reading'],held:['warning','Held'],fetch_failed:['danger','Fetch failed'],none:['neutral','Not read']}
export function RowPill({status,title}){const[t,l]=ROW_PILL[status]||['neutral',String(status||'—')];return <span data-aer-pill={status}><StatusChip tone={t} label={l} title={title}/></span>}
function HoldPill({state,title}){const[t,l]=HOLD_PILL[state]||['neutral',String(state||'—')];return <span data-aer-hold={state}><StatusChip tone={t} label={l} title={title}/></span>}
const SCALE_LABEL={percentage:'Percentage',points:'Points',aggregate:'Aggregate',gpa:'GPA',letter:'Letter grade',rank:'Rank',none:'No scale'}
const KIND_LABEL={provider_minimum:'Provider minimum',band_ladder:'Band table',course_minimum:'Course minimum',rank_band:'Rank band',prior_qualification:'Prior qualification',minimum_grade:'Minimum grade',subject_prerequisite:'Subject prerequisite',portfolio_interview:'Portfolio or interview',work_experience:'Work experience',other:'Other',override:'Course rule (override)',general_note:'General note'}
const READ_LABEL={done:'Read',failed:'Held or failed',queued:'Waiting to read',leased:'Reading',manual:'Added by hand'}
const opt=(value,label,meta)=>({value,label,meta})
const short=(s,n=80)=>{s=String(s||'');return s.length>n?s.slice(0,n-1)+'…':s}
const minText=r=>r.min_grade||(r.min_value!=null?String(Number(r.min_value)):'')
const l4Href=r=>hrefFor('layer4','inbox',{provider:r.provider_id})
const evHref=id=>hrefFor('evidence','',{evidence_id:id})
const Src=({url})=>url?<a className="cf-link" href={url} target="_blank" rel="noreferrer" onClick={e=>e.stopPropagation()}>source <ExternalLink size={11}/></a>:'—'

// columns shown/hidden per view, remembered in this browser only (a convenience; the list itself is the server's)
function useColumns(view,all){
  const key=`cf-aer-cols:${view}`
  const[hidden,setHidden]=useState(()=>{try{return JSON.parse(localStorage.getItem(key)||'[]')||[]}catch{return[]}})
  const save=h=>{setHidden(h);try{localStorage.setItem(key,JSON.stringify(h))}catch{}}
  return[all.filter((c,i)=>i===0||!hidden.includes(c.key)),hidden,save]
}
function ColumnsMenu({all,hidden,onChange}){
  return <details className="aer-columns" data-aer-columns><summary><Columns3 size={14}/>Columns</summary>
    <div className="aer-columns-menu" role="group" aria-label="Show or hide columns">
      {all.map((c,i)=><label key={c.key}><input type="checkbox" checked={!hidden.includes(c.key)} disabled={i===0} onChange={e=>onChange(e.target.checked?hidden.filter(k=>k!==c.key):[...hidden,c.key])} data-aer-col={c.key}/>{c.label}</label>)}
      <button type="button" className="m-secondary compact" onClick={()=>onChange([])}>Show all columns</button>
    </div></details>
}

// the summary of the current scope (W: "operational totals"), one aggregate read
export function AerSummary({providerId,onError,refreshKey}){
  const[s,setS]=useState(null)
  useEffect(()=>{let on=true;aer('summary',providerId?{provider_id:providerId}:{}).then(x=>on&&setS(x)).catch(e=>on&&onError?.(plainError(e)));return()=>{on=false}},[providerId,refreshKey])
  if(!s)return <div className="aer-summary" data-aer-summary="loading"><Loading compact label="Counting…"/></div>
  const m=s.matrix||{},c=s.course||{},src=s.sources||{}
  const tile=(key,tone,label,value,detail)=><div className={`aer-tile tone-${tone}`} data-aer-tile={key}><small>{label}</small><strong>{fmtNumber(Number(value||0))}</strong>{detail&&<span>{detail}</span>}</div>
  return <div className="aer-summary" data-aer-summary>
    {tile('active','success','Active',m.active,'used by the website')}
    {tile('proposed','info','Waiting in Layer 4',m.proposed,'read by AI, not yet approved')}
    {tile('quarantined','danger','Quarantined',m.unverified,'evidence in doubt')}
    {tile('withdrawn','neutral','Withdrawn or superseded',Number(m.inactive||0)+Number(m.superseded||0))}
    {tile('held','warning','Sources held',Number(src.held||0)+Number(src.fetch_failed||0),`${fmtNumber(Number(src.total||0))} sources · ${fmtNumber(Number(src.reading||0))} reading`)}
    {tile('courses','info','Courses with requirements',s.courses_with_active,`${fmtNumber(Number(c.active||0))} active rows · ${fmtNumber(Number(s.courses_waiting||0))} courses waiting`)}
  </div>
}

// ----------------------------------------------------------------------------------------------- shared list frame
function useOptions(onError){
  const[o,setO]=useState(null)
  useEffect(()=>{let on=true;aer('options').then(x=>on&&setO(x)).catch(e=>on&&onError?.(plainError(e)));return()=>{on=false}},[])
  return o||{}
}
function useList(action,args,onError,refreshKey){
  const[d,setD]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const key=JSON.stringify(args)
  useEffect(()=>{let on=true;setBusy(true);setErr('');aer(action,args).then(x=>on&&setD(x)).catch(e=>{if(on){setErr(plainError(e));setD({rows:[],total:0})}}).finally(()=>on&&setBusy(false));return()=>{on=false}},[action,key,refreshKey])
  return[d,busy,err,setD]
}
function TextFilter({label,value,onChange,placeholder}){
  const[v,setV]=useState(value||'')
  useEffect(()=>setV(value||''),[value])
  useEffect(()=>{const t=setTimeout(()=>{if((v||'')!==(value||''))onChange(v)},300);return()=>clearTimeout(t)},[v])
  return <label className="m-searchbox aer-text-filter"><Search size={15}/><input aria-label={label} value={v} placeholder={placeholder} onChange={e=>setV(e.target.value)}/>{v&&<button type="button" aria-label={`Clear ${label}`} onClick={()=>{setV('');onChange('')}}><X size={13}/></button>}</label>
}
function Chips({filters,labels,names,set,clear}){
  const active=Object.entries(filters).filter(([k,v])=>v!==''&&v!=null&&!['sort','direction'].includes(k))
  if(!active.length)return null
  return <div className="m-chip-row" data-aer-chips>{active.map(([k,v])=><FilterChip key={k} label={`${names[k]||k}: ${labels[k]||v}`} onRemove={()=>set(k,'','')}/>)}<button type="button" className="m-secondary compact" onClick={clear} data-aer-clear>Clear filters</button></div>
}
function useFilters(view,defaults,overrides={}){
  const key=`cf-aer-filters:${view}`
  // a shortcut from a provider or course drawer (?provider=, ?course=) wins over the filters remembered in this browser
  const given=Object.fromEntries(Object.entries(overrides).filter(([,v])=>v))
  const[f,setF]=useState(()=>{let kept={};try{kept=JSON.parse(localStorage.getItem(key)||'{}')||{}}catch{}return{...defaults,...kept,...given}})
  const[labels,setLabels]=useState({}),[offset,setOffset]=useState(0)
  useEffect(()=>{try{localStorage.setItem(key,JSON.stringify(f))}catch{}},[JSON.stringify(f)])
  const set=(k,v,l)=>{setOffset(0);setF(x=>({...x,[k]:v}));setLabels(x=>({...x,[k]:l||''}))}
  const clear=()=>{setOffset(0);setF({...Object.fromEntries(Object.keys(defaults).map(k=>[k,''])),sort:defaults.sort||'',direction:defaults.direction||'asc'});setLabels({})}
  const sortBy=k=>{if(!k)return;setOffset(0);setF(x=>x.sort===k?{...x,direction:x.direction==='asc'?'desc':'asc'}:{...x,sort:k,direction:'asc'})}
  return{f,set,clear,labels,offset,setOffset,sortBy}
}

// ----------------------------------------------------------------------------------------------- Provider entry matrix
const MATRIX_NAMES={provider_id:'Provider',country:'Country',level:'Study level',status:'Status',matrix_kind:'Kind',band:'Band',q:'Search',edition:'Edition',intake_year:'Intake year',read_state:'Read'}
const MATRIX_FIELDS=[
  {key:'qualification',label:'Qualification',width:260},
  {key:'level_label',label:'Level (as published)',width:160},
  {key:'level_code',label:'Mapped level',width:150,kind:'level'},
  {key:'band',label:'Band',width:110},
  {key:'min_grade',label:'Minimum',width:140},
  {key:'min_value',label:'Value',width:90,kind:'number'},
  {key:'scale',label:'Scale',width:130,kind:'scale'},
  {key:'edition',label:'Edition',width:110},
  {key:'intake_year',label:'Intake year',width:100,kind:'number'},
  {key:'as_at',label:'As at',width:120,kind:'date'},
]
export function MatrixView({rank,onError,navigate,routeParams}){
  const o=useOptions(onError)
  const{f,set,clear,labels,offset,setOffset,sortBy}=useFilters('matrix',{provider_id:'',country:'',level:'',status:'active',matrix_kind:'',band:'',q:'',edition:'',intake_year:'',read_state:'',sort:'provider',direction:'asc'},{provider_id:routeParams?.get?.('provider')||''})
  const[refresh,setRefresh]=useState(0),[open,setOpen]=useState(null),[edit,setEdit]=useState(false),[adding,setAdding]=useState(false)
  const args=useMemo(()=>({...f,offset,page_size:PAGE}),[JSON.stringify(f),offset])
  const[d,busy,err,setD]=useList('matrix_list',args,onError,refresh)
  const rows=d?.rows||[]
  const all=[
    {key:'provider_name',label:'Provider',width:220,sortKey:'provider',render:r=><span className="m-cell-title"><strong>{r.provider_name}</strong>{r.course_code&&<small>{r.course_code}</small>}</span>},
    {key:'country',label:'Country',width:120,sortKey:'country',render:r=><span title={r.country_name}>{r.country} <small>{short(r.country_name,18)}</small></span>},
    {key:'level_label',label:'Level',width:160,sortKey:'level',render:r=><span>{r.level_label||'—'}{r.level_code&&<small> · {r.level_code}</small>}</span>},
    {key:'qualification',label:'Qualification',width:280,sortKey:'qualification',render:r=><span className="aer-wrap">{r.qualification}</span>},
    {key:'band',label:'Band',width:100,sortKey:'band',render:r=>r.band||'—'},
    {key:'min',label:'Minimum',width:150,sortKey:'min',render:r=>minText(r)?<span className="aer-wrap">{minText(r)}</span>:<em>case by case</em>},
    {key:'scale',label:'Scale',width:110,render:r=>SCALE_LABEL[r.scale]||r.scale||'—'},
    {key:'matrix_kind',label:'Kind',width:130,render:r=>KIND_LABEL[r.matrix_kind]||r.matrix_kind},
    {key:'edition',label:'Edition',width:110,sortKey:'edition',render:r=>[r.edition,r.intake_year].filter(Boolean).join(' · ')||'—'},
    {key:'as_at',label:'As at',width:110,sortKey:'as_at',render:r=>fmtDate(r.as_at)},
    {key:'status',label:'Status',width:170,sortKey:'status',render:r=><span className="aer-status"><RowPill status={r.status} title={r.status_reason||undefined}/>{r.manual&&<small>by hand</small>}{r.status==='proposed'&&<a className="cf-link" href={l4Href(r)} onClick={e=>e.stopPropagation()}>Layer 4</a>}</span>},
    {key:'quote',label:'Quote',width:260,render:r=><small className="aer-wrap">“{short(r.quote,120)}”</small>},
    {key:'source',label:'Source',width:90,render:r=><Src url={r.source_url}/>},
    {key:'updated',label:'Updated',width:130,sortKey:'updated',render:r=>fmtDate(r.updated_at)},
  ]
  const[cols,hidden,setHidden]=useColumns('matrix',all)
  const can=Number(rank)>=3
  const onSaved=row=>setD(x=>x?{...x,rows:x.rows.map(r=>r.id===row.id?row:r)}:x)
  return <div className="m-page-stack aer-page" data-aer-view="matrix">
    <AerSummary providerId={f.provider_id} onError={onError} refreshKey={refresh}/>
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>Provider entry matrix</h2><p>The requirement each provider publishes for a student's country of prior education. Only active rows reach the website.</p></div>
        <div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(Number(d?.total||0))}</strong><span>matching</span></>}</div></div>
      <div className="m-search-row">
        <TextFilter label="Search qualification, quote or level" value={f.q} onChange={v=>set('q',v,v)} placeholder="Search qualification, quote or level"/>
        <ColumnsMenu all={all} hidden={hidden} onChange={setHidden}/>
        {can&&<button type="button" className={`m-secondary compact${edit?' active':''}`} aria-pressed={edit} onClick={()=>setEdit(x=>!x)} data-aer-edit-toggle><Pencil size={14}/>{edit?'Done editing':'Edit in list'}</button>}
        {can&&<button type="button" className="m-secondary compact" onClick={()=>setAdding(true)} data-aer-add><Plus size={14}/>Add requirement</button>}
      </div>
      <div className="m-filter-bar" data-aer-filters="matrix">
        <FilterSelect label="Provider" value={f.provider_id} onChange={(v,l)=>set('provider_id',v,l)} options={(o.providers||[]).map(p=>opt(p.id,p.name))}/>
        <FilterSelect label="Country" value={f.country} onChange={(v,l)=>set('country',v,l)} options={(o.countries||[]).map(c=>opt(c.code,c.name,c.code))}/>
        <FilterSelect label="Study level" value={f.level} onChange={(v,l)=>set('level',v,l)} options={[...(o.levels||[]).map(l=>opt(l.code,l.name,l.code)),...(o.level_labels||[]).map(l=>opt(l,l,'as published'))]}/>
        <FilterSelect label="Status" value={f.status} emptyLabel="Any status" onChange={(v,l)=>set('status',v,l)} options={(o.statuses||[]).map(s=>opt(s,ROW_PILL[s]?.[1]||s))}/>
        <FilterSelect label="Kind" value={f.matrix_kind} onChange={(v,l)=>set('matrix_kind',v,l)} options={(o.matrix_kinds||[]).map(k=>opt(k,KIND_LABEL[k]||k))}/>
        <FilterSelect label="Band" value={f.band} onChange={(v,l)=>set('band',v,l)} options={(o.bands||[]).map(b=>opt(b,b))}/>
        <FilterSelect label="Edition" value={f.edition} onChange={(v,l)=>set('edition',v,l)} options={(o.editions||[]).map(b=>opt(b,b))}/>
        <FilterSelect label="Intake year" value={f.intake_year} onChange={(v,l)=>set('intake_year',v,l)} options={(o.intake_years||[]).map(y=>opt(String(y),String(y)))}/>
        <FilterSelect label="Read" value={f.read_state} onChange={(v,l)=>set('read_state',v,l)} options={Object.entries(READ_LABEL).map(([k,l])=>opt(k,l))}/>
      </div>
      <Chips filters={f} labels={{...labels,status:labels.status||ROW_PILL[f.status]?.[1]}} names={MATRIX_NAMES} set={set} clear={clear}/>
      {err&&<p className="fr-error" role="alert" data-aer-error>{err}</p>}
      {edit&&can?<EditList kind="matrix" rows={rows} busy={busy} fields={MATRIX_FIELDS} levels={o.levels||[]} scales={o.scales||[]} label={r=>`${r.provider_name} · ${r.country} · ${short(r.qualification,40)}`} onSaved={onSaved} onOpen={r=>setOpen(r)}/>
        :<DataTable rows={rows} columns={cols} loading={busy} sort={f.sort} direction={f.direction} onSort={sortBy} onRow={r=>setOpen(r)} selected={open?.id} tableId="aer-matrix"/>}
      <Pager offset={offset} limit={PAGE} total={Number(d?.total||0)} onOffset={setOffset}/>
    </section>
    {open&&<RowDrawer kind="matrix" id={open.id} rank={rank} onError={onError} onClose={()=>setOpen(null)} onChanged={row=>{onSaved(row);setRefresh(n=>n+1)}}/>}
    {adding&&<AddRequirement kind="matrix" options={o} defaults={{provider_id:f.provider_id,country:f.country}} onError={onError} onClose={()=>setAdding(false)} onAdded={row=>{setAdding(false);setRefresh(n=>n+1);setOpen(row)}}/>}
  </div>
}

// ----------------------------------------------------------------------------------------------- Course entry requirements
const COURSE_NAMES={provider_id:'Provider',course:'Course',requirement_kind:'Kind',audience:'For',status:'Status',band:'Band',as_at_from:'As at from',as_at_to:'As at to',q:'Search'}
const COURSE_FIELDS=[
  {key:'description',label:'Requirement',width:300},
  {key:'min_grade',label:'Minimum',width:140},
  {key:'min_value',label:'Value',width:90,kind:'number'},
  {key:'scale',label:'Scale',width:130,kind:'scale'},
  {key:'min_entry_score',label:'Course score',width:110,kind:'number'},
  {key:'min_entry_score_basis',label:'Printed basis',width:170},
  {key:'band',label:'Band',width:110},
  {key:'as_at',label:'As at',width:120,kind:'date'},
]
export function CourseView({rank,onError,routeParams}){
  const o=useOptions(onError)
  const{f,set,clear,labels,offset,setOffset,sortBy}=useFilters('course',{provider_id:'',course:'',requirement_kind:'',audience:'',status:'',band:'',as_at_from:'',as_at_to:'',q:'',sort:'provider',direction:'asc'},{course:routeParams?.get?.('course')||''})
  const[refresh,setRefresh]=useState(0),[open,setOpen]=useState(null),[edit,setEdit]=useState(false),[adding,setAdding]=useState(false)
  const args=useMemo(()=>({...f,offset,page_size:PAGE}),[JSON.stringify(f),offset])
  const[d,busy,err,setD]=useList('course_list',args,onError,refresh)
  const rows=d?.rows||[]
  const all=[
    {key:'course_title',label:'Course',width:260,sortKey:'course',render:r=><span className="m-cell-title"><strong>{r.course_title}</strong><small>{[r.provider_name,r.course_code].filter(Boolean).join(' · ')}</small></span>},
    {key:'requirement_kind',label:'Kind',width:160,sortKey:'kind',render:r=>KIND_LABEL[r.requirement_kind]||r.requirement_kind},
    {key:'description',label:'Requirement',width:300,render:r=><span className="aer-wrap">{short(r.description,160)}</span>},
    {key:'score',label:'Score and basis',width:170,sortKey:'score',render:r=>r.min_entry_score!=null?<span>{Number(r.min_entry_score)} <small>({r.min_entry_score_basis})</small></span>:(minText(r)||'—')},
    {key:'band',label:'Band',width:100,render:r=>r.band||'—'},
    {key:'audience',label:'For',width:120,render:r=>r.audience},
    {key:'country',label:'Country',width:100,render:r=>r.country||'Any'},
    {key:'as_at',label:'As at',width:110,sortKey:'as_at',render:r=>fmtDate(r.as_at)},
    {key:'status',label:'Status',width:170,sortKey:'status',render:r=><span className="aer-status"><RowPill status={r.status} title={r.status_reason||undefined}/>{r.manual&&<small>by hand</small>}{r.status==='proposed'&&<a className="cf-link" href={l4Href(r)} onClick={e=>e.stopPropagation()}>Layer 4</a>}</span>},
    {key:'quote',label:'Quote',width:260,render:r=><small className="aer-wrap">“{short(r.quote,120)}”</small>},
    {key:'source',label:'Source',width:90,render:r=><Src url={r.source_url}/>},
  ]
  const[cols,hidden,setHidden]=useColumns('course',all)
  const can=Number(rank)>=3
  const onSaved=row=>setD(x=>x?{...x,rows:x.rows.map(r=>r.id===row.id?row:r)}:x)
  return <div className="m-page-stack aer-page" data-aer-view="course">
    <AerSummary providerId={f.provider_id} onError={onError} refreshKey={refresh}/>
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>Course entry requirements</h2><p>What each course's own page asks for: a course rule, a minimum, a score with its printed basis, a band, prerequisites.</p></div>
        <div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(Number(d?.total||0))}</strong><span>matching</span></>}</div></div>
      <div className="m-search-row">
        <TextFilter label="Search requirement or quote" value={f.q} onChange={v=>set('q',v,v)} placeholder="Search requirement or quote"/>
        <TextFilter label="Course title or code" value={f.course} onChange={v=>set('course',v,v)} placeholder="Course title or code"/>
        <ColumnsMenu all={all} hidden={hidden} onChange={setHidden}/>
        {can&&<button type="button" className={`m-secondary compact${edit?' active':''}`} aria-pressed={edit} onClick={()=>setEdit(x=>!x)} data-aer-edit-toggle><Pencil size={14}/>{edit?'Done editing':'Edit in list'}</button>}
        {can&&<button type="button" className="m-secondary compact" onClick={()=>setAdding(true)} data-aer-add><Plus size={14}/>Add requirement</button>}
      </div>
      <div className="m-filter-bar" data-aer-filters="course">
        <FilterSelect label="Provider" value={f.provider_id} onChange={(v,l)=>set('provider_id',v,l)} options={(o.providers||[]).map(p=>opt(p.id,p.name))}/>
        <FilterSelect label="Kind" value={f.requirement_kind} onChange={(v,l)=>set('requirement_kind',v,l)} options={(o.requirement_kinds||[]).map(k=>opt(k,KIND_LABEL[k]||k))}/>
        <FilterSelect label="For" value={f.audience} onChange={(v,l)=>set('audience',v,l)} options={(o.audiences||[]).map(k=>opt(k,k))}/>
        <FilterSelect label="Status" value={f.status} emptyLabel="Any status" onChange={(v,l)=>set('status',v,l)} options={(o.statuses||[]).map(s=>opt(s,ROW_PILL[s]?.[1]||s))}/>
        <FilterSelect label="Band" value={f.band} onChange={(v,l)=>set('band',v,l)} options={(o.bands||[]).map(b=>opt(b,b))}/>
        <label className="aer-date-filter"><small>As at from</small><input type="date" value={f.as_at_from} onChange={e=>set('as_at_from',e.target.value,fmtDate(e.target.value))} aria-label="As at from"/></label>
        <label className="aer-date-filter"><small>As at to</small><input type="date" value={f.as_at_to} onChange={e=>set('as_at_to',e.target.value,fmtDate(e.target.value))} aria-label="As at to"/></label>
      </div>
      <Chips filters={f} labels={labels} names={COURSE_NAMES} set={set} clear={clear}/>
      {err&&<p className="fr-error" role="alert" data-aer-error>{err}</p>}
      {edit&&can?<EditList kind="course" rows={rows} busy={busy} fields={COURSE_FIELDS} scales={o.scales||[]} label={r=>`${r.course_title} · ${KIND_LABEL[r.requirement_kind]||r.requirement_kind}`} onSaved={onSaved} onOpen={r=>setOpen(r)}/>
        :<DataTable rows={rows} columns={cols} loading={busy} sort={f.sort} direction={f.direction} onSort={sortBy} onRow={r=>setOpen(r)} selected={open?.id} tableId="aer-course"/>}
      <Pager offset={offset} limit={PAGE} total={Number(d?.total||0)} onOffset={setOffset}/>
    </section>
    {open&&<RowDrawer kind="course" id={open.id} rank={rank} onError={onError} onClose={()=>setOpen(null)} onChanged={row=>{onSaved(row);setRefresh(n=>n+1)}}/>}
    {adding&&<AddRequirement kind="course" options={o} defaults={{provider_id:f.provider_id}} onError={onError} onClose={()=>setAdding(false)} onAdded={row=>{setAdding(false);setRefresh(n=>n+1);setOpen(row)}}/>}
  </div>
}

// ----------------------------------------------------------------------------------------------- Edit in list (the ListEdit pattern)
// One cell at a time: click (or Tab and Enter) to edit, Enter or leaving the cell saves, Esc cancels; one save at a time per cell; a tick
// on success; the error under the row. A reason for this editing session is asked once and sent with every save (kept in the history).
// Only active or quarantined rows are editable; a proposed row links to Layer 4 instead.
function EditList({kind,rows,busy,fields,levels=[],scales=[],label,onSaved,onOpen}){
  const[reason,setReason]=useState(''),[vals,setVals]=useState({}),[saving,setSaving]=useState(''),[saved,setSaved]=useState(''),[rowErr,setRowErr]=useState({})
  useEffect(()=>{setVals(Object.fromEntries(rows.map(r=>[r.id,r])))},[rows.map(r=>r.id+r.updated_at).join(',')])
  if(busy&&!rows.length)return <Loading label="Loading editable rows…"/>
  if(!rows.length)return <EmptyInline text="No records match the current filters."/>
  const ok=reason.trim().length>=5
  const save=async(id,field,value)=>{
    const cur=vals[id]||{},k=`${id}:${field.key}`
    const before=cur[field.key]==null?'':String(field.kind==='number'&&cur[field.key]!==''?Number(cur[field.key]):cur[field.key])
    if(String(value??'')===before)return true
    if(!ok){setRowErr(x=>({...x,[id]:'Give a reason for these changes first (kept in the history).'}));return false}
    setSaving(k);setRowErr(x=>({...x,[id]:''}))
    try{const r=await aer('update',{kind,id,expected_updated_at:cur.updated_at,reason:reason.trim(),changes:{[field.key]:value}})
      setVals(v=>({...v,[id]:r.row}));onSaved?.(r.row);setSaved(k);setTimeout(()=>setSaved(s=>s===k?'':s),2000);return true}
    catch(e){setRowErr(x=>({...x,[id]:plainError(e)}));return false}finally{setSaving('')}
  }
  return <div className="m-table-wrap le-wrap" data-aer-edit={kind}>
    <div className="aer-edit-reason"><label>Reason for these changes <input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="For example: corrected from the provider's 2027 table" aria-label="Reason for these changes" data-aer-reason/></label>
      {!ok&&<small>At least 5 characters. Each change is kept with this reason, who made it and when.</small>}</div>
    <table className="m-table le-table"><thead><tr><th style={{minWidth:240}}>Row</th><th style={{minWidth:130}}>Status</th>{fields.map(f=><th key={f.key} style={{minWidth:f.width}}>{f.label}</th>)}</tr></thead>
      <tbody>{rows.map(r0=>{const r=vals[r0.id]||r0,editable=['active','unverified'].includes(r.status)
        return <React.Fragment key={r.id}><tr data-edit-row={r.id}>
          <td><button type="button" className="aer-row-link" onClick={()=>onOpen(r)}><span className="m-cell-title"><strong>{short(label(r),60)}</strong><small>“{short(r.quote,70)}”</small></span></button></td>
          <td><RowPill status={r.status}/>{r.status==='proposed'&&<a className="cf-link" href={l4Href(r)}> Layer 4</a>}</td>
          {fields.map(f=>{const k=`${r.id}:${f.key}`
            return <td key={f.key} className="le-cell"><Cell field={f} levels={levels} scales={scales} value={r[f.key]==null?'':String(f.kind==='number'?Number(r[f.key]):r[f.key])} can={editable} busy={saving===k} ok={saved===k} label={`${f.label} for ${short(label(r),40)}`} onSave={x=>save(r.id,f,x)}/></td>})}
        </tr>{rowErr[r.id]&&<tr className="le-err-row"><td colSpan={fields.length+2}><p className="fr-error" role="alert" data-aer-row-error>{rowErr[r.id]}</p></td></tr>}</React.Fragment>})}</tbody></table>
    <p className="l3v-note">Quotes, sources and stored copies are never edited. Waiting rows are decided in Layer 4.</p></div>
}
function Cell({field,value,can,busy,ok,label,onSave,levels,scales}){
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(value),ref=useRef(null),saving=useRef(false)
  useEffect(()=>{if(!edit)setDraft(value)},[value,edit])
  useEffect(()=>{if(edit)ref.current?.focus()},[edit])
  const shown=field.kind==='scale'?(SCALE_LABEL[value]||value):field.kind==='date'?(value?fmtDate(value):''):value
  const commit=async()=>{if(saving.current)return;saving.current=true;try{if(await onSave(String(draft??'').trim()))setEdit(false)}finally{saving.current=false}}
  const key=e=>{if(e.key==='Escape'){setDraft(value);setEdit(false)}if(e.key==='Enter'){e.preventDefault();commit()}}
  if(!can)return <span className="le-view">{shown||'—'}</span>
  if(!edit)return <button type="button" className={`le-view le-btn${ok?' le-ok':''}`} aria-label={`Edit ${label}`} onClick={()=>setEdit(true)} data-aer-cell={field.key}>
    <span className={shown?'':'le-empty'}>{shown||'Add'}</span>{ok&&<Check size={12} className="le-tick"/>}</button>
  if(field.kind==='scale')return <select ref={ref} className="fv-input" aria-label={label} value={draft||'none'} onChange={e=>setDraft(e.target.value)} onKeyDown={key} onBlur={commit} disabled={busy}>{(scales.length?scales:['none']).map(s=><option key={s} value={s}>{SCALE_LABEL[s]||s}</option>)}</select>
  if(field.kind==='level')return <select ref={ref} className="fv-input" aria-label={label} value={draft||''} onChange={e=>setDraft(e.target.value)} onKeyDown={key} onBlur={commit} disabled={busy}><option value="">Not mapped</option>{levels.map(l=><option key={l.code} value={l.code}>{l.name} ({l.code})</option>)}</select>
  return <input ref={ref} className="fv-input le-input" type={field.kind==='date'?'date':'text'} inputMode={field.kind==='number'?'decimal':undefined} aria-label={label} value={draft} onChange={e=>setDraft(e.target.value)} onKeyDown={key} onBlur={commit} disabled={busy}/>
}

// ----------------------------------------------------------------------------------------------- the row drawer
export function RowDrawer({kind,id,rank,onError,onClose,onChanged}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[msg,setMsg]=useState('')
  const load=()=>aer('row',{kind,id}).then(setD).catch(e=>setErr(plainError(e)))
  useEffect(()=>{setD(null);load()},[kind,id])
  useEffect(()=>{const k=e=>e.key==='Escape'&&onClose();addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose])
  const life=async(action,reason)=>{try{const r=await aer('lifecycle',{kind,id,lifecycle:action,reason,expected_updated_at:d.updated_at});setMsg(action==='withdraw'?'Withdrawn. It no longer reaches the website.':action==='quarantine'?'Quarantined. It no longer reaches the website.':'Restored. It reaches the website again.');onChanged?.(r.row);await load()}catch(e){setErr(plainError(e));throw e}}
  const saveConditions=async(conditions,reason)=>{try{const r=await aer('update',{kind,id,reason,expected_updated_at:d.updated_at,changes:{conditions}});setMsg('Conditions saved.');onChanged?.(r.row);await load()}catch(e){setErr(plainError(e));throw e}}
  const title=d?(kind==='matrix'?`${d.provider_name} · ${d.country}`:d.course_title):'Loading…'
  return <><button className="m-drawer-backdrop" onClick={onClose} aria-label="Close"/><aside className="m-drawer aer-drawer" aria-label="Entry requirement detail" data-aer-drawer={kind}>
    <div className="m-drawer-head"><div><small>{kind==='matrix'?'Provider entry matrix row':'Course entry requirement'}</small><h2>{title}</h2></div><button onClick={onClose} aria-label="Close detail"><X size={18}/></button></div>
    <div className="m-drawer-body aer-drawer-body">
      {err&&<p className="fr-error" role="alert">{err}</p>}{msg&&<p className="aer-msg" role="status">{msg}</p>}
      {!d?<Loading label="Loading the row…"/>:<>
        <div className="aer-drawer-pills"><RowPill status={d.status}/>{d.manual&&<StatusChip tone="violet" label="Added by hand"/>}{d.version&&<StatusChip tone="neutral" label={`Version ${d.version}`}/>}</div>
        {d.status_reason&&<p className="sd-desc"><small>{d.status_reason}</small></p>}
        <h3>Requirement</h3>
        <dl className="aer-dl">
          {kind==='matrix'?<>
            <dt>Provider</dt><dd>{d.provider_name}</dd><dt>Country of prior education</dt><dd>{d.country_name} ({d.country})</dd>
            <dt>Level</dt><dd>{d.level_label||'—'}{d.level_name&&<small> · mapped to {d.level_name} ({d.level_code})</small>}</dd>
            {d.course_code&&<><dt>Course</dt><dd>{d.course_title} · {d.course_code}</dd></>}
            <dt>Qualification</dt><dd>{d.qualification}</dd><dt>Kind</dt><dd>{KIND_LABEL[d.matrix_kind]||d.matrix_kind}</dd>
            <dt>Band</dt><dd>{d.band||'—'}</dd><dt>Minimum</dt><dd>{minText(d)||<em>case by case</em>}{d.min_value!=null&&d.min_grade&&<small> · value {Number(d.min_value)}</small>}</dd>
            <dt>Scale</dt><dd>{SCALE_LABEL[d.scale]||d.scale}</dd><dt>For</dt><dd>{d.audience}</dd>
            <dt>Edition · intake year</dt><dd>{[d.edition,d.intake_year].filter(Boolean).join(' · ')||'—'}</dd>
          </>:<>
            <dt>Course</dt><dd>{d.course_title}{d.course_code&&<small> · {d.course_code}</small>}<br/><small>{d.provider_name}</small></dd>
            <dt>Kind</dt><dd>{KIND_LABEL[d.requirement_kind]||d.requirement_kind}</dd><dt>Requirement</dt><dd>{d.description}</dd>
            <dt>Minimum</dt><dd>{minText(d)||'—'}{d.scale&&d.scale!=='none'&&<small> · {SCALE_LABEL[d.scale]}</small>}</dd>
            <dt>Course score</dt><dd>{d.min_entry_score!=null?`${Number(d.min_entry_score)} (${d.min_entry_score_basis})`:'—'}</dd>
            <dt>Band</dt><dd>{d.band||'—'}</dd><dt>For</dt><dd>{d.audience}{d.country?` · ${d.country_name}`:''}</dd>
          </>}
          <dt>As at</dt><dd>{fmtDate(d.as_at)}{d.valid_to&&<small> · until {fmtDate(d.valid_to)}</small>}</dd>
        </dl>
        {kind==='matrix'&&<ConditionsBlock value={d.conditions} can={d.can_edit} onSave={saveConditions}/>}
        <h3>Evidence</h3>
        <blockquote className="aer-quote" data-aer-quote>“{d.quote}”</blockquote>
        <dl className="aer-dl"><dt>Source</dt><dd><Src url={d.source_url}/> <small className="aer-wrap">{d.source_url}</small></dd>
          <dt>Stored copy</dt><dd>{d.evidence?<><a className="cf-link" href={evHref(d.evidence.id)}>Open the stored copy</a><small> · {fmtDateTime(d.evidence.captured_at)} · {d.evidence.mime||''}{d.evidence.content_hash?` · ${d.evidence.content_hash}`:''}</small></>:'—'}</dd></dl>
        <h3>Reading and review</h3>
        <dl className="aer-dl">
          <dt>Read by</dt><dd>{d.manual?'Added by hand':d.run?<>{d.run.model||'AI'}{d.run.worker&&<small> · {d.run.worker}</small>}{d.run.basis&&<small> · {d.run.basis}</small>}{d.run.cost_usd!=null&&<small> · US${Number(d.run.cost_usd).toFixed(4)}</small>}</>:(d.provenance?.model||'—')}</dd>
          <dt>Layer 4</dt><dd>{d.review_item_id?<><StatusChip value={d.review_status} label={d.review_status||'—'}/> <a className="cf-link" href={l4Href(d)} data-aer-l4>Open in Layer 4</a></>:'—'}</dd>
          <dt>Created · updated</dt><dd>{fmtDateTime(d.created_at)} · {fmtDateTime(d.updated_at)}</dd>
          {d.confidence!=null&&<><dt>Confidence</dt><dd>{Number(d.confidence)}</dd></>}
        </dl>
        {Number(rank)>=3&&<div className="sd-actions aer-life" data-aer-lifecycle>
          {d.status==='active'&&<><ReasonAction label="Withdraw" testid="aer-withdraw" onDo={r=>life('withdraw',r)} placeholder="Why it is withdrawn (kept in the history)"/>
            <ReasonAction label="Quarantine" testid="aer-quarantine" onDo={r=>life('quarantine',r)} placeholder="Why the evidence is in doubt (kept in the history)"/></>}
          {d.can_restore&&<ReasonAction label="Restore" variant="primary" testid="aer-restore" onDo={r=>life('restore',r)} placeholder="Why it is restored (kept in the history)"/>}
          {d.status==='proposed'&&<small>A waiting row is decided in <a className="cf-link" href={l4Href(d)}>Layer 4</a>.</small>}
        </div>}
        <h3>History</h3>
        {(d.history||[]).length===0?<small>No change by a person yet.</small>:
          <div className="cf-table-wrap"><table className="cf-table" data-aer-history><thead><tr><th>When</th><th>Who</th><th>What</th><th>Before</th><th>After</th><th>Reason</th></tr></thead>
            <tbody>{d.history.map((h,i)=><tr key={i}><td>{fmtDateTime(h.at)}</td><td>{h.actor}</td><td>{h.action==='edit'?`Edited ${h.field}`:h.action}</td><td><small>{histText(h.before)}</small></td><td><small>{histText(h.after)}</small></td><td><small>{h.reason}</small></td></tr>)}</tbody></table></div>}
      </>}
    </div></aside></>
}
const histText=v=>v==null?'—':typeof v==='object'?short(JSON.stringify(v),80):short(String(v),80)

// structured conditions (best of N, subject minimums, alternative routes), never free-form JSON (W4)
function ConditionsBlock({value,can,onSave}){
  const c=value&&typeof value==='object'?value:{}
  const[edit,setEdit]=useState(false),[draft,setDraft]=useState(null)
  const start=()=>{setDraft({best_n:c.best_n??'',subject_minimums:[...(c.subject_minimums||[])],alternatives:[...(c.alternatives||[])]});setEdit(true)}
  const has=c.best_n||(c.subject_minimums||[]).length||(c.alternatives||[]).length
  const list=(k,a,b)=>draft[k].map((x,i)=><div key={i} className="aer-cond-row"><input className="fv-input" value={x[a]||''} placeholder={a==='subject'?'Subject':'Route'} aria-label={`${a} ${i+1}`} onChange={e=>setDraft(d=>({...d,[k]:d[k].map((y,j)=>j===i?{...y,[a]:e.target.value}:y)}))}/><input className="fv-input" value={x[b]||''} placeholder="Minimum (optional)" aria-label={`${a} ${i+1} minimum`} onChange={e=>setDraft(d=>({...d,[k]:d[k].map((y,j)=>j===i?{...y,[b]:e.target.value}:y)}))}/><button type="button" aria-label="Remove" onClick={()=>setDraft(d=>({...d,[k]:d[k].filter((_,j)=>j!==i)}))}><X size={13}/></button></div>)
  return <div className="aer-conditions" data-aer-conditions>
    <h3>Conditions {can&&!edit&&<Button compact onClick={start} data-aer-conditions-edit><Pencil size={12}/>Edit</Button>}</h3>
    {!edit?(!has?<small>None published.</small>:<ul>{c.best_n&&<li>Best {c.best_n} subjects</li>}{(c.subject_minimums||[]).map((x,i)=><li key={'s'+i}>{x.subject}{x.min_grade?`: ${x.min_grade}`:''}</li>)}{(c.alternatives||[]).map((x,i)=><li key={'a'+i}>Or: {x.route}{x.min_grade?` (${x.min_grade})`:''}</li>)}</ul>)
    :<div className="aer-cond-edit">
      <label>Best of N subjects <input className="fv-input aer-n" inputMode="numeric" value={draft.best_n} onChange={e=>setDraft(d=>({...d,best_n:e.target.value}))} aria-label="Best of N subjects"/></label>
      <strong>Subject minimums</strong>{list('subject_minimums','subject','min_grade')}<Button compact onClick={()=>setDraft(d=>({...d,subject_minimums:[...d.subject_minimums,{subject:'',min_grade:''}]}))}><Plus size={12}/>Subject</Button>
      <strong>Alternative routes</strong>{list('alternatives','route','min_grade')}<Button compact onClick={()=>setDraft(d=>({...d,alternatives:[...d.alternatives,{route:'',min_grade:''}]}))}><Plus size={12}/>Route</Button>
      <div className="sd-actions"><ReasonAction label="Save conditions" variant="primary" testid="aer-conditions" onDo={r=>onSave({best_n:draft.best_n===''?null:Number(draft.best_n),subject_minimums:draft.subject_minimums.filter(x=>String(x.subject||'').trim()),alternatives:draft.alternatives.filter(x=>String(x.route||'').trim())},r).then(()=>setEdit(false))}/><Button compact onClick={()=>setEdit(false)}>Cancel</Button></div>
    </div>}
  </div>
}

// ----------------------------------------------------------------------------------------------- Add requirement (W5)
function AddRequirement({kind,options:o,defaults={},onError,onClose,onAdded}){
  const[v,setV]=useState({provider_id:defaults.provider_id||'',country:defaults.country||'',matrix_kind:'provider_minimum',requirement_kind:'minimum_grade',audience:'international',scale:'none',as_at:new Date().toISOString().slice(0,10)})
  const[ev,setEv]=useState([]),[courseQ,setCourseQ]=useState(''),[courses,setCourses]=useState([]),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const set=(k,x)=>setV(s=>({...s,[k]:x}))
  useEffect(()=>{if(!v.provider_id&&!v.course_id&&!v.source_url){setEv([]);return}let on=true;aer('evidence_options',{provider_id:v.provider_id||null,course_id:v.course_id||null,url:v.source_url||null}).then(x=>on&&setEv(x||[])).catch(()=>on&&setEv([]));return()=>{on=false}},[v.provider_id,v.course_id,v.source_url])
  useEffect(()=>{if(kind!=='course'&&v.matrix_kind!=='course_minimum')return;if(courseQ.trim().length<2){setCourses([]);return}let on=true;const t=setTimeout(()=>aer('course_search',{q:courseQ,provider_id:v.provider_id||null}).then(x=>on&&setCourses(x||[])).catch(()=>{}),250);return()=>{on=false;clearTimeout(t)}},[courseQ,v.provider_id,kind,v.matrix_kind])
  const submit=async e=>{e.preventDefault();setBusy(true);setErr('')
    try{const r=await aer('add',{...v,kind});onAdded(r.row)}catch(x){setErr(plainError(x))}finally{setBusy(false)}}
  const field=(k,lab,props={})=><label className="aer-field"><span>{lab}</span><input className="fv-input" value={v[k]||''} onChange={e=>set(k,e.target.value)} {...props}/></label>
  const needCourse=kind==='course'||v.matrix_kind==='course_minimum'
  return <><button className="m-drawer-backdrop" onClick={onClose} aria-label="Close"/><aside className="m-drawer aer-drawer" aria-label="Add an entry requirement" data-aer-add-form={kind}>
    <div className="m-drawer-head"><div><small>{kind==='matrix'?'Provider entry matrix':'Course entry requirements'}</small><h2>Add a requirement</h2></div><button onClick={onClose} aria-label="Close"><X size={18}/></button></div>
    <form className="m-drawer-body aer-form" onSubmit={submit}>
      <p className="sd-desc"><small>Only from the provider's own published source, with its stored copy. The row is active at once and every value must be printed in the quote. It is kept with your reason, name and time.</small></p>
      {kind==='matrix'&&<label className="aer-field"><span>Provider</span><select className="fv-input" value={v.provider_id} onChange={e=>set('provider_id',e.target.value)} required aria-label="Provider"><option value="">Choose…</option>{(o.providers||[]).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}
      {needCourse&&<div className="aer-field"><span>Course</span><input className="fv-input" value={courseQ} onChange={e=>setCourseQ(e.target.value)} placeholder="Course title or code" aria-label="Find the course"/>
        {courses.length>0&&<div className="aer-suggest">{courses.map(c=><button type="button" key={c.id} className={v.course_id===c.id?'selected':''} onClick={()=>{set('course_id',c.id);if(kind==='course')set('provider_id',c.provider_id);setCourseQ(`${c.title}${c.code?' · '+c.code:''}`);setCourses([])}}>{c.title}<small> · {c.provider}{c.code?' · '+c.code:''}</small></button>)}</div>}</div>}
      {kind==='matrix'?<>
        <label className="aer-field"><span>Country of prior education</span><select className="fv-input" value={v.country} onChange={e=>set('country',e.target.value)} required aria-label="Country"><option value="">Choose…</option>{(o.all_countries||[]).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
        <label className="aer-field"><span>Kind</span><select className="fv-input" value={v.matrix_kind} onChange={e=>set('matrix_kind',e.target.value)} aria-label="Kind">{(o.matrix_kinds||[]).map(k=><option key={k} value={k}>{KIND_LABEL[k]||k}</option>)}</select></label>
        {field('level_label','Level (as published)',{placeholder:'e.g. Bachelor degrees'})}
        <label className="aer-field"><span>Mapped level</span><select className="fv-input" value={v.level_code||''} onChange={e=>set('level_code',e.target.value)} aria-label="Mapped level"><option value="">Not mapped</option>{(o.levels||[]).map(l=><option key={l.code} value={l.code}>{l.name} ({l.code})</option>)}</select></label>
        {field('qualification','Qualification',{required:true,placeholder:'As published'})}
        {field('band','Band',{placeholder:'Only if printed, e.g. 65%'})}
        {field('min_grade','Minimum',{placeholder:'As printed, e.g. 75% or B'})}
        {field('edition','Edition',{placeholder:'e.g. 2027'})}{field('intake_year','Intake year',{inputMode:'numeric'})}
      </>:<>
        <label className="aer-field"><span>Kind</span><select className="fv-input" value={v.requirement_kind} onChange={e=>set('requirement_kind',e.target.value)} aria-label="Requirement kind">{(o.requirement_kinds||[]).map(k=><option key={k} value={k}>{KIND_LABEL[k]||k}</option>)}</select></label>
        <label className="aer-field"><span>For</span><select className="fv-input" value={v.audience} onChange={e=>set('audience',e.target.value)} aria-label="Audience">{(o.audiences||[]).map(k=><option key={k} value={k}>{k}</option>)}</select></label>
        <label className="aer-field"><span>Country (optional)</span><select className="fv-input" value={v.country||''} onChange={e=>set('country',e.target.value)} aria-label="Country"><option value="">Any country</option>{(o.all_countries||[]).map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
        {field('description','Requirement',{required:true,placeholder:'As published'})}
        {field('min_grade','Minimum',{placeholder:'As printed'})}
        {field('min_entry_score','Course score',{inputMode:'decimal'})}{field('min_entry_score_basis','Printed basis of the score',{placeholder:'e.g. 2027 Guaranteed ATAR'})}
        {field('band','Band',{placeholder:'Only if printed'})}
      </>}
      {field('min_value','Numeric value',{inputMode:'decimal',placeholder:'Only with a scale'})}
      <label className="aer-field"><span>Scale</span><select className="fv-input" value={v.scale} onChange={e=>set('scale',e.target.value)} aria-label="Scale">{(o.scales||['none']).map(s=><option key={s} value={s}>{SCALE_LABEL[s]||s}</option>)}</select></label>
      <label className="aer-field aer-wide"><span>Exact quote</span><textarea className="fv-input" value={v.quote||''} onChange={e=>set('quote',e.target.value)} maxLength={300} required aria-label="Exact quote"/></label>
      {field('source_url','Official source address',{type:'url',required:true,placeholder:'https://'})}
      <label className="aer-field aer-wide"><span>Stored copy of that address</span><select className="fv-input" value={v.evidence_id||''} onChange={e=>set('evidence_id',e.target.value)} required aria-label="Stored copy"><option value="">{ev.length?'Choose…':'No stored copy found for this provider or address'}</option>{ev.map(e=><option key={e.id} value={e.id}>{short(e.source_url,70)} · {fmtDate(e.captured_at)}</option>)}</select></label>
      {field('as_at','As at',{type:'date'})}
      {field('reason','Reason (kept in the history)',{required:true,minLength:5})}
      {err&&<p className="fr-error" role="alert" data-aer-add-error>{err}</p>}
      <div className="sd-actions"><Button type="submit" variant="primary" disabled={busy} data-aer-add-submit>{busy?'Adding…':'Add requirement'}</Button><Button onClick={onClose}>Cancel</Button></div>
    </form></aside></>
}

// ----------------------------------------------------------------------------------------------- Sources, reads and holds
const SOURCE_NAMES={provider_id:'Provider',status:'Fetch',hold_state:'Read state',q:'Search'}
export function SourcesView({rank,onError,routeParams}){
  const o=useOptions(onError)
  const{f,set,clear,labels,offset,setOffset,sortBy}=useFilters('sources',{provider_id:'',status:'',hold_state:'',q:'',sort:'provider',direction:'asc'},{provider_id:routeParams?.get?.('provider')||''})
  const[refresh,setRefresh]=useState(0),[msg,setMsg]=useState({})
  const args=useMemo(()=>({...f,offset,page_size:PAGE}),[JSON.stringify(f),offset])
  const[d,busy,err]=useList('sources_list',args,onError,refresh)
  const rows=d?.rows||[]
  const reread=async(s,reason)=>{try{await aer('reread',{source_id:s.id,reason});setMsg(m=>({...m,[s.id]:'Asked. The read waits for the next run of the entry reader; its rows go to Layer 4.'}));setRefresh(n=>n+1)}catch(e){setMsg(m=>({...m,[s.id]:plainError(e)}));throw e}}
  const all=[
    {key:'provider_name',label:'Provider',width:200,sortKey:'provider',render:s=><span className="m-cell-title"><strong>{s.provider_name}</strong>{!s.in_scope&&<small>outside reading scope</small>}</span>},
    {key:'url',label:'Source',width:260,render:s=><span className="m-cell-title"><a className="cf-link aer-wrap" href={s.url} target="_blank" rel="noreferrer" onClick={e=>e.stopPropagation()}>{short(s.url.replace(/^https?:\/\/(www\.)?/,''),70)}</a><small>{s.type}{s.title?` · ${short(s.title,40)}`:''}</small></span>},
    {key:'status',label:'Fetch',width:150,sortKey:'status',render:s=><span><StatusChip value={s.status} label={s.status}/>{s.read_via&&<small> · {s.read_via}</small>}</span>},
    {key:'stored',label:'Stored copy',width:170,render:s=>s.evidence_id?<span><a className="cf-link" href={evHref(s.evidence_id)} onClick={e=>e.stopPropagation()}>{fmtDate(s.captured_at)}</a><small> · {s.content_hash||''}</small></span>:'—'},
    {key:'read',label:'Latest read',width:160,sortKey:'read',render:s=><span><HoldPill state={s.hold_state} title={s.run?.error||s.error||undefined}/>{s.run?.attempts!=null&&<small> · {s.run.attempts} tries</small>}</span>},
    {key:'rows',label:'Rows · not kept',width:130,render:s=>s.run?`${fmtNumber(Number(s.run.rows||0))} · ${fmtNumber(Number(s.run.not_kept||0))}`:'—'},
    {key:'why',label:'Hold, error or rows not kept',width:300,render:s=><small className="aer-wrap">{s.run?.error||s.error||(s.run?.dropped&&Object.keys(s.run.dropped).length?Object.entries(s.run.dropped).map(([k,n])=>`${n} ${k.replaceAll('_',' ')}`).join(' · '):'—')}</small>},
    {key:'cost',label:'Cost',width:90,sortKey:'cost',render:s=>s.run?.cost_usd!=null?`US$${Number(s.run.cost_usd).toFixed(4)}`:'—'},
    {key:'layer4',label:'Layer 4',width:130,render:s=>s.run?.review_item_id?<a className="cf-link" href={hrefFor('layer4','inbox',{provider:s.provider_id})} onClick={e=>e.stopPropagation()}>{s.run.review_status}</a>:'—'},
    {key:'last_success',label:'Last read · next refresh',width:180,sortKey:'read_at',render:s=><small>{s.last_success?fmtDate(s.last_success):'never'}{s.next_refresh?` · ${fmtDate(s.next_refresh)}`:''}</small>},
    {key:'action',label:'Read again',width:230,render:s=>d?.can_reread&&s.in_scope&&!['reading'].includes(s.hold_state)&&!(s.run?.error||'').startsWith('held_unparsed')&&s.run?
      <span onClick={e=>e.stopPropagation()}><ReasonAction label="Read again" testid="aer-reread" onDo={r=>reread(s,r)}/>{msg[s.id]&&<small role="status"> {msg[s.id]}</small>}</span>
      :<small>{(s.run?.error||'').startsWith('held_unparsed')?'Held as unreadable':msg[s.id]||'—'}</small>},
  ]
  const[cols,hidden,setHidden]=useColumns('sources',all)
  return <div className="m-page-stack aer-page" data-aer-view="sources">
    <AerSummary providerId={f.provider_id} onError={onError} refreshKey={refresh}/>
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>Sources, reads and holds</h2><p>Every official page or PDF the entry reader uses, its stored copy, its latest read and why rows were held or not kept.{d&&!d.ai_allowed?' AI reading is stopped (AI limits).':''}</p></div>
        <div className="m-result-count">{busy?<><span className="m-spinner"/>Loading…</>:<><strong>{fmtNumber(Number(d?.total||0))}</strong><span>sources</span></>}</div></div>
      <div className="m-search-row"><TextFilter label="Search address or error" value={f.q} onChange={v=>set('q',v,v)} placeholder="Search address or error"/><ColumnsMenu all={all} hidden={hidden} onChange={setHidden}/>
        <button type="button" className="m-secondary compact" onClick={()=>setRefresh(n=>n+1)}><RefreshCw size={14}/>Refresh</button></div>
      <div className="m-filter-bar" data-aer-filters="sources">
        <FilterSelect label="Provider" value={f.provider_id} onChange={(v,l)=>set('provider_id',v,l)} options={(o.providers||[]).map(p=>opt(p.id,p.name))}/>
        <FilterSelect label="Fetch" value={f.status} onChange={(v,l)=>set('status',v,l)} options={['read','found','reading','failed','pdf_step_b','robots_disallowed'].map(s=>opt(s,s))}/>
        <FilterSelect label="Read state" value={f.hold_state} onChange={(v,l)=>set('hold_state',v,l)} options={Object.entries(HOLD_PILL).map(([k,[,l]])=>opt(k,l))}/>
      </div>
      <Chips filters={f} labels={labels} names={SOURCE_NAMES} set={set} clear={clear}/>
      {err&&<p className="fr-error" role="alert" data-aer-error>{err}</p>}
      <DataTable rows={rows} columns={cols} loading={busy} sort={f.sort} direction={f.direction} onSort={sortBy} tableId="aer-sources"/>
      <Pager offset={offset} limit={PAGE} total={Number(d?.total||0)} onOffset={setOffset}/>
    </section>
  </div>
}

// ----------------------------------------------------------------------------------------------- Resolution inspection (W13)
const RULE_TEXT={course_override:'Course rule (override) for this country or any country',course_country_row:'A provider row for this course and this country',band_ladder:'The course band, entered in the provider\'s band table',provider_minimum:'The provider minimum for this country and the course level',contact_provider:'Nothing published applies: contact the provider'}
const OUTCOME={minimum_published:['success','A minimum is published'],case_by_case:['warning','Considered case by case'],contact_provider:['neutral','Contact the provider']}
export function ResolveView({onError,routeParams}){
  const o=useOptions(onError)
  const[q,setQ]=useState(''),[list,setList]=useState([]),[course,setCourse]=useState(null),[cc,setCc]=useState(routeParams?.get?.('country')||''),[res,setRes]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  useEffect(()=>{if(q.trim().length<2||course){setList([]);return}let on=true;const t=setTimeout(()=>aer('course_search',{q}).then(x=>on&&setList(x||[])).catch(()=>{}),250);return()=>{on=false;clearTimeout(t)}},[q,course])
  useEffect(()=>{const id=routeParams?.get?.('course');if(id&&!course)setCourse({id,title:'Course'})},[])
  const run=async()=>{if(!course||!cc)return;setBusy(true);setErr('');setRes(null);try{setRes(await aer('resolve',{course_id:course.id,country:cc}))}catch(e){setErr(plainError(e))}finally{setBusy(false)}}
  useEffect(()=>{if(course&&cc)run()},[course?.id,cc])
  const r=res?.resolution,step=Number(r?.step||0)
  return <div className="m-page-stack aer-page" data-aer-view="resolve">
    <section className="m-panel m-catalogue-panel">
      <div className="m-workspace-head"><div><h2>Resolution inspection</h2><p>Which of the five rules gives a course's requirement for a student's country of prior education, and why the earlier rules did not. An operator check of the live resolver, not a preview of the website and not an eligibility check.</p></div></div>
      <div className="m-search-row aer-resolve-pick">
        <div className="aer-field"><span>Course</span>{course?<span className="aer-picked"><strong>{res?.course?.title||course.title}</strong>{(res?.course?.code||course.code)&&<small> · {res?.course?.code||course.code}</small>}{(res?.course?.provider||course.provider)&&<small> · {res?.course?.provider||course.provider}</small>}<button type="button" aria-label="Choose another course" onClick={()=>{setCourse(null);setRes(null);setQ('')}}><X size={13}/></button></span>
          :<><input className="fv-input" value={q} onChange={e=>setQ(e.target.value)} placeholder="Course title or code, e.g. 0100714" aria-label="Find a course" data-aer-resolve-course/>
            {list.length>0&&<div className="aer-suggest">{list.map(c=><button type="button" key={c.id} onClick={()=>{setCourse(c);setList([])}}>{c.title}<small> · {c.provider}{c.code?' · '+c.code:''}</small></button>)}</div>}</>}</div>
        <FilterSelect label="Country of prior education" value={cc} emptyLabel="Choose…" onChange={v=>setCc(v)} options={(o.all_countries||[]).map(c=>opt(c.code,c.name,c.code))}/>
        <button type="button" className="m-secondary compact" onClick={run} disabled={!course||!cc||busy}><RefreshCw size={14}/>Inspect again</button>
      </div>
      {err&&<p className="fr-error" role="alert">{err}</p>}
      {busy&&<Loading label="Resolving…"/>}
      {res&&<div className="aer-resolution" data-aer-resolution={r?.outcome}>
        <div className="aer-outcome"><span data-aer-outcome={r?.outcome}><StatusChip tone={OUTCOME[r?.outcome]?.[0]||'neutral'} label={OUTCOME[r?.outcome]?.[1]||r?.outcome}/></span>
          <strong>Rule {step}: {RULE_TEXT[r?.rule]||r?.rule}</strong>{r?.band&&<small> · band {r.band}</small>}</div>
        {r?.note&&<p className="sd-desc">{r.note}</p>}
        <div className="cf-table-wrap"><table className="cf-table" data-aer-steps><thead><tr><th>Rule</th><th>What it looks for</th><th>Active rows found</th><th>Result</th></tr></thead>
          <tbody>{(res.steps||[]).map(s=><tr key={s.step} data-aer-step={s.step} className={s.step===step?'aer-step-hit':''}>
            <td>{s.step}</td><td>{RULE_TEXT[s.rule]}{s.step===3&&<small> · course band: {s.band||'none printed'}</small>}</td>
            <td>{s.step===5?'—':fmtNumber(Number(s.active_rows||0))}{s.step===3&&s.band_table_rows!=null&&<small> · {fmtNumber(Number(s.band_table_rows))} rows in the band table</small>}</td>
            <td>{s.step<step?<small>Did not apply: {s.step===3&&!s.band?'the course prints no band':'no active row'}</small>:s.step===step?<strong>Used</strong>:<small>Not reached</small>}</td></tr>)}</tbody></table></div>
        {(r?.rows||[]).length>0&&<div className="cf-table-wrap"><table className="cf-table" data-aer-resolved-rows><thead><tr><th>Qualification or rule</th><th>Level</th><th>Minimum</th><th>Scale or basis</th><th>Band</th><th>Quote</th><th>As at</th></tr></thead>
          <tbody>{r.rows.map((x,i)=><tr key={i}><td>{x.qualification||x.text}</td><td>{x.study_level||'—'}</td><td>{x.min_grade||x.min_score||<em>case by case</em>}</td><td>{SCALE_LABEL[x.scale]||x.scale||x.min_score_basis||'—'}</td><td>{x.band||'—'}</td><td><small>“{x.quote}”</small></td><td>{fmtDate(x.as_at)}</td></tr>)}</tbody></table></div>}
        <p className="aer-not-used" data-aer-not-used><small>Not used by the website: {fmtNumber(Number(res.not_used?.proposed_matrix||0))} provider rows for this country waiting in Layer 4 · {fmtNumber(Number(res.not_used?.unverified_matrix||0))} quarantined · {fmtNumber(Number(res.not_used?.proposed_course||0))} course rows waiting. Levels matched: {(res.not_used?.levels||[]).join(', ')||'none'}.</small></p>
      </div>}
      {!res&&!busy&&!err&&<EmptyInline text="Choose a course and a country."/>}
    </section>
  </div>
}

export default function AerWorkspace({tab,rank,onError,navigate,routeParams}){
  if(tab==='course')return <CourseView rank={rank} onError={onError} routeParams={routeParams}/>
  if(tab==='sources')return <SourcesView rank={rank} onError={onError} routeParams={routeParams}/>
  if(tab==='resolve')return <ResolveView onError={onError} routeParams={routeParams}/>
  return <MatrixView rank={rank} onError={onError} navigate={navigate} routeParams={routeParams}/>
}
