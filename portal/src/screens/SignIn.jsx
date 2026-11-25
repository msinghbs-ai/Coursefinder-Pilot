import React, { useState } from 'react'
import { supabase } from '../lib/supabase.js'

export default function SignIn() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [reset, setReset] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true); setMessage('')
    if (reset) {
      const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${location.origin}/` })
      setMessage(error ? 'We could not send that email. Check the address and try again.' : 'If that address has an account, a reset link is on its way.')
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
      if (error) setMessage('That email and password did not match. Please try again.')
    }
    setBusy(false)
  }

  return (
    <main className="center-card">
      <h1>StudySearch Portal</h1>
      <p className="muted">{reset ? 'Enter your email and we will send a link to choose a new password.' : 'Sign in with your StudySearch account.'}</p>
      <form onSubmit={submit} className="stack">
        <label>Email<input type="email" autoComplete="username" value={email} onChange={e => setEmail(e.target.value)} required /></label>
        {!reset && <label>Password<input type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>}
        <button className="btn primary" disabled={busy}>{reset ? 'Send reset link' : 'Sign in'}</button>
      </form>
      {message && <p role="status" className="notice">{message}</p>}
      <button className="link" onClick={() => { setReset(!reset); setMessage('') }}>{reset ? 'Back to sign in' : 'Forgot your password?'}</button>
    </main>
  )
}
