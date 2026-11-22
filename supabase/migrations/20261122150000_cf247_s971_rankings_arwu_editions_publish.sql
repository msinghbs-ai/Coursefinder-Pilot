-- CF-247 s971 (session S1-API-Frontend-Delivery, consolidated batch; Platform Admin 22 Nov 2026 14:22 AEDT): rankings consolidation.
-- 1. QS stays on the annual file upload (IR-011 decision); nothing here reads or re-links QS.
-- 2. ARWU (Academic Ranking of World Universities, ShanghaiRanking), the third institutional ranking. Probed 22 Nov 2026 14:30 AEDT with a
--    plain GET: https://www.shanghairanking.com/api/pub/v1/arwu/rank?version=2026 answers JSON (1,000 rows, 6 indicators, no challenge;
--    the site has no robots.txt). ranking-layer1-etl v1.9.0 reads it like THE ($0: no Firecrawl, no browser, no AI):
--      - ARWU 2026 is registered as a Layer 1 source beside THE (source system ARWU, family global_arwu);
--      - svc_ranking_ingest_apply holds arwu_public_json_v1 while it loads, like the THE and QS public revisions (md5-guarded edit);
--      - the first run is queued on deploy for the existing layer1-run-driver.
-- 3. svc_ranking_public_edition_publish_v1: the register-name rule also ignores a leading "The" on both sides and a trailing
--    ", <country>" on the publisher's name; the match must still be one provider only.
-- 4. Ranking editions are published and rolled back by the Platform Admin: public.admin_ranking_editions_v1 lists the editions
--    (Pipeline Operator and above) and, for a Platform Admin with a reason, publishes an edition (accepted; any other revision of the same
--    edition superseded) or unpublishes it (superseded; the website then shows the latest edition still published). Every change is logged
--    in the new table ranking.edition_status_changes.
-- Consumer API untouched (G3 checked before and after): the website reads accepted editions per ranking body, so THE, QS and ARWU sit side by
-- side per provider. Live on deploy. $0. G1: no new job. G2: no operational value. Locks unchanged.
-- Parity: live head 20261122140000 read 22 Nov 2026 14:25 AEDT; this file is numbered strictly above it.
-- Replaces: nothing (ARWU had no edition).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s971_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s971_cron on commit drop as select count(*) n from cron.job where active;

-- regex edits of the live definition, guarded by its md5 before; each edit must apply exactly once
create or replace function pg_temp.edit_re(p_sig text, p_before text, p_after text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_new text;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g')) <> 1 then
      raise exception '%: edit % must apply exactly once (found %)', p_sig, i, (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g'));
    end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', 'c3f601c25e9b4cba1480d7ae04ce6b2b', null, array[
  array[$o$p_source_revision in \('the_public_json_v1','qs_public_json_v1'\) then 'parsed'$o$, $n$p_source_revision in ('the_public_json_v1','qs_public_json_v1','arwu_public_json_v1') then 'parsed'$n$],
  array[$o$p_source_revision in \('the_public_json_v1','qs_public_json_v1'\) and editions\.status$o$, $n$p_source_revision in ('the_public_json_v1','qs_public_json_v1','arwu_public_json_v1') and editions.status$n$]]);

