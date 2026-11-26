import React from 'react'
import { firstName } from '../lib/roles.js'
import { PortalProvider } from '../lib/portal.jsx'
import Dashboard from './Dashboard.jsx'
import Courses from './Courses.jsx'
import EntryRequirements from './EntryRequirements.jsx'
import Providers from './Providers.jsx'
import Scholarships from './Scholarships.jsx'
import Saved from './Saved.jsx'
import Proposals from './Proposals.jsx'
import ProposalEditor from './ProposalEditor.jsx'
import ProposalSheet from './ProposalSheet.jsx'

// Menu. Saved courses and Proposals belong to a Counsellor (rank 2 and above); a Viewer (rank 1) browses only.
// The database enforces the same rule on every call; this decides what the screen offers.
const NAV = [
  { to: '/', label: 'Dashboard' },
  { to: '/courses', label: 'Courses' },
  { to: '/entry-requirements', label: 'Entry Requirements' },
  { to: '/providers', label: 'Universities & Providers' },
  { to: '/scholarships', label: 'Scholarships' },
  { to: '/saved', label: 'Saved courses', counsellor: true },
  { to: '/proposals', label: 'Proposals', counsellor: true },
]

const COUNSELLOR_ONLY = what => (
  <div className="empty"><strong>{what} are for Counsellors.</strong><p className="muted">Your role is Viewer. Ask a Platform Admin for the Counsellor role to save, compare and build proposals.</p><a className="btn" href="#/courses">Back to Courses</a></div>
)

// /proposals, /proposals/new, /proposals/<id> and /proposals/<id>/sheet
function proposalRoute(here) {
  const m = /^\/proposals(?:\/([^/]+))?(?:\/(sheet))?\/?$/.exec(here)
  return m ? { id: m[1] || '', sheet: m[2] === 'sheet' } : null
}

function Screen({ here, route, access, name, userId }) {
  const prop = proposalRoute(here)
  if (prop) {
    if (access.kind !== 'counsellor') return COUNSELLOR_ONLY('Proposals')
    if (!prop.id) return <Proposals />
    if (prop.sheet) return <ProposalSheet key={prop.id} id={prop.id} />
    return <ProposalEditor key={prop.id} id={prop.id} params={route.params} />
  }
  if (here === '/courses') return <Courses params={route.params} access={access} />
  if (here === '/entry-requirements') return <EntryRequirements access={access} />
  if (here === '/providers') return <Providers />
  if (here === '/scholarships') return <Scholarships />
  if (here === '/saved') {
    return access.kind === 'counsellor'
      ? <Saved />
      : <div className="empty"><strong>Saved courses are for Counsellors.</strong><p className="muted">Your role is Viewer. Ask a Platform Admin for the Counsellor role to save and compare courses.</p><a className="btn" href="#/courses">Back to Courses</a></div>
  }
  return <Dashboard name={name} access={access} userId={userId} />
}

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
  const nav = NAV.filter(n => !n.counsellor || access.kind === 'counsellor')
  const here = route.path
  return (
    <PortalProvider userId={context?.user_id}>
      <div className="shell">
        <aside className="side">
          <div className="brand"><strong>StudySearch</strong><span>StudySearch Portal</span></div>
          <nav aria-label="Portal">
            {nav.map(n => <a key={n.to} href={`#${n.to}`} aria-current={here === n.to || (n.to !== '/' && here.startsWith(`${n.to}/`)) ? 'page' : undefined}>{n.label}</a>)}
          </nav>
        </aside>
        <div className="main">
          <header className="top">
            <span className="who">{name || 'Signed in'} <span className="pill">{access.label}</span></span>
            <button className="btn" onClick={onSignOut}>Sign out</button>
          </header>
          <div className="content"><Screen here={here} route={route} access={access} name={name} userId={context?.user_id} /></div>
        </div>
      </div>
    </PortalProvider>
  )
}
