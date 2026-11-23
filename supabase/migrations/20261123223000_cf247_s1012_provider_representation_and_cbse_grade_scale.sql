-- CF-247 s1012 (S1-RM-Design; Platform Admin 23 Nov 2026 20:38 AEDT): two additive parts.
-- 1. REQ-118 / IR-023 (approved contract, admin docs/platform/2026-11-23-counsellor-feedback-1-3-traceability.md section 5 and P3, provider level):
--    pipeline.provider_representation holds Study Square's relationship with a provider (representation_status: represented, direct, not_represented;
--    no row = "Not recorded"), restriction_mode (include, exclude, none) and restriction_markets (ISO 3166-1 alpha-2, empty when none), the dates the
--    agreement covers, and who said so, with every change logged with a reason in pipeline.provider_representation_events. It is entered in Admin
--    (public.admin_provider_representation_save_v1, PIM Admin and above) from the Study Square partner agreement register; it is never read from a
--    website. public.admin_provider_representation_read_v1 is an Admin read (Counsellor and above). It is not served to the website or Zoho: no
--    consumer object is touched (a new v3 field would need the Platform Admin's decision).
-- 2. REQ-110: ref.grade_scale_conversions (0 rows) gets only rows an official source states. CBSE Circular 24/2010 (https://www.cbse.gov.in/circulars/cir24-2010.pdf)
--    states the Class X grade table (A1 to D, grade points 10 to 4) and "subject wise indicative percentage of marks = 9.5 x GP of the subject; overall
--    indicative percentage of marks = 9.5 x CGPA": seven rows, one per grade point. A fractional CGPA is 9.5 x CGPA by the same formula. Scales with no
--    official 0 to 100 statement (NCEA, AU GPA, ATAR, gaokao and the other Indian boards) are not seeded: deriving them would put unsourced numbers in
--    front of reviewers.
-- G1: no job. G2: no operational value (the role ranks are fixed role codes, marked). G3: no consumer object is touched (75/48 before and after).
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the new tables

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1012_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1012_cron on commit drop as select count(*) n from cron.job where active;

create table if not exists pipeline.provider_representation (
  provider_id uuid primary key references catalogue.providers(id) on delete restrict,
  representation_status text check (representation_status in ('represented', 'direct', 'not_represented')),
  restriction_mode text not null default 'none' check (restriction_mode in ('include', 'exclude', 'none')),
  restriction_markets text[] not null default '{}',
  effective_from date,
  effective_to date,
  source text,
  recorded_by uuid,
  recorded_at timestamptz not null default now(),
  reason text,
  updated_at timestamptz not null default now(),
  constraint provider_representation_markets_chk check (
    (restriction_mode = 'none' and cardinality(restriction_markets) = 0) or (restriction_mode in ('include', 'exclude') and cardinality(restriction_markets) > 0)),
  constraint provider_representation_dates_chk check (effective_to is null or effective_from is null or effective_to >= effective_from)
);
comment on table pipeline.provider_representation is 'CF-247 s1012 (REQ-118 / IR-023): Study Square representation status of a provider with its market restriction (restriction_mode include, exclude or none, and restriction_markets as ISO 3166-1 alpha-2 codes). Entered in Admin from the partner agreement register, never read from a website; a provider with no row is Not recorded. Admin-only: not served to the website or Zoho.';
alter table pipeline.provider_representation enable row level security;
revoke all on pipeline.provider_representation from public, anon, authenticated;

create table if not exists pipeline.provider_representation_events (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete restrict,
  actor_id uuid,
  reason text not null,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
comment on table pipeline.provider_representation_events is 'CF-247 s1012 (REQ-118 / IR-023): every change to a provider representation row with its reason, the actor and the row before and after. Append only.';
alter table pipeline.provider_representation_events enable row level security;
revoke all on pipeline.provider_representation_events from public, anon, authenticated;
create index if not exists provider_representation_events_provider_idx on pipeline.provider_representation_events (provider_id, created_at desc);

create or replace function public.admin_provider_representation_save_v1(p_provider uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_uid uuid := auth.uid(); v_reason text := nullif(btrim(coalesce(p_payload->>'reason', '')), '');
        v_status text := nullif(btrim(coalesce(p_payload->>'representation_status', '')), '');
        v_mode text := lower(btrim(coalesce(nullif(p_payload->>'restriction_mode', ''), 'none')));
        v_markets text[]; v_bad text[]; v_old pipeline.provider_representation%rowtype; v_new pipeline.provider_representation%rowtype;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Admin role required for provider representation' using errcode = '42501'; end if; -- fixed: same role as partner contact entry
  if v_reason is null then raise exception 'INVALID_INPUT: a reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = p_provider) then raise exception 'INVALID_INPUT: provider not found' using errcode = '22023'; end if;
  if v_status is not null and v_status not in ('represented', 'direct', 'not_represented') then raise exception 'INVALID_INPUT: representation_status is represented, direct or not_represented' using errcode = '22023'; end if;
  if v_mode not in ('include', 'exclude', 'none') then raise exception 'INVALID_INPUT: restriction_mode is include, exclude or none' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct upper(btrim(m)) order by upper(btrim(m))), '{}') into v_markets from jsonb_array_elements_text(coalesce(p_payload->'restriction_markets', '[]'::jsonb)) m where btrim(m) <> '';
  select coalesce(array_agg(x), '{}') into v_bad from unnest(v_markets) x where not exists (select 1 from ref.countries c where c.iso_alpha2 = x);
  if cardinality(v_bad) > 0 then raise exception 'INVALID_INPUT: unknown market code(s) %', v_bad using errcode = '22023'; end if;
  if v_mode = 'none' and cardinality(v_markets) > 0 then raise exception 'INVALID_INPUT: restriction_markets must be empty when restriction_mode is none' using errcode = '22023'; end if;
  if v_mode in ('include', 'exclude') and cardinality(v_markets) = 0 then raise exception 'INVALID_INPUT: restriction_markets is required when restriction_mode is include or exclude' using errcode = '22023'; end if;
  select * into v_old from pipeline.provider_representation where provider_id = p_provider for update;
  insert into pipeline.provider_representation as r (provider_id, representation_status, restriction_mode, restriction_markets, effective_from, effective_to, source, recorded_by, recorded_at, reason, updated_at)
  values (p_provider, v_status, v_mode, v_markets, nullif(p_payload->>'effective_from', '')::date, nullif(p_payload->>'effective_to', '')::date,
          nullif(btrim(coalesce(p_payload->>'source', '')), ''), v_uid, now(), v_reason, now())
  on conflict (provider_id) do update set representation_status = excluded.representation_status, restriction_mode = excluded.restriction_mode,
    restriction_markets = excluded.restriction_markets, effective_from = excluded.effective_from, effective_to = excluded.effective_to,
    source = excluded.source, recorded_by = excluded.recorded_by, recorded_at = excluded.recorded_at, reason = excluded.reason, updated_at = now()
  returning * into v_new;
  insert into pipeline.provider_representation_events (provider_id, actor_id, reason, before, after)
  values (p_provider, v_uid, v_reason, case when v_old.provider_id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return jsonb_build_object('provider_id', p_provider, 'representation_status', v_new.representation_status, 'restriction_mode', v_new.restriction_mode,
                            'restriction_markets', to_jsonb(v_new.restriction_markets));
end $function$;
comment on function public.admin_provider_representation_save_v1(uuid, jsonb) is 'CF-247 s1012 (REQ-118 / IR-023): Admin entry of a provider representation row (status, restriction_mode, restriction_markets, dates, source) with a required reason; PIM Admin and above; every change is logged. Not a consumer object.';
revoke all on function public.admin_provider_representation_save_v1(uuid, jsonb) from public, anon;
grant execute on function public.admin_provider_representation_save_v1(uuid, jsonb) to authenticated;

create or replace function public.admin_provider_representation_read_v1(p_provider uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor role or above required' using errcode = '42501'; end if; -- fixed: Counsellor is the lowest staff role
  return coalesce((select jsonb_agg(jsonb_build_object('provider_id', r.provider_id, 'representation_status', r.representation_status,
           'restriction_mode', r.restriction_mode, 'restriction_markets', to_jsonb(r.restriction_markets), 'effective_from', r.effective_from,
           'effective_to', r.effective_to, 'source', r.source, 'recorded_at', r.recorded_at) order by r.provider_id)
           from pipeline.provider_representation r where p_provider is null or r.provider_id = p_provider), '[]'::jsonb);
end $function$;
comment on function public.admin_provider_representation_read_v1(uuid) is 'CF-247 s1012 (REQ-118 / IR-023): Admin read of provider representation rows (one provider or all). A provider with no row is not returned: the screen shows Not recorded. Counsellor and above. Not a consumer object.';
revoke all on function public.admin_provider_representation_read_v1(uuid) from public, anon;
grant execute on function public.admin_provider_representation_read_v1(uuid) to authenticated;

-- REQ-110: the CBSE Class X grade points (Circular 24/2010; CBSE secondary curriculum grade table), 9.5 x GP = indicative percentage of marks
insert into ref.grade_scale_conversions (country_id, qualification_code, qualification_name, board_or_stream, scale_code, raw_min_value, raw_max_value, raw_grade_label, normalized_0_100, is_active, source_url, notes)
select c.id, 'IN_CBSE_X', 'Secondary School Examination (Class X)', 'CBSE', 'CBSE_X_GP10', v.gp, v.gp, v.grade, round(v.gp * 9.5, 2), true,
       'https://www.cbse.gov.in/circulars/cir24-2010.pdf',
       'CBSE Circular 24/2010: subject wise indicative percentage of marks = 9.5 x GP of the subject; overall indicative percentage of marks = 9.5 x CGPA (a fractional CGPA uses the same formula). Marks range ' || v.marks || ' = grade ' || v.grade || ', grade point ' || v.gp || '. Indicative, not exact.'
  from ref.countries c,
       (values (10, 'A1', '91-100'), (9, 'A2', '81-90'), (8, 'B1', '71-80'), (7, 'B2', '61-70'), (6, 'C1', '51-60'), (5, 'C2', '41-50'), (4, 'D', '33-40')) as v(gp, grade, marks)
 where c.iso_alpha2 = 'IN'
   and not exists (select 1 from ref.grade_scale_conversions g where g.country_id = c.id and g.scale_code = 'CBSE_X_GP10' and g.raw_min_value = v.gp);

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1012_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1012_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if has_table_privilege('anon', 'pipeline.provider_representation', 'select') or has_table_privilege('authenticated', 'pipeline.provider_representation', 'select')
     or has_function_privilege('anon', 'public.admin_provider_representation_save_v1(uuid,jsonb)', 'execute') or has_function_privilege('anon', 'public.admin_provider_representation_read_v1(uuid)', 'execute') then
    raise exception 'post-check: a role can reach a new object it should not';
  end if;
  if (select count(*) from ref.grade_scale_conversions where scale_code = 'CBSE_X_GP10' and is_active) <> 7 then raise exception 'post-check: the CBSE rows are not seven'; end if;
  if (select normalized_0_100 from ref.grade_scale_conversions where scale_code = 'CBSE_X_GP10' and raw_min_value = 10) <> 95 then raise exception 'post-check: GP 10 is not 95'; end if;
  if (select count(*) from ref.grade_scale_conversions) <> 7 then raise exception 'post-check: an unexpected grade scale row exists'; end if;
end $post$;
