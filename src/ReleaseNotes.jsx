// v2.15.291 (Phase 5, retire the leftovers): the top-bar version pill and its release notes, drawn by React.
// Replaces two scripts that patched the page after it was drawn: pim-version-entry.js (an old v2.15.78 pill binder and
// release list) and release-currentness-entry.js (which then corrected the version and added missing notes).
// The version comes only from release-manifest.js; the history comes from public/release-history.json, which
// scripts/build-release-history.mjs builds before every build (docs/release-notes, the manifest and the legacy list).
import React,{useEffect,useRef,useState}from'react'
import{UI_VERSION,RELEASE}from'./release-manifest.js'
import'./release-notes.css'

export const RELEASE_TITLE=`StudySearch PIM Admin v${UI_VERSION}`

/** Puts the current version on the browser tab and on <html data-cf-release-version> (read by the deployed checks). */
export function applyReleaseIdentity(){
  if(typeof document==='undefined')return
  document.title=RELEASE_TITLE
  document.documentElement.dataset.cfReleaseVersion=UI_VERSION
}

let historyCache=null
function loadHistory(){
  if(!historyCache)historyCache=fetch('/release-history.json',{cache:'no-store'}).then(r=>r.ok?r.json():null).catch(()=>null).then(h=>{if(!h)historyCache=null;return h})
  return historyCache
}

function ReleaseNote({release}){
  return <article className="m-release-note" data-release-version={release.version}>
    <div className="m-release-note-meta"><span className="m-release-note-version">v{release.version}</span><span className="m-release-note-date">{release.date}</span></div>
    <h3>{release.title}</h3>
    <ul>{(release.changes||[]).map((x,i)=><li key={i}>{x}</li>)}</ul>
    {release.bugFixes?.length>0&&<div className="m-release-note-fixes"><strong>Bug / UI fixes</strong><ul>{release.bugFixes.map((x,i)=><li key={i}>{x}</li>)}</ul></div>}
  </article>
}

function ReleaseNotesDialog({onClose}){
  const[history,setHistory]=useState(null),closeRef=useRef(null)
  useEffect(()=>{let live=true;loadHistory().then(h=>{if(live)setHistory(h)});closeRef.current?.focus();return()=>{live=false}},[])
  useEffect(()=>{const k=e=>{if(e.key==='Escape')onClose()};document.addEventListener('keydown',k);return()=>document.removeEventListener('keydown',k)},[onClose])
  // The current release always comes from the manifest and is shown first; every other release comes from the built history.
  const older=(history?.releases||[]).filter(r=>r&&r.version&&r.version!==UI_VERSION)
  return <div className="m-release-notes-backdrop is-open" onClick={e=>{if(e.target===e.currentTarget)onClose()}}>
    <section className="m-release-notes-dialog" role="dialog" aria-modal="true" aria-labelledby="pim-release-notes-title">
      <div className="m-release-notes-head"><div><small>StudySearch Admin</small><h2 id="pim-release-notes-title">Release notes</h2></div><button ref={closeRef} type="button" className="m-release-notes-close" aria-label="Close release notes" onClick={onClose}>×</button></div>
      <div className="m-release-notes-list">
        {history?.count>0&&<p className="m-release-history-link"><a href="/release-history.html" target="_blank" rel="noopener">All release notes ({history.count}) →</a></p>}
        <ReleaseNote release={{...RELEASE,version:UI_VERSION}}/>
        {older.map(r=><ReleaseNote key={r.version} release={r}/>)}
      </div>
    </section>
  </div>
}

/** The version pill in the top bar. Click, Enter or Space opens the release notes; Escape closes them and returns focus. */
export function ReleasePill(){
  const[open,setOpen]=useState(false),pillRef=useRef(null)
  const close=React.useCallback(()=>{setOpen(false);requestAnimationFrame(()=>pillRef.current?.focus())},[])
  return <>
    <span ref={pillRef} className="m-release-pill" role="button" tabIndex={0} aria-haspopup="dialog" aria-label={`Open release notes for PIM Admin v${UI_VERSION}`} title="View release notes" onClick={()=>setOpen(true)} onKeyDown={e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();setOpen(true)}}}><span className="m-live-dot"/><span className="m-release-version-label">v{UI_VERSION}</span></span>
    {open&&<ReleaseNotesDialog onClose={close}/>}
  </>
}
