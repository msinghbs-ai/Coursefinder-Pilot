// Guards: Platform Admin 22 Nov 2026 09:22 AEDT (IR-005 / RM1J): THE and QS are attributed public rankings read by Layer 1 readers and published live; no publisher file or terms hold
// s966. The THE and QS readers in ranking-layer1-etl v1.8.0: deterministic JSON parsing (exact ranks, ties, bands, reporters, overall and
// pillar scores), edition year and attribution, robots.txt honoured, a challenge page reported and never bypassed, $0 (no Firecrawl, no
// browser, no AI); and the migration that publishes the edition, links register-name parts deterministically and queues the first run.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PUBLIC_SOURCES, attribution, isChallenge, parsePublicRank, qsIndicatorCode, qsRowsFromRestPages, robotsAllows, robotsRules, scoreParts, theRowsFromPublicJson } from '../../supabase/functions/ranking-layer1-etl/public-readers.ts'

const read = (p) => fs.readFileSync(p, 'utf8')
const THE = JSON.parse(read('tests/fixtures/rankings/the-wur-2027-sample.json'))
const QS = JSON.parse(read('tests/fixtures/rankings/qs-wur-2027-sample-pages.json'))
const ETL = read('supabase/functions/ranking-layer1-etl/index.ts')
const READERS = read('supabase/functions/ranking-layer1-etl/public-readers.ts')
const MIG = read('supabase/migrations/20261122110000_cf247_s966_public_ranking_readers_the_qs.sql')

