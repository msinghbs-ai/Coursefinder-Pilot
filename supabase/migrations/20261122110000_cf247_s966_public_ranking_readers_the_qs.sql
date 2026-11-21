-- CF-247 s966 (session S1-API-Frontend-Delivery; Platform Admin 22 Nov 2026 09:22 AEDT, IR-005 / RM1J): attributed public university rankings.
-- "We can attribute and use both Times Higher Education (THE) and QS World University Rankings directly. Do NOT gate them behind a manual
-- publisher file upload or a terms = restricted hold."
--
-- ranking-layer1-etl v1.8.0 reads THE from its public ranking JSON (timeshighereducation.com/json/ranking_tables/...) and QS from its public
-- results endpoint (topuniversities.com/rankings/endpoint) with a plain GET (robots.txt and its crawl-delay honoured; $0: no Firecrawl, no
-- browser, no AI), applies the rows through svc_ranking_ingest_apply (deterministic provider matching: accepted mappings, ranking aliases, then
-- the normalised name with the country) and publishes the edition with this function (one more rule: a register name part, below):
--   public.svc_ranking_public_edition_publish_v1: the edition is accepted with access 'public' and its attribution, any other revision of the
--   same edition is superseded (one edition per system and year on the website), and the AU, NZ and CA rows with no provider are listed for
--   review (they stay unlinked in Rankings › links; the run does not fail).
-- Sources: THE 2027 is registered as a Layer 1 source beside THE 2026; QS 2027 moves to the public reader. Both are read on demand from
-- Layer 1 › Sources (Validate, Run) and refreshed by the existing scheduled verification and automatic ingestion (auto_ingest on); no new job.
-- Initial ingest on deploy: one apply run per source is queued for the existing layer1-run-driver, starting after the edge function deploy
-- that follows this migration in Deploy on merge.
-- Consumer API untouched (G3 checked before and after): the website already reads accepted editions; display was approved earlier
-- (website.rankings_display_approved). $0. G1: no new job. G2: no operational value. Locks: unchanged.
-- Parity: live head 20261122100000 read 22 Nov 2026 09:40 AEDT; this file is numbered strictly above it.
-- Replaces: the publisher-file requirement for the current THE and QS editions and the "direct publisher JSON apply is disabled" hold.
-- Retires: nothing. The publisher-file route (Sources & Imports) stays for past editions. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s966_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s966_cron on commit drop as select count(*) n from cron.job where active;

create or replace function public.svc_ranking_public_edition_publish_v1(p_system_code text, p_edition_year integer, p_source_artifact_id uuid, p_attribution text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_system uuid; v_edition uuid; v_revision text; v_superseded int; v_rows bigint; v_linked bigint; v_unmatched jsonb; v_segment int := 0; r record; v_ids uuid[];
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
  for r in select o.id obs, o.publisher_institution_id pub, c.id cid, lower(regexp_replace(pi.institution_name, '[^A-Za-z0-9]+', '', 'g')) k
             from ranking.observations o
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
             join ref.countries c on lower(c.name) = lower(coalesce(pi.country_text, '')) or lower(c.iso_alpha2::text) = lower(coalesce(pi.country_text, ''))
            where o.edition_id = v_edition and not exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id) loop
    select array_agg(distinct p.id) into v_ids
      from catalogue.providers p
      cross join lateral regexp_split_to_table(regexp_replace(coalesce(p.display_name, p.canonical_name), ',\s+including\s.*$', '', 'i'), '\s*/\s*') seg
     where p.country_id = r.cid and p.lifecycle_status = 'active' and coalesce(p.display_name, p.canonical_name) ~* '(/|,\s+including\s)'
       and lower(regexp_replace(seg, '[^A-Za-z0-9]+', '', 'g')) = r.k;
    if coalesce(cardinality(v_ids), 0) = 1 then
      update ranking.observations set provider_id = v_ids[1] where id = r.obs;
      insert into ranking.observation_provider_links (observation_id, provider_id, link_method, is_primary) values (r.obs, v_ids[1], 'primary_name_segment_country', true) on conflict do nothing;
      insert into ranking.provider_mappings (publisher_institution_id, provider_id, mapping_method, confidence, status, evidence_artifact_id, reviewed_at, note)
      select r.pub, v_ids[1], 'name_segment_country', 1.0, 'accepted', p_source_artifact_id, now(),
             'Deterministic (s966): the publisher name equals one part of the provider register name (split on "/" or before ", including") in the same country; one provider only'
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
     and exists (select 1 from catalogue.providers p where p.country_id = c.id and p.lifecycle_status = 'active');
  return jsonb_build_object('edition_id', v_edition, 'source_revision', v_revision, 'access_status', 'public', 'status', 'accepted',
    'superseded_revisions', v_superseded, 'name_segment_links', v_segment, 'rows', v_rows, 'linked_rows', v_linked, 'unmatched_in_provider_countries', v_unmatched);
end $f$;
comment on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) is 'CF-247 s966 (Platform Admin 22 Nov 2026 09:22, IR-005): publishes an attributed public ranking edition read by ranking-layer1-etl v1.8.0 (access public, attribution recorded, other revisions of the edition superseded) and lists the AU, NZ and CA rows with no provider for review. Service role only.';
revoke all on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) from public, anon, authenticated;
grant execute on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) to service_role;

