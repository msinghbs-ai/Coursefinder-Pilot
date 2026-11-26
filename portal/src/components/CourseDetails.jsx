import React, { useEffect, useState } from 'react'
import { usePortal } from '../lib/portal.jsx'
import { useCourseDetail } from '../lib/courseDetail.js'
import { rpc } from '../lib/api.js'
import { feeLabel, feeAmount, feeAudience, entryLine, entryForMarket, englishLine, outcomeValue, intakeText, deliveryText, durationText, matrixLine, groupByScope, primaryFeeAmount, primaryFeeNote } from '../lib/courseDetailFormat.js'
import { dateText, stateShort, money, NOT_RECORDED } from '../lib/format.js'
import { ExtLink } from './ExtLink.jsx'
import { Pill, Select, MarketOptions } from './ui.jsx'

// Course details (Courses, Saved courses, Entry Requirements). Since s1222 it opens in the right-hand drawer (DetailDrawer.jsx), and
// it reads the course when it is opened. "Not recorded" is said here, inside the details, never on the concise cards.
export const DetailsButton = ({ open, onClick, id }) => (
  <button type="button" className={`btn${open ? ' open' : ''}`} aria-expanded={Boolean(open)} aria-haspopup="dialog" aria-controls={id} onClick={onClick}>Course details</button>
)

const Section = ({ title, note, children }) => (
  <section className="d-sec"><h4>{title}</h4>{note && <p className="muted small">{note}</p>}{children}</section>
)
const None = ({ what }) => <p className="muted">{what || NOT_RECORDED}</p>

export function CourseDetails({ id, courseId }) {
  const { market, markets, setMarket, priority } = usePortal()
  const d = useCourseDetail(courseId, true)
  const body = d.data
  return (
    <div className="details" id={id} role="region" aria-label="Course details" aria-live="polite">
      {d.loading && <p className="muted" role="status">Loading the course details…</p>}
      {d.error && <div className="notice bad" role="alert">{d.unavailable ? 'Course details are not switched on yet.' : d.error}</div>}
      {d.gone && <div className="notice" role="status">This course is no longer listed, so its details are not shown.</div>}
      {body && <Body body={body} market={market} markets={markets} priority={priority} setMarket={setMarket} />}
    </div>
  )
}