test.describe('CF-247 s966 public ranking readers (THE and QS)', () => {
  test('ranks: exact, tied, bands, open bands, reporters; anything else is unknown', () => {
    expect(parsePublicRank('1')).toMatchObject({ rank_exact: 1, is_tied: false, rank_status: 'ranked_exact' })
    expect(parsePublicRank('=34')).toMatchObject({ rank_display: '=34', rank_exact: 34, is_tied: true, rank_status: 'ranked_exact' })
    expect(parsePublicRank('34=')).toMatchObject({ rank_exact: 34, is_tied: true })
    expect(parsePublicRank('601–650')).toMatchObject({ rank_low: 601, rank_high: 650, rank_exact: null, rank_status: 'ranked_band' })
    expect(parsePublicRank('1001-1200')).toMatchObject({ rank_low: 1001, rank_high: 1200, rank_status: 'ranked_band' })
    expect(parsePublicRank('1501+')).toMatchObject({ rank_low: 1501, rank_high: null, rank_status: 'ranked_band' })
    expect(parsePublicRank('Reporter')).toMatchObject({ rank_status: 'reporter', rank_exact: null })
    expect(parsePublicRank('n/a')).toMatchObject({ rank_status: 'unranked' })
    expect(parsePublicRank('')).toMatchObject({ rank_status: 'unranked', rank_display: null })
    expect(parsePublicRank('top ten').rank_status).toBe('unknown')
    expect(parsePublicRank('0').rank_status).toBe('unknown')
    expect(scoreParts('97.9')).toEqual({ display: '97.9', numeric: 97.9, low: null, high: null })
    expect(scoreParts('43.4–44.4')).toEqual({ display: '43.4–44.4', numeric: null, low: 43.4, high: 44.4 })
    expect(scoreParts('n/a')).toEqual({ display: null, numeric: null, low: null, high: null })
  })

  test('THE: rows from the public ranking JSON keep ranks, ties, pillar scores, publisher labels and the earlier pillar codes', () => {
    const { rows, stats } = theRowsFromPublicJson(THE, 2027)
    expect(stats).toMatchObject({ rows: 6, exact: 3, tied: 2, bands: 2, reporters: 1 })
    const ox = rows[0]
    expect(ox).toMatchObject({ publisher_institution_id: '468', institution_name: 'University of Oxford', country_text: 'United Kingdom', rank_exact: 1, overall_score: 97.9 })
    expect(Object.keys(ox.indicators).sort()).toEqual(['citations', 'industry_income', 'international_outlook', 'overall', 'research', 'teaching'])
    expect(ox.indicators.research).toMatchObject({ label: 'Research Environment', value_numeric: 100, rank_exact: 2, methodology_version: '2027' })
    expect(ox.indicators.citations).toMatchObject({ label: 'Research Quality', value_numeric: 96.8, rank_exact: 13 })
    expect(ox.indicators.industry_income.label).toBe('Industry')
    // scores_overall_rank is the sort order, not a rank
    expect(ox.indicators.overall.rank_exact).toBeUndefined()
    expect(ox.source_row_payload.apply_link).toBeUndefined()
    expect(ox.source_row_payload.cta_button).toBeUndefined()
    expect(ox.source_row_payload.edition_year).toBe(2027)
    const mel = rows.find((r) => r.institution_name === 'The University of Melbourne')
    expect(mel).toMatchObject({ rank_display: '=34', rank_exact: 34, is_tied: true, country_text: 'Australia' })
    const band = rows.find((r) => r.institution_name === 'Example University B')
    expect(band).toMatchObject({ rank_low: 601, rank_high: 650, overall_score: null, overall_score_low: 43.4, overall_score_high: 44.4 })
    expect(rows.find((r) => r.institution_name === 'Example Reporter College').rank_status).toBe('reporter')
    expect(() => theRowsFromPublicJson({ data: [] }, 2027)).toThrow(/no data rows/)
    expect(() => theRowsFromPublicJson({ data: [{ name: 'X', rank: 'soon' }] }, 2027)).toThrow(/does not recognise/)
  })

  test('QS: rows from the public results pages keep ranks, ties (printed or repeated), bands and indicator codes; a short read fails', () => {
    const { rows, stats } = qsRowsFromRestPages(QS, 2027)
    expect(stats).toMatchObject({ rows: 5, exact: 3, bands: 2 })
    const mit = rows[0]
    expect(mit).toMatchObject({ publisher_institution_id: '294850', institution_name: 'Massachusetts Institute of Technology (MIT)', rank_exact: 1, overall_score: 100, location_text: 'Cambridge, United States' })
    expect(mit.indicators.academic_reputation).toMatchObject({ label: 'Academic Reputation', value_numeric: 100, rank_exact: 4, group: 'Research & Discovery' })
    expect(mit.indicators.sustainability).toMatchObject({ rank_display: '=43', rank_exact: 43, is_tied: true })
    expect(mit.source_row_payload.logo).toBeUndefined()
    const mel = rows.find((r) => r.country_text === 'Australia')
    expect(mel).toMatchObject({ rank_display: '=2', rank_exact: 2, is_tied: true })
    const d = rows.find((r) => r.institution_name === 'Example University D')
    expect(d).toMatchObject({ rank_display: '=2', is_tied: true })
    expect(rows.find((r) => r.country_text === 'New Zealand')).toMatchObject({ rank_low: 1001, rank_high: 1200, overall_score: null })
    expect(qsIndicatorCode('Faculty Student Ratio')).toBe('faculty_student_ratio')
    expect(qsIndicatorCode('International Research Network')).toBe('international_research_network')
    expect(() => qsRowsFromRestPages([QS[0]], 2027)).toThrow(/lists 5 institutions but returned 3/)
  })

  test('robots.txt is honoured (paths and crawl-delay) and a challenge page is never treated as data', () => {
    const theRobots = 'User-agent: *\nDisallow: /includes/\nDisallow: /sites/default/files/pdf/\nDisallow: *?*search=*\n'
    const qsRobots = 'User-agent: *\ncrawl-delay: 10\nAllow: /profiles/*.css$\nDisallow: /profiles/\nDisallow: /search/\nDisallow: /qs-profiles/rank-data/.*\n'
    expect(robotsAllows(theRobots, PUBLIC_SOURCES.the_wur.jsonUrl(2027))).toBe(true)
    expect(robotsAllows(theRobots, 'https://www.timeshighereducation.com/sites/default/files/pdf/x.pdf')).toBe(false)
    expect(robotsAllows(qsRobots, 'https://www.topuniversities.com/rankings/endpoint?nid=4153156&tab=indicators&items_per_page=500&page=0')).toBe(true)
    expect(robotsAllows(qsRobots, 'https://www.topuniversities.com/profiles/x')).toBe(false)
    expect(robotsAllows(qsRobots, 'https://www.topuniversities.com/profiles/a.css')).toBe(true)
    expect(robotsRules(qsRobots).crawlDelaySeconds).toBe(10)
    expect(robotsRules('User-agent: Googlebot\nCrawl-delay: 99\n\nUser-agent: *\nDisallow: /x/\n')).toMatchObject({ crawlDelaySeconds: null, disallow: ['/x/'] })
    expect(isChallenge(403, 'text/html', '<!DOCTYPE html><html><head><title>Just a moment...</title>')).toBe(true)
    expect(isChallenge(200, 'text/html', '<html><script src="https://challenges.cloudflare.com/x"></script>')).toBe(true)
    expect(isChallenge(200, 'application/json', '{"data":[]}')).toBe(false)
  })

  test('attribution names the publisher and the edition', () => {
    expect(attribution('the_wur', 2027)).toMatch(/^Times Higher Education World University Rankings 2027\. Source: Times Higher Education \(timeshighereducation\.com\)/)
    expect(attribution('qs_wur', 2027)).toMatch(/^QS World University Rankings 2027\. Source: QS World University Rankings \(topuniversities\.com\)/)
    expect(PUBLIC_SOURCES.the_wur.jsonUrl(2027)).toBe('https://www.timeshighereducation.com/json/ranking_tables/world_university_rankings/2027')
  })

  test('ranking-layer1-etl applies and publishes public JSON with a plain GET only ($0: no Firecrawl, no browser, no AI)', () => {
    expect(ETL).toMatch(/const VERSION="ranking-layer1-etl-v1\.8\.\d+"/)
    expect(ETL).toContain('fetchThePublic(editionYear)')
    expect(ETL).toContain('"publisher_public_json"')
    expect(ETL).toContain('svc_ranking_public_edition_publish_v1')
    expect(ETL).toContain('robotsFor(src.origin')
    expect(ETL).toContain('no bypass attempted')
    expect(ETL).toContain('temporarily unavailable')
    expect(ETL).not.toContain('Direct publisher JSON APPLY is intentionally disabled')
    for (const src of [ETL, READERS]) {
      expect(src).not.toMatch(/api\.firecrawl|firecrawl\.dev|openrouter\.ai|anthropic\.com|from ['"][^'"]*(playwright|puppeteer|firecrawl)/i)
    }
  })

  test('migration: publish function, THE 2027 source, QS 2027 public mode, initial runs; no new job; consumer API guarded', () => {
    expect(MIG).toMatch(/^-- Replaces: /m)
    expect(MIG).toMatch(/^-- Retires: /m)
    expect(MIG).toContain('create or replace function public.svc_ranking_public_edition_publish_v1(p_system_code text, p_edition_year integer, p_source_artifact_id uuid, p_attribution text)')
    expect(MIG).toContain("security definer set search_path = ''")
    expect(MIG).toContain("if current_user not in ('service_role', 'postgres') then raise exception 'service role required'")
    expect(MIG).toContain('grant execute on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) to service_role;')
    expect(MIG).not.toMatch(/grant [^;]*svc_ranking_public_edition_publish_v1[^;]* to [^;]*(anon|authenticated)/i)
    expect(MIG).toContain("access_status = 'public'")
    expect(MIG).toContain("set status = 'superseded'")
    expect(MIG).toContain("'primary_name_segment_country'")
    expect(MIG).toContain("'Times Higher Education World University Rankings 2027'")
    expect(MIG).toContain("'acquisition_mode', 'publisher_public_json'")
    expect(MIG).toContain("'s966-initial:' || s.id::text")
    expect(MIG).toContain('security.consumer_api_check_v1()')
    expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|alter table [^;]* drop |delete from |truncate /i)
  })
})
