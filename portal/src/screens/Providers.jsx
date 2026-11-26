import React, { useState } from 'react'
import { usePortal, usePagedList, useDebounced } from '../lib/portal.jsx'
import { initials, stateShort } from '../lib/format.js'
import { PageHead, StudyInBar, PillGroup, Select, LoadState, ShowMore, Count, Pill, MarketOptions } from '../components/ui.jsx'
import { ExtLink } from '../components/ExtLink.jsx'

const ROUTE_WORDS = {
  represented: ['green', 'Represented'], direct: ['blue', 'Direct'], not_represented: ['grey', 'Not represented'], not_recorded: ['dashed', 'Status not recorded'],
}
const routeName = code => (ROUTE_WORDS[code] || [null, String(code || '').replace(/_/g, ' ')])[1]

const joinNames = names => names.length < 2 ? names.join('') : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`

function routeText(p) {
  const markets = Array.isArray(p.route_markets) ? p.route_markets : []
  const list = joinNames(markets)
  if (p.route === 'represented') {
    if (p.route_mode === 'include' && markets.length) return `Applications through Study Square for ${list}.`
    if (p.route_mode === 'exclude' && markets.length) return `Applications through Study Square, except for ${list}.`
    return 'Applications through Study Square for all markets.'
  }
  if (p.route === 'direct') return 'Apply direct with the provider. Study Square does not submit the application.'
  if (p.route === 'not_represented') return 'Study Square cannot process applications for this provider.'
  return 'No status recorded yet. Ask the Study Square team before promising a route.'
}

function ProviderCard({ p }) {
  const [tone, word] = ROUTE_WORDS[p.route] || ['grey', routeName(p.route)]
  const place = [stateShort(p.state_code), p.city].filter(Boolean)
  return (
    <article className="card prov">
      <header className="prov-head">
        <span className="logo-tile" aria-hidden="true">{initials(p.short_name || p.name)}</span>
        <div>
          <h3>{p.name}</h3>
          <div className="tags">
            {p.type_name && <Pill>{p.type_name}</Pill>}
            {place.length > 0 && <Pill><strong>{place[0]}</strong>{place[1] && <span>{place[1]}</span>}</Pill>}
            <Pill>{p.country_code}</Pill>
          </div>
        </div>
      </header>
      <div className="route-box">
        <Pill tone={tone === 'dashed' ? 'grey' : tone} dashed={tone === 'dashed'}>{word}</Pill>
        <p>{routeText(p)}</p>
      </div>
      <div className="actions">
        <a className="btn primary" href={`#/courses?provider=${p.id}&providerName=${encodeURIComponent(p.name)}`}>View courses{p.course_count ? ` (${p.course_count.toLocaleString('en-AU')})` : ''}</a>
        {p.website
          ? <ExtLink className="btn" href={p.website}>Provider website</ExtLink>
          : <span className="muted small">Website not recorded</span>}
      </div>
    </article>
  )
}

export default function Providers() {
  const { studyIn, market, setMarket, markets, priority } = usePortal()
  const [text, setText] = useState('')
  const [type, setType] = useState('')
  const [route, setRoute] = useState('')
  const [state, setState] = useState('')
  const q = useDebounced(text.trim())
  const args = { q, countries: studyIn ? [studyIn] : [], types: type ? [type] : [], states: state ? [state] : [], routes: route ? [route] : [], market }
  const list = usePagedList('portal_providers_v1', args)
  const f = list.facets || {}
  const stateValid = !state || (f.states || []).some(s => s.code === state)

  return (
    <div className="stack-lg">
      <PageHead title="Universities & Providers" sub="Every published provider, and whether Study Square can process applications." />
      <StudyInBar />
      <section className="card filters" aria-label="Filters">
        <label className="field wide"><span className="field-label">Search</span>
          <input type="search" placeholder="University, TAFE or college" value={text} onChange={e => setText(e.target.value)} />
        </label>
        <PillGroup label="Provider type" value={type} onChange={setType}
          options={[{ value: '', label: 'All' }, ...(f.types || []).map(t => ({ value: t.code, label: t.name, count: t.count }))]} />
        <PillGroup label="Study Square can process applications" value={route} onChange={setRoute}
          options={[{ value: '', label: 'Any' }, ...(f.routes || []).map(r => ({ value: r.code, label: routeName(r.code), count: r.count }))]} />
        <div className="selects">
          <Select label="State" value={stateValid ? state : ''} onChange={setState}>
            <option value="">Any state</option>
            {(f.states || []).map(s => <option key={s.code} value={s.code}>{s.name} ({s.count})</option>)}
          </Select>
          <Select label="Student market" value={market} onChange={setMarket}>
            <option value="">Not chosen</option>
            <MarketOptions markets={markets} priority={priority} />
          </Select>
        </div>
      </section>
      <LoadState loading={list.loading && !list.items.length} error={list.error} unavailable={list.unavailable} onRetry={list.retry} what="providers" />
      {!list.loading && !list.error && (
        <>
          <div className="count-row">
            <Count n={list.total}>{list.total === 1 ? 'provider' : 'providers'} shown</Count>
            <span className="muted small">{market ? 'The application route follows the student market chosen above.' : 'Choose a student market to see the route for that market.'}</span>
          </div>
          {list.total === 0 && <div className="empty"><strong>No providers match.</strong><p className="muted">Clear a filter or change the destination to see more.</p></div>}
          <div className="grid2">{list.items.map(p => <ProviderCard key={p.id} p={p} />)}</div>
          <ShowMore shown={list.items.length} total={list.total} loading={list.more} onClick={list.showMore} noun="providers" />
        </>
      )}
    </div>
  )
}
