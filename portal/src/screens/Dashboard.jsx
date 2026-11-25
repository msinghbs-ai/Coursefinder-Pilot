import React, { useState } from 'react'
import { greeting } from '../lib/roles.js'
import { EXAMPLE_PROMPTS, RECENT_SEARCHES_SHOWN } from '../copy.js'

const key = id => `studysearch-portal-recent:${id || 'anon'}`
function readRecent(id) { try { const v = JSON.parse(localStorage.getItem(key(id)) || '[]'); return Array.isArray(v) ? v : [] } catch { return [] } }
function saveRecent(id, text) {
  try { localStorage.setItem(key(id), JSON.stringify([text, ...readRecent(id).filter(x => x !== text)].slice(0, RECENT_SEARCHES_SHOWN))) } catch { /* a light per-person convenience; ignore if the browser blocks storage */ }
}

export default function Dashboard({ name, access, userId }) {
  const [text, setText] = useState('')
  const recent = readRecent(userId)

  function go(query) {
    const q = String(query || '').trim()
    if (!q) return
    saveRecent(userId, q)
    location.hash = `#/courses?q=${encodeURIComponent(q)}`
  }

  return (
    <div className="stack-lg">
      <div>
        <h1>{greeting()}{name ? `, ${name}` : ''}</h1>
        <p className="muted">{access.label}</p>
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
      <section>
        <h2>Recent searches</h2>
        {recent.length
          ? <div className="chips">{recent.map(p => <button key={p} type="button" className="chip light" onClick={() => go(p)}>{p}</button>)}</div>
          : <p className="muted">Your recent searches will appear here.</p>}
      </section>
      <section>
        <h2>Quick actions</h2>
        <div className="chips">
          <a className="btn" href="#/courses">Find a course</a>
        </div>
        {access.kind === 'viewer' && <p className="muted">Your role is Viewer. You can browse courses. To save courses and build student proposals, ask a Platform Admin for the Counsellor role.</p>}
      </section>
    </div>
  )
}
