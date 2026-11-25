import React, { useState } from 'react'
import { supabase, keyInfo } from '../lib/supabase.js'
import { explainAuthError } from '../lib/authErrors.js'
import BrandPanel from './BrandPanel.jsx'

export default function SignIn() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState(null)
  const [reset, setReset] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true); setMessage(null)
    const address = email.trim()
    try {
      if (reset) {
        // The link comes back to this site, whichever address it is served from, never to the Admin app.
        const { error } = await supabase.auth.resetPasswordForEmail(address, { redirectTo: window.location.origin })
        setMessage(error ? explainAuthError(error, keyInfo) : { kind: 'ok', text: 'If that address has an account, a reset link is on its way.' })
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: address, password })
        if (error) setMessage(explainAuthError(error, keyInfo))
      }
    } catch (err) {
      setMessage(explainAuthError(err, keyInfo))
    }
    setBusy(false)
  }

  return (
    <div className="auth-split">
      <BrandPanel />
      <main className="auth-pane">
        <div className="auth-card">
          <h1>{reset ? 'Reset your password' : 'Sign in'}</h1>
          <p className="muted">{reset ? 'Enter your email and we will send a link to choose a new password.' : 'Use your StudySearch account.'}</p>
          <form onSubmit={submit} className="stack">
            <label>Email<input type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} required /></label>
            {!reset && <label>Password<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>}
            <button className="btn primary" disabled={busy}>{busy ? 'Please wait…' : reset ? 'Send reset link' : 'Sign in'}</button>
          </form>
          {message && <p role="status" className={`notice ${message.kind === 'ok' ? 'ok' : message.kind === 'setup' ? 'bad' : ''}`}>{message.text}</p>}
          <button className="link" onClick={() => { setReset(!reset); setMessage(null) }}>{reset ? 'Back to sign in' : 'Forgot your password?'}</button>
        </div>
      </main>
    </div>
  )
}
