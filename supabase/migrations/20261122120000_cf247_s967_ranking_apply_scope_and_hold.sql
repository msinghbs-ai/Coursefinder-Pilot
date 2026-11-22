-- CF-247 s967 (session S1-API-Frontend-Delivery, fix to s966 found on its first live run, 22 Nov 2026 11:15 AEDT; IR-005 / RM1J).
-- The first THE 2027 run (s966) timed out: svc_ranking_ingest_apply ran the provider-name searches for every row, including the ~3,000 rows
-- of countries with no providers, so a batch of 200 rows passed the 8 s statement limit of the service role. Three batches (600 rows) had
-- been applied and, because apply marks an edition accepted on its first batch, the website showed that partial THE 2027 edition.
-- This change:
--   1. svc_ranking_ingest_apply skips the alias and name searches for a row whose country has no provider (both searches already require
--      the country, so no match is lost); the accepted-mapping lookup still runs for every row.
--   2. svc_ranking_ingest_apply holds an attributed public revision (the_public_json_v1, qs_public_json_v1) as 'parsed' while it loads;
--      svc_ranking_public_edition_publish_v1 accepts it when the whole edition is in. An edition already published stays accepted on a re-read.
--      Uploaded editions behave as before.
--   3. svc_ranking_public_edition_publish_v1: the register-name-part rule looks only at rows of countries with providers.
--   4. The partial THE 2027 revision is held (parsed), so the website shows THE 2026 until THE 2027 is complete. The s966 runs still waiting
--      to retry are cancelled and the THE and QS 2027 runs queued again for the run driver.
-- Rehearsal (rolled back, 22 Nov 2026 11:20 AEDT): THE 2027 3,146 rows applied in 15 s, slowest batch of 200 4.3 s (limit 8 s); finalize 1.5 s;
-- publish 0.25 s; the website kept THE 2026 while loading and showed THE 2027 after publish (77 AU/NZ/CA rows linked).
-- Live on deploy. $0. G1: no job. G2: no operational value. G3 checked before and after; locks and cron unchanged.
-- Parity: live head 20261122110000 read 22 Nov 2026 11:10 AEDT; this file is numbered strictly above it.
-- Replaces: the per-row provider searches for rows outside the provider countries; accepting a public edition on its first batch; the s966 initial runs.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s967_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s967_cron on commit drop as select count(*) n from cron.job where active;

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

select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', '1f2c868020597212ed7be6fb51390b9d', null, array[
  array[$o$v_indicator record;\s*begin$o$, $n$v_indicator record; v_scope_names text[]; v_scope boolean; begin$n$],
  array[$o$v_alias_type\s*:=\s*p_system_code\s*\|\|\s*'_publisher_name';$o$,
        $n$v_alias_type:=p_system_code||'_publisher_name'; select coalesce(array_agg(distinct lower(x)), '{}'::text[]) into v_scope_names from ref.countries c cross join lateral unnest(array[c.name::text, c.iso_alpha2::text, c.iso_alpha3::text]) x where x is not null and exists (select 1 from catalogue.providers p where p.country_id = c.id);$n$],
  array[$o$v_provider_id\s*:=\s*null;\s*v_equiv_ids\s*:=\s*null;$o$, $n$v_provider_id:=null; v_equiv_ids:=null; v_scope:=v_country is null or lower(v_country)=any(v_scope_names);$n$],
  array[$o$if\s+v_provider_id\s+is\s+null\s+then\s+select\s+array_agg\(distinct\s+pa\.provider_id$o$, $n$if v_provider_id is null and v_scope then select array_agg(distinct pa.provider_id$n$],
  array[$o$if\s+v_provider_id\s+is\s+null\s+then\s+select\s+array_agg\(p\.id\s+order\s+by\s+p\.id\)\s+into\s+v_candidate_ids$o$, $n$if v_provider_id is null and v_scope then select array_agg(p.id order by p.id) into v_candidate_ids$n$],
  array[$o$'licensed_upload',\s*'Authorised publisher artifact registered through governed Layer 1 Evidence flow',\s*'accepted'\)$o$,
        $n$'licensed_upload','Authorised publisher artifact registered through governed Layer 1 Evidence flow',case when p_source_revision in ('the_public_json_v1','qs_public_json_v1') then 'parsed' else 'accepted' end)$n$],
  array[$o$access_status='licensed_upload',\s*status='accepted'$o$,
        $n$access_status='licensed_upload',status=case when p_source_revision in ('the_public_json_v1','qs_public_json_v1') and editions.status is distinct from 'accepted' then 'parsed' else 'accepted' end$n$]]);

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
  for r in select o.id obs, o.publisher_institution_id pub, c.id cid, lower(regexp_replace(pi.institution_name, '[^A-Za-z0-9]+', '', 'g')) k
             from ranking.observations o
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
             join ref.countries c on lower(c.name) = lower(coalesce(pi.country_text, '')) or lower(c.iso_alpha2::text) = lower(coalesce(pi.country_text, ''))
            where o.edition_id = v_edition and c.id = any(v_cids) and not exists (select 1 from ranking.observation_provider_links l where l.observation_id = o.id) loop
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
     and c.id = any(v_cids);
  return jsonb_build_object('edition_id', v_edition, 'source_revision', v_revision, 'access_status', 'public', 'status', 'accepted',
    'superseded_revisions', v_superseded, 'name_segment_links', v_segment, 'rows', v_rows, 'linked_rows', v_linked, 'unmatched_in_provider_countries', v_unmatched);
