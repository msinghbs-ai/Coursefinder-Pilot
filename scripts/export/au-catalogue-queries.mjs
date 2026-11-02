// AU catalogue export: the read-only queries (Platform Admin 2 Nov 2026 11:10 §1 and §4; snapshot method 11:18).
// Pure data, no side effects: scripts/export/au-catalogue-export.mjs runs these, and tests/uat/cf-247-s219-au-catalogue-export-contract
// checks that every one is a single read-only select (no insert, update, delete, merge, DDL, grant or function that writes).
//
// Every dataset is read with keyset pagination on its own unique key (`key`, in order): the page boundary is read first
// (boundarySql, index order, limit = batch), then the rows from the previous boundary (exclusive) to this one (inclusive) are copied
// (pageSql). Nothing is flattened: each one-to-many table is its own dataset, with its stable ids. Null stays empty in the CSV.
//
// Flag columns added to the database columns start with x_ so they never collide with a table column:
//   x_admission_state   admitted (status active) | held (unverified or proposed: stored from the source, not admitted)
//                       | retired (inactive, superseded, withdrawn or deprecated) | the raw status otherwise
//   x_consumer_visible  the row is served by Website API v2 under the rule written in the dataset's `visibleRule` (exact copy of the
//                       live projection or payload condition); null where the API does not read the table
//   x_course_in_website_api_v2  the course has a search.course_documents row (the API's course population)
// Every child row is a source-held value (its source_id or source_url names the source). Rejections are Layer 4 decisions, exported in
// layer4_course_review_items and summarised per field in field_state_reconciliation.

export const COUNTRY_RE = /^[A-Z]{2}$/

export function sets(country) {
  if (!COUNTRY_RE.test(country)) throw new Error(`country must be two capital letters, got ${country}`)
  const AUP = `(select p.id from catalogue.providers p where p.country_id = (select co.id from ref.countries co where co.iso_alpha2 = '${country}'))`
  const AUC = `(select c.id from catalogue.courses c where c.provider_id in ${AUP})`
  const AUS = `(select s.id from scholarship.scholarships s where s.provider_id in ${AUP} union select m.scholarship_id from scholarship.course_mappings m where m.course_id in ${AUC})`
  return { AUP, AUC, AUS }
}

export const ADMISSION = (col) => `case ${col} when 'active' then 'admitted' when 'unverified' then 'held' when 'proposed' then 'held'
  when 'inactive' then 'retired' when 'superseded' then 'retired' when 'withdrawn' then 'retired' when 'deprecated' then 'retired' else ${col} end`
const DOC = (col) => `exists (select 1 from search.course_documents d0 where d0.course_id = ${col})`
// served: a projection row and no active Layer 4 search block (api.website_v2_course_item returns null for a blocked course, 2 Nov 2026 live body)
const SERVED = (col) => `(${DOC(col)} and ${col} not in (select b.course_id from security.layer4_search_blocked_courses b where b.course_id is not null))`
const GATE = (domain, src) => `exists (select 1 from search.enrichment_source_gates sg where sg.projection_code = 'courses' and sg.domain_code = '${domain}' and sg.source_id = ${src} and sg.gate_status = 'approved')
  and exists (select 1 from search.enrichment_gates g where g.projection_code = 'courses' and g.domain_code = '${domain}' and g.gate_status = 'approved')`
const VALID = (a) => `(${a}.valid_from is null or ${a}.valid_from <= current_date) and (${a}.valid_to is null or ${a}.valid_to >= current_date)`

