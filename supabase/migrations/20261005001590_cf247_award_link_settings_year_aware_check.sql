-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 19:18, follow-up after the first run across all universities).
-- The register (CRICOS) is a fee year behind the universities' current fees: La Trobe's 2027 fees sit 2.7% to 4.7%
-- above the 2026 register, so genuine award links failed a 2% check. The register check now allows for that lag:
--   same fee year: the award's registered fee per year within the same-year tolerance of the parent's current fee,
--   parent fee year after the register year (or register against register, where a two-year total blends two fee
--   years): the award may sit below the parent by up to the lagged tolerance, and above by the same-year tolerance.
-- The tolerances are settings (pipeline.award_link_settings), changed from Coverage › Universities, not fixed here.
-- A link set by hand is a Platform Admin's decision: it is applied whatever the check says (the check is shown).
-- No text value in this file contains a semicolon.

create table if not exists pipeline.award_link_settings (
  id int primary key default 1 check (id = 1),
  same_year_tolerance numeric(5,4) not null default 0.02 check (same_year_tolerance between 0 and 0.5),
  lagged_tolerance numeric(5,4) not null default 0.06 check (lagged_tolerance between 0 and 0.5),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  reason text
);
alter table pipeline.award_link_settings enable row level security;
revoke all on table pipeline.award_link_settings from anon, authenticated;
insert into pipeline.award_link_settings(id, reason) values (1, 'Decision 254 defaults (5 Oct 2026 19:18)') on conflict (id) do nothing;

create or replace function security.award_register_check(p_child uuid, p_parent uuid) returns text[]
language sql stable security definer set search_path = '' as $f$
  with st as (select same_year_tolerance sy, lagged_tolerance lg from pipeline.award_link_settings where id = 1),
       c as (select f.amount / nullif(co.duration_value, 0) * 52 py, f.amount a, co.duration_value w, extract(year from coalesce(f.source_snapshot_at::date, f.valid_from))::int ry from catalogue.courses co
               left join catalogue.course_fees f on f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
              where co.id = p_child and co.duration_unit = 'weeks' order by f.valid_from desc nulls last limit 1),
       p as (select f.amount / nullif(co.duration_value, 0) * 52 py, f.amount a, co.duration_value w from catalogue.courses co
               left join catalogue.course_fees f on f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and f.status = 'active' and f.audience in ('international', 'all') and f.amount > 0
              where co.id = p_parent and co.duration_unit = 'weeks' order by f.valid_from desc nulls last limit 1),
       a as (select f.amount an, f.fee_year fy from catalogue.course_fees f where f.course_id = p_parent and f.fee_type = 'provider_current_tuition' and f.status = 'active' and f.audience = 'international' and f.amount > 0 order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
       d as (select c.py, c.a, c.w, c.ry, p.py ppy, p.a pa, p.w pw, a.an, a.fy, st.sy, st.lg,
                    case when a.an is not null then c.py / a.an - 1 when p.py is not null then c.py / p.py - 1 end diff,
                    case when a.an is not null and (a.fy is null or c.ry is null or a.fy <= c.ry) then st.sy else st.lg end below_ok
               from (select 1) one left join c on true left join p on true left join a on true cross join st)
  select case when security.is_double_degree_title((select canonical_title from catalogue.courses where id = p_parent)) then array['fail', 'parent is a double degree']
              when d.py is null then array['none', 'the award has no registered total']
              when d.an is null and d.ppy is null then array['none', 'the parent has no current fee and no registered total']
              when d.diff >= -d.below_ok and d.diff <= d.sy then
                   array['pass', 'register ' || round(d.a) || ' over ' || d.w || ' weeks = ' || round(d.py) || ' a year, ' || round(d.diff * 100, 1) || '% against ' || case when d.an is not null then 'the parent fee ' || round(d.an) || ' (' || d.fy || ')' else 'the parent register ' || round(d.pa) || ' over ' || d.pw || ' weeks' end || ' (allowed -' || round(d.below_ok * 100, 1) || '% to +' || round(d.sy * 100, 1) || '%)']
              else array['fail', 'register ' || round(d.a) || ' over ' || d.w || ' weeks = ' || round(d.py) || ' a year is ' || round(d.diff * 100, 1) || '% off ' || case when d.an is not null then 'the parent fee ' || round(d.an) || ' (' || d.fy || ')' else 'the parent register ' || round(d.pa) || ' over ' || d.pw || ' weeks' end || ' (allowed -' || round(d.below_ok * 100, 1) || '% to +' || round(d.sy * 100, 1) || '%)'] end
    from d
$f$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.exit_awards_apply_v2(uuid)'::regprocedure) is distinct from 'b7bbbaf995aa59b844b5cc3a67934b5c' then
    raise exception 'exit_awards_apply_v2 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.exit_awards_apply_v2(uuid)'::regprocedure);
  v_pairs := array[
    array[$s$if r.register_check = 'fail' then v_skipped := v_skipped + 1; continue; end if;$s$,
          $s$if r.register_check = 'fail' and r.set_by <> 'hand' then v_skipped := v_skipped + 1; continue; end if;$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_exit_awards(text,jsonb)'::regprocedure) is distinct from 'c283d0e4caba6beab84ab1336c585983' then
    raise exception 'admin_exit_awards changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_exit_awards(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$  if p_action = 'read' then
    return coalesce((select jsonb_agg($s$,
          $s$  if p_action = 'read' and p_args->>'scope' = 'settings' then
    return (select to_jsonb(s) - 'id' from pipeline.award_link_settings s where s.id = 1);
  end if;
  if p_action = 'read' then
    return coalesce((select jsonb_agg($s$],
    array[$s$  elsif p_action in ('off', 'on') then$s$,
          $s$  elsif p_action = 'settings' then
    update pipeline.award_link_settings set same_year_tolerance = coalesce((p_args->>'same_year_tolerance')::numeric, same_year_tolerance), lagged_tolerance = coalesce((p_args->>'lagged_tolerance')::numeric, lagged_tolerance), updated_by = auth.uid(), updated_at = now(), reason = v_reason where id = 1;
    update pipeline.course_exit_awards x set register_check = (security.award_register_check(x.child_course_id, x.parent_course_id))[1], check_detail = (security.award_register_check(x.child_course_id, x.parent_course_id))[2] where x.active;
    update pipeline.course_host_pages h set register_check = (security.award_register_check(h.course_id, h.host_course_id))[1], check_detail = (security.award_register_check(h.course_id, h.host_course_id))[2] where h.active and h.link_type = 'shared_page';
    v_res := jsonb_build_object('ok', true, 'links', (select count(*) from pipeline.course_exit_awards where active), 'passing', (select count(*) from pipeline.course_exit_awards where active and register_check = 'pass'));
  elsif p_action in ('off', 'on') then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

-- Every link checked again under the new rule
update pipeline.course_exit_awards x set register_check = (security.award_register_check(x.child_course_id, x.parent_course_id))[1], check_detail = (security.award_register_check(x.child_course_id, x.parent_course_id))[2] where x.active;
update pipeline.course_host_pages h set register_check = (security.award_register_check(h.course_id, h.host_course_id))[1], check_detail = (security.award_register_check(h.course_id, h.host_course_id))[2] where h.active and h.link_type = 'shared_page';
