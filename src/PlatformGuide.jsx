// Help › Platform guide (Decision 209): the operator and Platform Admin walkthrough, inside the app. Its words live in
// src/guide/platformGuide.js, reviewed every release (contract test: reviewed version = UI version; every menu page
// has an entry). Each screen links straight to itself, so the guide never relies on screenshots that go stale.
import React,{useState}from'react'
import{ArrowRight,BookOpen,CalendarCheck,Compass,Mail,ShieldCheck,Siren,Sparkles,Users}from'lucide-react'
import{PAGES,SECTIONS,canOpen}from'./nav-map'
import{UI_VERSION,RELEASE}from'./release-manifest'
import{GUIDE_REVIEWED_FOR,ROLES,RULES,DAILY_ROUTINE,SCREENS,SIGNALS,ADMIN_DUTIES,ALERTS}from'./guide/platformGuide'

const PARTS=[['flow','How it works',Compass],['roles','Who does what',Users],['daily','Daily routine',CalendarCheck],['screens','The screens',BookOpen],['signals','Signal → action',Siren],['admin','Platform Admin duties',ShieldCheck],['alerts','Alert emails',Mail],['new','What changed',Sparkles]]

function Flow(){
  const box=(x,y,w,name,l1,l2,main)=><g><rect x={x} y={y} width={w} height="72" rx="8" className={main?'pg-box main':'pg-box'}/><text x={x+14} y={y+24} className="pg-name">{name}</text><text x={x+14} y={y+44} className="pg-line">{l1}</text><text x={x+14} y={y+60} className="pg-line">{l2}</text></g>
  return <svg viewBox="0 48 760 312" role="img" aria-label="Data reaches the catalogue only through rules, checks or a person" className="pg-flow">
    <defs><marker id="pg-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" className="pg-arrowhead"/></marker></defs>
    <g className="pg-edge" fill="none"><path d="M244 100H270" markerEnd="url(#pg-arrow)"/><path d="M490 100H516" markerEnd="url(#pg-arrow)"/><path d="M626 136V200" markerEnd="url(#pg-arrow)"/><path d="M560 136V168H134V200" markerEnd="url(#pg-arrow)"/><path d="M244 236H270" markerEnd="url(#pg-arrow)"/><path d="M490 236H516" markerEnd="url(#pg-arrow)"/><path d="M626 272V292"/></g>
    {box(24,64,220,'Sources','Registers, university sites,','fee documents, portals')}
    {box(270,64,220,'Layer 1 · Register','Official provider and course','lists (CRICOS, NZQA)')}
    {box(516,64,220,'Layer 2 · Find and read','Finds pages and fee schedules;','keeps every page as evidence')}
    {box(24,200,220,'Layer 3 · AI validation','Tested, pinned models check','what rules cannot decide')}
    {box(270,200,220,'Layer 4 · Review','A person decides where the AI','and the records disagree')}
    {box(516,200,220,'Published catalogue','Values set by hand are never','overwritten by automation',true)}
    <text x="636" y="172" className="pg-line">clear values</text><text x="347" y="160" textAnchor="middle" className="pg-line">unclear values</text>
    <rect x="24" y="292" width="712" height="52" rx="8" className="pg-gate"/>
    <text x="40" y="314" className="pg-name small">Gate: a Platform Admin approves bulk writes (fee schedules, rules) and new AI models.</text>
    <text x="40" y="332" className="pg-line">A passing test never switches anything on by itself.</text>
  </svg>
}

