-- CF-247 s930 (session S1-Dynamic-Lookups, Platform Admin 21 Nov 2026 11:52, 11:55 and 12:11 AEDT): admin lookups read live from the database.
--
-- Found live (rolled back, 21 Nov 2026 12:05 AEDT): the Provider list of Entry requirements (public.admin_aer 'options', used by Provider entry matrix,
-- Course entry requirements, Sources and Add a requirement) took the first 300 of the 843 providers with entry rows in no order, then sorted them. So
-- typing "charles" found Charles Institute of Technology only: Charles Sturt University (7 active rows) and Charles Darwin University (129 rows) were
-- outside the 300. Countries were written into seven screens as AU, NZ and CA.
--
-- What changes:
--   (1) public.admin_aer 'options' (md5-guarded edit, admin only): the Provider list is every active provider (3,090) and any provider with entry rows,
--       sources or course rows, in name order, with each provider's active and waiting matrix row counts. No part of the list is cut.
--   (2) public.admin_lookups_v1 (new, read only, any assigned role): countries (active providers or admission target countries, with provider and
--       course counts), study levels (ref.study_levels) and the rolling intake years (this year, Melbourne time, to lookups.intake_years_ahead).
--   (3) setting lookups.intake_years_ahead (pipeline, 2 years, range 0 to 5).
-- Audit (read live): no year-rollover rule holds a written year; the only year literals beside "intake" or "year" are in messages and comments.
-- G1: no new job. G2: one new setting. G3 stays 75/48 (admin_aer and admin_lookups_v1 are admin functions). Spend: none.
-- Parity: head 20261121170000 read 21 Nov 2026 12:05 AEDT; open Pilot #1454 is 20261121173000; this file is numbered strictly above both.
-- Replaces: the cut Provider list of public.admin_aer 'options'.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: the post-check reads the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s930_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s930_cron on commit drop as select count(*) n from cron.job where active;

-- the Provider list of Entry requirements (admin only): every active provider and any provider with entry rows, in name order, with its row counts
do $e$
declare
  v_sig constant text := 'public.admin_aer(text,jsonb)';
  v_def text := pg_get_functiondef(v_sig::regprocedure);
  v_re constant text := $o$'providers',\s+\(select\s+coalesce\(jsonb_agg\(jsonb_build_object\('id',\s+z\.id,\s+'name',\s+z\.n\)\s+order\s+by\s+z\.n\),\s+'\[\]'::jsonb\)\s+from\s+\(\s+select\s+p\.id,\s+coalesce\(p\.display_name,\s+p\.canonical_name\)\s+n\s+from\s+catalogue\.providers\s+p\s+where\s+exists\s+\(select\s+1\s+from\s+catalogue\.provider_entry_matrix\s+m0\s+where\s+m0\.provider_id\s+=\s+p\.id\)\s+or\s+exists\s+\(select\s+1\s+from\s+pipeline\.entry_matrix_sources\s+s0\s+where\s+s0\.provider_id\s+=\s+p\.id\)\s+or\s+exists\s+\(select\s+1\s+from\s+catalogue\.course_entry_requirements\s+x0\s+join\s+catalogue\.courses\s+c0\s+on\s+c0\.id\s+=\s+x0\.course_id\s+where\s+c0\.provider_id\s+=\s+p\.id\)\s+limit\s+300\)\s+z\),\s+--\s+fixed:\s+option\s+list\s+bound\s+\(W11\)$o$;
  v_new constant text := $n$'providers', (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.n, 'active_rows', z.a, 'waiting_rows', z.w) order by z.n), '[]'::jsonb) from (  -- CF-247 s930: every active provider and any provider with entry rows, never part of the list
                     select p.id, coalesce(p.display_name, p.canonical_name) n, coalesce(mc9.a, 0) a, coalesce(mc9.w, 0) w from catalogue.providers p
                       left join (select m0.provider_id, count(*) filter (where m0.status = 'active') a, count(*) filter (where m0.status in ('proposed', 'unverified')) w
                                    from catalogue.provider_entry_matrix m0 group by m0.provider_id) mc9 on mc9.provider_id = p.id
                      where p.lifecycle_status = 'active' or mc9.provider_id is not null
                         or exists (select 1 from pipeline.entry_matrix_sources s0 where s0.provider_id = p.id)
                         or exists (select 1 from catalogue.course_entry_requirements x0 join catalogue.courses c0 on c0.id = x0.course_id where c0.provider_id = p.id)) z),$n$;
  v_c int;