-- Publish: the register-name rule also ignores a leading "The" and a trailing ", <country>" (s971)
create or replace function public.svc_ranking_public_edition_publish_v1(p_system_code text, p_edition_year integer, p_source_artifact_id uuid, p_attribution text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_system uuid; v_edition uuid; v_revision text; v_superseded int; v_rows bigint; v_linked bigint; v_unmatched jsonb; v_segment int := 0; r record; v_ids uuid[];
  v_cids uuid[] := array(select distinct p.country_id from catalogue.providers p where p.lifecycle_status = 'active' and p.country_id is not null);
begin
  if current_user not in ('service_role', 'postgres') then raise exception 'service role required' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_attribution, '')), '') is null then raise exception 'an attributed public edition needs its attribution' using errcode = '22023'; end if;
  select id into v_system from ranking.systems where code = p_system_code and active;
  if v_system is null then raise exception 'unsupported ranking system' using errcode = '22023'; end if;
  select e.id, e.source_revision into v_edition, v_revision from ranking.editions e
   where e.system_id = v_system and e.edition_year = p_edition_year and e.source_artifact_id = p_source_artifact_id order by e.updated_at desc limit 1;
  if v_edition is null then raise exception 'ranking edition not found for source artifact' using errcode = '22023'; end if;
  update ranking.editions set access_status = 'public', licensing_note = left(btrim(p_attribution), 600), status = 'accepted', updated_at = now() where id = v_edition;
  update ranking.editions set status = 'superseded', updated_at = now()
   where system_id = v_system and edition_year = p_edition_year and id <> v_edition and status = 'accepted';
  get diagnostics v_superseded = row_count;
  -- One more deterministic rule for rows still unlinked: the publisher's name equals one part of a provider's register name in the same
  -- country (the register writes "Université d'Ottawa/University of Ottawa" and "University of Regina, including Campion College ..."),
  -- and exactly one provider matches. The link is saved as an accepted mapping, so later editions and the ranking-link job reuse it.
  -- s971: both sides also drop a leading "The", and the publisher's name a trailing ", <country>" ("University of Sydney" and "The University
  -- of Sydney"; "The University of Calgary" and "University of Calgary"); still one provider only.
  for r in select o.id obs, o.publisher_institution_id pub, c.id cid,
                  lower(regexp_replace(regexp_replace(regexp_replace(pi.institution_name, ',\s*' || c.name || '\s*$', '', 'i'), '^\s*the\s+', '', 'i'), '[^A-Za-z0-9]+', '', 'g')) k
             from ranking.observations o
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
             join ref.countries c on lower(c.name) = lower(coalesce(pi.country_text, '')) or lower(c.iso_alpha2::text) = lower(coalesce(pi.country_text, ''))
            where o.edition_id = v_edition and c.id = any(v_cids) and not exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id) loop
    select array_agg(distinct p.id) into v_ids
      from catalogue.providers p
      cross join lateral regexp_split_to_table(regexp_replace(coalesce(p.display_name, p.canonical_name), ',\s+including\s.*$', '', 'i'), '\s*/\s*') seg
     where p.country_id = r.cid and p.lifecycle_status = 'active'
       and lower(regexp_replace(regexp_replace(seg, '^\s*the\s+', '', 'i'), '[^A-Za-z0-9]+', '', 'g')) = r.k;
    if coalesce(cardinality(v_ids), 0) = 1 then
      update ranking.observations set provider_id = v_ids[1] where id = r.obs;
      insert into ranking.observation_provider_links (observation_id, provider_id, link_method, is_primary) values (r.obs, v_ids[1], 'primary_name_segment_country', true) on conflict do nothing;
      insert into ranking.provider_mappings (publisher_institution_id, provider_id, mapping_method, confidence, status, evidence_artifact_id, reviewed_at, note)
      select r.pub, v_ids[1], 'name_segment_country', 1.0, 'accepted', p_source_artifact_id, now(),
             'Deterministic (s966, s971): the publisher name equals one part of the provider register name (split on "/" or before ", including"; a leading "The" and a trailing country ignored) in the same country; one provider only'
       where not exists (select 1 from ranking.provider_mappings m where m.publisher_institution_id = r.pub and m.status = 'accepted' and m.valid_to is null);
      v_segment := v_segment + 1;
    end if;
  end loop;
  select count(*), count(*) filter (where exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id))
    into v_rows, v_linked from ranking.observations o where o.edition_id = v_edition;
  select coalesce(jsonb_agg(jsonb_build_object('institution', pi.institution_name, 'country', pi.country_text, 'rank', o.rank_display) order by c.iso_alpha2, o.source_row_ordinal), '[]'::jsonb)
    into v_unmatched
    from ranking.observations o
    join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
    join ref.countries c on lower(c.name) = lower(coalesce(pi.country_text, '')) or lower(c.iso_alpha2::text) = lower(coalesce(pi.country_text, ''))
   where o.edition_id = v_edition and not exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id)
     and c.id = any(v_cids);
  return jsonb_build_object('edition_id', v_edition, 'source_revision', v_revision, 'access_status', 'public', 'status', 'accepted',
    'superseded_revisions', v_superseded, 'name_segment_links', v_segment, 'rows', v_rows, 'linked_rows', v_linked, 'unmatched_in_provider_countries', v_unmatched);
end $f$;
comment on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) is 'CF-247 s966, s967, s971 (Platform Admin 22 Nov 2026 09:22, IR-005): publishes an attributed public ranking edition read by ranking-layer1-etl v1.8.0 (access public, attribution recorded, other revisions of the edition superseded) and lists the AU, NZ and CA rows with no provider for review. Service role only.';
revoke all on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) from public, anon, authenticated;
grant execute on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) to service_role;

