-- CF-247 RM0F: database side of the Admin "Destination data" fitout (Platform Admin 17 Nov 2026 13:12, S1-RM-Design lane: Admin UI and registers;
-- decisions G-2, G-3 and G-5 approved 11:52; admin DESTINATION-DATA-UI-AND-INGESTION-SPEC.md v1.2 section 1.5). Read paths, review and approval
-- functions only: no row of destination data is loaded here (loaders are S2-Build's lane) and the importer and guards of 20261115230000 and the
-- career outcomes key (G-1, with the loader) are not touched.
--   1. Admin wrappers: admin_destination_edition_set_terms, admin_destination_edition_publish (Platform Admin, reason recorded),
--      admin_destination_postcode_resolve (Curator and above, reason recorded).
--   2. admin_destination_overview gains the edition list, the catalogued destination load jobs and the postcodes waiting; admin_destination_review
--      gains editions, postcodes grouped with their candidate localities, and each study rule's applicability and stored evidence.
--   3. Quote verifier: destination.study_rules.evidence_id names the stored page the quote is checked against.
--   4. G-3: Layer 4 Inbox kind "Campus locality", registered as a kind hook (contract admin 2026-11-04-layer4-inbox-paging-contract.md): one
--      item per campus whose postcode has candidate localities but no primary match. No change to admin_layer4_inbox.
--   5. G-5: campuses[].locality on the API v3 provider action (website_v3_provider_item and zoho_v3_provider; v3 is open to additions,
--      Decision 277). Null until the postcode has a primary match in an approved or published locality.
--   7. svc_admin_access_log_event accepts the action password_reset_sent, so the reset action of admin-user-management can record it.
--   6. Admin reads for the adapted screens: admin_course_destination_read (schemes and proven study rules of a course) and
--      admin_provider_destination_read (primary campus, mapped locality, registrations by scheme with DLI apart from PGWP).
-- G1: no job. G2: no new operational value; page sizes are bounded like the Inbox's own (marked fixed). G3: no v2 object is read differently,
-- altered, renamed or retyped; the two replaced functions are v3 wrappers.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $$ declare v text; begin
  if to_regclass('destination.localities') is null or to_regclass('destination.locality_postcodes') is null or to_regclass('ref.registration_schemes') is null
     or to_regprocedure('public.admin_destination_set_status(text,uuid,text,text)') is null or to_regclass('pipeline.layer4_inbox_kind_hooks') is null
     or to_regclass('pipeline.admin_control_events') is null then
    raise exception 'an object this change builds on is missing';
  end if;
  -- the functions replaced below are the ones this change was written against (skipped where a fixture has no such function)
  for v in select x from unnest(array['public.admin_destination_overview()=8c45c1fedbaa0dd2f47ab3a8d9bccbaa', 'public.admin_destination_review(text,text)=93874f01200c26de1f3d996bcf1d084f',
                                      'public.website_v3_provider_item(jsonb)=0371e5331d95a3ae6f120b3d46b5771d', 'public.zoho_v3_provider(text)=a903ef945439b17dd590629d0558df44']) x loop
    if to_regprocedure(split_part(v, '=', 1)) is not null and md5(pg_get_functiondef(to_regprocedure(split_part(v, '=', 1)))) <> split_part(v, '=', 2)
       and obj_description(to_regprocedure(split_part(v, '=', 1)), 'pg_proc') is distinct from 'cf247_rm0f' then
      raise exception 'function % is not the definition this change was written against', split_part(v, '=', 1);
    end if;
  end loop;
end $$;

-- 3. the stored page a rule's quote is checked against; who settled a postcode and why
alter table destination.study_rules add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id);
alter table destination.locality_postcodes
  add column if not exists resolved_by uuid,
  add column if not exists resolved_at timestamptz,
  add column if not exists resolve_reason text;

