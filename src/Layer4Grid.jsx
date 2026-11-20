// CF-247 UI/UX audit Phase 5, first slice (18 Nov 2026; admin docs/platform/ui-audit/ui-ux-settings-audit-2026-11-15.md §4.2, §5, §7.3):
// Layer 4 › Inbox › Grid. One built-in Layer 4 kind as rows on the shared table (DataTable), paged on the server
// (public.admin_layer4_grid_read_v1, page size layer4.inbox_page_size), with column choice and a CSV export (up to layer4.grid_export_max_rows).
// Saved views (pipeline.saved_views): the shared views AER Audit Samples, Official URLs and Provider Blockers (changed by a Platform Admin only,
// checked on the server) and each person's own views. A view only chooses what is shown; the AER audit sample and the Layer 4 URL rules are
// unchanged. A row opens the Source Quote vs Extracted Value drawer (public.admin_layer4_item_trace_v1): the saved page quote beside the value,
// the evidence link and the decision history. Decisions are taken in the drawer with the Inbox's own card (every action, decision path and audit
// trail unchanged, public.admin_layer4_inbox).
import React,{useEffect,useMemo,useRef,useState}from'react'
import{ChevronLeft,ChevronRight,Columns3,Download,ExternalLink,RefreshCw,Save,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{DataTable}from'./DataTable'
import{Button,EmptyInline,Pager,StatusChip,fmtDate,fmtNumber}from'./ui-kit'
import{DEFAULT_COLS,GRID_COLUMNS,quoteValuePairs,toCsv,urlOf}from'./lib/layer4-grid'
import Layer4GroupDecide from'./Layer4GroupDecide'
import Layer4Clusters from'./Layer4Clusters' // v2.16.43: clusters by kind, university, reason and quote
import AerRuleChecks from'./AerRuleChecks' // S831: the rule checks of an AER course entry read
import{CountryFlag}from'./ProviderListParts' // s767: the drawn flags of Catalogue › Providers

const call=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data}
const QUOTE_CAP=4 // the review column shows the first quotes; the table below lists every row
export function Drawer({target,kinds,targetDays,renderItem,onClose,onDecided,nav}){
  const[t,setT]=useState(null),[err,setErr]=useState(''),[tick,setTick]=useState(0)
  useEffect(()=>{setT(null);setErr('');call('admin_layer4_item_trace_v1',{p_kind:target.kind,p_ref:target.ref}).then(setT).catch(e=>setErr(e.message))},[target.kind,target.ref,tick])
  const it=t?.item,pairs=useMemo(()=>quoteValuePairs(it),[it])
  const withValue=pairs.filter(p=>String(p.value??'').trim()!==''&&String(p.value)!=='—'),quotes=pairs.filter(p=>p.quote)
  const evidenceUrl=urlOf(t?.evidence?.source_url)||urlOf(it?.detail?.source_url)||urlOf(it?.detail?.evidence?.page_url)
  return <><button className="m-drawer-backdrop" onClick={onClose} aria-label="Close"/><aside className="m-drawer l4g-drawer" aria-label="Source quote and extracted value" data-l4g-drawer>
    <div className="m-drawer-head"><div><small>{kinds[target.kind]?.label||target.kind}</small><h2>{it?.subject||target.subject||'Item'}</h2>{it?.provider&&<p className="l4g-sub">{it.provider}</p>}</div><button onClick={onClose} aria-label="Close"><X size={18}/></button></div>
    {nav&&<div className="l4g-nav" role="toolbar" aria-label="Move between items" data-l4g-nav>
      <button type="button" onClick={nav.prev} disabled={!nav.canPrev} data-l4g-prev title="Previous item (K)"><ChevronLeft size={14}/>Previous <kbd>K</kbd></button>
      <span data-l4g-pos>{nav.pos>0?`${nav.pos} of ${fmtNumber(nav.total)}`:'Not on this page'}</span>
      <button type="button" onClick={nav.next} disabled={!nav.canNext} data-l4g-next title="Next item (J)">Next <kbd>J</kbd><ChevronRight size={14}/></button>
    </div>}
    <div className="m-drawer-body">
      {err&&<p className="l4g-err" role="alert">{err}</p>}
      {!t&&!err&&<p className="l4g-sub">Loading…</p>}
      {t&&!t.waiting&&<p className="l4g-note" data-l4g-decided>This item is no longer waiting: it was decided or closed. Its history is below.</p>}
      {it&&<section className="l4g-review" data-l4g-review aria-label="Review side by side">
        <div className="l4g-rv-col" data-l4g-proposed><h3>Proposed text or value</h3>
          {withValue.length?withValue.map((p,i)=><div key={i} className="l4g-rv-val">{p.link&&urlOf(p.value)?<a href={p.value} target="_blank" rel="noreferrer">{p.value} <ExternalLink size={11}/></a>:<span>{String(p.value)}</span>}{p.before&&<small className="l4g-muted"> (held now: {p.before})</small>}</div>)
            :pairs.length?<p className="l4g-muted" data-l4g-rows-only>{fmtNumber(pairs.length)} proposed row{pairs.length===1?'':'s'}; each is read with its quote under Source quote and extracted value below.</p>
            :<p className="l4g-muted">This kind holds no proposed value; the reason and the suggestion say what is needed.</p>}
        </div>
        <div className="l4g-rv-col" data-l4g-source><h3>Verbatim source quote</h3>
          {quotes.length?<>{quotes.slice(0,QUOTE_CAP).map((p,i)=><q key={i} className="l4g-rv-quote">{p.quote}</q>)}{quotes.length>QUOTE_CAP&&<p className="l4g-muted" data-l4g-more-quotes>and {fmtNumber(quotes.length-QUOTE_CAP)} more, in the table below.</p>}</>:<p className="l4g-muted">No quote is held for this item.</p>}
          {evidenceUrl?<p className="l4g-rv-src"><a href={evidenceUrl} target="_blank" rel="noreferrer" data-l4g-source-link>{evidenceUrl} <ExternalLink size={11}/></a>{t?.evidence?.captured_at&&<small className="l4g-muted"> · saved {fmtDate(t.evidence.captured_at)}</small>}</p>:<p className="l4g-muted">No source page is linked to this item.</p>}
        </div>
        <div className="l4g-rv-col" data-l4g-hold><h3>Machine hold reason</h3>
          {it.why?<p className="l4g-hold-badge" data-l4g-hold-reason title="The exact reason the machine rules held this item for a person">{it.why}</p>:<p className="l4g-muted">No reason is recorded.</p>}
          {it.suggestion&&<p className="l4g-rv-sug"><strong>Suggested next step:</strong> {it.suggestion}</p>}
        </div>
      </section>}
      {it&&target.kind==='aer_review'&&<section data-l4g-rule-checks><h3>Rule checks</h3><AerRuleChecks id={target.ref}/></section>}
      {it&&t.waiting&&renderItem&&<section data-l4g-decide><h3>Decide</h3>
        <p className="l4g-sub">The decisions below are this kind's own (Approve, Edit and approve, Reject or Hold, each with a reason). Nothing is decided by moving between items.</p>
        {renderItem({...it,late:Number(targetDays)>0&&Date.now()-new Date(it.created_at).getTime()>Number(targetDays)*86400000},r=>{onDecided?.(r);setTick(x=>x+1)})}
      </section>}
      {it&&pairs.length>0&&<section data-l4g-quote-value><h3>Source quote and extracted value</h3>
        <table className="l4g-qv"><thead><tr><th>Quote on the saved page</th><th>Value it produced</th></tr></thead><tbody>
          {pairs.map((p,i)=><tr key={i}><td>{p.quote?<q>{p.quote}</q>:<span className="l4g-muted">No quote held for this value</span>}</td>
            <td>{p.link&&urlOf(p.value)?<a href={p.value} target="_blank" rel="noreferrer">{p.value} <ExternalLink size={11}/></a>:p.value}{p.before&&<small className="l4g-muted"> (held now: {p.before})</small>}</td></tr>)}
        </tbody></table>
      </section>}
      <section data-l4g-evidence><h3>Evidence</h3>
        {evidenceUrl?<p><a href={evidenceUrl} target="_blank" rel="noreferrer">{evidenceUrl} <ExternalLink size={11}/></a>{t?.evidence?.captured_at&&<small className="l4g-muted"> · saved {fmtDate(t.evidence.captured_at)}</small>}</p>:<p className="l4g-muted">No evidence page is linked to this item.</p>}
      </section>
      <section data-l4g-history><h3>Decision history</h3>
        {t?.history?.length?<ol className="l4g-history">{t.history.map((h,i)=><li key={i}><strong>{h.choice||h.action}</strong>{h.value?` → ${h.value}`:''}<small className="l4g-muted"> · {fmtDate(h.at)} · {h.by||(h.auto?`machine rule ${h.machine_rule||''}`:'the platform')}</small>{h.reason&&<div>{h.reason}</div>}</li>)}</ol>:<p className="l4g-muted">No decision recorded for this item yet.</p>}
      </section>
    </div>
  </aside></>}

