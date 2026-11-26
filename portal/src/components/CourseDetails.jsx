import React, { useState } from 'react'
import { usePortal } from '../lib/portal.jsx'
import { useCourseDetail } from '../lib/courseDetail.js'
import { feeLabel, feeAmount, feeAudience, feeIsAnnual, entryLine, entryForMarket, englishLine, outcomeValue, intakeText, deliveryText, durationText, matrixLine, matrixForMarket } from '../lib/courseDetailFormat.js'
import { dateText, stateShort, money, NOT_RECORDED } from '../lib/format.js'
import { ExtLink } from './ExtLink.jsx'
import { Pill, Select } from './ui.jsx'

// The expandable Course details panel (Courses, Saved courses, Entry Requirements). It reads the course when it is opened.
export const DetailsButton = ({ open, onClick, id }) => (
  <button type="button" className={`btn${open ? ' open' : ''}`} aria-expanded={open} aria-controls={id} onClick={onClick}>{open ? 'Hide details' : 'Course details'}</button>
)

const Section = ({ title, note, children }) => (
  <section className="d-sec"><h4>{title}</h4>{note && <p className="muted small">{note}</p>}{children}</section>
)
const None = ({ what }) => <p className="muted">{what || NOT_RECORDED}</p>

export function CourseDetails({ id, courseId }) {
  const { market, markets, setMarket } = usePortal()
  const d = useCourseDetail(courseId, true)
  const body = d.data
  return (
    <div className="details" id={id} role="region" aria-label="Course details" aria-live="polite">
      {d.loading && <p className="muted" role="status">Loading the course details…</p>}
      {d.error && <div className="notice bad" role="alert">{d.unavailable ? 'Course details are not switched on yet.' : d.error}</div>}
      {d.gone && <div className="notice" role="status">This course is no longer listed, so its details are not shown.</div>}
      {body && <Body body={body} market={market} markets={markets} setMarket={setMarket} />}
    </div>
  )
}

function Body({ body, market, markets, setMarket }) {
  const campuses = body.campuses || [], fees = body.fees || [], intakes = body.intakes || []
  const allEntry = body.entry_requirements || [], entry = entryForMarket(allEntry, market).map(entryLine), english = (body.english_requirements || []).map(englishLine)
  const countrySpecific = allEntry.filter(r => r.country_code).length
  const outcomes = body.career_outcomes || []
  const perYear = fees.filter(feeIsAnnual), whole = fees.filter(f => !feeIsAnnual(f))
  const marketName = markets.find(m => m.code === market)?.name
  return (
    <div className="d-grid">
      <Section title="Overview">
        {body.description ? <p className="d-text">{body.description}</p> : <None />}
        <dl className="d-facts">
          <div><dt>Level</dt><dd>{body.level?.name || NOT_RECORDED}</dd></div>
          <div><dt>Field</dt><dd>{body.field || NOT_RECORDED}</dd></div>
          <div><dt>Length</dt><dd>{durationText(body.duration_value, body.duration_unit)}</dd></div>
          <div><dt>Delivery</dt><dd>{deliveryText(body.delivery_mode)}</dd></div>
          <div><dt>Course code</dt><dd>{body.course_code || NOT_RECORDED}</dd></div>
        </dl>
      </Section>

      <Section title="Campuses and delivery">
        {campuses.length === 0 ? <None /> : <ul className="d-list">{campuses.map((k, n) => (
          <li key={k.campus_id || n}><strong>{k.name}</strong>{[k.city, stateShort(k.state_code)].filter(Boolean).length > 0 && <span className="muted">{[k.city, stateShort(k.state_code)].filter(Boolean).join(', ')}</span>}
            <div className="tags">{k.delivery_mode && <Pill>{deliveryText(k.delivery_mode)}</Pill>}{k.is_primary && <Pill tone="teal">Main campus</Pill>}</div></li>
        ))}</ul>}
        {body.open_to_international === false && <p className="muted small">This course is not open to international students.</p>}
      </Section>

      <Section title="Fees" note="Amounts are shown as recorded. Different lines are not added together.">
        {fees.length === 0 && !body.annual_tuition ? <None /> : (
          <>
            {perYear.length > 0 && <FeeList rows={perYear} />}
            {perYear.length === 0 && body.annual_tuition && <ul className="d-list"><li><span className="d-k">Tuition per year (provider)</span><strong className="d-v">{money(body.annual_tuition.amount, body.annual_tuition.currency) || NOT_RECORDED}</strong></li></ul>}
            {whole.length > 0 && <FeeList rows={whole} />}
          </>
        )}
      </Section>

      <Section title="Intakes and deadlines">
        {intakes.length === 0 ? <None what="No upcoming intake recorded" /> : <ul className="d-list">{intakes.map((i, n) => (
          <li key={n}><strong>{intakeText(i)}</strong>
            <span className="muted">{i.start_date ? `starts ${dateText(i.start_date, 'day')}` : 'start date not recorded'} · {i.application_deadline ? `apply by ${dateText(i.application_deadline, 'day')}` : 'deadline not recorded'}{i.campus ? ` · ${i.campus}` : ''}</span></li>
        ))}</ul>}
      </Section>

      <Section title="Academic entry requirements" note={marketName ? `For students from ${marketName}, with anything that applies to every country.` : 'Showing what applies to every country. Choose the student’s country to include its own requirements.'}>
        <Select label="Student’s country of education" value={market} onChange={setMarket}>
          <option value="">Not chosen</option>
          {markets.map(m => <option key={m.code} value={m.code}>{m.name}</option>)}
        </Select>
        {entry.length === 0 ? <None what={market ? `No academic entry requirement recorded for ${marketName || 'this country'}` : undefined} /> : <ul className="d-list">{entry.map((e, n) => <EntryItem key={n} e={e} />)}</ul>}
        {!market && countrySpecific > 0 && <p className="muted small">{countrySpecific} more {countrySpecific === 1 ? 'requirement applies' : 'requirements apply'} to named countries. Choose a country above.</p>}
      </Section>

      <MatrixSection body={body} market={market} marketName={marketName} />

      <Section title="English language requirements">
        {english.length === 0 ? <None /> : <ul className="d-list">{english.map((e, n) => <li key={n}><strong>{e.test}</strong>{e.overall && <Pill tone="teal">{e.overall}</Pill>}{e.parts && <div className="muted small">{e.parts}</div>}{e.notes && <div className="muted small">{e.notes}</div>}</li>)}</ul>}
      </Section>

      <Section title="Career outcomes" note={`Provider-level results${outcomes[0]?.years ? `, ${outcomes[0].years}` : ''}${outcomes[0]?.survey ? ` (${outcomes[0].survey})` : ''}. They describe ${body.provider?.name || 'the provider'}, not this course.`}>
        {outcomes.length === 0 ? <None /> : <OutcomeList rows={outcomes} />}
      </Section>

      <Section title="Official source">
        <div className="actions">
          <ExtLink className="btn" href={body.official_url}>Open the official course page</ExtLink>
          <ExtLink className="btn" href={body.provider_website}>Open the provider website</ExtLink>
        </div>
        {!body.official_url && <None what="The official course page is not recorded" />}
        {!body.provider_website && <None what="Provider website: Not recorded" />}
        <p className="muted small">Last checked {dateText(body.last_checked, 'day') || NOT_RECORDED}. Confirm fees and entry requirements with the provider before advising a student.</p>
      </Section>
    </div>
  )
}

