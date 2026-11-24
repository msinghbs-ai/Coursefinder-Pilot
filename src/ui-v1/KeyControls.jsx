// UI/UX Unification v1.2 Slice 2 (Platform Admin brief 24 Nov 2026 12:42): the few controls an operator changes most, at the top of Settings, with plain
// titles. Everything else stays in Advanced System Keys. The values come from the live settings (public.admin_toolsets_read); a change goes through the
// same governed write the rest of Settings uses (admin_toolsets_write 'setting', with a reason of 4 or more characters, logged). No value is written here:
// the list below only names WHICH existing settings are shown first (toolset and key), and the title, range and unit come from the database.
import { useEffect, useState } from 'react'
import './tokens.css'
import './ui-kit.css'
import { supabase } from '../lib/supabase.js'

// [toolset, key]: spend and credit limits first, then the switches that stop or start automatic work
export const PRIMARY_KEYS = [
  ['pipeline', 'budgets.paid_daily_cap_usd'], ['firecrawl', 'daily_budget_on'], ['firecrawl', 'daily_budget_total'], ['firecrawl', 'monitor_weekly_credits'],
  ['openrouter', 'credit_floor_usd'], ['pipeline', 'aer.machine_suspended'], ['pipeline', 'plans.noop_wait_hours'],
]
export const pickPrimary = toolsets => PRIMARY_KEYS.map(([t, k]) => {
  const ts = (toolsets || []).find(x => x.key === t); const s = (ts?.settings || []).find(x => x.key === k)
  return s ? { ...s, toolset: t } : null
}).filter(Boolean)

function Row({ s, can, onSave }) {
  const yn = s.kind === 'boolean'
  const [v, setV] = useState(String(s.value ?? '')), [reason, setReason] = useState(''), [busy, setBusy] = useState(false), [err, setErr] = useState('')
  useEffect(() => { setV(String(s.value ?? '')) }, [s.value])
  const n = Number(v), changed = v !== String(s.value ?? '')
  const valid = yn || (Number.isFinite(n) && v !== '' && (s.min == null || n >= Number(s.min)) && (s.max == null || n <= Number(s.max)))
  const go = async () => { setBusy(true); setErr(''); try { await onSave(s, yn ? v === 'true' : n, reason.trim()); setReason('') } catch (e) { setErr(e.message || 'The change was not saved.') } finally { setBusy(false) } }
  return <div className="ui-keyrow" data-key-control={`${s.toolset}.${s.key}`}>
    <div><strong>{s.label}</strong>{s.help && <div className="ui-note">{s.help}</div>}<div className="ui-note">{s.toolset}.{s.key}{s.min != null && s.max != null ? ` · between ${s.min} and ${s.max}` : ''}{s.unit ? ` · ${s.unit}` : ''}</div></div>
    <div className="ui-keyedit">
      {yn ? <select className="ui-input" value={v} disabled={!can} aria-label={s.label} onChange={e => setV(e.target.value)}><option value="true">On</option><option value="false">Off</option></select>
        : <input className="ui-input" type="number" value={v} disabled={!can} aria-label={s.label} onChange={e => setV(e.target.value)} />}
      {can && changed && <><input className="ui-input" placeholder="Reason (4 or more characters)" aria-label={`Reason for ${s.label}`} value={reason} onChange={e => setReason(e.target.value)} />
        <button type="button" className="ui-btn ui-btn-primary ui-btn-sm" disabled={busy || !valid || reason.trim().length < 4} onClick={go}>{busy ? 'Saving…' : 'Save'}</button></>}
      {err && <div className="ui-alert" role="alert">{err}</div>}
    </div>
  </div>
}

export default function KeyControls() {
  const [d, setD] = useState(null), [err, setErr] = useState('')
  const load = () => supabase.rpc('admin_toolsets_read').then(({ data, error }) => { if (error) throw error; setD(data || {}) }).catch(e => setErr(e.message || 'Key controls could not be loaded.'))
  useEffect(() => { load() }, [])
  const save = async (s, value, reason) => { const { error } = await supabase.rpc('admin_toolsets_write', { p_action: 'setting', p_args: { toolset: s.toolset, key: s.key, value, reason } }); if (error) throw error; await load() }
  const rows = pickPrimary(d?.toolsets)
  return <section className="ui-keycontrols" data-key-controls aria-label="Key controls">
    <h2 className="ui-section-title">Key controls</h2>
    <div className="ui-note">The limits and switches changed most often. Every change needs a reason and is logged. Everything else is under Advanced System Keys below.</div>
    {err && <div className="ui-alert" role="alert">{err}</div>}
    {!d && !err ? <div className="ui-note">Loading…</div> : rows.length === 0 && !err ? <div className="ui-note">No key controls are available to your role.</div>
      : rows.map(s => <Row key={`${s.toolset}.${s.key}`} s={s} can={Boolean(d.can_manage)} onSave={save} />)}
  </section>
}
