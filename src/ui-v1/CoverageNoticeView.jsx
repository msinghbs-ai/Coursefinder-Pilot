import './ui-kit.css'
// CF-247 s931 (Decision 279 §6.3): What StudySearch covers. The countries come from the live lookups (public.admin_lookups_v1), never written here.
// Role-aware: Curator and above also read that an official address can be added from the pill. Dismissal lasts for this visit to the page (the v1.1 build keeps no browser storage).
import React,{useState}from'react'
import{Info,X}from'lucide-react'
import{useLookups}from'../lib/lookups.js'

export default function CoverageNotice({rank=0,onPills}){
  const lk=useLookups(),[gone,setGone]=useState(false)
  const names=(lk.countries||[]).filter(c=>c.target).map(c=>c.name)
  if(gone)return null
  return <aside className="ui-cf-coverage-notice" role="note" data-coverage-notice>
    <Info size={16} aria-hidden="true"/>
    <div><strong>What StudySearch covers</strong>
      <p>Countries live: {names.length?names.join(', '):'reading…'}. Values come from official registers (CRICOS, NZQA, DLI list) and each institution's own pages. A blank shows why: in review, university-wide rule, no official address, or not stated on the page.{Number(rank)>=3?' Add an official address from the pill on the record.':''}</p>
      {onPills&&<button type="button" className="ui-cf-link-button" onClick={onPills} data-coverage-pills>How to read the pills →</button>}</div>
    <button type="button" className="ui-hd-x" aria-label="Dismiss" onClick={()=>setGone(true)} data-coverage-dismiss><X size={14}/></button>
  </aside>
}