function FeeList({ rows }) {
  return <ul className="d-list">{rows.map((f, n) => (
    <li key={n}><span className="d-k">{feeLabel(f)}{f.year ? ` · ${f.year}` : ''}{feeAudience(f) ? ` · ${feeAudience(f)}` : ''}{f.campus ? ` · ${f.campus}` : ''}</span><strong className="d-v">{feeAmount(f)}</strong>
      {f.notes && <div className="muted small">{f.notes}</div>}</li>
  ))}</ul>
}

function EntryItem({ e }) {
  return (
    <li><span className="d-k">{e.kind}{e.countryName ? ` · ${e.countryName}` : ''}</span>
      <div>{e.main || NOT_RECORDED}{e.grade && <> <Pill tone="teal">{e.grade}</Pill></>}</div>
      <div className="muted small">{e.asAt ? `Checked ${dateText(e.asAt, 'day')}` : ''} {e.url && <ExtLink className="textlink" href={e.url}>Source</ExtLink>}</div></li>
  )
}

function OutcomeList({ rows }) {
  return <ul className="d-list">{rows.map((o, n) => (
    <li key={n}><span className="d-k">{o.metric}</span><strong className="d-v">{outcomeValue(o)}</strong>
      {Number.isFinite(Number(o.national_benchmark)) && o.national_benchmark !== null && <div className="muted small">National figure {outcomeValue({ ...o, value: o.national_benchmark })}</div>}</li>
  ))}</ul>
}

// s1220: the provider's country-by-country entry requirements (entry_matrix, s1216), for the student's country when one is chosen.
function MatrixSection({ body, market, marketName }) {
  const [all, setAll] = useState(false)
  const rows = body.entry_matrix || []
  const total = Number(body.entry_matrix_total) || rows.length
  const shown = (all ? rows : matrixForMarket(rows, market)).map(matrixLine)
  const hidden = rows.length - shown.length
  return (
    <Section title="Entry requirements by country (provider)" note={market && !all ? `The provider’s published requirement for students from ${marketName || 'the chosen country'}, with any that applies to every country.` : 'The provider’s published requirements by the student’s country of education.'}>
      {rows.length === 0 ? <None /> : shown.length === 0 ? <None what={`No row recorded for ${marketName || 'this country'}`} /> : (
        <ul className="d-list d-matrix">{shown.map((m, n) => (
          <li key={n}>
            <span className="d-k">{m.country}{m.forCourse ? ' · this course' : ''}</span>
            <div>{m.qualification || NOT_RECORDED}{m.grade && <> <Pill tone="teal">{m.grade}</Pill></>}{m.band && <> <Pill>{m.band}</Pill></>}</div>
            {(m.scale || m.level) && <div className="muted small">{[m.scale && `Scale: ${m.scale}`, m.level].filter(Boolean).join(' · ')}</div>}
            {m.conditions && <div className="muted small">{m.conditions}</div>}
            <div className="muted small">{m.asAt ? `Checked ${dateText(m.asAt, 'day')}` : ''} {m.url && <ExtLink className="textlink" href={m.url}>Source</ExtLink>}</div>
          </li>
        ))}</ul>
      )}
      {(hidden > 0 || all) && rows.length > 0 && market && <div className="actions"><button type="button" className="btn" onClick={() => setAll(a => !a)}>{all ? `Show ${marketName || 'the chosen country'} only` : `Show all ${rows.length} rows`}</button></div>}
      {total > rows.length && <p className="muted small">Showing {rows.length} of {total} rows recorded for this provider. The provider’s source page has the rest.</p>}
    </Section>
  )
}

