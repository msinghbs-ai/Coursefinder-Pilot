-- CF-247 s1164 (S1-RM-Design; Global Autonomous PIM step 1, interface 2 completed; Platform Admin 25 Nov 2026 21:37: "Complete the field-state contract, including partial completeness
-- and the provider, course, award and country/edition grains.").
--   security.field_state_entity_v1(p_field, p_entity) reads one field of one entity at the grain the register names:
--     course   -> security.field_state_v1 (live, unchanged), with completeness upgraded from verified to partial when an active row behind the field has no stored evidence
--                (english, academic_entry, intakes, campus), and campus_city measured (verified when every campus of the course has a city, partial when some do);
--     provider -> the provider's own columns (address, contact, description, international, logo, type, website) and its campuses;
--     any other grain (award, country/edition) -> unmeasured with reason grain_not_registered until a field of that grain is registered. A field the register does not hold is field_not_registered.
--   Completeness is one of verified, partial, none, unmeasured. Nothing is guessed: a field with no stored measure stays unmeasured.
-- G1: no job. G2: no operational value. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: none. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the guard reads and the smoke reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regprocedure('security.field_state_v1(text,uuid)') is null or to_regprocedure('security.field_applicable_v1(text,uuid)') is null then
    raise exception 'guard: the s1160 and s1161 functions are not live';
  end if;
end $g$;
create temp table s1164_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1164_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.field_state_entity_v1(p_field text, p_entity uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare r pipeline.field_register%rowtype; s jsonb; p catalogue.providers%rowtype; v_held boolean; v_part boolean := false;
        v_total int; v_with int; v_locked boolean; v_comp text;
begin
  select * into r from pipeline.field_register where field = p_field;
  if r.field is null or not r.active then
    return jsonb_build_object('field', p_field, 'applicability', security.field_applicable_v1(p_field, p_entity), 'completeness', 'unmeasured', 'reason', 'field_not_registered',
                              'freshness', null, 'source_finding', null, 'protected_hold', false, 'processing', null);
  end if;
  if r.entity_grain = 'course' then
    s := security.field_state_v1(p_field, p_entity);
    if s is null then return null; end if;
    if p_field = 'campus_city' then
      select count(*), count(*) filter (where nullif(btrim(coalesce(k.city, '')), '') is not null) into v_total, v_with
        from catalogue.course_campuses x join catalogue.campuses k on k.id = x.campus_id where x.course_id = p_entity;
      v_comp := case when v_total = 0 then 'none' when v_with = v_total then 'verified' when v_with = 0 then 'none' else 'partial' end;
      return s || jsonb_build_object('completeness', v_comp);
    end if;
    if s->>'completeness' = 'verified' then
      v_part := case p_field
        when 'english' then exists (select 1 from catalogue.course_english_requirements e where e.course_id = p_entity and coalesce(e.status, 'active') = 'active' and e.evidence_id is null)
        when 'academic_entry' then exists (select 1 from catalogue.course_entry_requirements q where q.course_id = p_entity and q.status = 'active' and q.evidence_id is null)
        when 'intakes' then exists (select 1 from catalogue.course_intakes i where i.course_id = p_entity and i.status = 'active' and i.evidence_id is null)
        when 'campus' then exists (select 1 from catalogue.course_campuses x where x.course_id = p_entity and x.evidence_id is null)
        else false end;
      if v_part then s := s || jsonb_build_object('completeness', 'partial'); end if;
    end if;
    return s;
  elsif r.entity_grain = 'provider' then
    select * into p from catalogue.providers where id = p_entity;
    if p.id is null then return null; end if;
    v_held := case p_field
      when 'p_address' then nullif(btrim(coalesce(p.address_line1, '')), '') is not null
      when 'p_contact' then nullif(btrim(coalesce(p.phone, '')), '') is not null or nullif(btrim(coalesce(p.email, '')), '') is not null
      when 'p_description' then nullif(btrim(coalesce(p.description, '')), '') is not null
      when 'p_international' then p.enrols_international is not null
      when 'p_logo' then nullif(btrim(coalesce(p.logo_url, '')), '') is not null
      when 'p_type' then p.provider_type_id is not null
      when 'p_website' then nullif(btrim(coalesce(p.website, '')), '') is not null
      when 'p_campuses' then exists (select 1 from catalogue.campuses k where k.provider_id = p.id)
      else null end;
    select exists (select 1 from pipeline.manual_locks lk where lk.entity = 'provider' and lk.entity_id = p.id and lk.field in (p_field, 'all')) into v_locked;
    return jsonb_build_object('field', p_field, 'applicability', security.field_applicable_v1(p_field, p_entity),
      'completeness', case when v_held is null then 'unmeasured' when v_held then 'verified' else 'none' end,
      'freshness', case when v_held then jsonb_build_object('last_verified_at', p.last_verified_at, 'window_days', null) end,
      'source_finding', null, 'protected_hold', coalesce(v_locked, false), 'processing', null);
  end if;
  return jsonb_build_object('field', p_field, 'applicability', security.field_applicable_v1(p_field, p_entity), 'completeness', 'unmeasured', 'reason', 'grain_not_registered',
                            'freshness', null, 'source_finding', null, 'protected_hold', false, 'processing', null);
end $f$;
comment on function security.field_state_entity_v1(text, uuid) is 'PIM field state (s1164): applicability, completeness (verified, partial, none, unmeasured), freshness, source finding, protected hold and processing for one field of one entity at the grain the register names.';
revoke all on function security.field_state_entity_v1(text, uuid) from public, anon, authenticated;
grant execute on function security.field_state_entity_v1(text, uuid) to service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); a jsonb; b jsonb; v_n int; c1 uuid; p1 uuid;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1164_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1164_cron) then raise exception 'guard: active cron jobs changed'; end if;
  select c.id into c1 from catalogue.courses c where c.lifecycle_status = 'active' order by c.id limit 1;  -- fixed: one sample course for the rehearsal
  select p.id into p1 from catalogue.providers p where p.lifecycle_status = 'active' order by p.id limit 1;  -- fixed: one sample provider for the rehearsal
  a := security.field_state_entity_v1('intakes', c1);
  if a->>'completeness' not in ('verified', 'partial', 'none') then raise exception 'guard: course state %', a; end if;
  a := security.field_state_entity_v1('p_website', p1);
  if a->>'completeness' not in ('verified', 'none') then raise exception 'guard: provider state %', a; end if;
  a := security.field_state_entity_v1('p_scholarships', p1);
  if a->>'completeness' <> 'unmeasured' then raise exception 'guard: provider scholarships must stay unmeasured, got %', a; end if;
  a := security.field_state_entity_v1('no_such_field', p1);
  if a->>'reason' <> 'field_not_registered' then raise exception 'guard: unregistered field %', a; end if;
  select count(*) into v_n from (select c.id from catalogue.courses c where c.lifecycle_status = 'active' order by c.id limit 200) s  -- fixed: a 200-course smoke sample
   where security.field_state_entity_v1('campus_city', s.id)->>'completeness' not in ('verified', 'partial', 'none');
  if v_n <> 0 then raise exception 'guard: % campus_city states out of range', v_n; end if;
end $c$;
