// CF-247 UI audit Phase 5, first slice (Platform Admin 18 Nov 2026 09:30 and 10:09; decisions of 16 Nov 2026 05:12): Layer 4 Review › Review grid.
// One grid over the items that wait for a person (the same items as Layer 4 › Inbox), with saved filter views and the Source quote vs extracted
// value drawer. Shared views (AER Audit Samples, Official URLs, Provider Blockers) are seen by everyone here and changed only by a Platform Admin,
// with a reason; personal views are the owner's alone. A view only filters what is shown. Decisions are still taken in the Inbox: the drawer opens
// the item there. Everything is read and kept through public.admin_review_grid; page sizes are settings (Settings › Pipeline settings › Layer 4).
import React,{useCallback,useEffect,useMemo,useState}from'react'
import{Archive,BookmarkPlus,ExternalLink,Filter,Quote,Search,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{DataTable}from'./DataTable'
import{Pager,humanLabel}from'./ui-kit'
import{fmtNumber}from'./lib/format'
import'./layer4-review-grid.css'

const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_review_grid',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
const when=v=>{if(!v)return'—';const d=new Date(v);return Number.isNaN(d.getTime())?String(v):d.toLocaleString('en-AU',{day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'})}
const short=(s,n=140)=>{const t=String(s??'');return t.length>n?t.slice(0,n-1)+'…':t||'—'}
export const inboxHref=it=>{const p=new URLSearchParams();if(it?.kind)p.set('kind',it.kind);if(it?.provider_id)p.set('provider',it.provider_id);if(it?.ref)p.set('ref',it.ref);if(it?.created_at)p.set('review_at',it.created_at);return `#layer-4-review?${p.toString()}`}
const valueText=v=>{if(v==null||v==='')return'—';if(typeof v!=='object')return String(v);return Object.entries(v).filter(([,x])=>x!=null&&typeof x!=='object').map(([k,x])=>`${humanLabel(k)}: ${x}`).join(' · ')||'Structured value (see the Inbox)'}

export default function Layer4ReviewGrid({onError}){
  const[meta,setMeta]=useState(null),[viewId,setViewId]=useState(''),[kind,setKind]=useState(''),[q,setQ]=useState(''),[qd,setQd]=useState(''),[older,setOlder]=useState('')
  const[data,setData]=useState(null),[offset,setOffset]=useState(0),[sort,setSort]=useState(''),[dir,setDir]=useState(''),[open,setOpen]=useState(null),[saving,setSaving]=useState(null),[note,setNote]=useState('')
  const loadViews=useCallback(()=>call('views').then(m=>{setMeta(m);setViewId(v=>v||m.views?.[0]?.id||'')}).catch(e=>onError?.(e.message)),[onError])
  useEffect(()=>{loadViews()},[loadViews])
  useEffect(()=>{const t=setTimeout(()=>setQd(q.trim()),350);return()=>clearTimeout(t)},[q])
  const view=meta?.views?.find(v=>v.id===viewId)||null
  const filters=useMemo(()=>({...(kind?{kinds:[kind]}:{}),...(qd?{q:qd}:{}),...(older?{older_than_days:Number(older)}:{})}),[kind,qd,older])
  useEffect(()=>{setOffset(0)},[viewId,kind,qd,older,sort,dir])
  useEffect(()=>{if(!meta)return;let live=true;setData(d=>d?{...d,loading:true}:null)
    call('rows',{...(viewId?{view_id:viewId}:{}),filters,offset,...(sort?{sort,direction:dir||'asc'}:{})}).then(d=>live&&setData(d)).catch(e=>{if(live){setData({rows:[],total:0});onError?.(e.message)}})
    return()=>{live=false}},[meta,viewId,filters,offset,sort,dir,onError])
  const onSort=k=>{if(sort===k||(!sort&&data?.sort===k))setDir((dir||data?.direction)==='asc'?'desc':'asc');else{setSort(k);setDir('asc')}}
  const kinds=meta?.kinds||[]
  const columns=[
    {key:'subject',label:'Item',width:260,sortKey:'subject',render:r=><span className="l4g-subject"><strong>{short(r.subject,90)}</strong><small>{r.kind_label}</small></span>},
    {key:'provider',label:'University',width:200,sortKey:'provider',render:r=>short(r.provider,60)},
    {key:'why',label:'Why it waits',width:300,render:r=><span className="l4g-why" title={r.why||''}>{short(r.why)}</span>},
    {key:'quotes',label:'Quotes',width:80,render:r=>Number(r.quotes)>0?<span className="l4g-q"><Quote size={12}/>{fmtNumber(r.quotes)}</span>:<span className="l4g-muted">none</span>},
    {key:'created_at',label:'Waiting since',width:150,sortKey:'created_at',render:r=><span title={when(r.created_at)}>{when(r.created_at)}<small className="l4g-age">{fmtNumber(r.age_days)} d</small></span>},
    {key:'kind',label:'Kind',width:140,sortKey:'kind',render:r=>r.kind_label}]
  const rows=(data?.rows||[]).map(r=>({...r,id:r.key}))
  if(!meta)return <div className="l4g" data-review-grid><p className="l4g-muted" data-review-grid-loading>Loading the Review grid…</p></div>
  return <div className="l4g" data-review-grid>
    <p className="l4g-help" data-review-grid-help>Every item that waits for a person, in one list. Choose a saved view or filter the list, then open an item to see the page quote beside the value taken from it. Decisions are taken in the Inbox: <em>Open in the Inbox</em> takes you to the item. A view only filters what is shown; it never changes an item, the AER audit sample or a Layer 4 rule.</p>
    <div className="l4g-views" role="tablist" aria-label="Saved views" data-review-grid-views>
      {meta.views.map(v=><button key={v.id} type="button" role="tab" aria-selected={v.id===viewId} className={`l4g-view${v.id===viewId?' on':''}${v.scope==='shared'?' shared':''}`} onClick={()=>setViewId(v.id)} title={v.description||''} data-view-key={v.view_key||'personal'}>{v.name}{v.scope==='shared'&&<small>shared</small>}</button>)}
      <button type="button" className={`l4g-view${viewId===''?' on':''}`} role="tab" aria-selected={viewId===''} onClick={()=>setViewId('')} data-view-key="all">Everything waiting</button>
    </div>
    {view?.description&&<p className="l4g-muted" data-review-grid-view-note>{view.description}</p>}
    <div className="l4g-bar" data-review-grid-filters>
      <label><Filter size={14}/><select value={kind} onChange={e=>setKind(e.target.value)} aria-label="Kind"><option value="">Every kind</option>{kinds.map(k=><option key={k.kind} value={k.kind}>{k.label}</option>)}</select></label>
      <label className="l4g-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search title, reason or university…" aria-label="Search"/></label>
      <label><span>Waiting more than</span><select value={older} onChange={e=>setOlder(e.target.value)} aria-label="Waiting more than"><option value="">any time</option>{[1,7,14,30,90].map(d=><option key={d} value={d}>{d} days</option>)}</select></label>
      <button type="button" className="cf-btn compact" onClick={()=>setSaving({mode:'new',name:''})} data-review-grid-save><BookmarkPlus size={14}/>Save as my view</button>
      {view&&view.scope==='personal'&&<button type="button" className="cf-btn compact" onClick={()=>call('view_archive',{id:view.id}).then(()=>{setNote(`“${view.name}” archived.`);setViewId('');loadViews()}).catch(e=>onError?.(e.message))} data-review-grid-archive><Archive size={14}/>Archive this view</button>}
      {view&&view.scope==='shared'&&meta.can_edit_shared&&<button type="button" className="cf-btn compact" onClick={()=>setSaving({mode:'shared',name:view.name,reason:''})} data-review-grid-edit-shared>Update this shared view</button>}
    </div>
    {saving&&<form className="l4g-save" data-review-grid-save-form onSubmit={e=>{e.preventDefault();const base=view?.filters||{};const f={...base,...filters}
        const args=saving.mode==='shared'?{id:view.id,name:saving.name,reason:saving.reason,filters:f,sort:sort?{key:sort,direction:dir||'asc'}:view.sort}:{name:saving.name,filters:f,...(sort?{sort:{key:sort,direction:dir||'asc'}}:{})}
        call('view_save',args).then(r=>{setNote(saving.mode==='shared'?'Shared view updated.':`“${saving.name}” saved as your view.`);setSaving(null);loadViews().then(()=>r?.id&&setViewId(r.id))}).catch(err=>onError?.(err.message))}}>
      <label>Name<input value={saving.name} maxLength={80} onChange={e=>setSaving(s=>({...s,name:e.target.value}))} required aria-label="View name"/></label>
      {saving.mode==='shared'&&<label>Reason (kept with the change)<input value={saving.reason} onChange={e=>setSaving(s=>({...s,reason:e.target.value}))} required aria-label="Reason"/></label>}
      <small className="l4g-muted">{saving.mode==='shared'?'Everyone who opens the Review grid sees this view.':`Only you see your views (up to ${fmtNumber(meta.personal_max)}). The current view's filters are kept and the ones above are added.`}</small>
      <div><button type="submit" className="cf-btn primary compact">Save</button><button type="button" className="cf-btn compact" onClick={()=>setSaving(null)}>Cancel</button></div>
    </form>}
    {note&&<p className="l4g-note" role="status">{note}</p>}
    <p className="l4g-count" data-review-grid-total>{data?`${fmtNumber(Number(data.total)||0)} items`:'…'}</p>
    <DataTable tableId="layer4-review-grid" rows={rows} columns={columns} loading={!data||data.loading} sort={sort||data?.sort} direction={dir||data?.direction} onSort={onSort} onRow={r=>setOpen(r)} selected={open?.key}/>
    {data&&Number(data.total)>Number(data.page_rows||50)&&<Pager offset={offset} limit={Number(data.page_rows)||50} total={Number(data.total)||0} onOffset={setOffset}/>}
    {open&&<QuoteValueDrawer it={open} onClose={()=>setOpen(null)} onError={onError}/>}
  </div>
}

export function QuoteValueDrawer({it,onClose,onError}){
  const[d,setD]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{let live=true;setD(null);setErr('');call('drawer',{kind:it.kind,ref:it.ref}).then(x=>live&&setD(x)).catch(e=>{if(live){setErr(e.message);onError?.(e.message)}});return()=>{live=false}},[it.kind,it.ref,onError])
  useEffect(()=>{const k=e=>{if(e.key==='Escape')onClose()};addEventListener('keydown',k);return()=>removeEventListener('keydown',k)},[onClose])
  const ev=d?.evidence||{}
  return <><button className="m-drawer-backdrop" onClick={onClose} aria-label="Close"/><aside className="m-drawer l4g-drawer" aria-label="Source quote vs extracted value" data-review-grid-drawer>
    <div className="m-drawer-head"><div><small>{it.kind_label} · {it.provider||'—'}</small><h2>{short(it.subject,120)}</h2></div><button onClick={onClose} aria-label="Close"><X size={18}/></button></div>
    <div className="m-drawer-body">
      {err&&<p className="fr-error" role="alert">{err}</p>}
      {!d&&!err&&<div className="m-drawer-loading"><span className="m-spinner"/>Loading the quotes and history…</div>}
      {d&&<>
        <p className="l4g-why-full">{d.item?.why}</p>
        <section data-review-grid-pairs><h3>Source quote vs extracted value</h3>
          <p className="l4g-muted">On the left, the words saved from the page; on the right, the value taken from them. Check that the value says what the quote says.</p>
          {d.pairs?.length?<div className="l4g-pairs" role="table" aria-label="Quotes and values">
            <div className="l4g-pair head" role="row"><span role="columnheader">What the page said</span><span role="columnheader">Value taken</span></div>
            {d.pairs.map((p,i)=><div className="l4g-pair" role="row" key={i}><blockquote role="cell">“{p.quote}”</blockquote><span role="cell"><small>{humanLabel(p.label)}{p.audience&&p.audience!==p.label?` · ${humanLabel(p.audience)}`:''}</small>{p.value||'—'}</span></div>)}
            {Number(d.pairs_total)>d.pairs.length&&<p className="l4g-muted">Showing {fmtNumber(d.pairs.length)} of {fmtNumber(d.pairs_total)} quotes.</p>}
          </div>:<p className="l4g-muted" data-review-grid-no-quote>No page quote was saved for this item. The value is shown below; check it against the page.</p>}
          <dl className="l4g-value"><dt>Value proposed</dt><dd>{valueText(d.value?.proposed)}</dd>{d.value?.before!=null&&<><dt>Held before</dt><dd>{valueText(d.value.before)}</dd></>}</dl>
        </section>
        <section data-review-grid-evidence><h3>Evidence</h3>
          {ev.source_url?<p><a className="cf-link" href={ev.source_url} target="_blank" rel="noreferrer">{short(ev.source_url,90)}<ExternalLink size={12}/></a></p>:<p className="l4g-muted">No page address was saved with this item.</p>}
          {ev.captured_at&&<p className="l4g-muted">Saved copy taken {when(ev.captured_at)}{ev.newer_copy===true?' · a newer copy of this page exists':''}</p>}
        </section>
        <section data-review-grid-history><h3>Decision history</h3>
          {d.review&&<p className="l4g-muted">Item {humanLabel(d.review.status)} · waiting since {when(d.review.created_at)}{d.review.decided_at?` · decided ${when(d.review.decided_at)}`:''}</p>}
          {d.history?.length?<ol className="l4g-history">{d.history.map((h,i)=><li key={i}><strong>{h.by==='rule'?`Rule${h.rule?` ${h.rule}`:''}`:h.by==='person'?'A person':'The platform'}</strong> · {humanLabel(h.action)}{h.choice?` · ${humanLabel(h.choice)}`:''}<small>{when(h.at)}</small>{h.reason&&<p>{h.reason}</p>}</li>)}</ol>:<p className="l4g-muted">No decision has been recorded on this item yet.</p>}
        </section>
        <p><a className="cf-btn primary compact" href={inboxHref({...it,created_at:d.item?.created_at||it.created_at})} data-review-grid-open-inbox>Open in the Inbox</a></p>
      </>}
    </div>
  </aside></>
}
