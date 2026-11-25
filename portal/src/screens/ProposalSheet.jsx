import React, { useEffect, useMemo, useState } from 'react'
import { getProposal, saveProposal } from '../lib/proposalApi.js'
import { sheetModel, proposalPayload } from '../lib/proposals.js'
import { initials } from '../lib/format.js'
import { LoadState } from '../components/ui.jsx'

// The Student Proposal Sheet (Mockups 13 and 14). It is the browser's own print layout: Save as PDF / Print opens the
// browser's print window, where "Save as PDF" makes the file. Nothing is rendered on a server, so there is no daily allowance
// to run out and the same sheet prints from a desktop or a phone.
// The sheet prints only what the student may see. The counsellor notes, internal labels and other students never reach it:
// sheetModel() does not read them, and the print styles hide everything outside .sheet.
export default function ProposalSheet({ id }) {
  const [state, setState] = useState({ loading: true, error: '', unavailable: false, p: null, counsellor: null })
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState(null)

  useEffect(() => {
    let live = true
    getProposal({ id })
      .then(r => { if (live) setState({ loading: false, error: '', unavailable: false, p: { ...r.proposal, counsellor: r.counsellor || r.proposal?.counsellor || null }, counsellor: r.counsellor || null }) })
      .catch(e => { if (live) setState({ loading: false, error: e.message, unavailable: e.kind === 'missing', p: null, counsellor: null }) })
    return () => { live = false }
  }, [id])

  const m = useMemo(() => (state.p ? sheetModel(state.p) : null), [state.p])

  const markSent = async () => {
    setBusy(true); setNote(null)
    try {
      const r = await saveProposal({ id: state.p.id, base_version: state.p.version, proposal: { ...proposalPayload(state.p), status: 'sent' }, note: 'sent as PDF' })
      if (r.status === 'saved') { setState(s => ({ ...s, p: { ...r.proposal, counsellor: s.counsellor } })); setNote({ tone: 'ok', text: `Marked as sent (version ${r.proposal?.version}).` }) }
      else setNote({ tone: 'bad', text: `${r.by_name || 'Someone'} saved a newer version first. Open the proposal to review it, then try again.` })
    } catch (e) { setNote({ tone: 'bad', text: e.message }) } finally { setBusy(false) }
  }

  if (state.loading) return <p className="muted" role="status">Preparing the sheet…</p>
  if (state.unavailable) return <div className="notice" role="status"><strong>Proposals are not switched on yet.</strong> The sheet appears here once they are.</div>
  if (state.error || !m) return <div className="stack"><a className="backlink" href="#/proposals">← Proposals</a><LoadState error={state.error || 'We could not open this proposal.'} /></div>

  const p = state.p
  const sendable = p.status === 'draft' || p.status === 'ready'
  const c = m.counsellor
  return (
    <div className="stack-lg sheet-wrap">
      <div className="sheet-toolbar no-print">
        <a className="backlink" href={`#/proposals/${p.id}`}>← Back to the proposal</a>
        <div className="actions">
          <button type="button" className="btn primary" onClick={() => window.print()}>Save as PDF / Print</button>
          {sendable && <button type="button" className="btn" disabled={busy} onClick={markSent}>Mark as sent</button>}
        </div>
        <p className="muted small">In the print window, choose “Save as PDF” as the printer. The sheet shows the saved version {p.version}{p.status === 'sent' ? ' (already sent)' : ''}.</p>
        {note && <div className={`notice ${note.tone}`} role="status">{note.text}</div>}
      </div>

      <div className="sheet" aria-label="Student proposal sheet">
        <section className="sheet-page">
          <header className="sheet-head">
            <span className="sheet-brand">StudySearch</span>
            <span className="sheet-small">Prepared {m.prepared}{m.asAt ? ` · Details as at ${m.asAt}` : ''}</span>
          </header>
          <h1>{m.heading}</h1>
          <dl className="sheet-student">
            {m.student.who && <div><dt>Student</dt><dd>{m.student.who}{m.student.ref ? ` (${m.student.ref})` : ''}</dd></div>}
            {m.student.qualification && <div><dt>Studied in</dt><dd>{[m.student.country, m.student.qualification].filter(Boolean).join(', ')}</dd></div>}
            {m.student.english && <div><dt>English</dt><dd>{m.student.english}</dd></div>}
            {m.student.budget && <div><dt>Budget</dt><dd>{m.student.budget}</dd></div>}
          </dl>
          {m.message && <p className="sheet-message">{m.message}</p>}
          <h2>Your options side by side</h2>
          <div className="sheet-courses" style={{ '--n': Math.max(1, m.courses.length) }}>
            {m.courses.map(k => (
              <article key={k.courseId} className="sheet-course">
                <header><span className="sheet-num">{k.n}</span><h3>{k.title}</h3></header>
                <dl>
                  <div><dt>Provider</dt><dd>{k.provider}</dd></div>
                  <div><dt>Campus</dt><dd>{k.campus}</dd></div>
                  <div><dt>Length</dt><dd>{k.length}</dd></div>
                  <div><dt>Tuition</dt><dd>{k.tuition}{k.tuitionTotal && <small>{k.tuitionTotal}</small>}</dd></div>
                  <div><dt>Next intake</dt><dd>{k.nextIntake}</dd></div>
                  <div><dt>Entry</dt><dd>{k.entry}</dd></div>
                  <div><dt>English</dt><dd>{k.english}</dd></div>
                  <div><dt>Scholarship</dt><dd>{k.scholarship}</dd></div>
                </dl>
                {k.why && <p className="sheet-why"><strong>Why this course:</strong> {k.why}</p>}
              </article>
            ))}
          </div>
          <p className="sheet-foot">Fees and dates are published by each provider and can change. Confirm with the provider before you apply.</p>
        </section>

        <section className="sheet-page">
          <h1>Your next steps</h1>
          <ol className="sheet-steps">
            {m.steps.map(s => (
              <li key={s.n}>
                <strong>{s.title}</strong>{s.due ? <span> · {s.due}</span> : null}{s.owner ? <span> · {s.owner}</span> : null}
                {s.detail && <p>{s.detail}</p>}
              </li>
            ))}
          </ol>
          <div className="sheet-two">
            {m.documents.length > 0 && <div><h2>Documents to have ready</h2><ul>{m.documents.map((d, i) => <li key={i}>{d}</li>)}</ul></div>}
            {m.dates.length > 0 && <div><h2>Dates to remember</h2><ul>{m.dates.map((d, i) => <li key={i}><strong>{d.when}</strong>: {d.what}</li>)}</ul><p className="sheet-small">Dates are targets. Each provider sets its own deadlines.</p></div>}
          </div>
          {c && (c.name || c.email || c.phone) && (
            <div className="sheet-counsellor">
              <span className="logo-tile" aria-hidden="true">{initials(c.name)}</span>
              <div><strong>{c.name}</strong>{c.title ? `, ${c.title}` : ''}<p>Your counsellor for every step. Questions about any provider, fee or date, ask before you pay anything.</p>
                <p className="sheet-small">{[c.phone, c.email, c.office].filter(Boolean).join(' · ')}</p></div>
            </div>
          )}
          <p className="sheet-foot">Prepared {m.prepared} from provider information. This is guidance, not an offer of a place.</p>
        </section>
      </div>
    </div>
  )
}
