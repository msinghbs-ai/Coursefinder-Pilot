// Guards: Provider Description autonomy mandate §11: realistic multi-country selection/source performance under actual 8-second limits.
// Isolated fictional data only. This file never widens processing policy, starts a reader, decides a proposal or invokes a vendor.
import fs from 'node:fs'
import { performance } from 'node:perf_hooks'
import { sql, quote } from './db.mjs'

const browserId = '10000000-0000-0000-0000-000000000013'
const core = `provider_id in (select provider_id from fixture.documents where provider_id<>'${browserId}'::uuid)`
const snapshot = () => sql(`select jsonb_build_object(
 'browser',(select to_jsonb(p) from catalogue.providers p where id='${browserId}'),
 'browser_reads',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from pipeline.provider_description_reads r where provider_id='${browserId}'),
 'reads',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from pipeline.provider_description_reads r where ${core}),
 'policy',(select jsonb_agg(jsonb_build_object('key',key,'value',value) order by key) from pipeline.platform_toolset_settings where toolset_key='pipeline' and key like 'pdesc.%')
);`, { role: 'postgres', json: true })
const before = snapshot()
const observedLimits = Object.fromEntries(['authenticated', 'postgres'].map(role => [role, sql(`select jsonb_build_object(
 'statement_timeout',current_setting('statement_timeout'),'lock_timeout',current_setting('lock_timeout'),
 'jit',current_setting('jit'),'work_mem',current_setting('work_mem'),
 'max_parallel_workers_per_gather',current_setting('max_parallel_workers_per_gather')
);`, { role, json: true })]))
for (const [role, limits] of Object.entries(observedLimits)) {
  if (limits.statement_timeout !== '8s' || limits.lock_timeout !== '0') throw new Error(`Captured timeout parity failed for ${role}: ${JSON.stringify(limits)}`)
}
const targets = [{ country: 'AU', providers: 1279, universities: 45 }, { country: 'NZ', providers: 416, universities: 8 }, { country: 'CA', providers: 1130, universities: 1 }]

for (const target of targets) {
  const held = sql(`select jsonb_build_object('providers',count(*),'universities',count(*) filter(where t.code='university'))
   from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id
   where k.iso_alpha2=${quote(target.country)} and p.lifecycle_status='active' and p.publication_status='published';`, { role: 'postgres', json: true })
  const needed = Math.max(0, target.providers - held.providers)
  const universityNeeded = Math.max(0, target.universities - held.universities)
  const existingNoise = Number(sql(`select coalesce(max(split_part(stable_key,':',4)::integer),0) from catalogue.providers where stable_key like 'fixture:benchmark:${target.country}:%';`, { role: 'postgres' }))
  for (let start = existingNoise + 1; start <= existingNoise + needed; start += 200) {
    const end = Math.min(existingNoise + needed, start + 199)
    sql(`with noise as (
      select md5('fixture:benchmark:${target.country}:'||g)::uuid id,g from generate_series(${start},${end})g
    ) insert into pim.entity_registry(id) select id from noise on conflict do nothing;
    with noise as (
      select md5('fixture:benchmark:${target.country}:'||g)::uuid id,g from generate_series(${start},${end})g
    ) insert into catalogue.providers(id,stable_key,canonical_name,website,country_id,provider_type_id,lifecycle_status,publication_status)
      select n.id,'fixture:benchmark:${target.country}:'||n.g,'Benchmark ${target.country} Provider '||n.g,
      'https://benchmark-${target.country.toLowerCase()}-'||n.g||'.example.edu',k.id,t.id,'active','published'
      from noise n join ref.countries k on k.iso_alpha2=${quote(target.country)}
      join ref.provider_types t on t.code=case when n.g<=${existingNoise + universityNeeded} then 'university' else 'college' end
      on conflict do nothing;
    insert into catalogue.courses(id,provider_id,canonical_title,lifecycle_status)
      select gen_random_uuid(),p.id,'Fictional benchmark programme '||c,'active'
      from catalogue.providers p cross join lateral generate_series(1,1+mod(split_part(p.stable_key,':',4)::integer,13))c
      where p.stable_key like 'fixture:benchmark:${target.country}:%'
      and split_part(p.stable_key,':',4)::integer between ${start} and ${end}
      and not exists(select 1 from catalogue.courses x where x.provider_id=p.id);`, { role: 'postgres' })
  }
}

