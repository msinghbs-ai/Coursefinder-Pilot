-- CF-247 RM1A-2 (O28, Australia): source-backed ASCED field-of-study codes on Website API v3 and Zoho API v3 course detail. Admin
-- destination data design v1.3 (docs/Roadmap/2026-01/DESTINATION-DATA-DESIGN.md), Platform Admin 16 Nov 2026 22:30 AEDT: Wave 1 RM1A-2,
-- and Zoho v3 additive fields merge on green like Website v3 (both pre-cutover, no handover document issued). Decision 277.
-- Guards: G1 (no job), G2 (no operational value), G3 (no website_v2_*, zoho_v2_*, api.* object or table they read is altered; v3 only),
--   G4 (tests/uat/cf-247-rm1a2-asced-field-codes-v3-contract.spec.mjs), Decision 260.
-- No new table: catalogue.course_field_observations already records each CRICOS "Field of Education" code against its source and stored
--   evidence (written by svc_layer1_apply_course_regulatory_facts and the register adapter). This change only reads it. The assignment
--   table proposed in design v1.1 §4 M2 is withdrawn.
-- What:
--   1. security.course_field_codes_v1(course ids): read only. field_of_study_codes[] = the course's current ASCED narrow-field observations
--      whose code is the 4-digit code the source printed, whose field is that same ASCED code, with an active public source, stored evidence
--      and a CRICOS registration. rank 1 = the register's first field (and the course's study_area), rank 2 = its second field. A primary
--      observation that no longer equals the course's field is left out (held reason primary_field_superseded). Nothing inferred is read:
--      courses.primary_field_id values set by the AI classifier (NZ, CA) have no observation row and give [].
--   2. security.course_roadmap_item_v1(item): a v3 course item with recognition[] (RM1A-1) and field_of_study_codes[] added, one course
--      lookup. [] when nothing is admitted; [] never means "none". study_area is not changed.
--   3. public.website_v3_course (both forms) and public.zoho_v3_course: their current answer with item 2 in place of the RM1A-1 item
--      function (Zoho: added). Zoho v3 search, courses, sync and export are unchanged.
--   4. Admin reads: public.admin_course_recognition_delivery() gains field_codes counts; public.admin_course_recognition_read(course)
--      gains field_codes and field_codes_held_reason.
-- Replaces: public.website_v3_course(text), public.website_v3_course(text, text), public.zoho_v3_course(text, text),
--   public.admin_course_recognition_delivery(), public.admin_course_recognition_read(uuid) (same names and signatures; the three v3
--   functions md5-guarded against live). Retires: security.course_recognition_item_v1 (marked retiring; replaced by
--   security.course_roadmap_item_v1; dropped later by paste file).
-- Reversal: re-create the three v3 functions from 20261113333000 (website) and 20261113290000 (zoho); v2 is unaffected either way.

do $guard$
declare v_want jsonb := jsonb_build_object(
  'public.website_v3_course(text)', 'edb1b66e12b9447ed08c4f0f9671c031',
  'public.website_v3_course(text,text)', 'cbb965e8f20490ac8bcf03853388e993',
  'public.zoho_v3_course(text,text)', 'f3e97603060758910666f4e0ac7928f6'); k text;
