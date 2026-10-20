// CF-247 v2.15.300 (Platform Admin, 20 Oct 2026 10:35: "suggest not used navigation items ... Suggest tabs and nav items that can retire"):
// Platform health › Screen use. Every page and tab of the menu with how often people opened it over the window (setting
// usage.screen_window_days), from public.admin_screen_usage; those not opened at all are listed first, as candidates to retire.
// Counting started with v2.15.300 (20 Oct 2026); before that only API logs were available.
import React,{useEffect,useMemo,useState}from'react'
import{Eye}from'lucide-react'
import{supabase}from'./lib/supabase'
import{PAGES,SECTIONS,shownTabs}from'./nav-map'
import{Loading,SectionTitle,StatusChip,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'

export default function ScreenUse({onError}){
  const[d,setD]=useState(null)
  useEffect(()=>{supabase.rpc('admin_screen_usage',{p_days:null}).then(({data,error})=>{if(error)throw error;setD(data||{})}).catch(e=>onError?.(e.message))},[])
  const rows=useMemo(()=>{if(!d)return[];const use=Object.fromEntries((d.rows||[]).map(r=>[`${r.page}|${r.tab}`,r]));const out=[]
    for(const s of SECTIONS)for(const k of s.pages){const p=PAGES[k];if(!p)continue;const tabs=shownTabs(p,6)
      if(!tabs.length)out.push({section:s.label,page:k,tab:'',label:p.label,u:use[`${k}|`]})
      else tabs.forEach(t=>out.push({section:s.label,page:k,tab:t.key,label:`${p.label} › ${t.label}`,u:use[`${k}|${t.key}`]||(t===tabs[0]?use[`${k}|`]:null)}))}
    return out.sort((a,b)=>Number(a.u?.opens||0)-Number(b.u?.opens||0)||a.label.localeCompare(b.label))},[d])
  if(!d)return <section className="m-panel"><Loading label="Reading screen use…"/></section>
  const none=rows.filter(r=>!r.u).length
  return <section className="m-panel" data-screen-use>
    <SectionTitle icon={Eye} title="Screen use" subtitle={`Opens of each page and tab by signed-in people over the last ${fmtNumber(d.days)} days${d.since?`, counted since ${fmtDate(d.since)}`:''}. Not opened at all: ${fmtNumber(none)}, listed first; candidates to retire.`}/>
    <div className="cf-table-wrap"><table className="cf-table" data-screen-use-table><thead><tr><th>Page and tab</th><th>Menu group</th><th className="num">Opens</th><th className="num">People</th><th className="num">Days used</th><th>Last opened</th></tr></thead><tbody>
      {rows.map(r=><tr key={`${r.page}|${r.tab}`} data-screen-use-row={`${r.page}|${r.tab}`}><td>{r.label}</td><td><small>{r.section||'—'}</small></td>
        <td className="num">{r.u?fmtNumber(r.u.opens):<StatusChip tone="warning" label="Not opened"/>}</td><td className="num">{r.u?fmtNumber(r.u.people):'—'}</td><td className="num">{r.u?fmtNumber(r.u.days_used):'—'}</td><td>{r.u?fmtDateTime(r.u.last_at):'—'}</td></tr>)}
    </tbody></table></div>
  </section>
}