// The first institution holds 3,856 unsuitable evidence copies; the next nine
// each hold 600. Their real approved About page remains the stored-page choice.
for (let institution = 1; institution <= 10; institution++) {
  const providerId = `10000000-0000-0000-0000-${String(institution).padStart(12, '0')}`
  const copies = institution === 1 ? 3856 : 600
  const existing = Number(sql(`select count(*) from pipeline.evidence_artifacts where source_url like 'https://p${institution}.example.edu/news/benchmark-%';`, { role: 'postgres' }))
  for (let start = existing + 1; start <= copies; start += 200) {
    const end = Math.min(copies, start + 199)
    sql(`insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at)
      select a.source_id,'page','https://p${institution}.example.edu/news/benchmark-'||g,
      'fixture/benchmark/p${institution}-'||g||'.html',repeat(md5('noise:p${institution}:'||g),2),'text/html',now()
      from fixture.documents d join pipeline.evidence_artifacts a on a.id=d.evidence_id
      cross join generate_series(${start},${end})g where d.provider_id='${providerId}'::uuid;`, { role: 'postgres' })
  }
  const chosen = sql(`select security.provider_description_stored_v1('${providerId}'::uuid)=(select evidence_id from fixture.documents where provider_id='${providerId}'::uuid);`, { role: 'postgres' })
  if (chosen !== 't') throw new Error(`Stored-source selection changed under unsuitable-evidence skew for fictional institution ${institution}`)
}

const stages = []
function benchmark(name, statement, role, runs = 5) {
  const samples = []
  for (let i = 0; i < runs; i++) {
    const started = performance.now()
    const plan = JSON.parse(sql(`explain (analyze,buffers,format json) ${statement}`, { role }))
    samples.push({ execution_ms: plan[0]['Execution Time'], transport_ms: performance.now() - started, plan })
  }
  const times = samples.map(s => s.execution_ms).sort((a, b) => a - b)
  const result = { name, role, statement_timeout_ms: 8000, lock_timeout_ms: 0, observed_limits: observedLimits[role], median_ms: times[Math.floor(times.length / 2)], max_ms: Math.max(...times), samples }
  if (result.max_ms >= 8000) throw new Error(`${name} exceeded the production-representative statement limit`)
  stages.push(result)
}

for (const { country } of targets) {
  const args = { country, provider_type: 'university', description_state: 'all', selection: 'top', size: 10, mode: 'stored' }
  benchmark(`Authenticated ${country} provider preview`, `select public.admin_provider_description_run_v1('preview',${quote(JSON.stringify(args))}::jsonb);`, 'authenticated')
}
for (const institution of [1, 2, 10]) {
  const providerId = `10000000-0000-0000-0000-${String(institution).padStart(12, '0')}`
  benchmark(`Stored official source lookup, institution ${institution}`, `select security.provider_description_stored_v1('${providerId}'::uuid);`, 'postgres')
}

const after = snapshot()
if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error('Benchmark changed the approved scope, Browser provider or existing reader outcomes')
const distribution = sql(`select jsonb_agg(x order by country) from (
 select k.iso_alpha2 country,count(*) providers,count(*) filter(where t.code='university') universities,
 (select count(*) from catalogue.courses c join catalogue.providers cp on cp.id=c.provider_id where cp.country_id=k.id and c.lifecycle_status='active') active_courses
 from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id
 where p.lifecycle_status='active' and p.publication_status='published' group by k.id,k.iso_alpha2
 )x;`, { role: 'postgres', json: true })
const report = {
  captured_at: new Date().toISOString(),
  environment: 'Isolated Docker PostgreSQL 17.6; fictional provider/source fixtures only',
  limits: 'Every SQL invocation enforces the captured 8-second statement timeout. The captured lock_timeout is 0 (disabled); the statement timeout still bounds the entire statement.',
  observed_limits: observedLimits,
  interpretation: 'Development performance measurements, not production measurements or admission/publication proof. RPC preview plans include selection/evidence lookup and preview persistence. Private stored-source helpers run as their internal database owner. Docker transport time is recorded separately.',
  policy: 'Existing fictional fixture scope keys and limits preserved. Noise providers receive no processing authority; no reader/model/reviewer is invoked. One Canadian university is retained to exercise the same country engine.',
  distribution,
  source_noise: { dominant_institution_copies: 3856, other_institutions: 9, copies_each: 600, approved_about_choice_unchanged: true },
  controlled_workflow_timings: 'Reader processing, controlled model call, Layer 4 hand-off and authorised publication timings are recorded separately by integration.mjs.',
  stages,
}
fs.mkdirSync('docs/ui-evidence', { recursive: true })
fs.writeFileSync('docs/ui-evidence/provider-description-benchmark.json', JSON.stringify(report, null, 2) + '\n')
process.stdout.write(JSON.stringify({ distribution, stages: stages.map(({ name, median_ms, max_ms }) => ({ name, median_ms, max_ms })) }, null, 2) + '\n')
