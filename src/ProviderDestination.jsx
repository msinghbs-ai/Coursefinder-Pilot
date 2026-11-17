// CF-247 RM0F (Platform Admin 17 Nov 2026 13:12; decision G-5): two cards in the provider summary. Campuses: the primary campus and the locality each
// campus postcode maps to (the same value API v3 provider sends as campuses[].locality), or that it waits in Layer 4. Registrations: one line per
// scheme the provider holds; a Canadian DLI number is a provider registration, and PGWP is a programme's work eligibility shown apart, never as a DLI.
// Read only: public.admin_provider_destination_read (any StudySearch role).
import React,{useEffect,useState}from'react'
import{StatusChip}from'./ui-kit'
import{supabase}from'./lib/supabase'
function FactCard({label,value,sub,children,id}){return <div className="ds-card wide" data-ds-card={id||label}><small>{label}</small>{value!=null&&<strong>{value}</strong>}{children&&<div className="ds-card-body">{children}</div>}{sub&&<span className="ds-sub">{sub}</span>}</div>}
export default function ProviderDestination({providerId,client=null}){
  const[d,setD]=useState(null)
  useEffect(()=>{if(!providerId)return;let live=true
    const call=client?client('admin_provider_destination_read',{p_provider_id:providerId}):supabase.rpc('admin_provider_destination_read',{p_provider_id:providerId})
    Promise.resolve(call).then(({data,error})=>{if(live&&!error)setD(data)}).catch(()=>{});return()=>{live=false}},[providerId])
  if(!d?.found)return null
  const cs=d.campuses||[],regs=d.registrations||[],we=d.work_eligibility,mapped=cs.filter(c=>c.locality).length
  return <>
    <FactCard id="campus-localities" label="Campuses and localities" value={cs.length?`${mapped} of ${cs.length} mapped to a locality`:'No campus held'}
      sub="API v3 provider sends the mapped locality as campuses[].locality. A postcode below the match share waits in Layer 4 Review › Inbox › Campus locality.">
      {cs.length>0&&<span className="ds-pill-list" data-provider-campus-localities>{cs.map(c=><StatusChip key={c.campus_id} tone={c.locality?'success':c.in_layer4?'warning':'neutral'}
        label={`${c.name||c.city||'Campus'}${c.is_primary?' · Primary campus':''}${c.postcode?` · ${c.postcode}`:''} · ${c.locality?`${c.locality.name} ${Math.round(Number(c.locality.match_share)*100)}%`:c.in_layer4?'in Layer 4':c.pending_locality?`${c.pending_locality} (not approved yet)`:'no locality'}`}
        title={c.is_primary&&c.primary_basis?`Primary campus by ${String(c.primary_basis).replaceAll('_',' ')}`:undefined}/>)}</span>}
    </FactCard>
    <FactCard id="provider-registrations" label="Provider registrations" value={regs.length?`${[...new Set(regs.map(r=>r.scheme))].length} scheme${[...new Set(regs.map(r=>r.scheme))].length===1?'':'s'}`:'None held'}
      sub={we?.courses?`Work eligibility, shown apart: ${we.label||'PGWP'} on ${we.courses} programme${we.courses===1?'':'s'}. It is never a provider registration.`:'Each scheme is listed on its own; schemes are never merged.'}>
      {regs.length>0&&<span className="ds-pill-list" data-provider-registrations>{regs.map((r,i)=><StatusChip key={i} tone={r.status==='active'?'neutral':'danger'}
        label={`${r.label||String(r.scheme).toUpperCase()} ${r.code}${r.status!=='active'?` (${r.status})`:''}`} title={[r.authority,(r.never_mixed_with||[]).length?`never mixed with ${r.never_mixed_with.join(', ')}`:null].filter(Boolean).join(' · ')}/>)}</span>}
    </FactCard>
  </>
}