-- the locality a postcode maps to: a primary match in an approved or published locality, newest boundary vintage first
create or replace function security.destination_locality_for_postcode_v1(p_country_code text, p_postcode text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('locality_id', l.id, 'name', l.name, 'geography_type', l.geography_type, 'geography_code', l.geography_code,
                            'boundary_vintage', l.boundary_vintage, 'match_share', p.containment_share)
    from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
   where p.country_code = upper(p_country_code) and p.postcode = nullif(btrim(p_postcode), '') and p.is_primary_match and l.status in ('approved', 'published')
   order by p.boundary_vintage desc limit 1
$$;
revoke all on function security.destination_locality_for_postcode_v1(text, text) from public, anon, authenticated;
grant execute on function security.destination_locality_for_postcode_v1(text, text) to service_role;

-- settle one postcode: one candidate becomes the primary match, or none does; every row of the postcode leaves the review list
create or replace function security.destination_postcode_resolve_v1(p_country_code text, p_postcode text, p_locality uuid, p_actor uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_cc text := upper(btrim(coalesce(p_country_code, ''))); v_pc text := btrim(coalesce(p_postcode, '')); v_n int; v_name text; v_ev bigint;
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  select count(*) into v_n from destination.locality_postcodes p where p.country_code = v_cc and p.postcode = v_pc;
  if v_n = 0 then raise exception 'no candidate locality is held for postcode % (%)', v_pc, v_cc using errcode = 'P0002'; end if;
  if p_locality is not null then
    select l.name into v_name from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
     where p.country_code = v_cc and p.postcode = v_pc and p.locality_id = p_locality limit 1;
    if v_name is null then raise exception 'that locality is not a candidate for postcode %', v_pc using errcode = '22023'; end if;
  end if;
  update destination.locality_postcodes p set is_primary_match = false, needs_layer4_review = false, resolved_by = p_actor, resolved_at = now(), resolve_reason = btrim(p_reason)
   where p.country_code = v_cc and p.postcode = v_pc;
  if p_locality is not null then
    update destination.locality_postcodes p set is_primary_match = true
     where p.country_code = v_cc and p.postcode = v_pc and p.locality_id = p_locality
       and p.boundary_vintage = (select max(x.boundary_vintage) from destination.locality_postcodes x where x.country_code = v_cc and x.postcode = v_pc and x.locality_id = p_locality);
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'postcode_resolve', v_cc || ':' || v_pc, jsonb_build_object('country_code', v_cc, 'postcode', v_pc, 'locality_id', p_locality, 'locality', v_name,
          'reason', btrim(p_reason), 'rows', v_n), p_actor) returning id into v_ev;
  return jsonb_build_object('ok', true, 'country_code', v_cc, 'postcode', v_pc, 'locality_id', p_locality, 'locality', v_name, 'rows', v_n, 'event_id', v_ev);
end $$;
revoke all on function security.destination_postcode_resolve_v1(text, text, uuid, uuid, text) from public, anon, authenticated;

-- 1. Admin wrappers
create or replace function public.admin_destination_postcode_resolve(p_country_code text, p_postcode text, p_locality_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return security.destination_postcode_resolve_v1(p_country_code, p_postcode, p_locality_id, auth.uid(), p_reason);
end $$;

create or replace function public.admin_destination_edition_set_terms(p_edition uuid, p_terms text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_old text; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to record the terms of a destination edition' using errcode = '42501'; end if; -- fixed: terms are the Platform Admin's (REQ-68)
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  select e.terms_status into v_old from destination.editions e where e.id = p_edition;
  perform security.destination_edition_set_terms_v1(p_edition, p_terms, auth.uid());
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'edition_terms', p_edition::text, jsonb_build_object('edition_id', p_edition, 'from', v_old, 'to', p_terms, 'reason', v_reason), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'edition_id', p_edition, 'from', v_old, 'to', p_terms, 'event_id', v_ev);
end $$;

create or replace function public.admin_destination_edition_publish(p_edition uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_old text; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to publish a destination edition' using errcode = '42501'; end if; -- fixed: publication is the Platform Admin's (REQ-68)
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  select e.status into v_old from destination.editions e where e.id = p_edition;
  perform security.destination_edition_publish_v1(p_edition, auth.uid());
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'edition_publish', p_edition::text, jsonb_build_object('edition_id', p_edition, 'from', v_old, 'to', 'published', 'reason', v_reason), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'edition_id', p_edition, 'from', v_old, 'to', 'published', 'event_id', v_ev);
end $$;

-- campuses whose postcode has candidate localities but no primary match (the Layer 4 kind and the overview count read this)
create or replace function security.destination_campus_locality_open_v1(p_provider uuid default null)
returns table(campus_id uuid, provider_id uuid, campus_name text, country_code text, postcode text, opened_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select k.id, k.provider_id, k.name, c.iso_alpha2::text, k.postcode,
         (select min(p.created_at) from destination.locality_postcodes p where p.country_code = c.iso_alpha2 and p.postcode = k.postcode and p.needs_layer4_review)
    from catalogue.campuses k
    join catalogue.providers pr on pr.id = k.provider_id
    join ref.countries c on c.id = coalesce(k.country_id, pr.country_id)
   where nullif(btrim(k.postcode), '') is not null and coalesce(k.status, 'active') <> 'inactive' and (p_provider is null or k.provider_id = p_provider)
     and exists (select 1 from destination.locality_postcodes p where p.country_code = c.iso_alpha2 and p.postcode = k.postcode and p.needs_layer4_review)
     and not exists (select 1 from destination.locality_postcodes p where p.country_code = c.iso_alpha2 and p.postcode = k.postcode and p.is_primary_match)
$$;
revoke all on function security.destination_campus_locality_open_v1(uuid) from public, anon, authenticated;

-- 2. Overview: the counts of 20261117040000, with the edition list, the load jobs and what waits for a person
create or replace function public.admin_destination_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_loads jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if to_regclass('pipeline.automation_catalogue') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object('jobname', a.jobname, 'label', a.label, 'description', a.description, 'control_rank', a.control_rank) order by a.sort, a.jobname), '[]'::jsonb)
                 from pipeline.automation_catalogue a where a.jobname like 'destination-%'$q$ into v_loads;
  end if;
  return jsonb_build_object(
    'editions', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select domain || ':' || status k, count(*) n from destination.editions group by 1) s),
    'editions_list', (select coalesce(jsonb_agg(jsonb_build_object('edition_id', e.id, 'country_code', c.iso_alpha2, 'domain', e.domain, 'edition_label', e.edition_label,
                         'effective_from', e.effective_from, 'effective_to', e.effective_to, 'status', e.status, 'terms_status', e.terms_status, 'source_owner', e.source_owner,
                         'source_url', e.source_url, 'attribution_text', e.attribution_text, 'attribution_present', nullif(btrim(coalesce(e.attribution_text, '')), '') is not null,
                         'approved_at', e.approved_at,
                         'rows', case e.domain when 'study_rules' then (select count(*) from destination.study_rules r where r.edition_id = e.id)
                                               when 'career_outcomes' then (select count(*) from destination.career_outcomes o where o.edition_id = e.id)
                                               else (select count(*) from destination.city_profiles p where p.edition_id = e.id) end,
                         'rows_approved', case e.domain when 'study_rules' then (select count(*) from destination.study_rules r where r.edition_id = e.id and r.approval_status = 'approved')
                                               when 'career_outcomes' then (select count(*) from destination.career_outcomes o where o.edition_id = e.id and o.status in ('approved', 'published')) end)
                         order by c.iso_alpha2, e.domain, e.effective_from desc), '[]'::jsonb)
                        from destination.editions e join ref.countries c on c.id = e.country_id),
    'localities', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from destination.localities group by 1) s),
    'localities_without_attribution', (select count(*) from destination.localities l where nullif(btrim(l.attribution_text), '') is null),
    'locality_postcodes', (select jsonb_build_object('rows', count(*), 'primary', count(*) filter (where is_primary_match), 'needs_layer4_review', count(*) filter (where needs_layer4_review),
                                                     'postcodes_needing_review', count(distinct (country_code, postcode)) filter (where needs_layer4_review)) from destination.locality_postcodes),
    'campuses_waiting_locality', (select count(*) from security.destination_campus_locality_open_v1(null)),
    'locality_metrics', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select metric_category || ':' || status k, count(*) n from destination.locality_metrics group by 1) s),
    'study_rules', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(rule_category, 'visa') || ':' || approval_status k, count(*) n from destination.study_rules group by 1) s),
    'rule_applicability', (select coalesce(jsonb_object_agg(applicability_status, n), '{}'::jsonb) from (select applicability_status, count(*) n from destination.rule_applicability group by 1) s),
    'career_outcomes', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from destination.career_outcomes group by 1) s),
    'registration_schemes', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select kind || ':' || status k, count(*) n from ref.registration_schemes group by 1) s),
    'loads', v_loads,
    'postcode_primary_min_share', security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9),
    'rank', security.current_role_rank(),
    'checked_at', now());