end $f$;
comment on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) is 'CF-247 s966, s967 (Platform Admin 22 Nov 2026 09:22, IR-005): publishes an attributed public ranking edition read by ranking-layer1-etl v1.8.0 (access public, attribution recorded, other revisions of the edition superseded) and lists the AU, NZ and CA rows with no provider for review. Service role only.';
revoke all on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) from public, anon, authenticated;
grant execute on function public.svc_ranking_public_edition_publish_v1(text, integer, uuid, text) to service_role;

-- the partial THE 2027 revision of the first run: held until the whole edition is in and published
update ranking.editions set status = 'parsed', updated_at = now()
 where source_revision in ('the_public_json_v1', 'qs_public_json_v1') and status = 'accepted' and access_status <> 'public';

-- the THE and QS 2027 runs again: the s966 runs that are waiting to retry (no worker holds them) are cancelled and replaced
update pipeline.layer1_run_queue set status = 'cancelled', current_stage = 'cancelled', completed_at = now(), heartbeat_at = now(), updated_at = now(),
       error_text = 'Replaced by the s967 re-run (the apply batch time-out is fixed)'
 where idempotency_key like 's966-initial:%' and status in ('queued', 'running') and (lease_until is null or lease_until < now());
insert into pipeline.layer1_run_queue (source_id, country_code, mode, status, idempotency_key, requested_by, expected_count, resume_cursor, processed_count,
  source_hash, warning_acknowledged, current_stage, heartbeat_at, result)
select s.id, 'GLOBAL', 'apply', 'queued', 's967-rerun:' || s.id::text, 'c0ffee00-0000-4000-8000-000000000150', null, 0, 0, null, false, 'queued',
       now() - interval '5 minutes', jsonb_build_object('start_cursor', 0, 'requested_reason', 's967: THE and QS 2027 read again after the s966 batch time-out fix')
  from pipeline.sources s
 where s.metadata->>'ranking_system_code' in ('the_wur', 'qs_wur') and (s.metadata->>'edition_year')::int = 2027 and s.metadata->>'acquisition_mode' = 'publisher_public_json'
   and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = s.id and q.status in ('queued', 'running'))
on conflict (idempotency_key) do nothing;

do $c$
declare v_api jsonb := security.consumer_api_check_v1(); v_def text := pg_get_functiondef('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)'::regprocedure);
begin
  if (select count(*) from regexp_matches(v_def, 'and v_scope then', 'g')) <> 2 then raise exception 'post-check: apply does not skip the searches outside the provider countries'; end if;
  if position('then ''parsed'' else ''accepted'' end' in v_def) = 0 then raise exception 'post-check: apply does not hold a public revision while it loads'; end if;
  if exists (select 1 from ranking.editions where source_revision in ('the_public_json_v1', 'qs_public_json_v1') and status = 'accepted' and access_status <> 'public') then
    raise exception 'post-check: a partial public revision is still accepted';
  end if;
  if (select count(*) from cron.job where active) <> (select n from s967_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s967_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
