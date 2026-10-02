// Layer 4 › Websites to find (Decision 222, v2.15.149). Universities whose own website the finder could not confirm
// (it searched by name and checked the CRICOS or DLI number, or the name on a .ca home page). A person enters the
// website here; it is saved as entered by hand (locked against automation and logged, like the provider editor), the
// site is mapped, the generic course-page recipe is added and the course-page search starts.
// Read: public.admin_provider_websites(args); write: public.admin_provider_website_set(provider, url), Curator and above
// (migration 20261002182000_cf247_fetch_area_sweep_websites).
import React,{useEffect,useState}from'react'
import{Check,Globe,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

export default function WebsitesToFind({onError}){
  const[data,setData]=useState(null),[country,setCountry]=useState(''),[busy,setBusy]=useState(false),[val,setVal]=useState({}),[done,setDone]=useState('')
  const load=async(c=country)=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_provider_websites',{p_args:{country:c||null,limit:200}});if(error)throw error;setData(d||{})}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load(country)},[country])
  const save=async it=>{const url=String(val[it.provider_id]||'').trim();if(!url)return;setBusy(true);setDone('')
    try{const{data:d,error}=await supabase.rpc('admin_provider_website_set',{p_provider_id:it.provider_id,p_url:url});if(error)throw error;setDone(`${it.name}: website saved. The sweep maps the site and searches for its course pages.`);setVal(v=>({...v,[it.provider_id]:''}));setData(d||{})}
    catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  if(!data)return <section className="m-panel"><Loading label="Loading websites to find…"/></section>
  const items=(data.items||[]).filter(i=>!country||i.country===country),cs=Object.entries(data.countries||{})
  return <section className="m-panel" data-websites-to-find>
    <SectionTitle icon={Globe} title="Websites to find" subtitle="The website finder could not confirm these universities’ own sites, so their course pages cannot be found. Check what was tried, find the university’s official website, and enter it." action={<div className="l3c-actions">
      <select className="fv-filter" value={country} onChange={e=>setCountry(e.target.value)} aria-label="Country"><option value="">All countries ({fmtNumber(cs.reduce((t,[,n])=>t+Number(n),0))})</option>{cs.map(([c,n])=><option key={c} value={c}>{c} ({fmtNumber(n)})</option>)}</select>
      <Button compact onClick={()=>load()} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>}/>
    <p className="l3v-note">Enter the university’s main website (for example https://www.example.edu.au). It is saved as entered by a person, so automation never changes it. Courses then join the sweep within minutes.</p>
    {done&&<p className="sb-done" role="status">{done}</p>}
    {items.length?<div className="cf-table-wrap"><table className="cf-table wtf-table"><thead><tr><th>University</th><th className="num">Courses</th><th>What was tried</th><th>Website</th></tr></thead><tbody>
      {items.map(it=><tr key={it.provider_id} data-website-row={it.provider_id}>
        <td><strong>{it.name}</strong><span className="l3v-code">{[it.country,it.cricos&&`CRICOS ${it.cricos}`,it.dli&&`DLI ${it.dli}`].filter(Boolean).join(' · ')}</span><span className="l3v-code">Searched {fmtDateTime(it.searched_at)}</span></td>
        <td className="num">{fmtNumber(it.courses)}</td>
        <td>{it.note?<span className="l3v-code">{it.note}</span>:null}{it.query&&<span className="l3v-code">Search: “{it.query}”</span>}
          {(it.tried||[]).length?<ul className="wtf-tried">{it.tried.slice(0,6).map((u,i)=><li key={i}><a href={u} target="_blank" rel="noreferrer">{u}</a></li>)}</ul>:<span className="l3v-code">No pages were opened.</span>}</td>
        <td><div className="wtf-edit"><input className="fv-input" type="url" placeholder="https://…" value={val[it.provider_id]||''} onChange={e=>setVal(v=>({...v,[it.provider_id]:e.target.value}))} aria-label={`Website for ${it.name}`}/>
          <Button compact variant="primary" disabled={busy||!String(val[it.provider_id]||'').trim()} onClick={()=>save(it)}><Check size={14}/>Save</Button></div></td></tr>)}
    </tbody></table></div>:<Empty text="Every university in the sweep has a website."/>}
  </section>
}