end $$;
comment on function public.admin_destination_overview() is 'cf247_rm0f';

-- 2. Review lists
create or replace function public.admin_destination_review(p_kind text, p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_max int := security.pipeline_num_v1('destination.review_list_max', 200)::int; v jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_kind = 'locality' then
    select coalesce(jsonb_agg(x.j), '[]'::jsonb) into v from (
      select to_jsonb(l) || jsonb_build_object('postcodes_primary', (select count(*) from destination.locality_postcodes p where p.locality_id = l.id and p.is_primary_match),
                                               'postcodes_review', (select count(*) from destination.locality_postcodes p where p.locality_id = l.id and p.needs_layer4_review),
                                               'metrics', (select count(*) from destination.locality_metrics m where m.locality_id = l.id)) j
        from destination.localities l where p_status is null or l.status = p_status order by l.country_code, l.name limit v_max) x;
  elsif p_kind = 'locality_metric' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select m.*, l.name locality_name, l.country_code from destination.locality_metrics m join destination.localities l on l.id = m.locality_id
                                                                    where p_status is null or m.status = p_status order by l.country_code, l.name, m.metric_key limit v_max) x;
  elsif p_kind = 'locality_postcode' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select p.*, l.name locality_name from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
                                                                    where p.needs_layer4_review order by p.country_code, p.postcode, p.containment_share desc limit v_max) x;
  elsif p_kind = 'postcode' then
    -- one row per postcode still waiting for a person, with its candidate localities and the campuses it holds up
    select coalesce(jsonb_agg(x.j), '[]'::jsonb) into v from (
      select jsonb_build_object('country_code', g.country_code, 'postcode', g.postcode, 'opened_at', g.opened_at,
               'candidates', (select jsonb_agg(jsonb_build_object('locality_id', l.id, 'name', l.name, 'geography_code', l.geography_code, 'locality_status', l.status,
                                        'containment_share', p.containment_share, 'boundary_vintage', p.boundary_vintage) order by p.containment_share desc, l.name)
                                from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id where p.country_code = g.country_code and p.postcode = g.postcode),
               'campuses', (select count(*) from catalogue.campuses k join catalogue.providers pr on pr.id = k.provider_id join ref.countries c on c.id = coalesce(k.country_id, pr.country_id)
                             where c.iso_alpha2 = g.country_code and k.postcode = g.postcode and coalesce(k.status, 'active') <> 'inactive')) j
        from (select p.country_code, p.postcode, min(p.created_at) opened_at from destination.locality_postcodes p where p.needs_layer4_review
               and not exists (select 1 from destination.locality_postcodes q where q.country_code = p.country_code and q.postcode = p.postcode and q.is_primary_match)
               group by 1, 2 order by 1, 2 limit v_max) g) x;
  elsif p_kind = 'study_rule' then
    select coalesce(jsonb_agg(x.j), '[]'::jsonb) into v from (
      select to_jsonb(r) || jsonb_build_object('edition_label', e.edition_label, 'edition_status', e.status, 'terms_status', e.terms_status,
               'country_code', (select c.iso_alpha2 from ref.countries c where c.id = r.country_id),
               'applicability', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'entity_type', a.entity_type, 'entity_id', a.entity_id, 'entity_code', a.entity_code,
                                            'status', a.applicability_status, 'evidence_url', a.evidence_url, 'quote_on_page', a.quote_on_page, 'verified_at', a.verified_at,
                                            'entity_name', case a.entity_type when 'country' then (select c.name from ref.countries c where c.id = a.entity_id)
                                                                              when 'locality' then (select l.name from destination.localities l where l.id = a.entity_id)
                                                                              when 'provider' then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = a.entity_id)
                                                                              else a.entity_code end) order by a.entity_type, a.entity_code)
                                           from destination.rule_applicability a where a.rule_id = r.id), '[]'::jsonb),
               'evidence', case when r.evidence_id is null then null else (select jsonb_build_object('evidence_id', ev.id, 'source_url', ev.source_url, 'captured_at', ev.captured_at,
                                            'stored', ev.storage_path is not null) from pipeline.evidence_artifacts ev where ev.id = r.evidence_id) end) j
        from destination.study_rules r join destination.editions e on e.id = r.edition_id
       where p_status is null or r.approval_status = p_status order by r.created_at desc limit v_max) x;
  elsif p_kind = 'career_outcome' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select o.*, e.edition_label, e.status edition_status, e.terms_status,
                                                                           (select c.iso_alpha2 from ref.countries c where c.id = o.country_id) country_code,
                                                                           (select l.name from destination.localities l where l.id = o.locality_id) locality_name
                                                                      from destination.career_outcomes o join destination.editions e on e.id = o.edition_id
                                                                     where p_status is null or o.status = p_status order by o.occupation_code limit v_max) x;
  else
    raise exception 'kind must be locality, locality_metric, locality_postcode, postcode, study_rule or career_outcome' using errcode = '22023';
  end if;
  return jsonb_build_object('kind', p_kind, 'status', p_status, 'limit', v_max, 'rows', v);