-- THE 2027: a Layer 1 source beside THE 2026 (same family and operations profile), read from the public ranking JSON.
insert into pipeline.sources (source_type, system_id, provider_id, country_id, url, label, trust_rank, status, metadata)
select s.source_type, s.system_id, s.provider_id, s.country_id, 'https://www.timeshighereducation.com/world-university-rankings/2027/world-ranking',
       'Times Higher Education World University Rankings 2027', s.trust_rank, 'active',
       s.metadata || jsonb_build_object('edition_year', 2027, 'current_edition_year', 2027, 'acquisition_mode', 'publisher_public_json',
         'json_url', 'https://www.timeshighereducation.com/json/ranking_tables/world_university_rankings/2027',
         'attribution', 'Times Higher Education World University Rankings 2027. Source: Times Higher Education (timeshighereducation.com).',
         'decision', 'Platform Admin 22 Nov 2026 09:22 (IR-005): attributed public ranking; no publisher file or terms hold', 'registered_by', 's966')
  from pipeline.sources s
 where s.id = 'a886e94f-bb68-4bfb-82a7-964b587f5067'
   and not exists (select 1 from pipeline.sources x where x.metadata->>'ranking_system_code' = 'the_wur' and (x.metadata->>'edition_year')::int = 2027);

insert into pipeline.layer1_source_operations (source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
  verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, min_expected_records, max_expected_records,
  verification_status, verification_message, variance_decision, next_verification_at, consecutive_failures, change_reason, updated_by, updated_at, auto_ingest)
select n.id, o.authority_name, o.authority_domains, 'THE public ranking JSON (timeshighereducation.com/json/ranking_tables)', o.expected_count_kind, true, false,
       o.verification_cadence_days, o.ingestion_cadence_days, o.variance_warn_percent, o.variance_block_percent, o.min_expected_records, o.max_expected_records,
       'unverified', 'Registered by s966 (Platform Admin 22 Nov 2026 09:22); the first read is queued on deploy', 'unknown',
       now() + make_interval(days => o.verification_cadence_days), 0, 's966: attributed public ranking reader', o.updated_by, now(), true
  from pipeline.layer1_source_operations o
  cross join lateral (select x.id from pipeline.sources x where x.metadata->>'ranking_system_code' = 'the_wur' and (x.metadata->>'edition_year')::int = 2027 order by x.created_at limit 1) n
 where o.source_id = 'a886e94f-bb68-4bfb-82a7-964b587f5067'
   and not exists (select 1 from pipeline.layer1_source_operations y where y.source_id = n.id);

-- QS 2027: from the qualification-only REST read to the public reader (applied and published).
update pipeline.sources set metadata = metadata || jsonb_build_object('acquisition_mode', 'publisher_public_json',
         'attribution', 'QS World University Rankings 2027. Source: QS World University Rankings (topuniversities.com).',
         'decision', 'Platform Admin 22 Nov 2026 09:22 (IR-005): attributed public ranking; no publisher file or terms hold'), updated_at = now()
 where id = '5f6dcd6f-d5ab-4c06-bbac-6611c4c24286';
update pipeline.layer1_source_operations set auto_ingest = true, expected_format = 'QS public results JSON (topuniversities.com/rankings/endpoint)',
       change_reason = 's966: attributed public ranking reader', updated_at = now()
 where source_id = '5f6dcd6f-d5ab-4c06-bbac-6611c4c24286';

-- Initial ingest on deploy: one apply run per source for the existing layer1-run-driver. The driver starts a run 3 minutes after its last
-- heartbeat, so these start about 10 minutes from now.
insert into pipeline.layer1_run_queue (source_id, country_code, mode, status, idempotency_key, requested_by, expected_count, resume_cursor, processed_count,
  source_hash, warning_acknowledged, current_stage, heartbeat_at, result)
select s.id, 'GLOBAL', 'apply', 'queued', 's966-initial:' || s.id::text, 'c0ffee00-0000-4000-8000-000000000150', null, 0, 0, null, false, 'queued',
       now() + interval '7 minutes',  -- fixed: fire guard, so the run starts after the edge function deploy that follows this migration
       jsonb_build_object('start_cursor', 0, 'requested_reason', 's966: initial ingest of the attributed public edition on deploy (Platform Admin 22 Nov 2026 09:22)')
  from pipeline.sources s
 where s.metadata->>'ranking_system_code' in ('the_wur', 'qs_wur') and (s.metadata->>'edition_year')::int = 2027 and s.metadata->>'acquisition_mode' = 'publisher_public_json'
   and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = s.id and q.status in ('queued', 'running'))
on conflict (idempotency_key) do nothing;

do $c$
declare v_api jsonb := security.consumer_api_check_v1(); v_src int; v_q int;
begin
  select count(*) into v_src from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
   where s.metadata->>'ranking_system_code' in ('the_wur', 'qs_wur') and (s.metadata->>'edition_year')::int = 2027 and s.metadata->>'acquisition_mode' = 'publisher_public_json' and o.auto_ingest;
  if v_src <> 2 then raise exception 'post-check: % public ranking sources for 2027, expected THE and QS', v_src; end if;
  select count(*) into v_q from pipeline.layer1_run_queue where idempotency_key like 's966-initial:%' and status in ('queued', 'running', 'completed');
  if v_q <> 2 then raise exception 'post-check: % initial ranking runs, expected 2', v_q; end if;
  if (select count(*) from cron.job where active) <> (select n from s966_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s966_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
