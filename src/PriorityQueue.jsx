// Priority queue (v2.15.113): the order in which the page reader and the Layer 3 AI checks take work. Platform Admin
// request, 30 Sep 2026: move universities or courses up or down, and add a country, state or university to the front.
// Order = pinned courses, then pinned universities / states / countries in pin order, then Australian providers by
// number of active courses. Read: public.admin_priority_read(), public.admin_priority_search(kind, q); write:
// public.admin_priority_control(action, args), Platform Admin (migration 20260930100000_cf247_priority_queue).
import React,{useEffect,useRef,useState}from'react'
import{ArrowDown,ArrowUp,ListOrdered,Plus,RefreshCw,Search,Trash2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'

export const KIND_LABEL={provider:'University',state:'State',country:'Country',course:'Course'}
const WHY={provider:'Pinned university',state:'Pinned state',country:'Pinned country'}
const ACTION={add:'Added',remove:'Removed',move:'Moved'}

export default function PriorityQueue({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_priority_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(action,args,confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_priority_control',{p_action:action,p_args:args});if(error)throw error;setData(d||{})}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading the priority queue…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`The priority queue could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const pins=data.pins||[],ranking=data.ranking||[],can=Boolean(data.can_control)&&!busy
  const pinnedProvider=new Set(pins.filter(p=>p.kind==='provider').map(p=>p.target_id))
  return <>
    <section className="m-panel">
      <SectionTitle icon={ListOrdered} title="Priority queue" subtitle="The page reader and the AI checks take work in this order: pinned courses first, then pinned universities, states and countries in the order below, then the largest Australian providers." action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button>}/>
      {!data.can_control&&<p className="l3v-note">You can view the queue. Only a Platform Admin can change it.</p>}
      {data.can_control&&<AddPin data={data} can={can} act={act} onError={onError}/>}
    </section>
    <section className="m-panel">
      <SectionTitle title="Pinned to the front" subtitle={pins.length?`${pins.length} pinned. Top of the list goes first.`:'Nothing pinned. Work follows provider size.'}/>
      {pins.length>0&&<div className="cf-table-wrap"><table className="cf-table pq-pins"><thead><tr><th className="num">#</th><th>Type</th><th>Name</th><th className="num">Courses</th><th>Added</th>{data.can_control&&<th>Change</th>}</tr></thead><tbody>
        {pins.map((p,i)=><tr key={p.id} data-pin={p.kind}>
          <td className="num">{i+1}</td>
          <td><StatusChip value={p.kind} tone={p.kind==='course'?'violet':'info'} label={KIND_LABEL[p.kind]||p.kind}/></td>
          <td><strong>{p.label}</strong>{p.detail&&<span className="l3v-code">{p.detail}</span>}</td>
          <td className="num">{fmtNumber(p.courses||0)}</td>
          <td><span className="l3v-code">{fmtDateTime(p.at)}</span></td>
          {data.can_control&&<td><div className="l3c-row-actions">
            <Button compact onClick={()=>act('move',{id:p.id,direction:'up'})} disabled={!can||i===0} aria-label={`Move ${p.label} up`}><ArrowUp size={14}/></Button>
            <Button compact onClick={()=>act('move',{id:p.id,direction:'down'})} disabled={!can||i===pins.length-1} aria-label={`Move ${p.label} down`}><ArrowDown size={14}/></Button>
            <Button compact variant="danger" onClick={()=>act('remove',{id:p.id},`Remove ${p.label} from the priority list?`)} disabled={!can} aria-label={`Remove ${p.label}`}><Trash2 size={14}/></Button>
          </div></td>}
        </tr>)}
      </tbody></table></div>}
    </section>
    <section className="m-panel">
      <SectionTitle title="Current order" subtitle="The first 60 providers as the queue takes them, with how many of their course pages are matched and how many are still waiting to be read."/>
      <div className="cf-table-wrap"><table className="cf-table pq-order"><thead><tr><th className="num">Order</th><th>Provider</th><th>Why here</th><th className="num">Courses</th><th className="num">Pages matched</th><th className="num">Pages waiting</th>{data.can_control&&<th>Change</th>}</tr></thead><tbody>
        {ranking.length?ranking.map(r=><tr key={r.provider_id} data-provider={r.provider_id}>
          <td className="num">{r.rank}</td>
          <td><strong>{r.name}</strong><span className="l3v-code">{[r.state,r.country].filter(Boolean).join(' · ')}</span></td>
          <td>{r.pinned_by?<StatusChip value="pinned" tone="info" label={WHY[r.pinned_by]||'Pinned'}/>:<span className="l3v-code">By size</span>}</td>
          <td className="num">{fmtNumber(r.courses||0)}</td>
          <td className="num">{fmtNumber(r.pages_matched||0)}<span className="l3v-code">{r.courses?`${Math.round(100*Number(r.pages_matched||0)/Number(r.courses))}%`:''}</span></td>
          <td className="num">{fmtNumber(r.pages_waiting||0)}</td>
          {data.can_control&&<td>{pinnedProvider.has(r.provider_id)?<span className="l3v-code">Pinned</span>
            :<Button compact onClick={()=>act('add',{kind:'provider',target_id:r.provider_id,top:true})} disabled={!can} aria-label={`Move ${r.name} to the front`}><ArrowUp size={14}/>To the front</Button>}</td>}
        </tr>):<tr><td colSpan={7} className="cf-empty-cell">No providers ranked yet.</td></tr>}
      </tbody></table></div>
    </section>
    {(data.events||[]).length>0&&<section className="m-panel"><SectionTitle title="Recent changes"/>
      <ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{ACTION[e.action]||e.action}</strong><small>{[KIND_LABEL[e.detail?.kind],e.target,e.detail?.direction&&`moved ${e.detail.direction}`].filter(Boolean).join(' · ')}</small></li>)}</ul></section>}
  </>
}

