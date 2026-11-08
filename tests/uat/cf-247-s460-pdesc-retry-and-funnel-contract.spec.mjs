// Guards: P-DESC lane E (Platform Admin directive 8 Nov 2026: restore independent execution of provider descriptions; no weakening of the duplicate or support rules; no AI approval of human review; no extra spend)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261108140000_cf247_pdesc_retry_on_new_evidence_and_funnel.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/pdesc-retry-funnel/run.sh', 'utf8')
const sc = fs.readFileSync('tests/fixtures/pdesc-retry-funnel/scenarios.sql', 'utf8')
const fn = fs.readFileSync('tests/fixtures/pdesc-retry-funnel/funnel.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)

test('one live function is edited under its live md5 with a recorded after md5, once, and nothing else is edited', () => {
  expect(M).toMatch(/--   security\.provider_description_selection_v1\(jsonb\) 6b43ea62758a2c6fac80affba14b12d5 -> [0-9a-f]{32}/)
  expect(M).not.toContain('@@AFTER@@')
  expect(C).toContain("select pg_temp.edit_once('security.provider_description_selection_v1(jsonb)', '6b43ea62758a2c6fac80affba14b12d5'")
  expect(C).toContain('the edit must apply exactly once')
  expect(C).toContain('already applied')
  expect(C.match(/pg_temp\.edit_once\('/g)?.length).toBe(1)
  expect(C).not.toMatch(/create or replace function security\.(provider_description_(fire|enqueue|validate|page|scope|stored|identity)_v1|pdesc_[a-z_]+|layer4_provider_description_apply_impl)|create or replace function public\.svc_provider_description_/)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(fs.readFileSync('tests/fixtures/provider-description-autonomy/migration-function-hashes.json', 'utf8')).not.toContain('selection_v1')
})

test('a held read is selected again only on a changed official copy; a person\'s rejection only when the page rule now refuses its source; every later check still applies', () => {
  expect(C).toContain("r.updated_at<=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int)")
  expect(C).toContain('a.id is not null')
  expect(C).toContain('coalesce(a.content_hash,a.id::text) is distinct from r.content_hash')
  expect(C).toContain("(r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))")
  // the 180-day wait itself is the existing setting and still the default branch
  expect(C).toContain("security.pipeline_num_v1('pdesc.recheck_days',180)")
  for (const label of ['held_new_copy|eligible', 'held_same_copy|unchanged_unsuitable_evidence', 'held_new_copy_just_now|retry_wait', 'rejected_source_now_refused|eligible',
    'rejected_source_still_valid|retry_wait', 'held_never_fetched|eligible', 'held_new_copy_manual_lock|manual_lock', 'held_past_recheck|eligible', 'rejected_no_source_recorded|retry_wait', 'proposed_open|existing_work'])
    expect(run).toContain(label)
  expect(run).toContain("'held_new_copy|retry_wait'")
  expect(sc).toContain("insert into pipeline.manual_locks")
  expect(run).toContain('the migration changed settings')
  expect(run).toContain('the migration changed Layer 4')
})

test('no duplicate or support rule, claim list, setting, flag, scope or Layer 4 item is touched, and no number is written into code', () => {
  expect(C).not.toMatch(/pdesc_similarity_v1|pdesc_support_v1|pdesc_present_support_v1|duplicate_share|support_min_share|pdesc\.claim_words|evidence_claim_words/)
  expect(C).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings|pdesc\.provider_keys['"]?\s*,?\s*['"]?\[|insert into pipeline\.layer4_|update pipeline\.layer4_|insert into pipeline\.provider_description_reads|update pipeline\.provider_description_reads|update catalogue\./)
  expect(C).not.toMatch(/cron\.(schedule|unschedule|alter_job)|run_now\.jobs|pdesc\.enabled'?\s*,\s*'?1/)
  // the only numbers are the defaults of settings that already exist (read through pipeline_num_v1)
  const edited = C.slice(C.indexOf("select pg_temp.edit_once("), C.indexOf('create or replace function public.admin_provider_description_funnel_v1()'))
  for (const m of edited.matchAll(/pipeline_num_v1\('([a-z_.]+)',\s*([0-9.]+)\)/g)) expect(['pdesc.retry_minutes', 'pdesc.recheck_days']).toContain(m[1])
  expect(fn).toContain('no read, item or description was written')
})

test('the funnel is read only, role gated, whole-catalogue, and names why the next run will or will not queue', () => {
  expect(C).toContain('create or replace function public.admin_provider_description_funnel_v1() returns jsonb')
  expect(C).toMatch(/language plpgsql stable security definer set search_path to ''/)
  expect(C).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'curator role required' using errcode = '42501'")
  expect(C).toContain('revoke all on function public.admin_provider_description_funnel_v1() from public, anon;')
  expect(C).toContain('grant execute on function public.admin_provider_description_funnel_v1() to authenticated;')
  const body = C.slice(C.indexOf('create or replace function public.admin_provider_description_funnel_v1()'), C.indexOf('revoke all on function public.admin_provider_description_funnel_v1()'))
  expect(body).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?[a-z_]+\./i)
  for (const k of ['registry', 'live', 'website', 'policy_scope', 'run_scope', 'identity_clear', 'stored_page', 'read', 'queued', 'proposed', 'held', 'rejected', 'admitted', 'published', 'consumer_checked'])
    expect(body).toContain(`'key', '${k}'`)
  for (const k of ['reader_off', 'job_paused', 'review_full', 'next_run_will_queue', 'run_scope_limited_by_pdesc_provider_keys', 'waiting_for_reviewers', 'no_eligible_provider_in_scope']) expect(body).toContain(`'${k}'`)
  expect(fn).toContain('the live shape reports the run scope as the limit')
  expect(fn).toContain('a viewer was served')
  expect(fn).toContain('the function is STABLE (read only)')
  expect(C).toContain("('function', 'public.admin_provider_description_funnel_v1', 'Operations'")
})

test('the fixtures mirror live: scratch database named g_, the loaded function is the live one, the migration is applied twice, and the consumer API is not touched', () => {
  expect(run).toContain('case "$DB" in g_*)')
  expect(run).toContain('6b43ea62758a2c6fac80affba14b12d5')
  expect(run).toContain('applied again: no change')
  expect(run).toContain('the migration changed a function it does not own')
  expect(C).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')).toContain('bash tests/fixtures/pdesc-retry-funnel/run.sh')
})
