import React from 'react'
import { firstName } from '../lib/roles.js'
import Dashboard from './Dashboard.jsx'
import Courses from './Courses.jsx'

export default function Shell({ session, context, access, loading, error, route, onSignOut }) {
  if (loading) return <div className="center-card"><p>Checking your access…</p></div>
  if (error) return <div className="center-card"><h1>StudySearch Portal</h1><p>{error}</p><button className="btn" onClick={onSignOut}>Sign out</button></div>
  if (!access.allowed) {
    return (
      <main className="center-card">
        <h1>No access yet</h1>
        <p>Your account is signed in, but it does not have a Counsellor or Viewer role. Ask a Platform Admin to give you one in Users and Roles.</p>
        <button className="btn" onClick={onSignOut}>Sign out</button>
      </main>
    )
  }
  const name = firstName(session.user, context)
  const nav = [{ to: '/', label: 'Dashboard' }, { to: '/courses', label: 'Courses' }]
  const here = route.path
  return (
    <div className="shell">
      <aside className="side">
        <div className="brand"><strong>StudySearch</strong><span>StudySearch Portal</span></div>
        <nav aria-label="Portal">
          {nav.map(n => <a key={n.to} href={`#${n.to}`} aria-current={here === n.to ? 'page' : undefined}>{n.label}</a>)}
        </nav>
      </aside>
      <div className="main">
        <header className="top">
          <span className="who">{name || 'Signed in'} <span className="pill">{access.label}</span></span>
          <button className="btn" onClick={onSignOut}>Sign out</button>
        </header>
        <div className="content">
          {here === '/courses' ? <Courses params={route.params} access={access} /> : <Dashboard name={name} access={access} userId={context?.user_id} />}
        </div>
      </div>
    </div>
  )
}