// docColumns: the live search.course_documents columns (read from the catalogue at the start), less the two derived search columns
export function datasets(country, docColumns = []) {
  const { AUP, AUC, AUS } = sets(country)
  const docCols = docColumns.filter((c) => !['search_tsv', 'search_text'].includes(c))
  const D = [
    {
      name: 'courses', sheet: '01 Courses', key: ['c.id'], idColumn: 'id', courseColumn: 'id',
      from: `catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id
        left join ref.study_levels sl on sl.id = c.study_level_id left join ref.fields_of_study fos on fos.id = c.primary_field_id
        left join ref.subdivisions psd on psd.id = p.subdivision_id`,
      where: `c.provider_id in ${AUP}`,
      select: `c.*, p.stable_key as x_provider_stable_key, coalesce(p.display_name, p.canonical_name) as x_provider_name,
        p.lifecycle_status as x_provider_lifecycle_status, p.publication_status as x_provider_publication_status, trim(co.iso_alpha2::text) as x_country_code,
        psd.code as x_provider_subdivision_code, sl.code as x_study_level_code, sl.name as x_study_level_name, fos.code as x_primary_field_code, fos.name as x_primary_field_name,
        ${DOC('c.id')} as x_in_website_api_v2,
        c.id in (select b.course_id from security.layer4_search_blocked_courses b) as x_website_search_blocked,
        ${SERVED('c.id')} as x_consumer_visible,
        (c.lifecycle_status = 'active' and p.lifecycle_status = 'active' and p.publication_status = 'published'
          and exists (select 1 from search.projection_country_gates pg where pg.projection_code = 'courses' and pg.gate_status = 'approved' and pg.country_id = p.country_id)) as x_projection_gate_eligible`,
      visibleRule: 'x_in_website_api_v2: the course has a search.course_documents row. The projection (search.refresh_course_base_v3) admits a course when it is active, its provider is active and published, and the provider country has an approved courses gate (x_projection_gate_eligible); search and the course item (api.website_v2_course_item) both leave out a course with an active Layer 4 search block (x_website_search_blocked). x_consumer_visible: served to the website (projection row and no block). Every child x_consumer_visible also requires its course to be served.',
    },
    {
      name: 'course_fees', sheet: '02 Course fees', key: ['f.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id`,
      where: `f.course_id in ${AUC}`,
      select: `f.*, s.label as x_source_label, s.source_type as x_source_type, ${ADMISSION('f.status')} as x_admission_state,
        ${DOC('f.course_id')} as x_course_in_website_api_v2,
        (${SERVED('f.course_id')} and f.status = 'active' and f.audience in ('international', 'all') and f.fee_type in ('tuition', 'provider_current_tuition')) as x_consumer_visible,
        (f.status = 'active' and f.audience in ('international', 'all') and f.fee_type = 'provider_current_tuition' and ${VALID('f')} and ${GATE('provider_current_tuition', 'f.source_id')}) as x_in_projection_tuition_options,
        (f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and s.label = 'CRICOS Providers, Courses and Locations'
          and f.id = (select f2.id from catalogue.course_fees f2 join pipeline.sources s2 on s2.id = f2.source_id where f2.course_id = f.course_id and f2.status = 'active'
            and f2.audience in ('international', 'all') and f2.fee_type = 'tuition' and f2.basis = 'registered_total_course' and s2.label = 'CRICOS Providers, Courses and Locations'
            order by f2.updated_at desc nulls last, f2.id limit 1)) as x_is_projection_regulatory_fee`,
      visibleRule: 'x_consumer_visible: the course detail tuition_history (website_v2_course) serves every active fee with audience international or all and fee_type tuition or provider_current_tuition. x_in_projection_tuition_options: the provider tuition options of search.course_documents (active, international or all, provider_current_tuition, inside valid_from/valid_to, source gate approved). x_is_projection_regulatory_fee: the one CRICOS registered total the projection shows.',
    },
    {
      name: 'course_intakes', sheet: '03 Course intakes', key: ['i.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_intakes i left join pipeline.sources s on s.id = i.source_id left join catalogue.campuses k on k.id = i.campus_id`,
      where: `i.course_id in ${AUC}`,
      select: `i.*, s.label as x_source_label, k.name as x_campus_name, k.city as x_campus_city, ${ADMISSION('i.status')} as x_admission_state,
        ${DOC('i.course_id')} as x_course_in_website_api_v2,
        (${SERVED('i.course_id')} and i.status = 'active' and ${GATE('course_intake', 'i.source_id')}) as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: active intake whose source has an approved course_intake gate on a course in the API population (search.refresh_course_enrichment_core_v1 intake_options; the API serves label, month, year, start_date and application_deadline).',
    },
    {
      name: 'course_entry_requirements', sheet: '04 Entry requirements', key: ['r.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_entry_requirements r left join ref.countries co on co.id = r.country_id`,
      where: `r.course_id in ${AUC}`,
      select: `r.*, trim(co.iso_alpha2::text) as x_country_code, ${ADMISSION('r.status')} as x_admission_state,
        ${DOC('r.course_id')} as x_course_in_website_api_v2,
        (${SERVED('r.course_id')} and r.status = 'active' and (r.kind in ('subject_prerequisite', 'portfolio_interview', 'override', 'general_note', 'prior_qualification', 'work_experience')
          or (r.kind = 'minimum_grade' and r.min_entry_score is not null) or (r.benchmark_band is not null and r.audience in ('international', 'all')))) as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: an active row the course detail entry object reads (security.entry_course_payload_v1): prerequisites, selection tasks and the requirements note list every such row; min_score and benchmark_band show only the first eligible row in the payload order (international first, latest updated).',
    },
    {
      name: 'english_requirements', sheet: '05 English requirements', key: ['e.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id left join pipeline.sources s on s.id = e.source_id`,
      where: `e.course_id in ${AUC}`,
      select: `e.*, t.code as x_test_code, t.name as x_test_name, s.label as x_source_label, ${ADMISSION('e.status')} as x_admission_state,
        ${DOC('e.course_id')} as x_course_in_website_api_v2,
        (${SERVED('e.course_id')} and e.status = 'active' and ${VALID('e')} and ${GATE('course_english', 'e.source_id')}) as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: active, inside valid_from/valid_to, source with an approved course_english gate, course in the API population (english_requirement_options).',
    },
    {
      name: 'course_scholarships', sheet: '06 Course scholarships', key: ['m.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
        left join (select fc.mapping_id, count(*) as n from scholarship.course_financial_calculations fc where fc.calculation_status = 'calculated' group by fc.mapping_id) fcs on fcs.mapping_id = m.id`,
      where: `m.course_id in ${AUC}`,
      select: `m.*, s.stable_key as x_scholarship_stable_key, s.name as x_scholarship_name, s.lifecycle_status as x_scholarship_lifecycle_status,
        s.publication_status as x_scholarship_publication_status, s.audience as x_scholarship_audience,
        coalesce(fcs.n, 0) as x_calculated_savings,
        ${DOC('m.course_id')} as x_course_in_website_api_v2,
        (${SERVED('m.course_id')} and m.mapping_state = 'mapped' and s.lifecycle_status = 'active' and s.publication_status in ('published', 'internal')
          and s.audience in ('international', 'international_and_domestic')
          and exists (select 1 from search.enrichment_gates g where g.projection_code = 'courses' and g.domain_code = 'scholarship' and g.gate_status = 'approved')) as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: the course scholarship_options rule (mapped, scholarship active, published or internal, audience international or international_and_domestic, scholarship gate approved). Truncation is per scholarship: see x_mapped_courses and x_linked_courses_truncated in scholarship_master (joined on scholarship_id).',
    },
    {
      name: 'scholarship_master', sheet: '07 Scholarship master', key: ['s.id'], idColumn: 'id',
      from: `scholarship.scholarships s left join catalogue.providers p on p.id = s.provider_id
        left join (select m.scholarship_id, count(*) filter (where m.mapping_state = 'mapped') as mapped, count(*) filter (where m.course_id in ${AUC}) as au
          from scholarship.course_mappings m group by m.scholarship_id) mc on mc.scholarship_id = s.id`,
      where: `s.id in ${AUS}`,
      select: `s.*, p.stable_key as x_provider_stable_key, (s.provider_id in ${AUP}) as x_au_provider,
        coalesce(mc.mapped, 0) as x_mapped_courses, coalesce(mc.au, 0) as x_mapped_au_courses, (coalesce(mc.mapped, 0) > 200) as x_linked_courses_truncated,
        s.id in (select b.scholarship_id from security.layer4_search_blocked_scholarships b) as x_website_search_blocked,
        (s.lifecycle_status = 'active' and s.publication_status = 'published' and s.id not in (select b.scholarship_id from security.layer4_search_blocked_scholarships b where b.scholarship_id is not null)) as x_consumer_visible`,
      visibleRule: 'Scope: scholarships of AU providers, and any scholarship linked to an AU course. x_linked_courses_truncated: the scholarship detail lists 200 linked courses (ordered by course title) and sets linked_courses_truncated when more are mapped. x_consumer_visible: the scholarship detail rule (active, published, no Layer 4 search block).',
    },
  ]
  for (const [name, table, extra] of [
    ['scholarship_award_tiers', 'award_tiers', ''], ['scholarship_criteria', 'criteria', ''], ['scholarship_criterion_groups', 'criterion_groups', ''],
    ['scholarship_application_windows', 'application_windows', ''], ['scholarship_offering_cycles', 'offering_cycles', ''], ['scholarship_identifiers', 'identifiers', ''],
  ]) {
    D.push({ name, sheet: `07 ${name.replace('scholarship_', 'Sch ').replace(/_/g, ' ')}`.slice(0, 31), key: ['x.id'], idColumn: 'id', scholarshipColumn: 'scholarship_id',
      from: `scholarship.${table} x`, where: `x.scholarship_id in ${AUS}`, select: `x.*${extra}`, visibleRule: '' })
  }
  D.push(
    {
      name: 'provider_rankings', sheet: '08 Provider rankings', key: ['r.id'], idColumn: 'id', providerColumn: 'provider_id',
      from: `catalogue.provider_rankings r join ref.ranking_sources rs on rs.id = r.ranking_source_id left join ref.fields_of_study fos on fos.id = r.subject_field_id`,
      where: `r.provider_id in ${AUP}`,
      select: `r.*, rs.code as x_ranking_code, rs.name as x_ranking_name, rs.publisher_name as x_publisher, rs.licence_status as x_licence_status, fos.code as x_subject_field_code`,
      visibleRule: '',
    },
    {
      name: 'provider_entry_matrices', sheet: '09 Entry matrices', key: ['m.id'], idColumn: 'id', providerColumn: 'provider_id',
      from: `catalogue.provider_entry_matrix m left join ref.study_levels sl on sl.id = m.study_level_id`,
      where: `m.provider_id in ${AUP}`,
      select: `m.*, sl.code as x_study_level_code, ${ADMISSION('m.status')} as x_admission_state, (m.status = 'active') as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: the provider detail entry_matrix serves active rows only (security.entry_matrix_payload_v1).',
    },
    {
      name: 'course_links', sheet: '10a Course links', key: ['l.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_links l left join pipeline.sources s on s.id = l.source_id left join search.course_documents d on d.course_id = l.course_id`,
      where: `l.course_id in ${AUC}`,
      select: `l.*, s.label as x_source_label, ${ADMISSION('l.status')} as x_admission_state, (d.course_id is not null) as x_course_in_website_api_v2,
        (l.status = 'active' and ${VALID('l')} and ${GATE('official_course_url', 'l.source_id')}) as x_projection_candidate,
        (d.official_course_url is not null and d.official_course_url = l.url and ${SERVED('l.course_id')}) as x_consumer_visible`,
      visibleRule: 'x_projection_candidate: an active, currently valid link from a source with an approved official_course_url gate. x_consumer_visible: this link is the official_url the API serves (search.course_documents.official_course_url).',
    },
    {
      name: 'course_campuses', sheet: '10b Course campuses', key: ['cc.course_id', 'cc.campus_id', 'cc.delivery_mode'], idColumn: 'course_id|campus_id|delivery_mode', courseColumn: 'course_id',
      from: `catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join ref.subdivisions sd on sd.id = k.subdivision_id`,
      where: `cc.course_id in ${AUC}`,
      select: `cc.*, k.stable_key as x_campus_stable_key, k.name as x_campus_name, k.city as x_campus_city, k.postcode as x_campus_postcode, sd.code as x_campus_subdivision_code,
        k.status as x_campus_status, k.publication_status as x_campus_publication_status, ${SERVED('cc.course_id')} as x_consumer_visible`,
      visibleRule: 'x_consumer_visible: the course item campuses list serves every course_campuses row of a course in the API population.',
    },
    {
      name: 'course_identifiers', sheet: '10c Course identifiers', key: ['i.id'], idColumn: 'id', courseColumn: 'course_id',
      from: `catalogue.course_identifiers i`, where: `i.course_id in ${AUC}`, select: `i.*`, visibleRule: '',
    },
    {
      name: 'course_pages_held', sheet: '10d Course pages held', key: ['g.course_id'], idColumn: 'course_id', courseColumn: 'course_id',
      from: `pipeline.coverage_course_pages g`, where: `g.course_id in ${AUC}`, select: `g.*`, visibleRule: '',
    },
    {
      name: 'search_course_documents', sheet: 'S Projection rows', key: ['d.course_id'], idColumn: 'course_id', courseColumn: 'course_id',
      from: `search.course_documents d`, where: `d.course_id in ${AUC}`,
      select: `${docCols.length ? docCols.map((c) => `d.${c}`).join(', ') : 'd.course_id'}, d.course_id in (select b.course_id from security.layer4_search_blocked_courses b) as x_website_search_blocked`,
      visibleRule: 'The Website API v2 course population and its projection values (search_tsv and search_text left out: derived search text).',
    },
    {
      name: 'layer4_course_review_items', sheet: 'S Layer 4 course items', key: ['l.id'], idColumn: 'id', courseColumn: 'entity_id',
      from: `pipeline.layer4_review_items l`, where: `l.entity_type = 'course' and l.entity_id in ${AUC}`, select: `l.*`, visibleRule: '',
    },
    {
      name: 'providers', sheet: 'S Providers', key: ['p.id'], idColumn: 'id', from: `catalogue.providers p left join ref.subdivisions sd on sd.id = p.subdivision_id`,
      where: `p.id in ${AUP}`, select: `p.*, sd.code as x_subdivision_code`, visibleRule: '',
    },
  )
  for (const [name, sql] of [
    ['ref_study_levels', `ref.study_levels x`], ['ref_fields_of_study', `ref.fields_of_study x`], ['ref_english_tests', `ref.english_tests x`],
    ['ref_ranking_sources', `ref.ranking_sources x`], ['ref_enrichment_gates', `search.enrichment_gates x`], ['ref_enrichment_source_gates', `search.enrichment_source_gates x`],
    ['ref_projection_country_gates', `search.projection_country_gates x`],
  ]) D.push({ name, sheet: `R ${name.slice(4).replace(/_/g, ' ')}`.slice(0, 31), key: null, from: sql, where: 'true', select: 'x.*', visibleRule: '', reference: true })
  D.push({ name: 'ref_sources', sheet: 'R sources', key: ['x.id'], idColumn: 'id', from: 'pipeline.sources x', where: 'true',
    select: 'x.id, x.source_type, x.provider_id, x.country_id, x.url, x.label, x.trust_rank, x.status', visibleRule: '', reference: true })
  return D
}

const keyList = (d) => d.key.join(', ')
const keyTuple = (d) => (d.key.length === 1 ? d.key[0] : `(${keyList(d)})`)
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`
const tupleLit = (d, last) => (d.key.length === 1 ? `${lit(last[0])}` : `(${last.map(lit).join(', ')})`)

// the last key of the next page (null when there is no next page)
export function boundarySql(d, last, batch) {
  const after = last ? ` and ${keyTuple(d)} > ${tupleLit(d, last)}` : ''
  return `select json_build_object('n', count(*), 'last', (array_agg(json_build_array(${d.key.map((k) => `k.${k.split('.')[1]}::text`).join(', ')}) order by ${d.key.map((k) => `k.${k.split('.')[1]}`).join(' desc, ')} desc))[1])
from (select ${d.key.join(', ')} from ${d.from} where ${d.where}${after} order by ${keyList(d)} limit ${Number(batch)}) k`
}

// the rows of the page (last, upto]; a reference dataset (no key) is one page
export function pageSql(d, last, upto) {
  if (!d.key) return `select ${d.select} from ${d.from} where ${d.where}`
  const after = last ? ` and ${keyTuple(d)} > ${tupleLit(d, last)}` : ''
  return `select ${d.select} from ${d.from} where ${d.where}${after} and ${keyTuple(d)} <= ${tupleLit(d, upto)} order by ${keyList(d)}`
}

export function countSql(d) {
  return `select json_build_object('n', count(*)) from ${d.from} where ${d.where}`
}

// snapshot facts and reconciliation counts, read in the same transaction as the data
export function checkSqls(country) {
  const { AUC } = sets(country)
  return {
    snapshot: `select json_build_object('now', now(), 'snapshot', txid_current_snapshot()::text, 'read_only', current_setting('transaction_read_only'),
      'isolation', current_setting('transaction_isolation'), 'statement_timeout', current_setting('statement_timeout'), 'server_version', current_setting('server_version'),
      'database', current_database(), 'user', current_user)`,
    courses: `select json_build_object('n', count(*)) from catalogue.courses c where c.id in ${AUC}`,
    documents: `select json_build_object('n', count(*), 'by_country_code', count(*) filter (where d.country_code = '${country}')) from search.course_documents d where d.course_id in ${AUC}`,
    documentsByCode: `select json_build_object('n', count(*)) from search.course_documents d where d.country_code = '${country}'`,
    regionFallback: `select json_build_object('countries', security.region_fallback_countries_v1())`,
  }
}

export const CATALOGUE_SQL = {
  docColumns: `select json_agg(a.attname order by a.attnum) from pg_attribute a where a.attrelid = 'search.course_documents'::regclass and a.attnum > 0 and not a.attisdropped`,
  // data dictionary: every exported table column with its type and comment
  columns: `select json_agg(json_build_object('table', n.nspname || '.' || c.relname, 'column', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
      'not_null', a.attnotnull, 'comment', col_description(c.oid, a.attnum)) order by n.nspname, c.relname, a.attnum)
    from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    where a.attnum > 0 and not a.attisdropped and (n.nspname || '.' || c.relname) = any(array['catalogue.courses', 'catalogue.course_fees', 'catalogue.course_intakes',
      'catalogue.course_entry_requirements', 'catalogue.course_english_requirements', 'scholarship.course_mappings', 'scholarship.scholarships', 'scholarship.award_tiers',
      'scholarship.criteria', 'scholarship.criterion_groups', 'scholarship.application_windows', 'scholarship.offering_cycles', 'scholarship.identifiers',
      'catalogue.provider_rankings', 'catalogue.provider_entry_matrix', 'catalogue.course_links', 'catalogue.course_campuses', 'catalogue.course_identifiers',
      'pipeline.coverage_course_pages', 'search.course_documents', 'pipeline.layer4_review_items', 'catalogue.providers'])`,
  tables: `select json_agg(json_build_object('table', n.nspname || '.' || c.relname, 'comment', obj_description(c.oid, 'pg_class')))
    from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind in ('r', 'p', 'v') and (n.nspname || '.' || c.relname) = any(array['catalogue.courses', 'catalogue.course_fees',
      'catalogue.course_intakes', 'catalogue.course_entry_requirements', 'catalogue.course_english_requirements', 'scholarship.course_mappings', 'scholarship.scholarships',
      'catalogue.provider_rankings', 'catalogue.provider_entry_matrix', 'catalogue.course_links', 'catalogue.course_campuses', 'catalogue.course_identifiers',
      'pipeline.coverage_course_pages', 'search.course_documents', 'pipeline.layer4_review_items'])`,
  // the admission jobs' schedules (read before any data, outside the data transaction)
  cron: (jobs) => `select json_agg(json_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active) order by j.jobname) from cron.job j where j.jobname = any(array[${jobs.map(lit).join(', ')}]::text[])`,
  // measure and back off (load policy rule 5): failures or time-outs in the latest job runs (index order on runid, bounded)
  recentFailures: `select json_build_object('n', count(*)) from (select r.status, r.return_message, r.start_time from cron.job_run_details r order by r.runid desc limit 300) x
    where x.start_time > now() - interval '15 minutes' and (x.status = 'failed' or x.return_message ilike '%timeout%')`,
  // courses changed after the first snapshot (drift between per-dataset snapshots)
  changedSince: (country, since) => `select json_build_object('n', count(*), 'ids', coalesce(json_agg(c.id order by c.id) filter (where true), '[]'::json))
    from catalogue.courses c where c.id in ${sets(country).AUC} and c.updated_at > ${lit(since)}::timestamptz`,
}

// every SQL text this module can produce, for the read-only check in the spec and the md5s in the manifest
export function allSql(country = 'AU', docColumns = ['course_id', 'search_tsv']) {
  const out = []
  for (const d of datasets(country, docColumns)) {
    out.push(countSql(d), pageSql(d, null, d.key ? d.key.map(() => 'x') : null))
    if (d.key) out.push(boundarySql(d, null, 2000), boundarySql(d, d.key.map(() => 'x'), 2000), pageSql(d, d.key.map(() => 'x'), d.key.map(() => 'y')))
  }
  out.push(...Object.values(checkSqls(country)), CATALOGUE_SQL.docColumns, CATALOGUE_SQL.columns, CATALOGUE_SQL.tables,
    CATALOGUE_SQL.cron(['coverage-admit']), CATALOGUE_SQL.recentFailures, CATALOGUE_SQL.changedSince(country, '2026-11-02T00:00:00Z'))
  return out
}
