-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 11:48). Delivery is collected as an attribute of the international view.
-- "The course had the filter for international student which reflects the Delivery (100% Online) and Fees ... Delivery is
-- also an important attribute." A university adapter's delivery reading (the mode field, from the international view of the
-- course page) can now be admitted as its own field, 'delivery', into catalogue.courses.delivery_mode:
--   online                 only online or distance (for example "100% online")
--   on_campus              only on campus, face to face or in person
--   on_campus_and_online   both offered
--   blended                blended, mixed mode, multi-modal or hybrid
-- Study load words (full-time, part-time) and research give no value. Domestic-only online options printed next to an
-- international on-campus offer ("Online - No", "Online available only for non-international student visa holders") are
-- ignored. A value entered by hand (manual lock delivery_mode) is never changed. Admission is a deliberate switch per
-- university and field, as for intakes, English and fee. A course and its delivery can be excluded like any other field.
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon:
-- where a replacement needs a statement break it is written {sc} and turned into a semicolon with chr(59).

create table if not exists pipeline.uni_adapter_delivery_exclusions (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null,
  active boolean not null default true,
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now()
);
alter table pipeline.uni_adapter_delivery_exclusions enable row level security;
revoke all on table pipeline.uni_adapter_delivery_exclusions from anon, authenticated;

create or replace function security.delivery_mode_from_text(p_text text) returns text
language sql immutable set search_path = '' as $f$
  with a as (select regexp_replace(lower(coalesce(p_text, '')), '(online\s*-\s*no\M|online[^.]{0,40}only for non-international[^.]{0,120}|not offered online)', ' ', 'g') s),
       b as (select regexp_replace(s, 'off[ -]campus', ' distance ', 'g') s from a),
       c as (select s ~ '(100% online|\monline\M|\mdistance\M)' o, s ~ '(on[ -]?campus|face[ -]to[ -]face|in[ -]person|\mcampus\M)' k, s ~ '(blended|mixed mode|multi[ -]?modal|hybrid)' m from b)
  select case when o and k then 'on_campus_and_online'
              when m then 'blended'
              when o then 'online'
              when k then 'on_campus'
              else null end
  from c
$f$;
revoke all on function security.delivery_mode_from_text(text) from public, anon, authenticated;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_excluded(uuid,text)'::regprocedure) is distinct from '1f51b515228e69890b873c7878d3575f' then
    raise exception 'uni_adapter_excluded changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_excluded(p_course_id uuid, p_field text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select case when p_field = 'delivery'
              then exists (select 1 from pipeline.uni_adapter_delivery_exclusions d where d.course_id = p_course_id and d.active)
              else exists (select 1 from pipeline.uni_adapter_exclusions x where x.course_id = p_course_id and x.field = p_field and x.active) end
$f$;

create or replace function security.university_course_delivery_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('value', c.delivery_mode,
           'read', pg.candidates->'adapter_extra'->>'mode',
           'source', case when nullif(c.delivery_mode, '') is null then 'missing'
                          when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('delivery_mode', 'delivery')) then 'hand'
                          when exists (select 1 from pipeline.adapter_overwrite_changes x where x.course_id = c.id and x.field = 'delivery' and x.after = to_jsonb(c.delivery_mode)) then 'adapter'
                          else 'other' end,
           'excluded', security.uni_adapter_excluded(c.id, 'delivery'))
  from catalogue.courses c left join pipeline.coverage_course_pages pg on pg.course_id = c.id
  where c.id = p_course_id
$f$;
revoke all on function security.university_course_delivery_v1(uuid) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_control(text,jsonb)'::regprocedure) is distinct from '2a67d9ad16f2c102769252b851ebe7ac' then
    raise exception 'admin_uni_adapter_control changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_control(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$jsonb_array_elements_text(p_args->'fields') f where f not in ('intakes', 'english', 'fee')$s$,
          $s$jsonb_array_elements_text(p_args->'fields') f where f not in ('intakes', 'english', 'fee', 'delivery')$s$],
    array[$s$'fields must be a list of intakes, english and fee'$s$,
          $s$'fields must be a list of intakes, english, fee and delivery'$s$],
    array[$s$if coalesce(v_field, '') not in ('intakes', 'english', 'fee') then raise exception 'field must be intakes, english or fee'$s$,
          $s$if coalesce(v_field, '') not in ('intakes', 'english', 'fee', 'delivery') then raise exception 'field must be intakes, english, fee or delivery'$s$],
    array[$s$select x, v_field, v_pid, v_on, v_reason, auth.uid(), now() from unnest(v_courses) x$s$,
          $s$select x, v_field, v_pid, v_on, v_reason, auth.uid(), now() from unnest(v_courses) x where v_field <> 'delivery'$s$],
    array[$s$if v_on and v_field = 'fee' then$s$,
          $s$insert into pipeline.uni_adapter_delivery_exclusions(course_id, provider_id, active, reason, set_by, set_at) select x, v_pid, v_on, v_reason, auth.uid(), now() from unnest(v_courses) x where v_field = 'delivery' on conflict (course_id) do update set active = excluded.active, reason = excluded.reason, set_by = excluded.set_by, set_at = now() where pipeline.uni_adapter_delivery_exclusions.course_id = excluded.course_id{sc}
    if v_on and v_field = 'fee' then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure) is distinct from 'b0bb638575bff44987fd9888fba8c8de' then
    raise exception 'adapter_overwrite_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.adapter_overwrite_v1(integer)'::regprocedure);
  v_pairs := array[
    array[$s$v_fy int{sc} v_cur text$s$,
          $s$v_fy int{sc} v_cur text{sc} v_mode_n int := 0$s$],
    array[$s$pg.identity_basis ib, u.admit_fields af,$s$,
          $s$pg.identity_basis ib, u.admit_fields af, co.delivery_mode cur_mode, security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode') new_mode,$s$],
    array[$s$or pg.candidates->>'fee_by' = 'adapter')$s$,
          $s$or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode')$s$],
    array[$s$continue when v_payload = '{}'::jsonb$s$,
          $s$-- 5 Oct (Platform Admin 11:48): delivery read from the international view of the course page
    if r.new_mode is not null and r.cur_mode is distinct from r.new_mode and 'delivery' = any (r.af) and not security.uni_adapter_excluded(r.course_id, 'delivery')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('delivery_mode', 'delivery')) then
      begin
        update catalogue.courses set delivery_mode = r.new_mode, updated_at = now() where id = r.course_id{sc}
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'delivery', to_jsonb(r.cur_mode), to_jsonb(r.new_mode), r.evidence_id, r.url){sc}
        v_mode_n := v_mode_n + 1{sc} v_courses := v_courses || r.course_id{sc}
      exception when others then v_err := v_err + 1{sc} v_last := left(sqlerrm, 200){sc}
      end{sc}
    end if{sc}
    continue when v_payload = '{}'::jsonb$s$],
    array[$s$return jsonb_build_object('replaced', v_ok,$s$,
          $s$return jsonb_build_object('delivery', v_mode_n, 'replaced', v_ok,$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_university_courses_read(uuid,jsonb)'::regprocedure) is distinct from '3e903e9b0a2f143135a78d4a70524e80' then
    raise exception 'admin_university_courses_read changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_university_courses_read(uuid,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$'excluded', y.fee_x)) order by y.course$s$,
          $s$'excluded', y.fee_x), 'delivery', security.university_course_delivery_v1(y.course_id)) order by y.course$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