export default function PlatformGuide({rank=1,navigate}){
  const[open,setOpen]=useState('')
  const go=(page,tab)=>navigate?.(page,tab?{tab}:{})
  const OpenBtn=({page,tab,label})=>canOpen(page,rank)?<button type="button" className="m-secondary compact pg-open" onClick={()=>go(page,tab)}>{label||'Open'}<ArrowRight size={12}/></button>:null
  return <div className="m-page-stack pg" data-platform-guide>
    <section className="m-panel">
      <p className="pg-lead">How operators and Platform Admins run StudySearch day to day: what each screen tells you, which numbers matter, and what to do when something turns amber or red.</p>
      <p className="pg-meta" data-guide-version>Reviewed for v{GUIDE_REVIEWED_FOR}{GUIDE_REVIEWED_FOR!==UI_VERSION?` · this app is v${UI_VERSION}`:''}</p>
      <nav className="pg-toc" aria-label="Guide contents">{PARTS.map(([id,label,Icon])=><a key={id} href={`#platform-guide`} onClick={e=>{e.preventDefault();document.getElementById('pg-'+id)?.scrollIntoView({behavior:'smooth',block:'start'})}}><Icon size={14}/>{label}</a>)}</nav>
    </section>

    <section className="m-panel" id="pg-flow"><h2>How it works</h2><Flow/>
      <p>Clear values from Layer 2 are admitted by rules; anything unclear goes to the AI step, and anything the AI cannot settle goes to a person in Layer 4.</p>
      <ul>{RULES.map(r=><li key={r}>{r}</li>)}</ul></section>

    <section className="m-panel" id="pg-roles"><h2>Who does what</h2>
      <p>Each role can do everything the roles below it can. You are signed in at rank {rank}.</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Role</th><th>Typical person</th><th>Can change</th></tr></thead>
        <tbody>{ROLES.map(r=><tr key={r.role} className={r.rank===rank?'pg-you':''}><td><b>{r.role}</b></td><td>{r.who}</td><td>{r.can}</td></tr>)}</tbody></table></div></section>

    {(()=>{const me=[...ROLES].reverse().find(r=>r.rank<=rank);return me?.daily?.length?<section className="m-panel" id="pg-myrole" data-guide-role={me.rank}><h2>Your role: {me.role}</h2><p>What a {me.role} looks at each day. Screens for other roles are not shown in your menu.</p>
      <ul>{me.daily.map(x=><li key={x}>{x}</li>)}</ul></section>:null})()}

    <section className="m-panel" id="pg-daily"><h2>Daily routine</h2><p>About 15 minutes, top to bottom; stop to act only where something is amber or red. Times on screen are Melbourne time.</p>
      <ol className="pg-steps">{DAILY_ROUTINE.map(s=><li key={s.title}><div><b>{s.title}</b><span>{s.text}</span></div><OpenBtn page={s.page} tab={s.tab}/></li>)}</ol></section>

    <section className="m-panel" id="pg-screens"><h2>The screens</h2><p>Every menu page, the question it answers, what to read and what to do. Open a screen from here.</p>
      {SECTIONS.map(sec=>{const pages=sec.pages.filter(k=>SCREENS[k]);if(!pages.length)return null;return <div key={sec.label||'home'} className="pg-group"><h3>{sec.label||'Start'}</h3>
        {pages.map(k=>{const s=SCREENS[k],p=PAGES[k],isOpen=open===k;return <article key={k} className="pg-screen" data-guide-screen={k}>
          <button type="button" className="pg-screen-head" aria-expanded={isOpen} onClick={()=>setOpen(isOpen?'':k)}><span><b>{p.label}</b><small>{s.answers}</small></span>{!canOpen(k,rank)&&<em>needs a higher role</em>}</button>
          {isOpen&&<div className="pg-screen-body"><div><h4>What to read</h4><ul>{s.read.map(x=><li key={x}>{x}</li>)}</ul></div><div><h4>What to do</h4><ul>{s.act.map(x=><li key={x}>{x}</li>)}</ul></div><OpenBtn page={k} label={`Open ${p.label}`}/></div>}
        </article>})}</div>})}</section>

    <section className="m-panel" id="pg-signals"><h2>Signal → action</h2><p>Most warnings clear on the next run; act when the same signal shows twice in a row or a count stays flat for a day.</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>What you see</th><th>Where</th><th>What it means</th><th>What to do</th><th>Who</th></tr></thead>
        <tbody>{SIGNALS.map(s=><tr key={s.see}><td>{s.see}</td><td>{s.where}</td><td>{s.means}</td><td>{s.act}</td><td>{s.who}</td></tr>)}</tbody></table></div></section>

    <section className="m-panel" id="pg-admin"><h2>Platform Admin duties</h2>
      <div className="pg-cards">{ADMIN_DUTIES.map(d=><div key={d.title}><h4>{d.title}</h4><ul>{d.items.map(x=><li key={x}>{x}</li>)}</ul></div>)}</div></section>

    <section className="m-panel" id="pg-alerts"><h2>Alert emails</h2><p>{ALERTS.status}</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Alert</th><th>When</th><th>To</th></tr></thead>
        <tbody>{ALERTS.rows.map(a=><tr key={a.alert}><td>{a.alert}</td><td>{a.when}</td><td>{a.to}</td></tr>)}</tbody></table></div></section>

    <section className="m-panel" id="pg-new"><h2>What changed in v{RELEASE.version}</h2><p><b>{RELEASE.title}</b> · {RELEASE.date}</p>
      <ul>{RELEASE.changes.map(c=><li key={c}>{c}</li>)}{(RELEASE.bugFixes||[]).map(c=><li key={c}>Fixed: {c}</li>)}</ul>
      <p className="pg-meta">Earlier releases: the version button at the top right.</p></section>
  </div>
}
