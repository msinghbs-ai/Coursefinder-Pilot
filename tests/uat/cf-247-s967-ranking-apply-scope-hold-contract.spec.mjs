// Guards: Platform Admin 22 Nov 2026 09:22 AEDT (IR-005 / RM1J): an attributed public ranking edition is published whole; no partial edition is ever shown
// s967 (fix to s966 from its first live run): svc_ranking_ingest_apply stays inside the service-role statement limit (no provider searches
// for rows of countries with no provider), holds a public revision as 'parsed' until svc_ranking_public_edition_publish_v1 accepts it, and
// the partial THE 2027 revision of the first run is held and read again.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122120000_cf247_s967_ranking_apply_scope_and_hold.sql', 'utf8')

test('s967: apply scope, hold while loading, partial edition held, runs queued again; no new job; consumer API guarded', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect(MIG).toContain("select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', '1f2c868020597212ed7be6fb51390b9d'")
  expect(MIG).toContain('v_scope:=v_country is null or lower(v_country)=any(v_scope_names);')
  expect(MIG).toContain('if v_provider_id is null and v_scope then select array_agg(distinct pa.provider_id')
  expect(MIG).toContain('if v_provider_id is null and v_scope then select array_agg(p.id order by p.id) into v_candidate_ids')
  expect(MIG).toContain("case when p_source_revision in ('the_public_json_v1','qs_public_json_v1') then 'parsed' else 'accepted' end")
  expect(MIG).toContain("and editions.status is distinct from 'accepted' then 'parsed' else 'accepted' end")
  expect(MIG).toContain("v_cids uuid[] := array(select distinct p.country_id from catalogue.providers p where p.lifecycle_status = 'active'")
  expect(MIG).toContain("update ranking.editions set status = 'parsed'")
  expect(MIG).toContain("'s967-rerun:' || s.id::text")
  expect(MIG).toContain("where idempotency_key like 's966-initial:%' and status in ('queued', 'running') and (lease_until is null or lease_until < now())")
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
