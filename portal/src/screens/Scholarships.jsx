import React, { useState } from 'react'
import { usePortal, usePagedList, useDebounced } from '../lib/portal.jsx'
import { awardValue, dateText, NOT_PUBLISHED, NOT_RECORDED } from '../lib/format.js'
import { PageHead, StudyInBar, PillGroup, Select, LoadState, ShowMore, Count, Pill } from '../components/ui.jsx'

const STATUS = {
  open_now: ['green', 'Open now'], opens_later: ['amber', 'Opens later'], closed: ['red', 'Closed'], dates_not_published: ['grey', 'Dates not published'],
}
const statusName = code => (STATUS[code] || [null, String(code || '').replace(/_/g, ' ')])[1]

function Cell({ label, children }) { return <div className="cell"><span className="cell-k">{label}</span><span className="cell-v">{children}</span></div> }

function ScholarshipCard({ s }) {
  const [tone, word] = STATUS[s.status] || ['grey', statusName(s.status)]
  const opens = dateText(s.application_open_date, s.application_open_precision)
  const closes = dateText(s.application_close_date, s.application_close_precision)
  const apply = s.application_required === true ? 'Application required' : s.application_required === false ? 'No separate application' : NOT_RECORDED
  return (
    <article className="card schol">
      <header className="schol-head">
        <div><h3>{s.name}</h3><p className="muted">{s.provider_name}{s.country_code ? ` · ${s.country_code}` : ''}</p></div>
        <Pill tone={tone}>{word}</Pill>
      </header>
      <div className="cells">
        <Cell label="Value">{awardValue(s)}</Cell>
        <Cell label="Eligible intake">{s.study_start_label || NOT_RECORDED}</Cell>
        <Cell label="Applications open">{opens || NOT_PUBLISHED}</Cell>
        <Cell label="Applications close">{closes || NOT_PUBLISHED}</Cell>
        <Cell label="How to apply">{apply}</Cell>
      </div>
      {s.source_url
        ? <p><a className="textlink" href={s.source_url} target="_blank" rel="noopener noreferrer">Provider scholarship page</a></p>
        : <p className="muted small">Provider page not recorded</p>}
    </article>
  )
}

export default function Scholarships() {
  const { studyIn } = usePortal()
  const [text, setText] = useState('')
  const [status, setStatus] = useState('')
  const [intake, setIntake] = useState('')
  const q = useDebounced(text.trim())
  const list = usePagedList('portal_scholarships_v1', { q, countries: studyIn ? [studyIn] : [], statuses: status ? [status] : [], intake })
  const f = list.facets || {}
  const intakes = f.intakes || []
  const intakeValid = !intake || intakes.some(i => i.label === intake)

  return (
    <div className="stack-lg">
      <PageHead title="Scholarships" sub="Published scholarships, with the intake they apply to and the dates you can act on." />
      <StudyInBar />
      <section className="card filters" aria-label="Filters">
        <label className="field wide"><span className="field-label">Search</span>
          <input type="search" placeholder="Scholarship or provider" value={text} onChange={e => setText(e.target.value)} />
        </label>
        <div className="selects">
          <PillGroup label="Application status" value={status} onChange={setStatus}
            options={[{ value: '', label: 'Any' }, ...[...(f.statuses || [])].sort((a, b) => Object.keys(STATUS).indexOf(a.code) - Object.keys(STATUS).indexOf(b.code)).map(x => ({ value: x.code, label: statusName(x.code), count: x.count }))]} />
          <Select label="Eligible intake" value={intakeValid ? intake : ''} onChange={setIntake}>
            <option value="">Any intake</option>
            {intakes.map(i => <option key={i.label} value={i.label}>{i.label} ({i.count})</option>)}
          </Select>
        </div>
      </section>
      <LoadState loading={list.loading && !list.items.length} error={list.error} unavailable={list.unavailable} onRetry={list.retry} what="scholarships" />
      {!list.loading && !list.error && (
        <>
          <Count n={list.total}>{list.total === 1 ? 'scholarship' : 'scholarships'} shown</Count>
          {list.total === 0 && <div className="empty"><strong>No scholarships match.</strong><p className="muted">Clear a filter or change the destination to see more.</p></div>}
          <div className="stack">{list.items.map(s => <ScholarshipCard key={s.id} s={s} />)}</div>
          <ShowMore shown={list.items.length} total={list.total} loading={list.more} onClick={list.showMore} noun="scholarships" />
        </>
      )}
    </div>
  )
}
