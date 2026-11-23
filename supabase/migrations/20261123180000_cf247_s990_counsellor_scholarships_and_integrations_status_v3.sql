-- CF-247 s990 (S1-API-Frontend-Delivery; Platform Admin 23 Nov 2026: Phase 1 of the v1.1 Counsellor and Admin UI replacement).
-- Two additive reads for the new screens (MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 section 2, rows 4 and 9b):
-- 1. public.counsellor_scholarships_list: the published scholarships for Counsellors (rank 2 and above), one paged read. The status
--    (Open / Closed / Opens <date> / Dates not published) is worked out in the database on the Australia/Melbourne date, so the screen
--    never decides it from the browser clock.
-- 2. public.admin_integrations_status: one row per integration with { status: healthy | degraded | unknown, last_checked_at }. A check that
--    cannot be read, or is older than the setting integrations.status_fresh_hours (48), returns unknown; it never raises a 403 or 500 to a screen. Website API reads the latest deploy check; Zoho Creator has no
--    check today and is reported unknown with a null date (the screen shows the date, so an old check is visible as old).
-- G1: no job. G2: page size is a setting (scholarships.counsellor_page_rows). G3: reads only; no consumer object is touched (75/48 before and
-- after). Manual locks untouched. Nothing dropped or removed. The pipeline.settings budget-cap key for the Dry-Lane banner belongs to S2-Build
-- (Platform Admin 23 Nov 2026) and is not part of this change.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new functions and the setting row

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s990_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- setting (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'scholarships.counsellor_page_rows', 'Counsellor scholarships: rows a page',
        'How many published scholarships one page of the Counsellor Scholarships screen returns. Further pages are fetched with the offset.',
        'number', to_jsonb(50), 10, 200, 'scholarships', 3320, 'Scholarships',
        'public.counsellor_scholarships_list', 'CF-247 s990 (Platform Admin 23 Nov 2026): Counsellor Scholarships screen')
on conflict do nothing;
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'integrations.status_fresh_hours', 'Integrations status: newest check still shown as current',
        'An integration check older than this many hours is shown as unknown, never as healthy, so the Admin screen cannot display a stale green badge. The check date is always shown beside the badge.',
        'number', to_jsonb(48), 1, 720, 'hours', 3321, 'Platform health',
        'public.admin_integrations_status', 'CF-247 s990 (Platform Admin 23 Nov 2026 17:35): stale checks must not show healthy')
on conflict do nothing;

create or replace function public.counsellor_scholarships_list(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb);
        v_page int := greatest(1, security.pipeline_num_v1('scholarships.counsellor_page_rows', 50)::int);
        v_off int := greatest(0, coalesce(nullif(a->>'offset', '')::int, 0));
        v_q text := nullif(btrim(a->>'q'), '');
        v_provider uuid := nullif(a->>'provider_id', '')::uuid;
        v_status text := nullif(a->>'status', '');
        v_today date := (now() at time zone 'Australia/Melbourne')::date; -- fixed: Melbourne is the platform's date for deadlines
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed for Scholarships' using errcode = '42501'; end if; -- fixed: who opens Scholarships
  if v_status is not null and v_status not in ('Open', 'Closed', 'Opens', 'Dates not published') then raise exception 'status is Open, Closed, Opens or Dates not published' using errcode = '22023'; end if;
  return (
    with s as (
      select x.id, x.name, x.provider_id, x.scholarship_type, x.audience, x.award_value_text, x.application_required, x.application_open_date,
             x.application_close_date, x.source_url, x.nationalities,
             coalesce(p.display_name, p.canonical_name) provider_name,
             case when x.application_open_date is null and x.application_close_date is null then 'Dates not published'
                  when x.application_open_date > v_today then 'Opens'
                  when x.application_close_date < v_today then 'Closed'
                  else 'Open' end status_key
        from scholarship.scholarships x
        left join catalogue.providers p on p.id = x.provider_id
       where x.publication_status = 'published' and x.lifecycle_status = 'active'
         and (v_provider is null or x.provider_id = v_provider)
         and (v_q is null or x.name ilike '%' || v_q || '%' or coalesce(p.display_name, p.canonical_name) ilike '%' || v_q || '%')),
    f as (select * from s where v_status is null or s.status_key = v_status),
    pg as (select * from f order by f.provider_name nulls last, f.name, f.id limit v_page offset v_off)
    select jsonb_build_object(
      'total', (select count(*) from f), 'page_rows', v_page, 'offset', v_off, 'today', v_today,
      'status_counts', (select coalesce(jsonb_object_agg(c.status_key, c.n), '{}'::jsonb) from (select s.status_key, count(*) n from s group by 1) c),
      'rows', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', pg.id, 'name', pg.name, 'provider_id', pg.provider_id, 'provider_name', pg.provider_name, 'type', pg.scholarship_type,
                 'audience', pg.audience, 'value_text', pg.award_value_text, 'application_required', pg.application_required,
                 'open_date', pg.application_open_date, 'close_date', pg.application_close_date, 'source_url', pg.source_url,
                 'nationalities', to_jsonb(pg.nationalities), 'status_key', pg.status_key,
                 'status', case pg.status_key when 'Opens' then 'Opens ' || to_char(pg.application_open_date, 'DD Mon YYYY') else pg.status_key end)
               order by pg.provider_name nulls last, pg.name, pg.id), '[]'::jsonb) from pg)));
end $function$;

create or replace function public.admin_integrations_status()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_ok boolean; v_at timestamptz; v_web text := 'unknown';
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  begin
    select d.ok, coalesce(d.operational_checked_at, d.checked_at) into v_ok, v_at
      from pipeline.integration_deploy_checks d order by d.checked_at desc limit 1;
    v_web := case when v_at is null or v_at < now() - make_interval(hours => security.pipeline_num_v1('integrations.status_fresh_hours', 48)::int) then 'unknown'
                  when v_ok is true then 'healthy' when v_ok is false then 'degraded' else 'unknown' end;
  exception when others then
    v_web := 'unknown'; v_at := null; -- fixed: a failed check is reported as unknown, never raised to the screen
  end;
  return jsonb_build_object('integrations', jsonb_build_array(
    jsonb_build_object('key', 'website_api', 'label', 'Website API', 'status', v_web, 'last_checked_at', v_at),
    jsonb_build_object('key', 'zoho_creator', 'label', 'Zoho Creator', 'status', 'unknown', 'last_checked_at', null)));
end $function$;

revoke all on function public.counsellor_scholarships_list(jsonb) from public, anon;
grant execute on function public.counsellor_scholarships_list(jsonb) to authenticated, service_role;
revoke all on function public.admin_integrations_status() from public, anon;
grant execute on function public.admin_integrations_status() to authenticated, service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API drifted: %', v;
  end if;
  select count(*) into n from pipeline.manual_locks;
  if n <> (select s.n from s990_locks s) then raise exception 'guard: manual locks changed'; end if;
end $c$;
