// CF-247 s1286 (SS-Programme-Control "Complete existing Data Delivery integration", 27 Nov 2026 00:09 AEDT; backend s1176b): `pim.operations.consumer_fields`,
// the rotating sample read back through the reads the website and Zoho call. Drawn inside the existing "Verified consumer read-back" section of Data Delivery:
// no new screen, tab or dashboard.
// Rules: every figure counts the courses that were checked and is never a population figure. Verified counts are shown as "n of the sampled courses", the
// population is shown beside them as its own figure, and nothing is extrapolated from one to the other. A figure the backend does not record (null) is
// "Not checked" or "Not recorded", never 0. States and reasons are the backend's own words; this file only lays them out.
import React from'react'
import{StatusChip,fmtDateTime,fmtNumber,fmtRelative}from'./ui-kit'
import'./pim-jobs.css'

const has=v=>v!=null&&v!==''&&Number.isFinite(Number(v))
const word=s=>{const t=String(s||'').replaceAll('_',' ').trim();return t?t[0].toUpperCase()+t.slice(1):''}
const NotRecorded=({w='Not recorded',why})=><span className="pjm-nr" data-cs-unknown><em>{w}</em>{why&&<small>{why}</small>}</span>
// Percentage of a sample against its population: the backend's own coverage figure, shown to the precision that keeps a small sample from reading as 0.
const pct=v=>{const n=Number(v)*100;return n>=1?`${fmtNumber(Math.round(n*10)/10)}%`:n>0?`${fmtNumber(Math.round(n*100)/100)}%`:'0%'}
const days=h=>has(h)?(Number(h)%24===0?`${fmtNumber(Number(h)/24)} days`:`${fmtNumber(Number(h))} hours`):null

function Reads({checked,intl}){
  const rows=[['website','Website'],['zoho','Zoho'],['website_v3_international','Website v3, international student']].filter(([k])=>checked?.[k])
  if(!rows.length)return null
  return <div className="pjm-frame"><table className="pjm-table" data-cs-reads><thead><tr><th>Read</th><th className="pjm-num">Returned</th><th className="pjm-num">Matched the canonical value</th>{intl&&<th className="pjm-num">No domestic-only row</th>}</tr></thead><tbody>
    {rows.map(([k,l])=>{const c=checked[k];return <tr key={k} data-cs-read={k}><td data-label="Read">{l}</td><td className="pjm-num" data-label="Returned">{has(c.returned)?fmtNumber(Number(c.returned)):<NotRecorded/>}</td><td className="pjm-num" data-label="Matched">{has(c.matches)?fmtNumber(Number(c.matches)):<NotRecorded/>}</td>{intl&&<td className="pjm-num" data-label="No domestic-only row">{has(c.intl_ok)?fmtNumber(Number(c.intl_ok)):<NotRecorded/>}</td>}</tr>})}</tbody></table></div>
}

