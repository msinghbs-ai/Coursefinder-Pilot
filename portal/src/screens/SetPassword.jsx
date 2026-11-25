import React, { useState } from 'react'
import { supabase } from '../lib/supabase.js'

// Shown after a reset link brings the person back here. The password rules are enforced by Supabase Auth, not here.
export default function SetPassword({ onDone }) {
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')

  async function submit(e) {
    e.preventDefault()
    setBusy(true); setMessage('')
    const { error } = await supabase.auth.updateUser({ password })
    setBusy(false)
    if (error) setMessage(error.message || 'That password was not accepted. Please try another.')
    else onDone()
  }

  return (
    <main className="center-card">
      <h1>Choose a new password</h1>
      <form onSubmit={submit} className="stack">
        <label>New password<input type="password" autoComplete="new-password" value={password} onChange={e => setPassword(e.target.value)} required /></label>
        <button className="btn primary" disabled={busy}>Save password</button>
      </form>
      {message && <p role="status" className="notice">{message}</p>}
    </main>
  )
}
