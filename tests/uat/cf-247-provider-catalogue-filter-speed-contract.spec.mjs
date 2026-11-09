// Guards: P1 fix to the Provider Catalogue whole-set filters (Platform Admin directive 9 Nov 2026, Provider Catalogue customisable columns; coordinator finding 9 Nov 2026: the Description, Admission, Source tier, Website and Zoho filters took 3 to 10 seconds on live against the 8 second statement limit). The same request must give the same answer, only sooner: the facts query is unchanged and planned with its own arguments, Description reads the provider's own column, and the facts are worked out only for the providers that pass the cheap filters.
// Source contract only. The timings and the totals against plain SELECT counts are measured on the live project by the held SELECT-only scripts after deploy
// (supabase/held/provider_catalogue_filter_speed_totals_equivalence.sql and provider_catalogue_columns_v2_v3_equivalence.sql); nothing here claims to have run them.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const OLD = fs.readFileSync('supabase/migrations/20261109200000_cf247_provider_catalogue_columns.sql', 'utf8')
const NEWFILE = 'supabase/migrations/20261109220000_cf247_provider_catalogue_filter_speed.sql'
const NEW = fs.readFileSync(NEWFILE, 'utf8')
const REC = fs.readFileSync('supabase/held/provider_catalogue_filter_speed_forward_recovery.sql', 'utf8')
const TOT = fs.readFileSync('supabase/held/provider_catalogue_filter_speed_totals_equivalence.sql', 'utf8')
const EQ = fs.readFileSync('supabase/held/provider_catalogue_columns_v2_v3_equivalence.sql', 'utf8')
const md5 = s => crypto.createHash('md5').update(s).digest('hex')
// the text between the first pair of $function$ markers after a marker (pg_proc.prosrc is exactly this)
const body = (src, marker) => { const i = src.indexOf(marker); expect(i, marker).toBeGreaterThan(-1); const a = src.indexOf('$function$', i) + 10; return src.slice(a, src.indexOf('$function$', a)) }
const FACTS_HEAD = 'CREATE OR REPLACE FUNCTION security.provider_catalogue_facts_v1'
const V3_HEAD = 'CREATE OR REPLACE FUNCTION security.admin_providers_page_v3'
const factsOld = body(OLD, FACTS_HEAD)
const factsNew = body(NEW, FACTS_HEAD)
const v3Old = body(OLD, V3_HEAD)
const v3New = body(NEW, V3_HEAD)
const NEW_SQL = NEW.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const queryOf = f => f.slice(f.indexOf('with pv as ('), f.lastIndexOf('from st s') + 'from st s'.length)

test('the migration is the next free version, guarded by the md5 of the two live bodies it replaces and of the two it writes, and says what it replaces and retires', () => {
  expect(fs.readdirSync('supabase/migrations').filter(f => f.startsWith('20261109220000'))).toEqual(['20261109220000_cf247_provider_catalogue_filter_speed.sql'])
  expect(md5(factsOld)).toBe('4127aab7f07d3b97431191e58f07bfdb')
  expect(md5(v3Old)).toBe('70be6f7e4b3faac863d7011f5fcec832')
  // the guard accepts the old body or the new one (a second run), refuses anything else, and the post-check requires the new one
  expect(NEW).toContain(`if v_f not in ('4127aab7f07d3b97431191e58f07bfdb', '${md5(factsNew)}')`)
  expect(NEW).toContain(`if v_v not in ('70be6f7e4b3faac863d7011f5fcec832', '${md5(v3New)}')`)
  expect(NEW).toContain(`if v_f <> '${md5(factsNew)}'`)
  expect(NEW).toContain(`if v_v <> '${md5(v3New)}'`)
  expect(NEW).toMatch(/^-- Replaces: .+/m)
  expect(NEW).toMatch(/^-- Retires: .+/m)
  expect(NEW).toContain('-- Nothing dropped, deleted or renamed by this migration.')
  expect(NEW_SQL).not.toMatch(/\b(drop|delete|truncate)\b/i)
  // no table, column, setting, job or consumer object
  expect(NEW_SQL).not.toMatch(/\b(create table|alter table|insert into)\b/i)
  expect(NEW_SQL).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(NEW_SQL).toMatch(/revoke all on function security\.provider_catalogue_facts_v1\(uuid\[\], boolean\), security\.admin_providers_page_v3\(jsonb\) from public, anon, authenticated;/)
})