end $$;
comment on function public.admin_destination_review(text, text) is 'cf247_rm0f';

-- 4. Layer 4 Inbox kind "Campus locality" (G-3), as a registered kind hook
create or replace function security.layer4_campus_locality_kind_v1() returns jsonb
language sql immutable set search_path = '' as $$
  select '{"label": "Campus locality", "order": 36, "choices": [
     {"key": "accept_largest", "label": "Accept the locality with the largest share", "rank": 3, "returns": "That locality becomes the match for this postcode and for every campus in it; API v3 shows it once the locality is approved"},
     {"key": "choose_locality", "label": "Choose another candidate (enter its code)", "input": "text", "rank": 3, "returns": "The candidate locality with the code you enter becomes the match for this postcode"},
     {"key": "no_locality", "label": "Not in any locality", "rank": 3, "returns": "The postcode is recorded as outside every locality; its campuses show no city figures"}]}'::jsonb
$$;
revoke all on function security.layer4_campus_locality_kind_v1() from public, anon, authenticated;

create or replace function security.layer4_campus_locality_inbox_counts_v1() returns jsonb
language sql stable security definer set search_path = '' as $$
  with o as (select * from security.destination_campus_locality_open_v1(null))
  select jsonb_build_object('kind', 'campus_locality', 'n', (select count(*) from o), 'oldest', (select min(o.opened_at) from o),
    'late', (select count(*) from o where o.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.opened_at) oldest from o group by 1) z), '[]'::jsonb))
