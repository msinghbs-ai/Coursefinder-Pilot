-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 15:22 La Trobe, 15:34 RMIT).
-- 1. Exit awards. A course page lists the awards a student can exit with ("After completing 1 year of full-time study,
--    You can exit with a Diploma of Biological Sciences", "2 years ... an Associate Degree in Biological Sciences").
--    Those awards are catalogue courses of their own with no page of their own. An adapter reads the list (pattern
--    exit_awards, worker v0.17.7). Each listed award that is a catalogue course of the same university becomes an exit
--    award of the course (pipeline.course_exit_awards) with its years of full-time study. When the university admits
--    'exit_awards', the award takes from its course, with the course page as evidence:
--      the course page as its official page, the international annual fee (the same per-year fee, its year), the start
--      months and the delivery. The whole fee for the award (annual fee x years) is kept with the award and in the fee
--      notes. Values entered by hand and excluded fields are never changed. It runs every hour after admission.
-- 2. Annual fee from a whole-course fee. Where a page prints only a whole-course fee and the full-time years (RMIT
--    "AU$49,500 (2027 total indicative)", "Full-time 2 years"), the adapter reads them (patterns fee_total and
--    course_years) and the worker gives the annual fee as total / years. New pattern fields are allowed here.
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon.

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_pattern_fields()'::regprocedure) is distinct from '24e995c907107b8d040756b28e672e5a' then
    raise exception 'uni_adapter_pattern_fields changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_pattern_fields() returns text[]
language sql immutable set search_path = '' as $f$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level', 'location', 'fee_total', 'course_years', 'exit_awards']
$f$;

create table if not exists pipeline.course_exit_awards (
  child_course_id uuid primary key references catalogue.courses(id),
  parent_course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  exit_years numeric(4,1) not null check (exit_years > 0 and exit_years <= 8),
  page_url text not null,
  evidence_id uuid,
  printed text,
  active boolean not null default true,
  set_by text not null default 'adapter',
  reason text,
  set_at timestamptz not null default now(),
  applied_at timestamptz,
  annual_fee numeric(12,2),
  fee_year int,
  total_fee numeric(12,2),
  check (child_course_id <> parent_course_id)
);
alter table pipeline.course_exit_awards enable row level security;
revoke all on table pipeline.course_exit_awards from anon, authenticated;

create or replace function security.course_title_key(p text) returns text
language sql immutable set search_path = '' as $f$
  select btrim(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[^a-z0-9]+', ' ', 'g'))
$f$;

create or replace function security.exit_awards_detect_v1(p_provider_id uuid) returns integer
language plpgsql security definer set search_path = '' as $f$
declare n int := 0; r record; m text[]; v_child uuid;
begin
  for r in
    select pg.course_id, pg.url, pg.evidence_id, pg.candidates->'adapter_extra'->>'exit_awards' ex, co.canonical_title
      from pipeline.coverage_course_pages pg join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
     where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null
       and coalesce(pg.candidates->'adapter_extra'->>'exit_awards', '') <> ''
  loop
    for m in select regexp_matches(r.ex, '([0-9](?:\.[0-9])?)\s+years?\s+of\s+full[ -]time\s+study[^|]{0,60}exit\s+with\s+(?:an?\s+)?([A-Z][^|.\n]{4,150})', 'gi') loop
      select co.id into v_child from catalogue.courses co
       where co.provider_id = p_provider_id and co.lifecycle_status = 'active' and co.id <> r.course_id
         and security.course_title_key(co.canonical_title) = security.course_title_key(btrim(m[2]))
       order by co.id limit 1;
      continue when v_child is null or security.course_title_key(m[2]) = security.course_title_key(r.canonical_title);
      insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, reason)
        values (v_child, r.course_id, p_provider_id, m[1]::numeric, r.url, r.evidence_id, left(m[1] || ' years: ' || btrim(m[2]), 300), 'read from the course page by the adapter')
      on conflict (child_course_id) do update set parent_course_id = excluded.parent_course_id, exit_years = excluded.exit_years, page_url = excluded.page_url, evidence_id = excluded.evidence_id, printed = excluded.printed, set_at = now() where pipeline.course_exit_awards.set_by = 'adapter';
      n := n + 1;
    end loop;
  end loop;
  return n;
end $f$;
revoke all on function security.exit_awards_detect_v1(uuid) from public, anon, authenticated;

create or replace function security.exit_awards_apply_v1(p_provider_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_src uuid; v_hash text; v_fee record; v_itk text[]; v_payload jsonb; v_mode text; v_done int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}';
begin
  if not exists (select 1 from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and 'exit_awards' = any (u.admit_fields)) then
    return jsonb_build_object('ok', false, 'note', 'exit awards are not admitted for this university'); end if;
  v_src := security.coverage_sweep_source(p_provider_id);
  for r in
    select x.*, pc.course_url parent_url, pc.delivery_mode parent_mode, ch.delivery_mode child_mode
      from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id join catalogue.courses ch on ch.id = x.child_course_id and ch.lifecycle_status = 'active'
     where x.provider_id = p_provider_id and x.active and x.evidence_id is not null
       and not security.layer4_entity_or_parent_blocked('course', x.child_course_id, 'operational')
  loop
    begin
      select e.content_hash into v_hash from pipeline.evidence_artifacts e where e.id = r.evidence_id;
      v_payload := jsonb_build_object('course_url', r.page_url);
      select f.amount, f.fee_year, f.currency_code into v_fee from catalogue.course_fees f
       where f.course_id = r.parent_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount > 0
       order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
      if v_fee.amount is not null and not security.uni_adapter_excluded(r.child_course_id, 'fee')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('tuition', 'fee', 'fees'))
         and (select f.amount from catalogue.course_fees f where f.course_id = r.child_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fee.fee_year, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee.amount then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.child_course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fee.fee_year, 0) and amount <> v_fee.amount;
        v_payload := v_payload || jsonb_build_object('fee_amount', v_fee.amount, 'fee_year', v_fee.fee_year, 'currency_code', v_fee.currency_code, 'fee_basis', 'annual', 'audience', 'international',
                       'fee_notes', 'Exit award after ' || r.exit_years || ' years of full-time study in the course on this page: annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')');
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'fee', null, jsonb_build_object('amount', v_fee.amount, 'year', v_fee.fee_year, 'exit_award_of', r.parent_course_id, 'years', r.exit_years, 'whole_fee', round(v_fee.amount * r.exit_years, 2)), r.evidence_id, r.page_url);
      end if;
      v_itk := (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.parent_course_id and i.status = 'active');
      if v_itk is not null and not security.uni_adapter_excluded(r.child_course_id, 'intakes')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('intakes', 'intake'))
         and (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.child_course_id and i.status = 'active') is distinct from v_itk then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.child_course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', 'exit-award:' || r.child_course_id || ':' || lower(m))) from unnest(v_itk) m));
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'intakes', null, jsonb_build_object('months', to_jsonb(v_itk), 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload);
      v_mode := r.parent_mode;
      if v_mode is not null and r.child_mode is distinct from v_mode and not security.uni_adapter_excluded(r.child_course_id, 'delivery')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('delivery_mode', 'delivery')) then
        update catalogue.courses set delivery_mode = v_mode, updated_at = now() where id = r.child_course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'delivery', to_jsonb(r.child_mode), jsonb_build_object('mode', v_mode, 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      update pipeline.course_exit_awards set applied_at = now(), annual_fee = v_fee.amount, fee_year = v_fee.fee_year, total_fee = round(v_fee.amount * r.exit_years, 2) where child_course_id = r.child_course_id;
      v_done := v_done + 1; v_courses := v_courses || r.child_course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('ok', true, 'applied', v_done, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.exit_awards_apply_v1(uuid) from public, anon, authenticated;

create or replace function security.exit_awards_hourly_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare u record; v jsonb := '[]'::jsonb;
begin
  for u in select a.provider_id from pipeline.uni_adapters a where a.enabled and a.admit and 'exit_awards' = any (a.admit_fields) loop
    v := v || jsonb_build_array(jsonb_build_object('provider_id', u.provider_id, 'found', security.exit_awards_detect_v1(u.provider_id), 'apply', security.exit_awards_apply_v1(u.provider_id)));
  end loop;
  return v;
end $f$;
revoke all on function security.exit_awards_hourly_v1() from public, anon, authenticated;
select cron.schedule('exit-awards-apply', '37 * * * *', 'select security.exit_awards_hourly_v1()');

create or replace function public.admin_exit_awards(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return coalesce((select jsonb_agg(jsonb_build_object('child_course_id', x.child_course_id, 'child', ch.canonical_title, 'parent_course_id', x.parent_course_id, 'parent', pc.canonical_title,
                     'years', x.exit_years, 'page_url', x.page_url, 'printed', x.printed, 'active', x.active, 'set_by', x.set_by, 'annual_fee', x.annual_fee, 'fee_year', x.fee_year, 'total_fee', x.total_fee, 'applied_at', x.applied_at) order by pc.canonical_title, x.exit_years)
                     from pipeline.course_exit_awards x join catalogue.courses ch on ch.id = x.child_course_id join catalogue.courses pc on pc.id = x.parent_course_id where x.provider_id = v_pid), '[]'::jsonb);
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'detect' then
    v_res := jsonb_build_object('found', security.exit_awards_detect_v1(v_pid));
  elsif p_action = 'apply' then
    v_res := security.exit_awards_apply_v1(v_pid);
  elsif p_action in ('off', 'on') then
    update pipeline.course_exit_awards set active = (p_action = 'on'), set_by = 'hand', reason = v_reason, set_at = now() where child_course_id = (p_args->>'child_course_id')::uuid;
    v_res := jsonb_build_object('ok', true);
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'exit_awards_' || p_action, coalesce(v_pid::text, p_args->>'child_course_id'), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;
revoke all on function public.admin_exit_awards(text, jsonb) from public, anon;
grant execute on function public.admin_exit_awards(text, jsonb) to authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_control(text,jsonb)'::regprocedure) is distinct from '3c749bdedf1134ef1fc9029a56d7fba6' then
    raise exception 'admin_uni_adapter_control changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_control(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$f where f not in ('intakes', 'english', 'fee', 'delivery')$s$, $s$f where f not in ('intakes', 'english', 'fee', 'delivery', 'exit_awards')$s$],
    array[$s$'fields must be a list of intakes, english, fee and delivery'$s$, $s$'fields must be a list of intakes, english, fee, delivery and exit_awards'$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