begin
  for k in select jsonb_object_keys(v_want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v_want->>k then
      raise exception 'live % differs from the definition this change replaces (md5 %)', k, md5(pg_get_functiondef(k::regprocedure));
    end if;
  end loop;
  if to_regclass('catalogue.course_field_observations') is null or to_regprocedure('security.course_recognition_v1(uuid[])') is null
  then raise exception 'an object this change reads is missing'; end if;
end $guard$;

-- 1 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_field_codes_v1(p_course_ids uuid[])
returns table (course_id uuid, field_of_study_codes jsonb, held_reason text)
language sql stable security definer set search_path = '' as $$
  select u.id,
         coalesce(jsonb_agg(jsonb_build_object(
             'scheme', 'ASCED', 'level', 'narrow', 'code', o.source_field_code, 'name', o.source_field_name,
             'rank', case when o.is_primary then 1 else 2 end, 'source_url', s.url,
             'evidence_date', to_char((e.captured_at at time zone 'Australia/Melbourne')::date, 'YYYY-MM-DD'))
           order by (not o.is_primary), o.source_field_code)
           filter (where o.id is not null and f.id is not null and s.url is not null and e.id is not null
                     and (not o.is_primary or o.field_id = c.primary_field_id)), '[]'::jsonb),
         case when bool_or(o.id is not null and o.is_primary and o.field_id is distinct from c.primary_field_id) then 'primary_field_superseded'
              when bool_or(o.id is not null and (f.id is null or s.url is null or e.id is null)) then 'field_code_source_missing' end
    from unnest(p_course_ids) u(id)
    left join catalogue.courses c on c.id = u.id
    left join catalogue.course_field_observations o
           on o.course_id = u.id and o.status = 'current' and o.source_field_code ~ '^[0-9]{4}$'
          and exists (select 1 from catalogue.course_registrations r where r.course_id = u.id and r.scheme = 'cricos')
    left join ref.fields_of_study f on f.id = o.field_id and f.code = 'asced-' || o.source_field_code and f.status = 'active'
    left join pipeline.sources s on s.id = o.source_id and s.status = 'active'
    left join pipeline.evidence_artifacts e on e.id = o.evidence_id
   where u.id is not null
   group by u.id
$$;
revoke all on function security.course_field_codes_v1(uuid[]) from public, anon, authenticated;
comment on function security.course_field_codes_v1(uuid[]) is
  'CF-247 RM1A-2 (O28): ASCED narrow-field codes for the given courses from catalogue.course_field_observations (CRICOS register evidence), with a held reason. Read only.';

-- 2 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_roadmap_item_v1(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_course uuid; v_rec jsonb; v_codes jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
  if v_course is not null then
    select x.recognition into v_rec from security.course_recognition_v1(array[v_course]) x;
    select x.field_of_study_codes into v_codes from security.course_field_codes_v1(array[v_course]) x;
  end if;
  return p_item || jsonb_build_object('recognition', coalesce(v_rec, '[]'::jsonb), 'field_of_study_codes', coalesce(v_codes, '[]'::jsonb));
end $$;
revoke all on function security.course_roadmap_item_v1(jsonb) from public, anon, authenticated;
comment on function security.course_roadmap_item_v1(jsonb) is
  'CF-247 RM1A (O29, O28): a v3 course item with recognition[] and field_of_study_codes[] added ([] when none is admitted); nothing else changed.';

-- 3 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function public.website_v3_course(p_identifier text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier);
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_roadmap_item_v1(v->'item')); end if;  -- RM1A (O29, O28)
  return v;
end $$;

create or replace function public.website_v3_course(p_identifier text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v #> '{item,entry,resolution,rows}') = 'array' then
    select d.course_id, d.provider_id into v_course, v_provider from search.course_documents d
     where lower(d.course_stable_key) = lower(v->'item'->>'course_id') and d.course_stable_key is not null limit 1;
    v := jsonb_set(v, '{item,entry,resolution,rows}', (select coalesce(jsonb_agg(r || jsonb_build_object('source_url', coalesce(
             (select m.source_url from catalogue.provider_entry_matrix m
               where m.provider_id = v_provider and m.status = 'active' and m.country_code = v_cc and m.quote = r->>'quote' order by m.updated_at desc limit 1),
             (select x.source_url from catalogue.course_entry_requirements x
               where x.course_id = v_course and x.status = 'active' and x.quote = r->>'quote' order by x.updated_at desc limit 1))) order by o), '[]'::jsonb)
        from jsonb_array_elements(v #> '{item,entry,resolution,rows}') with ordinality t(r, o)));
  end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_roadmap_item_v1(v->'item')); end if;  -- RM1A (O29, O28)
  return v;
end $$;
comment on function public.website_v3_course(text) is 'Website API v3 (Decision 277): website_v2_course with R28, recognition[] (O29) and field_of_study_codes[] (O28).';
comment on function public.website_v3_course(text, text) is 'Website API v3 (Decision 277): website_v2_course with R28, entry.resolution.rows[] source_url (O20), recognition[] (O29) and field_of_study_codes[] (O28).';

create or replace function public.zoho_v3_course(p_identifier text, p_edu_country text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.zoho_v2_course(p_identifier); w jsonb;
begin
  if nullif(btrim(coalesce(p_edu_country, '')), '') is not null then
    w := public.website_v3_course(p_identifier, p_edu_country); -- refuses an unknown country (INVALID_INPUT), as the website action does
  end if;
  if jsonb_typeof(v->'item') = 'object' then
    v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item'));
    if w #> '{item,entry}' is not null and w #>> '{item,course_id}' = v #>> '{item,course_id}' then v := jsonb_set(v, '{item,entry}', w #> '{item,entry}'); end if;
    v := jsonb_set(v, '{item}', security.course_roadmap_item_v1(v->'item'));  -- RM1A (O29, O28): Zoho v3 course detail, Platform Admin 16 Nov 2026 22:30
  end if;
  return v;
end $$;

-- 4 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_field_codes_delivery_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  with x as (select d.course_id,
               bool_or(o.is_primary and o.field_id = c.primary_field_id and f.id is not null and s.url is not null and e.id is not null) rank1,
               bool_or(not o.is_primary and f.id is not null and s.url is not null and e.id is not null) rank2,
               bool_or(o.is_primary and o.field_id is distinct from c.primary_field_id) superseded
          from search.course_documents d join catalogue.courses c on c.id = d.course_id
          left join catalogue.course_field_observations o on o.course_id = d.course_id and o.status = 'current' and o.source_field_code ~ '^[0-9]{4}$'
          left join ref.fields_of_study f on f.id = o.field_id and f.code = 'asced-' || o.source_field_code and f.status = 'active'
          left join pipeline.sources s on s.id = o.source_id and s.status = 'active'
          left join pipeline.evidence_artifacts e on e.id = o.evidence_id
         where d.country_code = 'AU' group by 1)
  select jsonb_build_object('au_searchable', count(*), 'served', count(*) filter (where rank1), 'with_second_field', count(*) filter (where rank1 and rank2),
           'superseded_primary_left_out', count(*) filter (where superseded), 'none', count(*) filter (where not coalesce(rank1, false)),
           'other_countries', 'not served: only codes the national register prints are returned (NZ and CA study areas are inferred)')
    into v from x;
  return v;
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $f$;
revoke all on function security.course_field_codes_delivery_v1() from public, anon, authenticated;
comment on function security.course_field_codes_delivery_v1() is
  'CF-247 RM1A-2 (O28): ASCED field-code coverage for the Data Delivery screen (public.admin_course_recognition_delivery). Read only.';

create or replace function public.admin_course_recognition_delivery()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;  -- fixed: the Data Delivery screen's rank (admin_layer23 data_delivery)
  return security.course_recognition_delivery_v1() || jsonb_build_object('field_codes', security.course_field_codes_delivery_v1(), 'counted_at', now());
end $f$;

create or replace function public.admin_course_recognition_read(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_rec record; v_codes record;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select * into v_rec from security.course_recognition_v1(array[p_course_id]);
  select * into v_codes from security.course_field_codes_v1(array[p_course_id]);
  return jsonb_build_object(
    'course_id', p_course_id,
    'in_search', exists (select 1 from search.course_documents d where d.course_id = p_course_id),
    'served', coalesce(v_rec.recognition, '[]'::jsonb),
    'held_reason', v_rec.held_reason,
    'field_codes', coalesce(v_codes.field_of_study_codes, '[]'::jsonb),
    'field_codes_held_reason', v_codes.held_reason,
    'registrations', coalesce((select jsonb_agg(jsonb_build_object(
        'scheme', r.scheme, 'code', r.registration_code, 'status', r.status, 'valid_from', r.valid_from, 'valid_to', r.valid_to,
        'source_label', s.label, 'source_url', s.url, 'evidence_id', r.evidence_id, 'captured_at', e.captured_at,
        'on_website_v3', r.scheme = 'cricos' and r.status = 'active' and s.url is not null and (r.valid_to is null or r.valid_to > current_date)
                         and exists (select 1 from search.course_documents d where d.course_id = p_course_id))
        order by r.status, r.scheme, r.registration_code)
      from catalogue.course_registrations r
      left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
      left join pipeline.evidence_artifacts e on e.id = r.evidence_id
     where r.course_id = p_course_id), '[]'::jsonb));
end $f$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_field_codes_v1', 'Platform', 'O28 ASCED field-of-study codes from CRICOS register observations, with held reason', 'active', '{}', '20261116200000'),
 ('function', 'security.course_roadmap_item_v1', 'Platform', 'v3 course item with recognition[] and field_of_study_codes[]', 'active', '{security.course_recognition_item_v1}', '20261116200000'),
 ('function', 'security.course_field_codes_delivery_v1', 'Platform', 'Data Delivery: ASCED field-code coverage', 'active', '{}', '20261116200000')
on conflict do nothing;
update pipeline.component_register set status = 'retiring', updated_at = now(), replaced_by = 'security.course_roadmap_item_v1',
       retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       note = 'Retired by migration 20261116200000: one item function adds recognition[] and field_of_study_codes[].'
 where kind = 'function' and name = 'security.course_recognition_item_v1';
