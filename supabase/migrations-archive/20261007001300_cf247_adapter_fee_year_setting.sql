-- CF-247, 7 Oct 2026 (Platform Admin: add a fee-year setting to the adapter). Some course pages print an annual fee with no year (WSU, CSU), and the sweep
-- filed it as the current year. An adapter can now carry reading.fee_year (a year); it is used only when the page itself gives no year, and only while it is
-- the current or next year, so a stale setting falls back to the current year rather than mislabelling. Setting it is a separate, logged Platform Admin step.
create or replace function security.adapter_fee_year_setting(p_reading jsonb)
returns int language sql stable set search_path to '' as $f$
  select case when coalesce(p_reading->>'fee_year', '') ~ '^20[2-9][0-9]$'
               and (p_reading->>'fee_year')::int between extract(year from now() at time zone 'Australia/Melbourne')::int
                                                     and extract(year from now() at time zone 'Australia/Melbourne')::int + 1
              then (p_reading->>'fee_year')::int end
$f$;
revoke all on function security.adapter_fee_year_setting(jsonb) from public, anon, authenticated;
do $p$
declare d text; o oid;
begin
  select p.oid into o from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'adapter_overwrite_v1';
  d := pg_get_functiondef(o);
  if md5(d) <> '72ef8bda97bb8df464425b350d6a3ce3' then raise exception 'adapter_overwrite_v1 is not the version this migration expects'; end if;
  if (select count(*) from regexp_matches(d, 'u\.admit_fields af,', 'g')) <> 1 then raise exception 'anchor 1 not found once'; end if;
  if strpos(d, $a$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, extract(year from now() at time zone 'Australia/Melbourne')::int);$a$) = 0 then raise exception 'anchor 2 not found'; end if;
  d := replace(d, 'u.admit_fields af,', 'u.admit_fields af, u.reading rd,');
  d := replace(d, $a$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, extract(year from now() at time zone 'Australia/Melbourne')::int);$a$,
                  $b$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, security.adapter_fee_year_setting(r.rd), extract(year from now() at time zone 'Australia/Melbourne')::int);$b$);
  execute d;

  select p.oid into o from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admin_uni_adapter_write';
  d := pg_get_functiondef(o);
  if md5(d) <> 'afb6a4518ea9205599db6285dc62f6d9' then raise exception 'admin_uni_adapter_write is not the version this migration expects'; end if;
  if strpos(d, $a$r.key not in ('numeric_dates', 'upper_dates', 'academic_year') or jsonb_typeof(r.value) <> 'boolean')$a$) = 0
     or strpos(d, 'reading may only hold numeric_dates, upper_dates and academic_year, each true or false') = 0 then raise exception 'reading anchors not found'; end if;
  d := replace(d, $a$r.key not in ('numeric_dates', 'upper_dates', 'academic_year') or jsonb_typeof(r.value) <> 'boolean')$a$,
                  $b$r.key not in ('numeric_dates', 'upper_dates', 'academic_year', 'fee_year') or (r.key <> 'fee_year' and jsonb_typeof(r.value) <> 'boolean') or (r.key = 'fee_year' and r.value::text !~ '^20[2-9][0-9]$'))$b$);
  d := replace(d, 'reading may only hold numeric_dates, upper_dates and academic_year, each true or false',
                  'reading may only hold numeric_dates, upper_dates and academic_year (each true or false) and fee_year (a year)');
  execute d;
end $p$;
create or replace function public.admin_uni_adapter_fee_year(p_provider_id uuid, p_year int, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_before jsonb; v_after jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_year is not null and p_year not between extract(year from now() at time zone 'Australia/Melbourne')::int and extract(year from now() at time zone 'Australia/Melbourne')::int + 1 then
    raise exception 'the fee year must be this year or next year'; end if;
  select reading into v_before from pipeline.uni_adapters where provider_id = p_provider_id for update;
  if not found then raise exception 'no adapter for this provider'; end if;
  update pipeline.uni_adapters
     set reading = case when p_year is null then coalesce(reading, '{}'::jsonb) - 'fee_year' else coalesce(reading, '{}'::jsonb) || jsonb_build_object('fee_year', p_year) end,
         reason = left(p_reason, 500), updated_by = auth.uid(), updated_at = now()
   where provider_id = p_provider_id returning reading into v_after;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('adapters', 'adapter_fee_year_set', p_provider_id::text, jsonb_build_object('provider_id', p_provider_id, 'before', v_before, 'after', v_after, 'reason', left(p_reason, 500)), auth.uid());
  return jsonb_build_object('ok', true, 'reading', v_after);
end $f$;
revoke all on function public.admin_uni_adapter_fee_year(uuid, int, text) from public, anon;
grant execute on function public.admin_uni_adapter_fee_year(uuid, int, text) to authenticated, service_role;
