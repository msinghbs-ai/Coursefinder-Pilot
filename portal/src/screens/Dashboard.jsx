import React, { useState } from 'react'
import { greeting } from '../lib/roles.js'
import { usePortal } from '../lib/portal.jsx'
import { useSaved } from '../lib/saved.js'
import { initials } from '../lib/format.js'
import { EXAMPLE_PROMPTS } from '../copy.js'

const key = id => `studysearch-portal-recent:${id || 'anon'}`
function readRecent(id) { try { const v = JSON.parse(localStorage.getItem(key(id)) || '[]'); return Array.isArray(v) ? v : [] } catch { return [] } }
// How many searches are kept and shown is a platform setting (portal.recent_searches_shown), read with the other portal settings.
function saveRecent(id, text, keep) {
  try { localStorage.setItem(key(id), JSON.stringify([text, ...readRecent(id).filter(x => x !== text)].slice(0, keep))) } catch { /* a light per-person convenience; ignored if the browser blocks storage */ }
}

function SavedPanel() {
  const saved = useSaved(true)
  const shown = saved.compareMax ? saved.items.slice(0, saved.compareMax) : saved.items  // as many as the compare limit (a setting)
  return (
    <section className="card side-card" aria-labelledby="saved-h">
      <div className="side-card-head"><h2 id="saved-h">Saved courses</h2>{saved.items.length > 0 && <span className="tag tag-pink">{saved.items.length} saved</span>}</div>
      {saved.loading && <p className="muted">Loading…</p>}
      {saved.error && <p className="muted">{saved.error}</p>}
      {!saved.loading && !saved.error && shown.length === 0 && <p className="muted">Courses you save will be listed here.</p>}
      <ul className="mini">{shown.map(c => <li key={c.course_id}><span className="logo-tile sm" aria-hidden="true">{initials(c.provider_name)}</span><span><strong>{c.title}</strong><small>{c.provider_name}</small></span></li>)}</ul>
      <a className="btn" href="#/saved">Compare saved courses</a>
    </section>
  )
}

export default function Dashboard({ name, access, userId }) {
  const { settings } = usePortal()
  const keep = Number(settings.recent_searches_shown) || 0
  const [text, setText] = useState('')
  const [, redraw] = useState(0)
  const recent = readRecent(userId).slice(0, keep)
  const counsellor = access.kind === 'counsellor'

  function go(query) {
    const q = String(query || '').trim()
    if (!q) return
    if (keep > 0) saveRecent(userId, q, keep)
    redraw(n => n + 1)
    location.hash = `#/courses?q=${encodeURIComponent(q)}`
  }
  const today = new Intl.DateTimeFormat('en-AU', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Australia/Melbourne' }).format(new Date())

  return (
    <div className="stack-lg">
      <div className="page-head">
        <h1>{greeting()}{name ? `, ${name}` : ''}</h1>
        <p className="muted">{access.label} · {today}</p>
      </div>
      <section className="hero" aria-labelledby="find-h">
        <h2 id="find-h">Describe the course you want</h2>
        <form className="searchbar" onSubmit={e => { e.preventDefault(); go(text) }}>
          <input aria-label="Describe the course you want" placeholder="For example: Master of Data Science in Sydney under $45,000 a year" value={text} onChange={e => setText(e.target.value)} />
          <button className="btn accent">Search</button>
        </form>
        <div className="chips" aria-label="Example searches">
          {EXAMPLE_PROMPTS.map(p => <button key={p} type="button" className="chip" onClick={() => go(p)}>{p}</button>)}
        </div>
      </section>
      <div className="dash-grid">
        <div className="stack-lg">
          <section aria-labelledby="pick-h">
            <h2 id="pick-h">Pick up where you left off</h2>
            {recent.length > 0
              ? <div className="card last"><span className="eyebrow">Last search</span><h3>{recent[0]}</h3><a className="btn primary" href={`#/courses?q=${encodeURIComponent(recent[0])}`}>Open results</a></div>
              : <p className="muted">Your last search will be remembered here, on this browser.</p>}
          </section>
          <section aria-labelledby="recent-h">
            <h2 id="recent-h">Recent searches</h2>
            {recent.length
              ? <div className="chips">{recent.map(p => <button key={p} type="button" className="chip light" onClick={() => go(p)}>{p}</button>)}</div>
              : <p className="muted">Your recent searches will appear here.</p>}
          </section>
        </div>
        <aside className="stack-lg">
          <section className="card side-card" aria-labelledby="qs-h">
            <h2 id="qs-h">Quick start</h2>
            <div className="stack">
              <a className="btn primary" href="#/courses">Find a course</a>
              <a className="btn" href="#/providers">Universities &amp; Providers</a>
              <a className="btn" href="#/scholarships">Scholarships</a>
            </div>
          </section>
          {counsellor
            ? <SavedPanel />
            : <p className="notice">Your role is Viewer. You can browse courses, providers and scholarships. To save courses and compare them, ask a Platform Admin for the Counsellor role.</p>}
        </aside>
      </div>
    </div>
  )
}
