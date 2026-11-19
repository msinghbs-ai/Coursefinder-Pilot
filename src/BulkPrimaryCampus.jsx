// CF-247 s812 (Platform Admin 20 Nov 2026 08:06): Bulk Flag Primary Campus for the ticked providers. The rule is the one approved on 20 Nov (B2): the campus
// with the most active courses becomes the primary campus. Preview first (nothing is written), then Apply with a reason. A provider that already has a primary
// campus, has it locked by hand, ties, or is outside the rule is skipped and listed with its reason. Platform Admin only; the server checks it again.
import React, { useState } from 'react'
import { bulkPrimaryApi } from './field-provenance-api'
import { PRIMARY_OUTCOME } from './field-provenance'
import './completeness-bar.css'

export default function BulkPrimaryCampus({ providerIds, onClose, onDone }) {
  const [pv, setPv] = useState(null), [busy, setBusy] = useState(''), [err, setErr] = useState(''), [reason, setReason] = useState(''), [done, setDone] = useState(null)
  const run = async (name, fn) => { if (busy) return; setBusy(name); setErr(''); try { await fn() } catch (e) { setErr(e?.message || 'The request failed.') } finally { setBusy('') } }
  const preview = () => run('Previewing', async () => { setDone(null); setPv(await bulkPrimaryApi.call('campus_primary_preview', { provider_ids: providerIds })) })
  const apply = () => run('Applying', async () => { const r = await bulkPrimaryApi.call('campus_primary_apply', { provider_ids: providerIds, reason: reason.trim() }); setDone(r); setPv(null); onDone?.(r) })
  const will = pv?.will_mark || 0
  return <section className="cprim" data-bulk-primary role="dialog" aria-label="Flag primary campus for the ticked providers">
    <strong>Flag primary campus for {providerIds.length} ticked provider{providerIds.length === 1 ? '' : 's'}</strong>
    <p className="cprov-note">The campus with the most active courses becomes the primary campus. Providers that already have one, have it locked by hand, tie, or are outside Australia, New Zealand and Canada are skipped. Nothing is written until you apply.</p>
    {err && <p role="alert" data-bulk-primary-error>{err}</p>}
    {!pv && !done && <div className="cprim-actions"><button type="button" className="m-primary compact" data-bulk-primary-preview onClick={preview} disabled={!!busy}>{busy === 'Previewing' ? 'Previewing…' : 'Preview'}</button><button type="button" className="m-secondary compact" onClick={onClose}>Close</button></div>}
    {pv && <>
      <p data-bulk-primary-summary><strong>{will}</strong> of {pv.ticked} would be marked; {Object.entries(pv.by_outcome || {}).filter(([k]) => k !== 'will_mark').map(([k, n]) => `${n} ${String(PRIMARY_OUTCOME[k] || k).toLowerCase()}`).join(', ') || 'none skipped'}.</p>
      <table data-bulk-primary-table><thead><tr><th>Provider</th><th>Result</th><th>Campus</th><th>Active courses</th></tr></thead>
        <tbody>{(pv.rows || []).map(r => <tr key={r.provider_id} data-outcome={r.outcome}><td>{r.name}</td><td>{PRIMARY_OUTCOME[r.outcome] || r.outcome}</td><td>{r.outcome === 'will_mark' ? r.campus : '—'}</td><td>{r.outcome === 'will_mark' ? r.courses : '—'}</td></tr>)}</tbody></table>
      <label>Reason (recorded in the audit event)<br /><input value={reason} onChange={e => setReason(e.target.value)} maxLength={300} aria-label="Reason" /></label>
      <div className="cprim-actions">
        <button type="button" className="m-primary compact" data-bulk-primary-apply onClick={apply} disabled={!!busy || will === 0 || reason.trim().length < 4}>{busy === 'Applying' ? 'Applying…' : `Mark ${will} as primary`}</button>
        <button type="button" className="m-secondary compact" onClick={preview} disabled={!!busy}>Preview again</button>
        <button type="button" className="m-secondary compact" onClick={onClose}>Close</button>
      </div>
    </>}
    {done && <><p data-bulk-primary-done role="status"><strong>{done.marked}</strong> provider{done.marked === 1 ? '' : 's'} marked. One audit event was written.</p><div className="cprim-actions"><button type="button" className="m-secondary compact" onClick={onClose}>Close</button></div></>}
  </section>
}
