import React, { useEffect, useState } from 'react'
import { supabase, configured, keyInfo, readContext } from './lib/supabase.js'
import { portalAccess } from './lib/roles.js'
import SignIn from './screens/SignIn.jsx'
import SetPassword from './screens/SetPassword.jsx'
import Shell from './screens/Shell.jsx'

function routeFromHash() {
  const raw = (location.hash || '#/').replace(/^#/, '')
  const [path, query = ''] = raw.split('?')
  return { path: path || '/', params: new URLSearchParams(query) }
}

export default function App() {
  const [session, setSession] = useState(null)
  const [booting, setBooting] = useState(true)
  const [context, setContext] = useState(null)
  const [contextError, setContextError] = useState('')
  const [recovery, setRecovery] = useState(false)
  const [route, setRoute] = useState(routeFromHash())

  useEffect(() => {
    if (!configured) { setBooting(false); return undefined }
    supabase.auth.getSession().then(({ data }) => { setSession(data.session ?? null); setBooting(false) })
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next)
      if (event === 'PASSWORD_RECOVERY') setRecovery(true)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) { setContext(null); setContextError(''); return }
    let live = true
    readContext()
      .then(value => { if (live) { setContext(value); setContextError('') } })
      .catch(() => { if (live) setContextError('We could not check your access just now. Please try again in a moment.') })
    return () => { live = false }
  }, [session])

  useEffect(() => {
    const onHash = () => setRoute(routeFromHash())
    addEventListener('hashchange', onHash)
    return () => removeEventListener('hashchange', onHash)
  }, [])

  if (!configured) return <div className="center-card"><h1>StudySearch Portal</h1><p>{keyInfo.kind === 'secret' ? 'The key built into the portal is a secret key, which must never run in a browser, so it was not used. A Platform Admin needs to set the publishable key instead.' : 'The portal is not configured yet. The Supabase address and publishable key are missing from the build.'}</p></div>
  if (booting) return <div className="center-card"><p>Loading…</p></div>
  if (recovery) return <SetPassword onDone={() => setRecovery(false)} />
  if (!session) return <SignIn />

  const access = portalAccess(context)
  return (
    <Shell
      session={session}
      context={context}
      access={access}
      loading={!context && !contextError}
      error={contextError}
      route={route}
      onSignOut={() => supabase.auth.signOut()}
    />
  )
}
