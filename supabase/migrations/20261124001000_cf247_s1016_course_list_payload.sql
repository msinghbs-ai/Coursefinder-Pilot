-- CF-247 s1016 (S1-Build; Platform Admin 24 Nov 2026 00:30 AEDT, Deployed UAT recovery): the Course list page carries what the list shows.
-- The deployed performance check measured 412,855 bytes for one 50-row Courses page against its 250,000-byte budget; under the suite's parallel
-- load the page took 3.3 to 4.8 s, which also made cf-061 miss its wait. Measured live (rolled back): last_admitted was 168,857 bytes of it
-- (whole before and after values, up to 13,409 characters, for an admission tooltip that shows 160 characters) and field_states 69,336 bytes
-- (every field state, while the default columns read none of them).
-- 1. security.course_list_trim_v1(p_args, p_page) (new): last_admitted.before and .after are sent as the 160-character preview the tooltip
--    shows; when the caller names field_states_keys, only those field states are sent. A caller that names none receives every field state.
-- 2. security.admin_course_page_fast (live md5 8308868b, s977; md5-guarded): its three returns pass the page through it. Nothing else changes.
-- Measured (rolled back, live): 412,855 -> 256,105 bytes with the preview alone (live on deploy); 186,869 bytes when the screen names the
-- field states its default columns read (none); 230,374 bytes with every field-state column shown. Same course ids in the same order; field
-- states unchanged when no keys are named; RMIT 113126B still row 22 of its search.
-- The Courses screen names its keys in a separate front-end change (S1-API-Frontend-Delivery, recorded in the master plan section 5).
-- Callers: security.admin_course_page_fast only (admin; read live). G1: no job. G2: no operational value (160 is the tooltip's own length).
-- G3: no consumer object changed (checked before and after). Manual locks and active cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: the whole before and after values on Course list rows (a 160-character preview instead).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the function change

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure), chr(13), '')) <> '8308868bb7211775018e0136e87241fc' then
    raise exception 'guard: live security.admin_course_page_fast differs from the definition this change edits';
  end if;
end $g$;
create temp table s1016_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1016_cron on commit drop as select count(*) n from cron.job where active;

CREATE OR REPLACE FUNCTION security.course_list_trim_v1(p_args jsonb, p_page jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- s1016 (S1-Build, Platform Admin 24 Nov 2026 00:30): the Course list page carries what the list shows.
  -- last_admitted.before and .after: the list shows them only as a 160-character preview in the admission tooltip, so the preview is sent
  -- (a text value as its text, any other value as its JSON text), not the whole value. field_states: when the screen names the field state keys
  -- its columns read (field_states_keys), only those are sent; a caller that names none receives every field state, as before.
  select case when jsonb_typeof(p_page -> 'items') is distinct from 'array' then p_page else
    jsonb_set(p_page, '{items}', coalesce((
      select jsonb_agg(
        case when jsonb_typeof(p_args -> 'field_states_keys') = 'array' and jsonb_typeof(y -> 'field_states') = 'object'
             then y || jsonb_build_object('field_states', coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(y -> 'field_states') e
                                                                    where e.key in (select jsonb_array_elements_text(p_args -> 'field_states_keys'))), '{}'::jsonb))
             else y end
        order by o)
      from (
        select o, case when jsonb_typeof(x -> 'last_admitted') = 'object'
                 then x || jsonb_build_object('last_admitted', (x -> 'last_admitted')
                        || jsonb_build_object('before', case when x #> '{last_admitted,before}' is null or jsonb_typeof(x #> '{last_admitted,before}') = 'null' then x #> '{last_admitted,before}'
                                                              when jsonb_typeof(x #> '{last_admitted,before}') = 'string' then to_jsonb(left(x #>> '{last_admitted,before}', 160))
                                                              else to_jsonb(left((x #> '{last_admitted,before}')::text, 160)) end,
                                              'after', case when x #> '{last_admitted,after}' is null or jsonb_typeof(x #> '{last_admitted,after}') = 'null' then x #> '{last_admitted,after}'
                                                             when jsonb_typeof(x #> '{last_admitted,after}') = 'string' then to_jsonb(left(x #>> '{last_admitted,after}', 160))
                                                             else to_jsonb(left((x #> '{last_admitted,after}')::text, 160)) end))
                 else x end y
          from jsonb_array_elements(p_page -> 'items') with ordinality a(x, o)) z), '[]'::jsonb))
  end
$function$;

revoke all on function security.course_list_trim_v1(jsonb, jsonb) from public, anon, authenticated;
comment on function security.course_list_trim_v1(jsonb, jsonb) is 'CF-247 s1016: Course list page as the list shows it (admission preview; named field states only).';

do $f$
declare d text := pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure);
  v_from text[] := array[$blk$return security.course_list_with_extras_v1(security.admin_course_page_unfiltered_fast(p_args));$blk$, $blk$return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text)));$blk$, $blk$return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args));$blk$];
  v_to text[] := array[$blk$return security.course_list_trim_v1(p_args, security.course_list_with_extras_v1(security.admin_course_page_unfiltered_fast(p_args)));$blk$, $blk$return security.course_list_trim_v1(p_args, security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text))));$blk$, $blk$return security.course_list_trim_v1(p_args, security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args)));$blk$];
begin
  for i in 1 .. 3 loop
    if (length(d) - length(replace(d, v_from[i], ''))) / length(v_from[i]) <> 1 then raise exception 'guard: return % is not found exactly once', i; end if;
    d := replace(d, v_from[i], v_to[i]);
  end loop;
  execute d;
end $f$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1016_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1016_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure), chr(13), '')) <> 'cd2d1610e25ca4fca3cefc33f77b4dc3' then
    raise exception 'post-check: security.admin_course_page_fast is not the rehearsed definition';
  end if;
end $post$;