test('the facts function keeps its signature, its columns and its query word for word; only the language and the planning change', () => {
  const sig = f => f.match(/RETURNS TABLE\(([\s\S]*?)\)\n LANGUAGE/)[1].replace(/\s+/g, ' ')
  expect(sig(NEW.slice(NEW.indexOf(FACTS_HEAD)))).toBe(sig(OLD.slice(OLD.indexOf(FACTS_HEAD))))
  expect(NEW).toContain('CREATE OR REPLACE FUNCTION security.provider_catalogue_facts_v1(p_ids uuid[] DEFAULT NULL, p_feeds boolean DEFAULT true)')
  // the query text is identical to the one applied by 20261109200000
  expect(queryOf(factsNew)).toBe(queryOf(factsOld))
  // planned with the actual arguments on every call; the output columns win over the query's names
  const header = NEW.slice(NEW.indexOf(FACTS_HEAD), NEW.indexOf('AS $function$', NEW.indexOf(FACTS_HEAD)))
  expect(header).toContain('LANGUAGE plpgsql')
  expect(header).toContain('STABLE SECURITY DEFINER')
  expect(header).toContain("SET search_path TO ''")
  expect(header).toContain("SET plan_cache_mode TO 'force_custom_plan'")
  expect(factsNew.trimStart().startsWith('#variable_conflict use_column')).toBe(true)
  expect(factsNew).toMatch(/\bbegin\n[\s\S]*\n {2}return query\n {2}with pv as \(/)
  expect(factsNew.trimEnd().endsWith('from st s;\nend')).toBe(true)
  // the feed scans are still gated by p_feeds (Unknown stays unknown: a state not fetched is null, never a guessed value)
  expect(factsNew).toMatch(/website_sync_candidates_v1\('provider'\) c where p_feeds and c\.ref_id is not null/)
  expect(factsNew).toMatch(/zoho_sync_candidates_v1\('provider'\) c where p_feeds and c\.ref_id is not null/)
  expect(factsNew).toContain('case when p_feeds then s.website_state end, case when p_feeds then s.zoho_state end')
  expect(factsNew).toContain('case when not p_feeds then null')
  // the grounds are written down in the migration
  expect(NEW).toMatch(/SQL functions are planned once with their arguments unknown/)
})

test('both functions are set to custom plans, because a plpgsql page statement switches to a generic plan from the sixth call on a connection and the facts function is planned with its arguments unknown', () => {
  const header = f => NEW.slice(NEW.indexOf(f), NEW.indexOf('AS $function$', NEW.indexOf(f)))
  expect(header(FACTS_HEAD)).toContain("SET plan_cache_mode TO 'force_custom_plan'")
  expect(header(V3_HEAD)).toContain("SET plan_cache_mode TO 'force_custom_plan'")
  expect(header(V3_HEAD)).toContain("SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'")
  expect(header(V3_HEAD)).toContain('LANGUAGE plpgsql')
  expect(header(V3_HEAD)).toContain('STABLE SECURITY DEFINER')
  // the post-check requires both settings; the recovery clears both
  expect(NEW).toMatch(/admin_providers_page_v3\(jsonb\)'\) and p\.proconfig @> array\['plan_cache_mode=force_custom_plan'\]/)
  expect(NEW).toMatch(/provider_catalogue_facts_v1\(uuid\[\],boolean\)'\) and p\.proconfig @> array\['plan_cache_mode=force_custom_plan'\]/)
  expect(REC).toContain('alter function security.admin_providers_page_v3(jsonb) reset plan_cache_mode;')
  expect(REC).toContain('alter function security.provider_catalogue_facts_v1(uuid[], boolean) reset plan_cache_mode;')
})

test('the page: Description reads the provider column and needs no facts; the facts are read for the providers that pass the cheap filters; everything after that is unchanged', () => {
  // Description filter and sort: the very test the facts use for description_filled, on the provider's own column
  expect(v3New).toContain("and (v_desc is null or (v_desc='filled')=(nullif(btrim(p.description),'') is not null))")
  expect(v3New).toContain("(nullif(btrim(p.description),'') is not null) description_filled,f.admission_state")
  expect(factsNew).toContain("(s.descr is not null)")
  const need = v3New.match(/v_need_facts:=([\s\S]*?);\n/)[1]
  expect(need).not.toMatch(/v_desc|'description'/)
  expect(need).toContain('coalesce(v_adm,v_tier,v_web,v_zoho) is not null')
  for (const k of ['admission', 'source', 'desc_admitted', 'reader', 'last_read', 'next_retry', 'layer4', 'canonical', 'website', 'zoho', 'mismatch']) expect(need, k).toContain(`'${k}'`)
  // the whole-set facts: only for the candidate providers; never the unrestricted call that planned badly
  expect(v3New).toContain('provider_catalogue_facts_v1(array(select x.id from cand x), v_scan_feeds) where v_need_facts')
  expect(v3New).not.toContain('provider_catalogue_facts_v1(null')
  expect(v3New).toContain('provider_catalogue_facts_v1(array(select k.id from keys k), v_page_feeds)')
  expect(v3New).toMatch(/with cand as \([\s\S]*?\), facts as materialized \([\s\S]*?\), base as \(/)
  // every filter on the provider's own columns moved into cand, unchanged; base keeps only the facts filters
  const cand = v3New.slice(v3New.indexOf('with cand as ('), v3New.indexOf('), facts as materialized'))
  for (const f of ['v_query is null', "c.iso_alpha2::text=upper(v_country)", 'ps.code=upper(v_subdivision)', 'p.lifecycle_status=v_lifecycle', 'p.publication_status=v_publication', 'security.university_group_provider_ids(v_group)', "v_type='unclassified' and p.provider_type_id is null"]) expect(cand, f).toContain(f)
  const baseWhere = v3New.slice(v3New.indexOf('left join facts f on f.provider_id=p.id'), v3New.indexOf('), filtered as ('))
  expect(baseWhere).toContain('(v_adm is null or f.admission_state=v_adm)')
  expect(baseWhere).toContain('(v_tier is null or f.source_tier=v_tier)')
  expect(baseWhere).toContain('(v_web is null or f.website_state=v_web)')
  expect(baseWhere).toContain('(v_zoho is null or f.zoho_state=v_zoho)')
  expect(baseWhere).not.toMatch(/v_query|v_country|v_lifecycle|v_desc/)
  // the declarations, validation (22023 errors), feed switches, and the whole of the code from the adapter filter on (filtering, order, paging, page rows, JSON) are byte for byte what 20261109200000 applied
  const tail = s => s.slice(s.indexOf('    ), filtered as ('))
  expect(tail(v3New)).toBe(tail(v3Old))
  const head = s => s.slice(0, s.indexOf('  -- the description facts are worked out'))
  expect(head(v3New)).toBe(head(v3Old))
  expect(v3New).toContain("v_scan_feeds:=coalesce(v_web,v_zoho) is not null or v_sort in ('website','zoho','mismatch');")
  expect(v3New).toContain("v_page_feeds:=v_scan_feeds or lower(coalesce(p_args->>'feeds',''))='true';")
  expect(v3New).toMatch(/unsupported provider type filter: %',v_type using errcode='22023'/)
})

test('the other columns the page selects from base are the same, and base is still the only place the facts reach the sort', () => {
  const cols = s => s.slice(s.indexOf('      select\n        p.id,p.display_name'), s.indexOf('      from ', s.indexOf('      select\n        p.id,p.display_name')))
  expect(cols(v3New).replace("(nullif(btrim(p.description),'') is not null) description_filled", 'f.description_filled')).toBe(cols(v3Old))
  // the sort on Description still orders by the same value
  expect(v3New).toContain("case when v_sort='description' and v_dir='asc' then f.description_filled::int end asc")
})

test('forward recovery restores the two 20261109200000 bodies byte for byte, guarded, with nothing dropped', () => {
  expect(fs.readdirSync('supabase/migrations').filter(f => /filter_speed_forward_recovery/.test(f))).toEqual([])
  expect(REC).toContain(`('${md5(factsNew)}', '4127aab7f07d3b97431191e58f07bfdb')`)
  expect(REC).toContain(`('${md5(v3New)}', '70be6f7e4b3faac863d7011f5fcec832')`)
  expect(md5(body(REC, FACTS_HEAD))).toBe('4127aab7f07d3b97431191e58f07bfdb')
  expect(md5(body(REC, V3_HEAD))).toBe('70be6f7e4b3faac863d7011f5fcec832')
  expect(REC).toContain('alter function security.provider_catalogue_facts_v1(uuid[], boolean) reset plan_cache_mode;')
  expect(REC).toMatch(/LANGUAGE sql/)
  expect(REC).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(REC).toContain("if v_f <> '4127aab7f07d3b97431191e58f07bfdb' or v_v <> '70be6f7e4b3faac863d7011f5fcec832'")
})

test('the post-deploy totals check covers every whole-set filter value, over all providers and over active ones, against plain SELECT counts, and only reads', () => {
  expect(TOT).not.toMatch(/^\s*(insert|update|delete|drop|alter|create|truncate)\b/im)
  expect(TOT).toContain("raise exception 'FILTER EQUIVALENCE")
  expect(TOT).toContain('security.admin_providers_page_v3(v_c->\'args\')')
  const checks = JSON.parse(TOT.match(/\$j\$(.*?)\$j\$::jsonb/s)[1])
  // 19 filter values (2 description, 4 admission, 5 source tier, 4 website, 4 zoho) in two scopes
  expect(checks).toHaveLength(38)
  const names = checks.map(c => c.name)
  expect(new Set(names).size).toBe(38)
  for (const scope of ['all', 'active']) {
    for (const n of ['description filled', 'description missing', 'admission admitted', 'admission held', 'admission pending', 'admission declined', 'source tier stored', 'source tier direct', 'source tier firecrawl', 'source tier registry_factual', 'source tier unknown',
      'website matched', 'website pending', 'website missing', 'website not_applicable', 'zoho matched', 'zoho pending', 'zoho missing', 'zoho not_applicable']) expect(names, `${n} (${scope})`).toContain(`${n} (${scope})`)
  }
  for (const c of checks) {
    expect(c.args.limit).toBe(200)
    expect(c.sql).toMatch(/^select p?\.?(id|provider_id|f\.provider_id)/)
    expect(c.args.lifecycle_status === 'active').toBe(/\(active\)$/.test(c.name))
  }
  // Description and Admission admitted/held are counted from the tables, not from the facts function
  for (const c of checks.filter(c => /^(description|admission (admitted|held))/.test(c.name))) { expect(c.kind).toBe('plain table'); expect(c.sql).not.toContain('provider_catalogue_facts_v1') }
  // the earlier equivalence script (v2 against v3) is unchanged and still the one to re-run
  expect(EQ).toContain("raise exception 'EQUIVALENCE")
  expect(EQ).toContain('security.admin_providers_page_v3(v_a)')
})
