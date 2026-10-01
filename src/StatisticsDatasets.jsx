// Rankings & statistics › Datasets (v2.15.131, screen review ds-blank). Replaces the panel that a separate script
// injected into an empty box (it showed nothing when the read failed). Lists every dataset, whether it is shown on
// Rankings & statistics, and links to its imports. Adding a dataset starts it hidden.
// Read: public.statistics_dataset_registry_read(); write: public.statistics_dataset_registry_write(p_dataset)
// (both server-checked; unchanged).
import React,{useEffect,useState}from'react'
import{BarChart3,Plus,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip}from'./ui-kit'

const TYPE={statistics:'Statistics',ranking:'Ranking',index:'Index'}
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')

export default function StatisticsDatasets({rank=0}){
  const[rows,setRows]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(''),[adding,setAdding]=useState(false)
  const[f,setF]=useState({dataset_key:'',label:'',dataset_type:'statistics',description:'',source_authority:''})
  const load=async()=>{setErr('');try{const{data,error}=await supabase.rpc('statistics_dataset_registry_read');if(error)throw error;setRows(Array.isArray(data)?data:[])}catch(e){setErr(errText(e));setRows(r=>r||[])}}
  useEffect(()=>{load()},[])
  const save=async(item,key)=>{setBusy(key);setErr('');try{const{error}=await supabase.rpc('statistics_dataset_registry_write',{p_dataset:item});if(error)throw error;await load();return true}catch(e){setErr(errText(e));return false}finally{setBusy('')}}
  const add=async e=>{e.preventDefault();const key=f.dataset_key.trim().toLowerCase().replace(/[^a-z0-9_]+/g,'_')
    if(!key||!f.label.trim())return setErr('Give the dataset a short key and a name.')
    if(await save({...f,dataset_key:key,label:f.label.trim(),display_enabled:false,display_order:100,compare_enabled:true},'add')){setAdding(false);setF({dataset_key:'',label:'',dataset_type:'statistics',description:'',source_authority:''})}}
  const can=rank>=4
  if(rows===null)return <Loading label="Loading datasets…"/>
  return <div className="m-page-stack"><section className="m-panel" data-stat-datasets>
    <SectionTitle icon={BarChart3} title="Datasets" subtitle="Statistics and rankings the platform holds. Choose which ones appear on Rankings & statistics; files are imported on Reference data › Ranking imports." action={<div className="sd-actions"><Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>{can&&<Button compact onClick={()=>setAdding(x=>!x)}><Plus size={14}/>Add dataset</Button>}</div>}/>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {adding&&<form className="sd-add" onSubmit={add} data-add-dataset>
      <label><small>Name</small><input className="fv-input" value={f.label} onChange={e=>setF({...f,label:e.target.value})} aria-label="Dataset name"/></label>
      <label><small>Short key</small><input className="fv-input" value={f.dataset_key} onChange={e=>setF({...f,dataset_key:e.target.value})} placeholder="e.g. arwu" aria-label="Short key"/></label>
      <label><small>Type</small><select className="fv-input" value={f.dataset_type} onChange={e=>setF({...f,dataset_type:e.target.value})} aria-label="Type">{Object.entries(TYPE).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
      <label><small>Published by</small><input className="fv-input" value={f.source_authority} onChange={e=>setF({...f,source_authority:e.target.value})} aria-label="Published by"/></label>
      <label className="sd-wide"><small>What it is</small><input className="fv-input" value={f.description} onChange={e=>setF({...f,description:e.target.value})} aria-label="What it is"/></label>
      <div className="sd-form-actions"><Button type="submit" disabled={busy==='add'}>Add dataset</Button><Button type="button" onClick={()=>setAdding(false)}>Cancel</Button><small>New datasets start hidden.</small></div>
    </form>}
    {rows.length===0?<Empty text="No datasets yet."/>:<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Dataset</th><th>Type</th><th>Published by</th><th>On Rankings & statistics</th><th>Imports</th></tr></thead>
      <tbody>{rows.map(x=><tr key={x.dataset_key} data-dataset={x.dataset_key}><td><strong>{x.label}</strong><small className="sd-desc">{x.description}</small></td><td>{TYPE[x.dataset_type]||x.dataset_type}</td><td>{x.source_authority||'—'}</td>
        <td>{can?<label className="sd-toggle"><input type="checkbox" checked={Boolean(x.display_enabled)} disabled={busy===x.dataset_key} onChange={e=>save({...x,display_enabled:e.target.checked},x.dataset_key)} aria-label={`Show ${x.label} on Rankings & statistics`}/>{x.display_enabled?'Shown':'Hidden'}</label>
          :<StatusChip value={x.display_enabled?'on':'off'} tone={x.display_enabled?'success':'neutral'} label={x.display_enabled?'Shown':'Hidden'}/>}</td>
        <td>{x.admin_import_system?<a href={`#reference-data?tab=imports&system=${encodeURIComponent(x.admin_import_system)}`}>Ranking imports</a>:'—'}</td></tr>)}</tbody></table></div>}
  </section></div>
}