begin
  if md5(v_def) = '6861985ad411dd171fc25793f554214d' then raise notice 's930: admin_aer already has this change'; return; end if;
  if md5(v_def) <> '0f4af8394ea36e6ef96df2e9130e0cc9' then raise exception 'guard: % is not the text this change was written against (md5 %)', v_sig, md5(v_def); end if;
  select count(*) into v_c from regexp_matches(v_def, v_re, 'g');
  if v_c <> 1 then raise exception 'guard: the provider list must appear exactly once (found %)', v_c; end if;
  execute regexp_replace(v_def, v_re, replace(v_new, '\', '\\'));
  if md5(pg_get_functiondef(v_sig::regprocedure)) <> '6861985ad411dd171fc25793f554214d' then raise exception 's930: admin_aer after the edit has md5 %', md5(pg_get_functiondef(v_sig::regprocedure)); end if;
end $e$;

-- the rolling intake-year window (G2: a setting, not a number in code)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'lookups.intake_years_ahead', 'Lookups: intake years ahead',
        'How many years after the current year (Melbourne time) the intake year lists offer, beside the years held in the data. 2 offers this year and the next two.',
        'number', '2'::jsonb, 0, 5, 'years', 1190, 'Run now',
        'public.admin_lookups_v1 (intake_years), read by the admin screens'' Intake year lists',
        'CF-247 s930 (Platform Admin 21 Nov 2026 11:55, S1-Dynamic-Lookups): rolling intake years from the database')
on conflict do nothing;

-- the admin lookups every screen reads (read only, any assigned role): countries, study levels and the rolling intake years, live
create or replace function public.admin_lookups_v1(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_y int; v_ahead int;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v_y := extract(year from now() at time zone 'Australia/Melbourne')::int;
  v_ahead := greatest(0, least(security.pipeline_num_v1('lookups.intake_years_ahead', 2)::int, 5));  -- fixed: the setting's own range (0 to 5)
  return jsonb_build_object(
    'as_at', now(),
    -- every country that has an active provider or is a target country of admission; target countries first, then by providers
    'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', z.code, 'name', z.name, 'target', z.target, 'providers', z.providers, 'courses', z.courses)
                                            order by z.target desc, z.providers desc, z.name), '[]'::jsonb) from (
                    select k.iso_alpha2::text code, k.name, coalesce(a.active, false) target, coalesce(p.n, 0) providers, coalesce(c.n, 0) courses
                      from ref.countries k
                      left join pipeline.coverage_admission_countries a on a.country_id = k.id
                      left join (select country_id, count(*) n from catalogue.providers where lifecycle_status = 'active' group by country_id) p on p.country_id = k.id
                      left join (select p2.country_id, count(*) n from catalogue.courses c2 join catalogue.providers p2 on p2.id = c2.provider_id
                                  where c2.lifecycle_status = 'active' and p2.lifecycle_status = 'active' group by p2.country_id) c on c.country_id = k.id
                     where coalesce(a.active, false) or p.n is not null) z),
    'study_levels', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'code', l.code, 'name', l.name) order by l.sort_order, l.name), '[]'::jsonb)
                       from ref.study_levels l where l.status is distinct from 'retired'),
    'intake_years', (select jsonb_agg(y order by y) from generate_series(v_y, v_y + v_ahead) y),
    'providers', jsonb_build_object('active', (select count(*) from catalogue.providers where lifecycle_status = 'active'),
                                    'published', (select count(*) from catalogue.providers where lifecycle_status = 'active' and publication_status = 'published')));
end $f$;
revoke all on function public.admin_lookups_v1(jsonb) from public, anon;
grant execute on function public.admin_lookups_v1(jsonb) to authenticated;
comment on function public.admin_lookups_v1(jsonb) is 'CF-247 s930 (Platform Admin 21 Nov 2026, S1-Dynamic-Lookups): the lookups the admin screens read live from the database: countries (active providers or admission target countries, with provider and course counts), study levels (ref.study_levels) and the rolling intake years (this year to lookups.intake_years_ahead). Read only; any assigned role. Not part of the consumer API.';

do $c$
declare v_api jsonb; v_admin uuid; r jsonb; v_n int; v_csu int; t0 timestamptz; v_ms numeric;
begin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  t0 := clock_timestamp(); r := public.admin_aer('options', '{}'); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  perform set_config('request.jwt.claims', '', true);
  v_n := jsonb_array_length(r->'providers');
  select count(*) into v_csu from jsonb_array_elements(r->'providers') e where e->>'id' in ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e');
  if v_n < (select count(*) from catalogue.providers where lifecycle_status = 'active') then raise exception 'post-check: % providers listed, fewer than the active providers', v_n; end if;
  if v_csu <> 1 then raise exception 'post-check: Charles Sturt University is not in the Provider list'; end if;
  if v_ms > 3000 then raise exception 'post-check: options took % ms (limit 3,000 ms)', round(v_ms); end if;
  if (select count(*) from cron.job where active) <> (select n from s930_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s930_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  r := public.admin_lookups_v1();
  perform set_config('request.jwt.claims', '', true);
  if jsonb_array_length(r->'countries') < (select count(*) from pipeline.coverage_admission_countries where active) then raise exception 'post-check: the lookups miss a target country'; end if;
  if jsonb_array_length(r->'intake_years') <> security.pipeline_num_v1('lookups.intake_years_ahead', 2)::int + 1 then raise exception 'post-check: the intake years are not the rolling window'; end if;
  if (r->'intake_years'->>0)::int <> extract(year from now() at time zone 'Australia/Melbourne')::int then raise exception 'post-check: the intake years do not start this year'; end if;
  raise notice 's930: % providers in the list (Charles Sturt included); options % ms; lookups %', v_n, round(v_ms), left(r::text, 300);
end $c$;