-- ARWU 2026: a Layer 1 source beside THE, read from the public ranking API
insert into pipeline.sources (source_type, system_id, provider_id, country_id, url, label, trust_rank, status, metadata)
select s.source_type, s.system_id, s.provider_id, s.country_id, 'https://www.shanghairanking.com/rankings/arwu/2026',
       'Academic Ranking of World Universities (ARWU) 2026', s.trust_rank, 'active',
       (s.metadata - 'json_url' - 'attribution' - 'decision' - 'registered_by' - 'current_edition_year') || jsonb_build_object(
         'publisher', 'ShanghaiRanking Consultancy', 'source_system', 'ARWU', 'ranking_system_code', 'arwu', 'dataset_family_code', 'global_arwu',
         'edition_year', 2026, 'current_edition_year', 2026, 'acquisition_mode', 'publisher_public_json',
         'json_url', 'https://www.shanghairanking.com/api/pub/v1/arwu/rank?version=2026',
         'attribution', 'Academic Ranking of World Universities (ARWU) 2026, ShanghaiRanking. Source: ShanghaiRanking (shanghairanking.com).',
         'decision', 'Platform Admin 22 Nov 2026 14:22: third institutional ranking; automated reader when the public JSON is clean', 'registered_by', 's971')
  from pipeline.sources s
 where s.id = 'a886e94f-bb68-4bfb-82a7-964b587f5067'
   and not exists (select 1 from pipeline.sources x where x.metadata->>'ranking_system_code' = 'arwu' and (x.metadata->>'edition_year')::int = 2026);

insert into pipeline.layer1_source_operations (source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
  verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, min_expected_records, max_expected_records,
  verification_status, verification_message, variance_decision, next_verification_at, consecutive_failures, change_reason, updated_by, updated_at, auto_ingest)
select n.id, 'ShanghaiRanking Consultancy', array['shanghairanking.com'], 'ARWU public ranking JSON (shanghairanking.com/api/pub/v1/arwu/rank)', o.expected_count_kind, true, false,
       o.verification_cadence_days, o.ingestion_cadence_days, o.variance_warn_percent, o.variance_block_percent, o.min_expected_records, o.max_expected_records,
       'unverified', 'Registered by s971 (Platform Admin 22 Nov 2026 14:22); the first read is queued on deploy', 'unknown',
       now() + make_interval(days => o.verification_cadence_days), 0, 's971: ARWU public ranking reader', o.updated_by, now(), true
  from pipeline.layer1_source_operations o
  cross join lateral (select x.id from pipeline.sources x where x.metadata->>'ranking_system_code' = 'arwu' and (x.metadata->>'edition_year')::int = 2026 order by x.created_at limit 1) n
 where o.source_id = 'a886e94f-bb68-4bfb-82a7-964b587f5067'
   and not exists (select 1 from pipeline.layer1_source_operations y where y.source_id = n.id);

-- Edition publish and rollback (Platform Admin), with a log
create table if not exists ranking.edition_status_changes (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references ranking.editions(id),
  action text not null check (action in ('publish', 'unpublish')),
  from_status text not null,
  to_status text not null,
  superseded_editions uuid[] not null default '{}',
  reason text not null check (length(btrim(reason)) >= 5),
  changed_by uuid,
  changed_at timestamptz not null default now()
);
comment on table ranking.edition_status_changes is 'CF-247 s971: every publish or unpublish (roll back) of a ranking edition by a Platform Admin through public.admin_ranking_editions_v1, with the reason and the editions it superseded.';
revoke all on ranking.edition_status_changes from public, anon, authenticated;

