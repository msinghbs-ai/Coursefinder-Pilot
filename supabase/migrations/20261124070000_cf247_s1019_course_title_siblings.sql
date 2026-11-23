-- CF-247 s1019 (S1-Build; Platform Admin 24 Nov 2026 06:45 AEDT, IR-027): same-title course siblings, no merge.
-- IR-027 named five UNSW and UQ "duplicate" course pairs that blocked the AER entry-table relink. Read live (rolled back, 24 Nov 2026):
-- each pair is two ACTIVE CRICOS registrations (for example 088869G and 110670B); across UNSW and UQ there are 203 same-title combinations,
-- their durations differ in 119, 6 carry manual locks, and they hold 1,558 fee, 228 intake and 148 entry rows. They are distinct courses,
-- so nothing is merged, retired or re-pointed.
-- pipeline.course_title_siblings_v (new, read-only): every provider's active courses that share a title, one row per group, each course with
-- its CRICOS code and register status, duration, study load, publication status and whether a manual lock is held. S1-RM-Design's relink
-- (AER v2, its own files) reads it to raise one Layer 4 card per printed label listing every sibling, for a person to apply.
-- Readers: postgres and service_role (definer functions, the relink); not exposed to anon or signed-in users.
-- G1: no job. G2: no operational value. G3: no consumer object changed (checked before and after). Manual locks and active cron jobs checked
-- unchanged. Nothing dropped, deleted or changed in catalogue.*.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1019_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1019_cron on commit drop as select count(*) n from cron.job where active;

create view pipeline.course_title_siblings_v as
select c.provider_id,
       lower(btrim(c.canonical_title)) as title_key,
       min(c.canonical_title) as title,
       count(*)::int as sibling_count,
       jsonb_agg(jsonb_build_object(
         'course_id', c.id,
         'cricos_code', c.course_code,
         'cricos_status', (select r.status from catalogue.course_registrations r where r.course_id = c.id and r.scheme = 'cricos' order by r.status limit 1),
         'duration_value', c.duration_value,
         'duration_unit', c.duration_unit,
         'study_load', c.study_load,
         'publication_status', c.publication_status,
         'locked', exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id)
       ) order by c.course_code) as siblings
  from catalogue.courses c
 where c.lifecycle_status = 'active'
   and nullif(btrim(c.canonical_title), '') is not null
 group by c.provider_id, lower(btrim(c.canonical_title))
having count(*) > 1;

comment on view pipeline.course_title_siblings_v is 'CF-247 s1019 (IR-027): active courses of one provider that share a title, with CRICOS code and status, duration, study load, publication and lock; read by the AER relink to raise one Layer 4 card per printed label. Nothing is merged.';
revoke all on pipeline.course_title_siblings_v from public, anon, authenticated;
grant select on pipeline.course_title_siblings_v to service_role;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_unsw int; v_uq int;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1019_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1019_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  select count(*) into v_unsw from pipeline.course_title_siblings_v where provider_id = '22657140-1cb0-4fa7-91df-90518ea8b35b';
  select count(*) into v_uq from pipeline.course_title_siblings_v where provider_id = 'e55396d2-869a-46ef-9d17-841c7eab1313';
  if v_unsw = 0 or v_uq = 0 then raise exception 'post-check: the UNSW and UQ sibling groups are missing (% / %)', v_unsw, v_uq; end if;
  if not exists (select 1 from pipeline.course_title_siblings_v where provider_id = 'e55396d2-869a-46ef-9d17-841c7eab1313' and title_key = 'bachelor of pharmacy (honours)') then
    raise exception 'post-check: the UQ Bachelor of Pharmacy (Honours) group (IR-027) is missing';
  end if;
  if has_table_privilege('authenticated', 'pipeline.course_title_siblings_v', 'select') or has_table_privilege('anon', 'pipeline.course_title_siblings_v', 'select') then
    raise exception 'post-check: the sibling view is readable outside the service roles';
  end if;
end $post$;
