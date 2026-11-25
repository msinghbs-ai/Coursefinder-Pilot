-- CF-247 s1160 (S1-RM-Design; Global Autonomous PIM, Master Plan section 6.3 step 1, interface 1; design approved Platform Admin 25 Nov 2026 18:42 AEDT, Admin PR #1097).
-- Applicability: whether a field applies to an entity is held once, in pipeline.field_register, and read through one function.
--   1. pipeline.field_register gains entity_grain (course, provider; the other grains of section 6.2 are allowed for later steps), applicability_rule
--      ('always' or 'countries') with applicability_param (the countries, from the register, not from code), and absence_field (the name the field
--      has in pipeline.course_field_absence, which is not always the register's name).
--   2. security.field_applicable_v1(field, entity) returns {applicable, reason, grain, rule}. Order: the field must be registered and active; an
--      evidence-backed open 'not_applicable' row in pipeline.course_field_absence makes a course field not applicable; then the register's rule.
-- Only registered_tuition carries a rule: the CRICOS register covers Australia only (its own register line says so). Every other field always applies.
-- Nothing is read or written by a scheduled job here; the gap scan and the planner use this function in the next slices. G1: no new job. G2: the rule
-- and its countries are data in the register. G3: no consumer API object is touched (checked before and after). Locks and cron unchanged.
-- Replaces: none. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: backfill of 24 rows and the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1160_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1160_cron on commit drop as select count(*) n from cron.job where active;

alter table pipeline.field_register
  add column if not exists entity_grain text,
  add column if not exists applicability_rule text not null default 'always',
  add column if not exists applicability_param jsonb not null default '{}'::jsonb,
  add column if not exists absence_field text;

update pipeline.field_register
   set entity_grain = case level when 'provider' then 'provider' else 'course' end
 where entity_grain is null;
update pipeline.field_register set absence_field = case field when 'academic_entry' then 'entry_requirements' else field end where absence_field is null;
update pipeline.field_register
   set applicability_rule = 'countries', applicability_param = jsonb_build_object('countries', jsonb_build_array('AU'))
 where field = 'registered_tuition' and applicability_rule = 'always';

alter table pipeline.field_register alter column entity_grain set not null;
alter table pipeline.field_register alter column absence_field set not null;
alter table pipeline.field_register add constraint field_register_grain_chk
  check (entity_grain in ('course', 'provider', 'course_country', 'course_test', 'award_course', 'provider_edition', 'country_edition'));
alter table pipeline.field_register add constraint field_register_rule_chk check (applicability_rule in ('always', 'countries'));

comment on column pipeline.field_register.entity_grain is 'Interface 1 (PIM step 1): what one value belongs to: course, provider, or a later grain (course_country, course_test, award_course, provider_edition, country_edition).';
comment on column pipeline.field_register.applicability_rule is 'Interface 1: always, or countries (applies only where applicability_param.countries lists the provider''s country code). Read through security.field_applicable_v1.';
comment on column pipeline.field_register.applicability_param is 'Interface 1: the rule''s data, for example {"countries":["AU"]}. Edited with a reason like the rest of the register, never in code (G2).';
comment on column pipeline.field_register.absence_field is 'The field''s name in pipeline.course_field_absence (academic_entry is entry_requirements there).';

create or replace function security.field_applicable_v1(p_field text, p_entity uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare r pipeline.field_register%rowtype; v_country text;
begin
  select * into r from pipeline.field_register where field = p_field;
  if r.field is null or not r.active then
    return jsonb_build_object('applicable', false, 'reason', 'field_not_registered', 'grain', null, 'rule', null);
  end if;
  if r.entity_grain = 'course' and exists (
       select 1 from pipeline.course_field_absence a
        where a.course_id = p_entity and a.field = r.absence_field and a.absence_class = 'not_applicable' and a.resolved_at is null) then
    return jsonb_build_object('applicable', false, 'reason', 'recorded_not_applicable', 'grain', r.entity_grain, 'rule', r.applicability_rule);
  end if;
  if r.applicability_rule = 'countries' then
    select k.iso_alpha2 into v_country
      from catalogue.providers p join ref.countries k on k.id = p.country_id
     where p.id = case r.entity_grain when 'course' then (select c.provider_id from catalogue.courses c where c.id = p_entity) else p_entity end;
    if v_country is null or not (r.applicability_param->'countries') ? v_country then
      return jsonb_build_object('applicable', false, 'reason', 'country_not_covered', 'grain', r.entity_grain, 'rule', r.applicability_rule, 'country', v_country);
    end if;
  end if;
  return jsonb_build_object('applicable', true, 'reason', 'applies', 'grain', r.entity_grain, 'rule', r.applicability_rule);
end $f$;
comment on function security.field_applicable_v1(text, uuid) is 'PIM interface 1 (s1160): does this registered field apply to this course or provider? One read for the gap scan, the planner and the delivery read.';
revoke all on function security.field_applicable_v1(text, uuid) from public, anon, authenticated;
grant execute on function security.field_applicable_v1(text, uuid) to service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); a int; b int; n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1160_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1160_cron) then raise exception 'guard: active cron jobs changed'; end if;
  select count(*) into n from pipeline.field_register where entity_grain is null or absence_field is null;
  if n <> 0 then raise exception 'guard: % register rows without grain or absence field', n; end if;
  -- the rule: an Australian course applies, a New Zealand course does not
  select count(*) filter (where (security.field_applicable_v1('registered_tuition', c.id)->>'applicable')::boolean),
         count(*) filter (where not (security.field_applicable_v1('registered_tuition', c.id)->>'applicable')::boolean)
    into a, b
    from (select c2.id from catalogue.courses c2 join catalogue.providers p on p.id = c2.provider_id join ref.countries k on k.id = p.country_id
           where c2.lifecycle_status = 'active' and k.iso_alpha2 = 'AU' limit 50) c;  -- fixed: a sample for the rehearsal
  if a <> 50 or b <> 0 then raise exception 'guard: AU sample applicable %, not applicable %', a, b; end if;
  select count(*) into n from (select c2.id from catalogue.courses c2 join catalogue.providers p on p.id = c2.provider_id join ref.countries k on k.id = p.country_id
           where c2.lifecycle_status = 'active' and k.iso_alpha2 = 'NZ' limit 50) c  -- fixed: a sample for the rehearsal
   where (security.field_applicable_v1('registered_tuition', c.id)->>'applicable')::boolean;
  if n <> 0 then raise exception 'guard: % NZ courses wrongly applicable', n; end if;
end $c$;