function AddPin({data,can,act,onError}){
  const[kind,setKind]=useState('provider'),[q,setQ]=useState(''),[hits,setHits]=useState([]),[pick,setPick]=useState(''),[top,setTop]=useState(false),[searching,setSearching]=useState(false)
  const timer=useRef(null)
  useEffect(()=>{setHits([]);setPick('');setQ('')},[kind])
  useEffect(()=>{
    if(!['provider','course'].includes(kind))return
    clearTimeout(timer.current)
    if(q.trim().length<2){setHits([]);return}
    timer.current=setTimeout(async()=>{setSearching(true);try{const{data:d,error}=await supabase.rpc('admin_priority_search',{p_kind:kind,p_q:q.trim()});if(error)throw error;setHits(d||[])}catch(e){onError?.(e.message||String(e))}finally{setSearching(false)}},300)
    return()=>clearTimeout(timer.current)
  },[q,kind])
  const add=target=>{if(target)act('add',{kind,target_id:target,top});setPick('');setQ('');setHits([])}
  const list=kind==='state'?data.states||[]:kind==='country'?data.countries||[]:[]
  return <div className="pq-add">
    <label><small>Add to the front</small><select className="fv-filter" value={kind} onChange={e=>setKind(e.target.value)} aria-label="What to prioritise" disabled={!can}>
      <option value="provider">University or provider</option><option value="state">State</option><option value="country">Country</option><option value="course">Single course</option></select></label>
    {['state','country'].includes(kind)?<label className="pq-grow"><small>{kind==='state'?'State':'Country'}</small><select className="fv-filter" value={pick} onChange={e=>setPick(e.target.value)} aria-label={kind==='state'?'State':'Country'} disabled={!can}>
        <option value="">Choose…</option>{list.map(x=><option key={x.id} value={x.id}>{x.name}{x.country?` (${x.country})`:''}</option>)}</select></label>
      :<label className="pq-grow"><small>{kind==='course'?'Course name or CRICOS code':'University name'}</small><span className="pq-search"><Search size={14}/><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder={kind==='course'?'e.g. 083765J or Master of Nursing':'e.g. Monash'} aria-label={kind==='course'?'Find a course':'Find a university'} disabled={!can}/></span></label>}
    <label className="pq-top"><input type="checkbox" checked={top} onChange={e=>setTop(e.target.checked)} disabled={!can}/><span>Put at the very top</span></label>
    {['state','country'].includes(kind)&&<Button compact variant="primary" onClick={()=>add(pick)} disabled={!can||!pick}><Plus size={14}/>Add</Button>}
    {['provider','course'].includes(kind)&&(hits.length>0||searching)&&<ul className="pq-hits" aria-label="Search results">
      {searching&&!hits.length&&<li><span className="l3v-code">Searching…</span></li>}
      {hits.map(h=><li key={h.id}><div><strong>{h.label}</strong><span className="l3v-code">{h.detail}</span></div><Button compact variant="primary" onClick={()=>add(h.id)} disabled={!can} aria-label={`Add ${h.label}`}><Plus size={14}/>Add</Button></li>)}
    </ul>}
  </div>
}
