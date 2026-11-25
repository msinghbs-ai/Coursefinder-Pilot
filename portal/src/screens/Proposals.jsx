import React, { useState } from 'react'
import { usePagedList, useDebounced } from '../lib/portal.jsx'
import { saveProposal } from '../lib/proposalApi.js'
import { statusInfo, whenText } from '../lib/proposals.js'
import { initials } from '../lib/format.js'
import { PageHead, LoadState, ShowMore, Pill } from '../components/ui.jsx'

// Proposals list (Mockups 09 and 10). Mine and Whole team are two scopes of the same list: every Counsellor and above sees
// every proposal (Platform Admin, 25 Nov 10:45). Filters, search and paging run in the database.
const FILTERS = [['', 'All'], ['draft', 'Drafts'], ['needs_refresh', 'Needs refresh'], ['sent', 'Sent'], ['archived', 'Archived']]

function ProposalCard({ p, onDuplicate, busy }) {
  const s = p.student || {}
  const info = statusInfo(p.needs_refresh ? 'needs_refresh' : p.status)
  const tone = p.needs_refresh ? 'amber' : info.tone
  const label = p.needs_refresh ? 'Needs refresh' : info.label
  const who = p.updated_by_me ? 'You' : (p.updated_by_name || 'Someone')
  const at = whenText(p.updated_at)
  const when = at ? (/^(today|yesterday)/.test(at) ? at : `on ${at}`) : ''
  const facts = [s.ref, s.source_country_name || s.source_country, [s.qualification, s.result_text].filter(Boolean).join(' '), s.english_text, s.preferred_intake].filter(Boolean)
  const courses = Array.isArray(p.courses) ? p.courses : []
  return (
    <article className="card proposal-card">
      <header className="proposal-card-head">
        <div>
          <h3><a href={`#/proposals/${p.id}`}>{p.title || 'Untitled proposal'}</a></h3>
          {facts.length > 0 && <p className="muted small">{facts.join(' · ')}</p>}
        </div>
        <Pill tone={tone}>{label}</Pill>
      </header>
      {courses.length > 0 && (
        <ul className="course-chips" aria-label="Courses in this proposal">
          {courses.map(c => <li key={c.course_id}><span className="logo-tile xs" aria-hidden="true">{initials(c.provider_name)}</span>{c.title}</li>)}
        </ul>
      )}
      {p.change_note && <p className="notice small">{p.change_note}</p>}
      <p className="muted small">
        {who} {p.last_pdf_version && p.status === 'sent' ? `sent PDF version ${p.last_pdf_version}` : 'saved'} {when}
        {p.details_checked_at ? ` · details checked ${whenText(p.details_checked_at)}` : ''}
      </p>
      <div className="actions">
        <a className="btn small primary" href={`#/proposals/${p.id}`}>Open</a>
        <a className="btn small" href={`#/proposals/${p.id}?refresh=1`}>Refresh</a>
        <button type="button" className="btn small" disabled={busy === p.id} onClick={() => onDuplicate(p)}>Duplicate</button>
        <a className="btn small" href={`#/proposals/${p.id}/sheet`}>PDF</a>
      </div>
    </article>
  )
}

export default function Proposals() {
  const [scope, setScope] = useState('mine')
  const [status, setStatus] = useState('')
  const [text, setText] = useState('')
  const [busy, setBusy] = useState('')
  const [message, setMessage] = useState('')
  const q = useDebounced(text.trim())
  const list = usePagedList('portal_proposal_list_v1', { scope, status, q })
  const counts = list.facets?.counts || {}

  const duplicate = async p => {
    setBusy(p.id); setMessage('')
    try {
      const r = await saveProposal({ duplicate_of: p.id })
      if (r?.id) location.hash = `#/proposals/${r.id}`
      else setMessage('The copy could not be made. Please try again.')
    } catch (e) { setMessage(e.message) } finally { setBusy('') }
  }

  const needing = list.facets?.needs_refresh_count
  return (
    <div className="stack-lg">
      <div className="count-row">
        <PageHead title="Proposals" sub="Find any student, then build, refresh and send their study options. Each proposal keeps its own history." />
        <a className="btn primary" href="#/proposals/new">+ New proposal</a>
      </div>
      <div className="seg" role="group" aria-label="Whose proposals">
        <button type="button" className="spill dark" aria-pressed={scope === 'mine'} onClick={() => setScope('mine')}>Mine{counts.mine !== undefined ? ` (${counts.mine})` : ''}</button>
        <button type="button" className="spill dark" aria-pressed={scope === 'team'} onClick={() => setScope('team')}>Whole team{counts.team !== undefined ? ` (${counts.team})` : ''}</button>
      </div>
      <p className="muted small">Every counsellor can find, open and edit any proposal. Each edit is saved as a new version with the editor’s name.</p>
      <div className="searchbar">
        <input aria-label="Find a proposal" placeholder="Student name, reference (for example SS-000142) or course" value={text} onChange={e => setText(e.target.value)} />
      </div>
      <div className="pillrow" role="group" aria-label="Show">
        {FILTERS.map(([value, label]) => <button key={value} type="button" className="fpill" aria-pressed={status === value} onClick={() => setStatus(value)}>{label}</button>)}
      </div>
      {Number(needing) > 0 && status !== 'needs_refresh' && <div className="notice" role="status">{needing} {Number(needing) === 1 ? 'proposal was' : 'proposals were'} built on details that have since changed. Open one and choose Refresh to see exactly what moved.</div>}
      {message && <div className="notice bad" role="alert">{message}</div>}
      <LoadState loading={list.loading && list.items.length === 0} unavailable={list.unavailable} error={list.unavailable ? '' : list.error} onRetry={list.retry} what="proposals" />
      {list.unavailable && <p className="muted">Proposals are being finished by the platform team. Your saved courses are safe, and you can keep comparing them on <a href="#/saved">Saved courses</a>.</p>}
      {!list.loading && !list.error && list.items.length === 0 && (
        <div className="empty"><strong>No proposals here yet.</strong><p className="muted">Start one from your saved courses, or choose + New proposal.</p><a className="btn primary" href="#/proposals/new">+ New proposal</a></div>
      )}
      <div className="stack">{list.items.map(p => <ProposalCard key={p.id} p={p} busy={busy} onDuplicate={duplicate} />)}</div>
      {list.items.length > 0 && <ShowMore shown={list.items.length} total={list.total} loading={list.more} onClick={list.showMore} noun="proposals" />}
      <p className="muted small">Only the student reference, given name and family initial are stored. Counsellors and Platform Admins can see every proposal. Viewers cannot see proposals.</p>
    </div>
  )
}