$$;
revoke all on function security.layer4_campus_locality_inbox_counts_v1() from public, anon, authenticated;

create or replace function security.layer4_campus_locality_inbox_page_v1(p_args jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  with o as (select * from security.destination_campus_locality_open_v1(nullif(p_args->>'provider_id', '')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.opened_at, o.campus_id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.opened_at, o.campus_id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'campus_locality',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.opened_at, o.campus_id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'campus_locality', 'ref', x.campus_id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce(nullif(btrim(x.campus_name), ''), 'Campus') || ' · postcode ' || x.postcode,
           'why', (select 'Largest share is ' || l.name || ' at ' || round(p.containment_share * 100) || '%, below the ' ||
                          round(security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9) * 100) || '% needed for an automatic match'
                     from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
                    where p.country_code = x.country_code and p.postcode = x.postcode order by p.containment_share desc, l.name limit 1),
           'suggestion', (select 'Accept ' || l.name || ' (' || round(p.containment_share * 100) || '%)'
                     from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
                    where p.country_code = x.country_code and p.postcode = x.postcode order by p.containment_share desc, l.name limit 1),
           'created_at', x.opened_at, 'postcode', x.postcode, 'country_code', x.country_code,
           'late', x.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.opened_at, x.campus_id::text) from x), '[]'::jsonb))
$$;
revoke all on function security.layer4_campus_locality_inbox_page_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_campus_locality_inbox_detail_v1(p_ref text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'candidates', 'title', 'Candidate localities for postcode ' || o.postcode,
        'body', coalesce((select jsonb_object_agg(l.name || ' (code ' || l.geography_code || ', ' || l.geography_type || ')', round(p.containment_share * 100, 1) || '% of the postcode')
                            from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id where p.country_code = o.country_code and p.postcode = o.postcode), '{}'::jsonb)),
      jsonb_build_object('key', 'effect', 'title', 'What a decision changes',
        'body', 'The decision is for the postcode: every campus in ' || o.postcode || ' gets the same answer. ' ||
                (select count(*) from security.destination_campus_locality_open_v1(null) z where z.country_code = o.country_code and z.postcode = o.postcode) || ' campus(es) wait on it.')),
    'actions', jsonb_build_array(jsonb_build_object('key', 'accept_largest', 'allowed', true), jsonb_build_object('key', 'choose_locality', 'allowed', true), jsonb_build_object('key', 'no_locality', 'allowed', true)))
    from security.destination_campus_locality_open_v1(null) o where o.campus_id::text = p_ref
$$;
revoke all on function security.layer4_campus_locality_inbox_detail_v1(text) from public, anon, authenticated;

