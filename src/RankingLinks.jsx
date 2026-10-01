// Decision 208: QS and THE universities linked to providers.
// RankingLinkPicker — for a ranked university with no provider: the candidates the linking rules offered (same
// country, most words in common) and a provider search; Link applies to every edition, Not this one rejects a
// candidate. Curator and above (public.admin_ranking_link). ProviderRankings — the provider record's QS and THE
// history by edition (read: provider_ranking_history).
import React,{useEffect,useState}from'react'
import{Check,Link2,Search,Trophy,X}from'lucide-react'
import{api}from'./lib/supabase'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const SYSTEM_LABEL={qs_wur:'QS World University Rankings',the_wur:'Times Higher Education'}

export function RankingLinkPicker({row,onLinked,onClose}){
  const[cands,setCands]=useState(null),[q,setQ]=useState(''),[found,setFound]=useState([]),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  useEffect(()=>{api.rankingLinkCandidates(row.publisher_institution_id).then(d=>setCands(d?.items||[])).catch(e=>setErr(errText(e)))},[row.publisher_institution_id])
  useEffect(()=>{if(q.trim().length<3){setFound([]);return}let live=true;const t=setTimeout(()=>api.rankingProviderSearch({query:q.trim(),country:row.country_text}).then(d=>live&&setFound(d?.items||[])).catch(e=>live&&setErr(errText(e))),250);return()=>{live=false;clearTimeout(t)}},[q,row.country_text])
  const act=async(action,p)=>{
    if(action==='link'&&!window.confirm(`Link "${row.publisher_institution_name}" to ${p.provider_name}? Every edition of this university in this ranking will show under that provider.`))return
    setBusy(true);setErr('')
    try{await api.rankingLink({publisherInstitutionId:row.publisher_institution_id,action,providerId:p.provider_id});if(action==='link')onLinked?.();else setCands(c=>(c||[]).filter(x=>x.provider_id!==p.provider_id))}
    catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const item=(p,isCand)=><li key={p.provider_id} data-candidate={isCand?p.provider_id:undefined}>
    <span>{p.provider_name}{p.state&&<small> · {p.state.replace(/^[A-Z]{2}-/,'')}</small>}{isCand&&p.confidence!=null&&<small> · {Math.round(Number(p.confidence)*100)}% of words in common</small>}</span>
    <span className="rl-actions"><button type="button" className="m-secondary compact" disabled={busy} onClick={()=>act('link',p)}><Check size={12}/>Link</button>
      {isCand&&<button type="button" className="m-secondary compact" disabled={busy} onClick={()=>act('reject',p)}><X size={12}/>Not this one</button>}</span></li>
  return <div className="rl-picker" data-ranking-link-picker>
    <div className="rl-head"><b>Link to a provider in {row.country_text||'the same country'}</b><button type="button" className="m-link-button" onClick={onClose} aria-label="Close"><X size={14}/></button></div>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {cands===null?<small>Loading suggestions…</small>:cands.length?<><small>Suggested (same country, most words in common):</small><ul>{cands.map(p=>item(p,true))}</ul></>:<small>No suggestions. Search for the provider below.</small>}
    <label className="m-searchbox rl-search"><Search size={14}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search providers by name (3+ letters)…" aria-label="Search providers to link"/></label>
    {found.length>0&&<ul>{found.map(p=>item(p,false))}</ul>}
  </div>
}

export function ProviderRankings({providerId,navigate}){
  const[items,setItems]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{if(!providerId)return;api.providerRankingHistory(providerId).then(d=>setItems(d?.items||[])).catch(e=>setErr(errText(e)))},[providerId])
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!items)return null
  const bySystem=['qs_wur','the_wur'].map(code=>({code,rows:items.filter(x=>x.system_code===code)}))
  return <section className="rl-provider" data-provider-rankings>
    <h4><Trophy size={14}/>World rankings</h4>
    {!items.length?<small>This provider is not linked to a QS or THE ranking. Universities are linked on Rankings & statistics.</small>:
    <div className="rl-grid">{bySystem.map(s=><div key={s.code} data-system={s.code}><b>{SYSTEM_LABEL[s.code]}</b>
      {s.rows.length?<table className="cf-table"><thead><tr><th>Edition</th><th>Rank</th><th>Score</th></tr></thead><tbody>{s.rows.slice(0,6).map(r=><tr key={r.edition_year+r.publisher_name}>
        <td>{r.edition_year}</td><td>{r.rank_display||r.rank_exact||'—'}</td><td>{r.overall_score??'—'}</td></tr>)}</tbody></table>:<small>Not ranked</small>}
      {s.rows.length>0&&<button type="button" className="m-link-button" onClick={()=>navigate?.('Statistics & Rankings',{dataset:s.code,year:s.rows[0].edition_year})}><Link2 size={12}/>Open {s.code==='qs_wur'?'QS':'THE'} {s.rows[0].edition_year}</button>}
    </div>)}</div>}
  </section>
}