function Body({ body, market, markets, priority, setMarket }) {
  const campuses = body.campuses || [], fees = body.fees || [], intakes = body.intakes || []
  const english = (body.english_requirements || []).map(englishLine)
  const outcomes = body.career_outcomes || []
  const primary = body.primary_fee || (body.annual_tuition ? { per_year: body.annual_tuition.amount, currency: body.annual_tuition.currency } : null)
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
          <div><dt>{body.regulator?.label ? `${body.regulator.label} code` : 'Course code'}</dt><dd>{body.regulator?.code || body.course_code || NOT_RECORDED}</dd></div>
        </dl>
      </Section>

      <Section title="Campuses and delivery">
        {campuses.length === 0 ? <None /> : <ul className="d-list">{campuses.map((k, n) => (
          <li key={k.campus_id || n}><strong>{k.name}</strong>{[k.city, stateShort(k.state_code)].filter(Boolean).length > 0 && <span className="muted">{[k.city, stateShort(k.state_code)].filter(Boolean).join(', ')}</span>}
            <div className="tags">{k.delivery_mode && <Pill>{deliveryText(k.delivery_mode)}</Pill>}{k.is_primary && <Pill tone="teal">Main campus</Pill>}</div></li>
        ))}</ul>}
        {body.open_to_international === false && <p className="muted small">This course is not open to international students.</p>}
      </Section>

      <Section title="Fees" note="One annual tuition fee: the provider's fee for the current year where it is held. Different lines are not added together.">
        {primaryFeeAmount(primary) ? (
          <ul className="d-list"><li><span className="d-k">Tuition per year (provider){primary.year ? ` · ${primary.year}` : ''}</span><strong className="d-v">{primaryFeeAmount(primary)}</strong><span className="muted small">{primaryFeeNote(primary)}</span></li></ul>
        ) : <None what="Annual tuition fee: Not recorded" />}
        {fees.length > 0 && (
          <details className="d-more"><summary>Other recorded fee lines ({fees.length})</summary><FeeList rows={fees} /></details>
        )}
      </Section>

      <Section title="Intakes and deadlines">
        {intakes.length === 0 ? <None what="No upcoming intake recorded" /> : <ul className="d-list">{intakes.map((i, n) => (
          <li key={n}><strong>{intakeText(i)}</strong>
            <span className="muted">{i.start_date ? `starts ${dateText(i.start_date, 'day')}` : 'start date not recorded'} · {i.application_deadline ? `apply by ${dateText(i.application_deadline, 'day')}` : 'deadline not recorded'}{i.campus ? ` · ${i.campus}` : ''}</span></li>
        ))}</ul>}
      </Section>

      <EntrySection body={body} market={market} markets={markets} priority={priority} setMarket={setMarket} marketName={marketName} />

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

// s1222: academic entry requirements in one place. The student's country picks the provider's rows for that country (this course,
// this study level, every course at the provider) through portal_entry_matrix_v1, so the chosen country is never cut off; rows that name
// no country apply to everyone; the course's own requirement lines follow.
function EntrySection({ body, market, markets, priority, setMarket, marketName }) {
  const [state, setState] = useState({ loading: false, rows: [], countryRows: 0, providerHas: true, error: '' })
  const [all, setAll] = useState(false)
  useEffect(() => {
    if (!market) { setState({ loading: false, rows: [], countryRows: 0, providerHas: true, error: '' }); return undefined }
    let live = true
    setState(s => ({ ...s, loading: true, error: '' }))
    rpc('portal_entry_matrix_v1', { p_args: { course_id: body.course_id, source_country: market } })
      .then(r => { if (live) setState({ loading: false, rows: (r?.rows || []).map(matrixLine), countryRows: Number(r?.country_rows) || 0, providerHas: r?.provider_has_matrix !== false, error: '' }) })
      .catch(e => { if (live) setState({ loading: false, rows: [], countryRows: 0, providerHas: true, error: e.message }) })
    return () => { live = false }
  }, [market, body.course_id])

  const detailRows = (body.entry_matrix || []).map(matrixLine)
  const everyCountry = detailRows.filter(l => !l.countryCode)
  const shown = market ? state.rows : (all ? detailRows : everyCountry)
  const courseLines = entryForMarket(body.entry_requirements || [], market).map(entryLine)
  const total = Number(body.entry_matrix_total) || detailRows.length
  const provider = body.provider?.name || 'This provider'
  return (
    <Section title="Academic entry requirements" note={market ? `For students from ${marketName || 'the chosen country'}, with anything that applies to every country.` : 'Choose the student’s country of education to see the provider’s requirement for that country.'}>
      <Select label="Student’s country of education" value={market} onChange={setMarket}>
        <option value="">Not chosen</option>
        <MarketOptions markets={markets} priority={priority} />
      </Select>
      {market && state.loading && <p className="muted" role="status">Loading the requirements for {marketName || 'that country'}…</p>}
      {market && state.error && <div className="notice bad" role="alert">{state.error}</div>}
      {market && !state.loading && !state.error && state.countryRows === 0 && (
        <div className="notice" role="status">{provider} has no entry requirement recorded for {marketName || 'this country'}{state.providerHas ? '' : ' (no country-by-country table is recorded for this provider yet)'}.{shown.length || courseLines.length ? ' What applies to every country is shown below.' : ''}</div>
      )}
      {shown.length > 0 && groupByScope(shown).map(g => (
        <div key={g.key} className="d-group">
          <h5>{g.label}</h5>
          <ul className="d-list d-matrix">{g.rows.map((m, n) => <MatrixItem key={n} m={m} />)}</ul>
        </div>
      ))}
      {!market && detailRows.length > everyCountry.length && (
        <div className="actions"><button type="button" className="btn" onClick={() => setAll(a => !a)}>{all ? 'Show only what applies to every country' : `Show all ${detailRows.length} country rows`}</button></div>
      )}
      {!market && all && total > detailRows.length && <p className="muted small">Showing {detailRows.length} of {total} rows recorded for this provider. Choose the student’s country to see that country’s rows in full.</p>}
      {courseLines.length > 0 && (
        <div className="d-group">
          <h5>Course requirement lines</h5>
          <ul className="d-list">{courseLines.map((e, n) => <EntryItem key={n} e={e} />)}</ul>
        </div>
      )}
      {!market && shown.length === 0 && courseLines.length === 0 && detailRows.length === 0 && <None />}
    </Section>
  )
}

function MatrixItem({ m }) {
  return (
    <li>
      <span className="d-k">{m.country}</span>
      <div>{m.qualification || NOT_RECORDED}{m.grade && <> <Pill tone="teal">{m.grade}</Pill></>}{m.band && <> <Pill>{m.band}</Pill></>}</div>
      {(m.scale || m.level) && <div className="muted small">{[m.scale && `Scale: ${m.scale}`, m.level].filter(Boolean).join(' · ')}</div>}
      {m.conditions && <div className="muted small">{m.conditions}</div>}
      <div className="muted small">{m.asAt ? `Checked ${dateText(m.asAt, 'day')}` : ''} {m.url && <ExtLink className="textlink" href={m.url}>Source</ExtLink>}</div>
    </li>
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

export { money }