function Stream({id,s,title}){
  const pop=has(s.population)?Number(s.population):null,n=has(s.sampled_in_window)?Number(s.sampled_in_window):null
  const intlApplies=has(s.international_verified)
  const reasons=s.failures_by_reason&&typeof s.failures_by_reason==='object'?Object.entries(s.failures_by_reason).sort((a,b)=>Number(b[1])-Number(a[1])||a[0].localeCompare(b[0])):null
  const latest=Array.isArray(s.latest_failures)?s.latest_failures:null
  return <li className="pjm-cs-stream" data-cs-stream={id}>
    <div className="pjm-card-head"><strong>{title}</strong><span className="cf-badge" title="Counted on the checked courses only">Sampled</span></div>
    <dl className="pjm-cs-grid">
      <dt>Canonical population</dt><dd data-cs-population>{pop!=null?<>{fmtNumber(pop)}<small>{s.population_meaning||'courses in scope'}</small></>:<NotRecorded/>}</dd>
      <dt>Sampled coverage</dt><dd data-cs-coverage>{n!=null&&pop!=null?<>{fmtNumber(n)} of {fmtNumber(pop)} courses{has(s.coverage_in_window)&&<> ({pct(s.coverage_in_window)})</>}<small>checked in the last {days(s.window_hours)||'window'}{has(s.sampled_ever)?`; ${fmtNumber(Number(s.sampled_ever))} ever checked`:''}. A sample, not the population.</small></>:<NotRecorded/>}</dd>
      <dt>Verified delivery</dt><dd data-cs-delivery>{has(s.delivery_verified)&&n!=null?<>{fmtNumber(Number(s.delivery_verified))} of the {fmtNumber(n)} sampled courses<small>the website and Zoho both returned the value and it matched. This says nothing about the other {pop!=null?fmtNumber(Math.max(pop-n,0)):''} courses.</small></>:<NotRecorded/>}</dd>
      <dt>International applicability</dt><dd data-cs-intl>{intlApplies&&n!=null?<>{fmtNumber(Number(s.international_verified))} of the {fmtNumber(n)} sampled courses<small>no domestic-only entry row reached an international student.</small></>:<NotRecorded w="Not checked" why="The backend records no international check for this stream."/>}</dd>
      <dt>Last verification</dt><dd data-cs-last>{s.last_checked?<>{fmtDateTime(s.last_checked)}<small>{fmtRelative(s.last_checked)}{s.oldest_check_in_window?`; oldest in the window ${fmtDateTime(s.oldest_check_in_window)}`:''}{has(s.avg_seconds_per_course)?`; about ${fmtNumber(Math.round(Number(s.avg_seconds_per_course)*10)/10)} s a course`:''}</small></>:<NotRecorded w="Never checked"/>}</dd>
      <dt>Failures</dt><dd data-cs-failures>{reasons==null?<NotRecorded/>:reasons.length===0?<>None in the sample<small>{has(s.with_failure)?`${fmtNumber(Number(s.with_failure))} sampled courses with a failure`:'measured: none'}</small></>
        :<><span className="pjm-outs">{reasons.map(([r,c])=><StatusChip key={r} tone="danger" label={`${word(r)}: ${fmtNumber(Number(c))}`}/>)}</span><small>{has(s.with_failure)?`${fmtNumber(Number(s.with_failure))} sampled course${Number(s.with_failure)===1?'':'s'} with a failure; a course can have more than one reason.`:''}</small></>}</dd>
    </dl>
    {latest&&latest.length>0&&<ul className="pjm-cs-latest" data-cs-latest>{latest.map(f=><li key={`${f.course}-${f.checked_at}`}><code>{f.course}</code>{f.country&&<span className="cf-badge">{f.country}</span>}<small>{(f.failures||[]).map(word).join('; ')}{f.checked_at?` · ${fmtDateTime(f.checked_at)}`:''}</small></li>)}</ul>}
    <Reads checked={s.checked} intl={intlApplies}/>
  </li>
}

/** The consumer_fields block: one card per stream the backend returns. Streams are different kinds of record and are never added together. */
export default function ConsumerSample({ops,streamTitle}){
  const cf=ops?.consumer_fields
  if(!cf||typeof cf!=='object')return <div data-cs-none><h5 className="sl-h4" data-pim-section="consumer-sample">Sampled delivery read-back</h5><NotRecorded w="Not available" why="The PIM snapshot carries no sampled read-back yet."/></div>
  const ids=Object.keys(cf.streams||{})
  return <div className="pjm" data-cs>
    <h5 className="sl-h4" data-pim-section="consumer-sample">Sampled delivery read-back (academic entry and descriptions)</h5>
    {cf.meaning&&<p className="sl-sub" data-cs-meaning>{cf.meaning}</p>}
    {ids.length?<ul className="pjm-cards">{ids.map(id=>cf.streams[id]&&typeof cf.streams[id]==='object'?<Stream key={id} id={id} s={cf.streams[id]} title={streamTitle?.(id)||word(id)}/>:null)}</ul>:<NotRecorded w="None" why="No stream has been sampled yet."/>}
  </div>
}