create or replace function security.layer4_campus_locality_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o record; v_loc uuid; v_r jsonb; v_ev bigint; v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Layer 4 Inbox: ' || p_choice);
begin
  select * into o from security.destination_campus_locality_open_v1(null) z where z.campus_id::text = p_ref;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'campus_locality', 'choice', p_choice, 'ref', p_ref, 'request', 'This postcode has already been settled; refresh the Inbox.');
  end if;
  if p_choice = 'accept_largest' then
    select p.locality_id into v_loc from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
     where p.country_code = o.country_code and p.postcode = o.postcode order by p.containment_share desc, l.name limit 1;
  elsif p_choice = 'choose_locality' then
    select p.locality_id into v_loc from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
     where p.country_code = o.country_code and p.postcode = o.postcode and (l.geography_code = btrim(coalesce(p_value, '')) or lower(l.name) = lower(btrim(coalesce(p_value, '')))) limit 1;
    if v_loc is null then
      return jsonb_build_object('ok', false, 'kind', 'campus_locality', 'choice', p_choice, 'ref', p_ref,
               'request', 'Enter the code or name of one of the candidate localities listed for postcode ' || o.postcode || '.');
    end if;
  elsif p_choice = 'no_locality' then
    v_loc := null;
  else
    raise exception 'unknown choice %', p_choice using errcode = '22023';
  end if;
  v_r := security.destination_postcode_resolve_v1(o.country_code, o.postcode, v_loc, auth.uid(), v_reason);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'campus_locality:' || p_ref, jsonb_build_object('kind', 'campus_locality', 'ref', p_ref, 'choice', p_choice, 'value', p_value, 'reason', v_reason,
          'provider_id', o.provider_id, 'result', v_r), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'kind', 'campus_locality', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'result', v_r,
           'returns', case when v_loc is null then 'Postcode ' || o.postcode || ' is recorded as outside every locality.' else 'Postcode ' || o.postcode || ' now maps to ' || (v_r->>'locality') || '.' end);
end $$;
revoke all on function security.layer4_campus_locality_inbox_decide_v1(text, text, text, text) from public, anon, authenticated;

insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('campus_locality', 'kind', 'security.layer4_campus_locality_kind_v1()', 'security.layer4_campus_locality_inbox_counts_v1()', 'security.layer4_campus_locality_inbox_page_v1(jsonb)',
        'security.layer4_campus_locality_inbox_detail_v1(text)', 'security.layer4_campus_locality_inbox_decide_v1(text,text,text,text)', true,
        'Destination data (cf247_rm0f_destination_admin_ui)', 'Campus postcodes below the primary-match share (decision G-3, Platform Admin 17 Nov 2026)')
on conflict (kind, mode) do nothing;

-- 5. G-5: campuses[].locality on the API v3 provider action. Website: the body of 20261113 (R23, R31) with one more key per campus.
create or replace function public.website_v3_provider_item(p_item jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_provider uuid; v_campuses jsonb; v_page record; v_cc text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'campuses') then return p_item; end if;
  select p.id, (select c.iso_alpha2 from ref.countries c where c.id = p.country_id) into v_provider, v_cc from catalogue.providers p where p.stable_key = p_item->>'provider_id';
  if v_provider is null then return p_item; end if;
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id, k.country_id
      from catalogue.campuses k
     where k.provider_id = v_provider and nullif(btrim(k.city), '') is not null and coalesce(k.status, 'active') <> 'inactive'),
  n as (
    -- one grouped read per provider, never one per campus
    select cc.campus_id, count(distinct cc.course_id) n
      from search.course_documents d
      join catalogue.course_campuses cc on cc.course_id = d.course_id
     where d.provider_id = v_provider
       -- checked per course: an anti-join builds the whole view on every call (measured 12 Nov 2026: 50 providers 2.3 s, per course 0.15 s)
       and (select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0
     group by cc.campus_id)
  select coalesce(jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name,
           'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0),
           -- G-5 (17 Nov 2026): the approved locality the campus postcode maps to; null until it has a primary match
           'locality', security.destination_locality_for_postcode_v1(coalesce((select c.iso_alpha2 from ref.countries c where c.id = k.country_id), v_cc), k.postcode))
           order by lower(nullif(btrim(k.name), '')) nulls last, k.stable_key), '[]'::jsonb)
    into v_campuses
    from k
    left join ref.subdivisions s on s.id = k.subdivision_id
    left join pipeline.campus_regional_class rc on rc.campus_id = k.id
    left join n on n.campus_id = k.id;
  -- R31: the scholarships listing page the platform reads for this provider, and when it was last read
  select lp.url, lp.read_at into v_page
    from pipeline.scholarship_listing_pages lp
   where lp.provider_id = v_provider and lp.active and lp.status = 'read' and lp.read_at is not null
   order by lp.read_at desc, lp.id limit 1;
  return jsonb_set(p_item, '{campuses}', v_campuses)
         || jsonb_build_object('scholarships_page_url', v_page.url, 'scholarships_last_reviewed_at', v_page.read_at);
end $$;
comment on function public.website_v3_provider_item(jsonb) is 'cf247_rm0f';