// s767: the pills offered; the server checks the same values (public.admin_layer4_grid_read_v1). University covers university, university college and wānanga; VET / College covers TAFE / polytechnic and private VET.
const COUNTRY_PILLS=[['','All'],['AU','Australia (AU)'],['NZ','New Zealand (NZ)'],['CA','Canada (CA)']]
const TYPE_PILLS=[['','All'],['university','University'],['vet_college','VET / College'],['school','School'],['hei','HEI']]
export default function Layer4Grid({kinds={},targetDays=0,rank,renderItem,onDecided,onError}){
  const[vs,setVs]=useState(null),[viewId,setViewId]=useState(''),[kind,setKind]=useState(''),[why,setWhy]=useState(''),[q,setQ]=useState(''),[sort,setSort]=useState('oldest')
  const[cols,setCols]=useState(DEFAULT_COLS),[offset,setOffset]=useState(0),[data,setData]=useState(null),[loading,setLoading]=useState(false),[err,setErr]=useState('')
  const[picker,setPicker]=useState(false),[open,setOpen]=useState(null),[saving,setSaving]=useState(''),[name,setName]=useState(''),[note,setNote]=useState('')
  const[cty,setCty]=useState(''),[ptype,setPtype]=useState('') // v2.16.53 (s767, Platform Admin 19 Nov 2026 16:18): Country and Provider type pills beside the kind and reason filters
  const[grouped,setGrouped]=useState(false) // v2.16.40: Grouped decisions (Platform Admin 18 Nov 2026 13:02)
  const[clustered,setClustered]=useState(false) // v2.16.43: Clusters (Platform Admin 18 Nov 2026 19:20)
  const[cohort,setCohort]=useState({}) // s767: waiting items for each pill with every other filter kept; read with an offset past the end so no rows travel
  const view=vs?.views?.find(v=>v.id===viewId)||null,vkinds=view?.definition?.kinds||null
  const loadViews=pick=>call('admin_saved_views_read_v1',{p_screen:'layer4_inbox'}).then(d=>{setVs(d);const v=(pick&&d.views.find(x=>x.id===pick))||d.views[0];if(v)apply(v)}).catch(e=>setErr(e.message))
  const apply=v=>{const d=v.definition||{};setViewId(v.id);setKind((d.kinds||[])[0]||'');setWhy(d.why_contains||'');setQ(d.q||'');setSort(d.sort||'oldest');setCols(Array.isArray(d.columns)&&d.columns.length?d.columns:DEFAULT_COLS);setOffset(0);setNote('')}
  useEffect(()=>{loadViews()},[])
  const args=o=>({kind,why_contains:why||undefined,q:q||undefined,country:cty||undefined,provider_type:ptype||undefined,sort,offset:o})
  const load=(o=offset)=>{if(!kind)return;setLoading(true);setErr('');call('admin_layer4_grid_read_v1',{p_args:args(o)}).then(d=>{setData(d);setLoading(false)}).catch(e=>{setErr(e.message);setData(null);setLoading(false)})}
  useEffect(()=>{setOffset(0);load(0)},[kind,why,sort,cty,ptype])
  useEffect(()=>{const h=setTimeout(()=>{setOffset(0);load(0)},350);return()=>clearTimeout(h)},[q])
  // s767 (Platform Admin 19 Nov 2026 19:26): live cohort counts on the pills. Each count is the same read with that pill chosen and the other filters kept
  // (offset past the end: only the total comes back). Two at a time, once the page has loaded, and kept by filter so going back costs nothing.
  const countKey=(c,t)=>JSON.stringify([kind,why,q,c,t])
  useEffect(()=>{
    if(!kind||!data)return
    let live=true;setCohort(m=>({...m,[countKey(cty,ptype)]:Number(data.total)}))
    const want=[...COUNTRY_PILLS.map(([c])=>[c,ptype]),...TYPE_PILLS.map(([t])=>[cty,t])].filter(([c,t])=>!(c===cty&&t===ptype))
    const todo=want.filter(([c,t])=>cohortRef.current[countKey(c,t)]===undefined)
    const run=async()=>{while(live&&todo.length){const[c,t]=todo.shift();try{const d=await call('admin_layer4_grid_read_v1',{p_args:{kind,why_contains:why||undefined,q:q||undefined,country:c||undefined,provider_type:t||undefined,sort,offset:100000000}});if(live)setCohort(m=>({...m,[countKey(c,t)]:Number(d.total)}))}catch{/* a count that fails shows a dash */}}}
    run();run()
    return()=>{live=false}
  },[data,kind,why,q,cty,ptype])
  const cohortRef=useRef({});cohortRef.current=cohort
  const countOf=(c,t)=>{const n=cohort[countKey(c,t)];return n===undefined?'…':fmtNumber(n)}
  // s768: J and K move to the next and previous waiting item of this page (the first of the next page past the end); they never decide anything
  const rows=data?.rows||[],openIx=open?rows.findIndex(r=>r.kind===open.kind&&r.ref===open.ref):-1
  const moveTo=async d=>{const i=openIx+d;if(i>=0&&i<rows.length){setOpen(rows[i]);return}
    const lim=Number(data?.limit)||0,next=offset+(d>0?lim:-lim);if(!lim||next<0||next>=Number(data?.total))return
    setOffset(next);setLoading(true);try{const r=await call('admin_layer4_grid_read_v1',{p_args:args(next)});setData(r);setLoading(false);const rr=r.rows||[];if(rr.length)setOpen(d>0?rr[0]:rr[rr.length-1])}catch(e){setErr(e.message);setLoading(false)}}
  useEffect(()=>{if(!open)return
    const onKey=e=>{if(e.defaultPrevented||e.ctrlKey||e.metaKey||e.altKey)return;const el=e.target,tag=(el?.tagName||'').toLowerCase()
      if(tag==='input'||tag==='textarea'||tag==='select'||el?.isContentEditable)return
      if(e.key==='j'||e.key==='J'){e.preventDefault();moveTo(1)}else if(e.key==='k'||e.key==='K'){e.preventDefault();moveTo(-1)}}
    window.addEventListener('keydown',onKey);return()=>window.removeEventListener('keydown',onKey)})
  const nav=open?{pos:openIx>=0?offset+openIx+1:0,total:Number(data?.total)||0,canPrev:openIx>0||(openIx===0&&offset>0),canNext:openIx>=0&&(openIx<rows.length-1||offset+rows.length<Number(data?.total)),prev:()=>moveTo(-1),next:()=>moveTo(1)}:null
  const gridKinds=vs?.grid_kinds||[],kindList=vkinds||Object.entries(kinds).filter(([k])=>!gridKinds.length||gridKinds.includes(k)).sort((a,b)=>(a[1].order||0)-(b[1].order||0)).map(([k])=>k)
  const columns=cols.map(c=>({key:c,label:GRID_COLUMNS[c]||c,width:c==='subject'||c==='why'?260:c==='age_days'||c==='country'?90:160,render:c==='kind'?r=>kinds[r.kind]?.label||r.kind:c==='created_at'?r=>fmtDate(r.created_at):c==='age_days'?r=><StatusChip tone={Number(targetDays)&&r.age_days>Number(targetDays)?'warning':'neutral'} label={fmtNumber(r.age_days)}/>:undefined}))
  const exportCsv=async()=>{setSaving('csv');try{const d=await call('admin_layer4_grid_read_v1',{p_args:{...args(0),export:true}});const blob=new Blob([toCsv(d.rows||[],cols)],{type:'text/csv;charset=utf-8'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`layer4-${kind}-${new Date().toISOString().slice(0,10)}.csv`;a.click();URL.revokeObjectURL(a.href)
    setNote(Number(d.total)>Number(d.limit)?`Exported the first ${fmtNumber(d.limit)} of ${fmtNumber(d.total)} rows (the export limit, layer4.grid_export_max_rows).`:`Exported ${fmtNumber(d.rows?.length||0)} rows.`)}catch(e){setErr(e.message)}setSaving('')}
  const definition=()=>({kinds:vkinds&&vkinds.includes(kind)?vkinds:[kind],...(why?{why_contains:why}:{}),...(q?{q}:{}),sort,columns:cols})
  const saveMine=async()=>{if(name.trim().length<2){setErr('Give the view a name of at least two characters.');return}setSaving('view');try{const r=await call('admin_saved_view_save_v1',{p_args:{scope:'personal',name:name.trim(),definition:definition()}});setName('');setNote('Saved as your view.');await loadViews(r.id)}catch(e){setErr(e.message)}setSaving('')}
  const updateView=async()=>{setSaving('view');try{await call('admin_saved_view_save_v1',{p_args:{id:view.id,definition:definition()}});setNote(view.scope==='shared'?'Shared view updated for everyone.':'Your view is updated.');await loadViews(view.id)}catch(e){setErr(e.message)}setSaving('')}
  const archive=async()=>{setSaving('view');try{await call('admin_saved_view_archive_v1',{p_id:view.id,p_reason:'removed from the grid'});setNote('View removed.');await loadViews()}catch(e){setErr(e.message)}setSaving('')}
  const canEdit=view&&(view.scope==='personal'?view.mine:vs?.can_edit_shared)
  return <div className="l4g" data-l4g-grid>
    <p className="l4g-help">The grid shows one kind of item at a time, paged on the server. The Country and Provider type pills narrow the rows and the count on this screen, and each shows how many items wait with it chosen (they are not saved in a view). With an item open, J moves to the next item and K to the previous one; moving never decides anything. A view chooses the kind, the reason filter, the order and the columns; it never changes a rule (the AER audit sample and the course-address rules are unchanged). Open a row to see the quote on the saved page beside the value it produced, the evidence and the decision history, and to decide it as on the other views.</p>
    <div className="l4g-views" role="toolbar" aria-label="Saved views">
      {(vs?.views||[]).map(v=><button key={v.id} type="button" className={v.id===viewId?'on':''} data-l4g-view={v.code||'personal'} title={v.description||''} onClick={()=>apply(v)}>{v.name}{v.scope==='personal'&&<small> · mine</small>}</button>)}
      <button type="button" className={!viewId?'on':''} data-l4g-view="custom" onClick={()=>{setViewId('');setWhy('');setQ('');setGrouped(false);setClustered(false)}}>Custom</button>
      <button type="button" className={grouped?'on':''} aria-pressed={grouped} data-l4g-view="grouped" onClick={()=>{setGrouped(x=>!x);setClustered(false)}}>Grouped decisions</button>
      <button type="button" className={clustered?'on':''} aria-pressed={clustered} data-l4g-view="clusters" onClick={()=>{setClustered(x=>!x);setGrouped(false)}}>Clusters</button>
    </div>
    {grouped&&<Layer4GroupDecide onDecided={()=>{onDecided?.();load(offset)}}/>}
    {clustered&&<Layer4Clusters kinds={kinds} rank={rank??data?.rank} onDecided={()=>{onDecided?.();load(offset)}}/>}
    <div className="l4g-bar">
      <label>Kind<select value={kind} onChange={e=>setKind(e.target.value)} data-l4g-kind><option value="">Choose a kind</option>{kindList.map(k=><option key={k} value={k}>{kinds[k]?.label||k}</option>)}</select></label>
      <label>Reason contains<input value={why} onChange={e=>setWhy(e.target.value)} maxLength={80} placeholder="e.g. audit_sample" data-l4g-why/></label>
      <label>Search<input value={q} onChange={e=>setQ(e.target.value)} maxLength={80} placeholder="Item or university" data-l4g-q/></label>
      <label>Order<select value={sort} onChange={e=>setSort(e.target.value)} data-l4g-sort><option value="oldest">Oldest first</option><option value="newest">Newest first</option></select></label>
      <div className="l4g-actions">
        <Button compact onClick={()=>setPicker(x=>!x)} aria-expanded={picker} data-l4g-columns><Columns3 size={14}/>Columns</Button>
        <Button compact disabled={!kind||saving!==''} onClick={exportCsv} data-l4g-csv><Download size={14}/>{saving==='csv'?'Exporting…':'Export CSV'}</Button>
        <Button compact onClick={()=>{setCohort({});load(offset)}} data-l4g-refresh><RefreshCw size={14}/>Refresh</Button>
      </div>
    </div>
    <div className="l4g-pills" data-l4g-pills>
      <div className="l4g-pillrow" role="toolbar" aria-label="Country" data-l4g-country-pills><span className="l4g-pilllabel">Country</span>
        {COUNTRY_PILLS.map(([v,l])=><button key={v||'all'} type="button" className={cty===v?'on':''} aria-pressed={cty===v} data-l4g-country={v||'all'} onClick={()=>setCty(v)}>{v&&<CountryFlag code={v}/>}{l}<b className="l4g-n" data-l4g-n>{countOf(v,ptype)}</b></button>)}</div>
      <div className="l4g-pillrow" role="toolbar" aria-label="Provider type" data-l4g-ptype-pills><span className="l4g-pilllabel">Provider type</span>
        {TYPE_PILLS.map(([v,l])=><button key={v||'all'} type="button" className={ptype===v?'on':''} aria-pressed={ptype===v} data-l4g-ptype={v||'all'} onClick={()=>setPtype(v)}>{l}<b className="l4g-n" data-l4g-n>{countOf(cty,v)}</b></button>)}</div>
    </div>
    {picker&&<fieldset className="l4g-picker" data-l4g-picker><legend>Columns shown</legend>{Object.entries(GRID_COLUMNS).map(([c,l])=><label key={c}><input type="checkbox" checked={cols.includes(c)} onChange={e=>setCols(x=>e.target.checked?[...x,c]:x.filter(y=>y!==c).length?x.filter(y=>y!==c):x)}/>{l}</label>)}</fieldset>}
    <div className="l4g-save">
      <input value={name} onChange={e=>setName(e.target.value)} maxLength={80} placeholder="Name for your own view" aria-label="Name for your own view" data-l4g-view-name/>
      <Button compact disabled={!kind||saving!==''} onClick={saveMine} data-l4g-save-mine><Save size={14}/>Save as my view</Button>
      {canEdit&&<Button compact disabled={saving!==''} onClick={updateView} data-l4g-update>{view.scope==='shared'?'Update shared view':'Update my view'}</Button>}
      {canEdit&&view.scope==='personal'&&<Button compact disabled={saving!==''} onClick={archive} data-l4g-archive>Remove my view</Button>}
      {view?.scope==='shared'&&!vs?.can_edit_shared&&<small className="l4g-muted" data-l4g-shared-note>Shared views are changed by a Platform Admin.</small>}
    </div>
    {note&&<p className="l4g-note" role="status">{note}</p>}
    {err&&<p className="l4g-err" role="alert">{err}</p>}
    {!kind?<EmptyInline text="Choose a view or a kind to see its items."/>:<>
      <p className="l4g-count" data-l4g-total>{data?`${fmtNumber(data.total)} waiting · ${data.kind_label||kind}${cty?` · ${cty}`:''}${ptype?` · ${(TYPE_PILLS.find(x=>x[0]===ptype)||[])[1]||ptype}`:''}`:'Loading…'}</p>
      <DataTable tableId="l4-grid" rows={(data?.rows||[]).map(r=>({...r,id:`${r.kind}:${r.ref}`}))} columns={columns} loading={loading} onRow={r=>setOpen(r)} selected={open?`${open.kind}:${open.ref}`:undefined} cellOf={(r,k)=>r[k]??'—'}/>
      {data&&Number(data.total)>Number(data.limit)&&<Pager offset={offset} limit={Number(data.limit)} total={Number(data.total)} onOffset={o=>{setOffset(o);load(o)}}/>}
    </>}
    {open&&<Drawer nav={nav} target={{kind:open.kind,ref:open.ref,subject:open.subject}} kinds={kinds} targetDays={targetDays} renderItem={renderItem} onClose={()=>setOpen(null)} onDecided={r=>{onDecided?.(r);setCohort({});load(offset)}}/>}
  </div>}
