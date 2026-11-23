// v1.1 Counsellor UI shell (S1-API-Frontend-Delivery, s990). Built on ui-v1/tokens.css and ui-v1/ui-kit.css only: no legacy class, no operator
// navigation, view or read is ever created here (role separation by construction, IR-021).
import { useEffect, useMemo, useState } from 'react'
import './tokens.css'
import './ui-kit.css'
import CoursesView from './CoursesView.jsx'
import ProvidersView from './ProvidersView.jsx'
import ScholarshipsView from './ScholarshipsView.jsx'
import GuideView from './GuideView.jsx'
import { supabase } from '../lib/supabase.js'
import { createSavedStore } from './saved-store.js'

export const COUNSELLOR_NAV = [['courses', 'Courses'], ['providers', 'Universities & Providers'], ['scholarships', 'Scholarships'], ['guide', 'Guide']]
const routeOf = () => { const m = /^#ui-v1\/([a-z-]+)/.exec(globalThis.location?.hash || ''); return COUNSELLOR_NAV.some(n => n[0] === m?.[1]) ? m[1] : 'courses' }

const SCREENS = { courses: CoursesView, providers: ProvidersView, scholarships: ScholarshipsView, guide: GuideView }

export default function CounsellorApp({ userId, screens = SCREENS }) {
  const [route, setRoute] = useState(routeOf)
  const saved = useMemo(() => createSavedStore(userId), [userId])
  useEffect(() => { document.body.classList.add('ui-v1'); return () => document.body.classList.remove('ui-v1') }, [])
  useEffect(() => { const f = () => setRoute(routeOf()); addEventListener('hashchange', f); return () => removeEventListener('hashchange', f) }, [])
  const View = screens[route]
  return <div className="ui-shell">
    <header className="ui-topbar"><span className="ui-brand">StudySearch</span><span className="ui-topbar-spacer" /><button type="button" className="ui-btn ui-btn-sm" onClick={() => supabase.auth.signOut()}>Sign out</button></header>
    <nav className="ui-nav" aria-label="Main">{COUNSELLOR_NAV.map(([k, l]) => <a key={k} href={`#ui-v1/${k}`} aria-current={k === route ? 'page' : 'false'}>{l}</a>)}</nav>
    <main className="ui-main">{View ? <View saved={saved} userId={userId} /> : <div className="ui-emptystate"><p className="ui-emptystate-title">This screen is being built</p></div>}</main>
  </div>
}