create or replace function public.admin_ranking_editions_v1(p_action text default 'list', p_edition_id uuid default null, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_e record; v_sup uuid[]; v_to text;
begin
  if v_rank < 4 then raise exception 'INVALID_INPUT: ranking editions need the Pipeline Operator role or above' using errcode = '42501'; end if;
  if coalesce(p_action, 'list') = 'list' then
    return jsonb_build_object('editions', coalesce((select jsonb_agg(jsonb_build_object(
        'edition_id', e.id, 'system_code', s.code, 'ranking_name', s.ranking_name, 'publisher', s.publisher_name, 'edition_year', e.edition_year,
        'source_revision', e.source_revision, 'status', e.status, 'access_status', e.access_status, 'attribution', e.licensing_note,
        'source_url', coalesce(e.source_url, s.official_url), 'updated_at', e.updated_at,
        'rows', (select count(*) from ranking.observations o where o.edition_id = e.id),
        'linked', (select count(*) from ranking.observations o where o.edition_id = e.id and exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id)),
        'last_change', (select jsonb_build_object('action', c.action, 'reason', c.reason, 'changed_at', c.changed_at) from ranking.edition_status_changes c where c.edition_id = e.id order by c.changed_at desc limit 1))
      order by s.code, e.edition_year desc, e.updated_at desc)
      from ranking.editions e join ranking.systems s on s.id = e.system_id), '[]'::jsonb),
      'can_publish', v_rank >= 6);
  end if;
  if p_action not in ('publish', 'unpublish') then raise exception 'INVALID_INPUT: action must be list, publish or unpublish'; end if;
  if v_rank < 6 then raise exception 'INVALID_INPUT: only a Platform Admin publishes or unpublishes a ranking edition' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'INVALID_INPUT: give a reason (at least 5 characters)'; end if;
  select e.id, e.system_id, e.edition_year, e.status into v_e from ranking.editions e where e.id = p_edition_id for update;
  if v_e.id is null then raise exception 'INVALID_INPUT: ranking edition not found'; end if;
  if p_action = 'publish' then
    if v_e.status = 'rejected' then raise exception 'INVALID_INPUT: a rejected edition is not published'; end if;
    select coalesce(array_agg(id), '{}') into v_sup from ranking.editions where system_id = v_e.system_id and edition_year = v_e.edition_year and id <> v_e.id and status = 'accepted';
    update ranking.editions set status = 'superseded', updated_at = now() where id = any(v_sup);
    update ranking.editions set status = 'accepted', updated_at = now() where id = v_e.id;
    v_to := 'accepted';
  else
    if v_e.status <> 'accepted' then raise exception 'INVALID_INPUT: only a published (accepted) edition can be unpublished'; end if;
    update ranking.editions set status = 'superseded', updated_at = now() where id = v_e.id;
    v_sup := '{}'; v_to := 'superseded';
  end if;
  insert into ranking.edition_status_changes (edition_id, action, from_status, to_status, superseded_editions, reason, changed_by)
  values (v_e.id, p_action, v_e.status, v_to, v_sup, btrim(p_reason), auth.uid());
  return jsonb_build_object('ok', true, 'edition_id', v_e.id, 'action', p_action, 'from_status', v_e.status, 'to_status', v_to, 'superseded_editions', to_jsonb(v_sup));
end $f$;
comment on function public.admin_ranking_editions_v1(text, uuid, text) is 'CF-247 s971: ranking editions for Rankings & statistics › Datasets: list (Pipeline Operator and above); publish or unpublish (roll back) an edition (Platform Admin, with a reason, logged in ranking.edition_status_changes).';
revoke all on function public.admin_ranking_editions_v1(text, uuid, text) from public, anon;
grant execute on function public.admin_ranking_editions_v1(text, uuid, text) to authenticated, service_role;

-- Initial ingest of ARWU 2026 on deploy for the existing layer1-run-driver
insert into pipeline.layer1_run_queue (source_id, country_code, mode, status, idempotency_key, requested_by, expected_count, resume_cursor, processed_count,
  source_hash, warning_acknowledged, current_stage, heartbeat_at, result)
select s.id, 'GLOBAL', 'apply', 'queued', 's971-initial:' || s.id::text, 'c0ffee00-0000-4000-8000-000000000150', null, 0, 0, null, false, 'queued',
       now() + interval '7 minutes',  -- fixed: fire guard, so the run starts after the edge function deploy that follows this migration
       jsonb_build_object('start_cursor', 0, 'requested_reason', 's971: initial ingest of ARWU 2026 on deploy (Platform Admin 22 Nov 2026 14:22)')
  from pipeline.sources s
 where s.metadata->>'ranking_system_code' = 'arwu' and (s.metadata->>'edition_year')::int = 2026
   and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = s.id and q.status in ('queued', 'running'))
on conflict (idempotency_key) do nothing;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if (select count(*) from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id where s.metadata->>'ranking_system_code' = 'arwu' and o.auto_ingest) <> 1 then raise exception 'post-check: the ARWU 2026 source is missing'; end if;
  if (select count(*) from regexp_matches(pg_get_functiondef('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)'::regprocedure), 'arwu_public_json_v1', 'g')) <> 2 then raise exception 'post-check: apply does not hold the ARWU revision while loading'; end if;
  if (select count(*) from pipeline.layer1_run_queue where idempotency_key like 's971-initial:%') <> 1 then raise exception 'post-check: the ARWU run was not queued'; end if;
  if (select count(*) from cron.job where active) <> (select n from s971_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s971_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