-- Zoho: the v2 answer with the same key on each campus (a v2 campus item carries its own country_code and postcode)
create or replace function public.zoho_v3_provider(p_identifier text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.zoho_v2_provider(p_identifier);
begin
  if jsonb_typeof(v->'item'->'campuses') = 'array' then
    v := jsonb_set(v, '{item,campuses}', coalesce((
           select jsonb_agg(case when jsonb_typeof(e) = 'object'
                                 then e || jsonb_build_object('locality', case when nullif(e->>'country_code', '') is null then null
                                                                               else security.destination_locality_for_postcode_v1(e->>'country_code', e->>'postcode') end)
                                 else e end order by o)
             from jsonb_array_elements(v->'item'->'campuses') with ordinality x(e, o)), '[]'::jsonb));
  end if;
  return v;
end $$;
comment on function public.zoho_v3_provider(text) is 'cf247_rm0f';

-- 6. Admin reads for the adapted Course and Provider screens
create or replace function public.admin_course_destination_read(p_course_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_provider uuid; v_country uuid; v_cc text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select c.provider_id, p.country_id, (select x.iso_alpha2 from ref.countries x where x.id = p.country_id) into v_provider, v_country, v_cc
    from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = p_course_id;
  if v_provider is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'country_code', v_cc,
    'registrations', coalesce((select jsonb_agg(jsonb_build_object('scheme', lower(r.scheme), 'code', r.registration_code, 'status', r.status, 'valid_to', r.valid_to,
                                 'label', s.label, 'authority', s.authority, 'registered_scheme', s.scheme is not null, 'never_mixed_with', coalesce(s.never_mixed_with, '{}'))
                                 order by lower(r.scheme), r.registration_code)
                                from catalogue.course_registrations r
                                left join ref.registration_schemes s on s.scheme = lower(r.scheme) and s.kind in ('course_registration', 'work_eligibility') and s.country_code = v_cc
                               where r.course_id = p_course_id), '[]'::jsonb),
    'field_schemes', coalesce((select jsonb_agg(jsonb_build_object('scheme', s.scheme, 'label', s.label, 'authority', s.authority, 'status', s.status) order by s.scheme)
                                from ref.registration_schemes s where s.kind = 'field_of_study' and s.country_code = v_cc), '[]'::jsonb),
    'study_rules', coalesce((select jsonb_agg(jsonb_build_object('rule_id', r.id, 'title', coalesce(r.title, r.visa_name), 'rule_category', coalesce(r.rule_category, 'visa'),
                                 'applies_through', a.entity_type, 'approval_status', r.approval_status, 'edition_status', e.status, 'effective_from', r.effective_from, 'effective_to', r.effective_to,
                                 'evidence_url', a.evidence_url) order by r.rule_category, r.title)
                               from destination.rule_applicability a
                               join destination.study_rules r on r.id = a.rule_id
                               join destination.editions e on e.id = r.edition_id
                              where a.applicability_status = 'proven'
                                and ((a.entity_type = 'course' and a.entity_id = p_course_id) or (a.entity_type = 'provider' and a.entity_id = v_provider)
                                     or (a.entity_type = 'country' and a.entity_id = v_country))), '[]'::jsonb),
    'excluded_rules', (select count(*) from destination.rule_applicability a where a.applicability_status = 'excluded'
                         and ((a.entity_type = 'course' and a.entity_id = p_course_id) or (a.entity_type = 'provider' and a.entity_id = v_provider))));
end $$;

create or replace function public.admin_provider_destination_read(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_cc text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select (select c.iso_alpha2 from ref.countries c where c.id = p.country_id) into v_cc from catalogue.providers p where p.id = p_provider_id;
  if not found then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'country_code', v_cc,
    'campuses', coalesce((select jsonb_agg(jsonb_build_object('campus_id', k.id, 'name', k.name, 'city', k.city, 'postcode', k.postcode, 'is_primary', coalesce(k.is_primary, false),
                            'primary_basis', k.primary_basis,
                            'locality', security.destination_locality_for_postcode_v1(coalesce((select c.iso_alpha2 from ref.countries c where c.id = k.country_id), v_cc), k.postcode),
                            -- a match that exists but whose locality is not approved yet, and a postcode waiting for a person, are shown as such
                            'pending_locality', (select l.name from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
                                                  where p.country_code = coalesce((select c.iso_alpha2 from ref.countries c where c.id = k.country_id), v_cc) and p.postcode = k.postcode
                                                    and p.is_primary_match and l.status not in ('approved', 'published') limit 1),
                            'in_layer4', exists (select 1 from security.destination_campus_locality_open_v1(p_provider_id) o where o.campus_id = k.id))
                            order by coalesce(k.is_primary, false) desc, k.name)
                           from catalogue.campuses k where k.provider_id = p_provider_id and coalesce(k.status, 'active') <> 'inactive'), '[]'::jsonb),
    'registrations', coalesce((select jsonb_agg(jsonb_build_object('scheme', lower(r.registration_scheme), 'code', r.registration_code, 'status', r.status,
                                 'label', s.label, 'authority', s.authority, 'never_mixed_with', coalesce(s.never_mixed_with, '{}')) order by lower(r.registration_scheme), r.registration_code)
                                from catalogue.provider_registrations r
                                left join ref.registration_schemes s on s.scheme = lower(r.registration_scheme) and s.kind = 'provider_registration' and s.country_code = v_cc
                               where r.provider_id = p_provider_id), '[]'::jsonb),
    -- PGWP is a programme's work eligibility, never a provider registration: counted apart from the DLI number
    'work_eligibility', (select jsonb_build_object('scheme', 'pgwp', 'label', (select s.label from ref.registration_schemes s where s.scheme = 'pgwp' limit 1),
                                  'courses', count(distinct r.course_id))
                           from catalogue.course_registrations r join catalogue.courses c on c.id = r.course_id where c.provider_id = p_provider_id and lower(r.scheme) = 'pgwp'));
end $$;

revoke all on function public.admin_destination_postcode_resolve(text, text, uuid, text) from public, anon;
revoke all on function public.admin_destination_edition_set_terms(uuid, text, text) from public, anon;
revoke all on function public.admin_destination_edition_publish(uuid, text) from public, anon;
revoke all on function public.admin_course_destination_read(uuid) from public, anon;
revoke all on function public.admin_provider_destination_read(uuid) from public, anon;
grant execute on function public.admin_destination_postcode_resolve(text, text, uuid, text) to authenticated, service_role;
grant execute on function public.admin_destination_edition_set_terms(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_destination_edition_publish(uuid, text) to authenticated, service_role;
grant execute on function public.admin_course_destination_read(uuid) to authenticated, service_role;
grant execute on function public.admin_provider_destination_read(uuid) to authenticated, service_role;

-- 7. Admin access history: the log function accepts password_reset_sent (the table has accepted it since 20261117040000). The body is the
-- live one with one more action; replaced only where it is the definition this change was written against.
do $do$ begin
  if to_regprocedure('public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb)') is null then return; end if;
  if md5(pg_get_functiondef('public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb)'::regprocedure)) not in ('09d33e410dc1529b6711f3ed3c34c5a7')
     and obj_description('public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb)'::regprocedure, 'pg_proc') is distinct from 'cf247_rm0f' then
    raise exception 'svc_admin_access_log_event is not the definition this change was written against';
  end if;
  execute $fn$
create or replace function public.svc_admin_access_log_event(p_actor_user_id uuid, p_target_user_id uuid, p_action text, p_before_state jsonb default '{}'::jsonb, p_after_state jsonb default '{}'::jsonb, p_metadata jsonb default '{}'::jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'security', 'auth'
as $body$
declare v_id uuid;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from security.user_roles ur
    join security.roles r on r.code=ur.role_code
    join auth.users u on u.id=ur.user_id
    where ur.user_id=p_actor_user_id
      and r.code='platform_admin' and r.status='active'
      and (ur.expires_at is null or ur.expires_at>now())
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now())
  ) then
    raise exception 'active platform admin actor required' using errcode='42501';
  end if;

  if p_action not in ('user_created','user_invited','roles_replaced','user_disabled','user_enabled','password_reset_sent') then
    raise exception 'unsupported access audit action' using errcode='22023';
  end if;

  insert into security.user_access_events(actor_user_id,target_user_id,action,before_state,after_state,metadata)
  values(
    p_actor_user_id,p_target_user_id,p_action,
    coalesce(p_before_state,'{}'::jsonb),coalesce(p_after_state,'{}'::jsonb),
    (coalesce(p_metadata,'{}'::jsonb) - 'password' - 'token' - 'access_token' - 'refresh_token')
  ) returning id into v_id;
  return v_id;
end
$body$
  $fn$;
  comment on function public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb) is 'cf247_rm0f';
end $do$;

-- Post-check
do $$ begin
  if security.layer4_campus_locality_kind_v1()->>'label' <> 'Campus locality' or (security.layer4_campus_locality_inbox_counts_v1()->>'n') is null then raise exception 'post-check: Layer 4 kind'; end if;
  if (select count(*) from pipeline.layer4_inbox_kind_hooks where kind = 'campus_locality' and mode = 'kind' and enabled) <> 1 then raise exception 'post-check: hook row'; end if;
  if security.destination_locality_for_postcode_v1('AU', '0000') is not null then raise exception 'post-check: an unknown postcode has no locality'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'destination' and table_name = 'study_rules' and column_name = 'evidence_id') then raise exception 'post-check: evidence_id'; end if;
end $$;
