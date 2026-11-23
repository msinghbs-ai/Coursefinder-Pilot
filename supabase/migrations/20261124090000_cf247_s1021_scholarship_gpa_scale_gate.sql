-- CF-247 s1021 (S1-Build; Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT; UI-UX plan v1.2 slice 6, gate 4): scholarship GPA thresholds need
-- their scale. A machine-written GPA threshold (scholarship.criteria, academic_minimum, value GPA) on a scholarship linked to a course is admitted
-- only with a stated scale (value_json.scale, or "out of N" / "/N" in its own text) and a threshold within it. Otherwise a new criterion is held
-- as unverified and opens a review in the Layer 4 Inbox kind "Scholarship GPA scale"; an active criterion being refreshed keeps its status and
-- opens the same review (nothing admitted is withdrawn). Measured live before this change (rolled back, 24 Nov 2026): 155 active GPA
-- criteria, 117 on course-linked scholarships, 145 without a scale; thresholds from 2 to 6 (both 4- and 7-point scales), so no scale is assumed.
-- Platform Admin 24 Nov 2026: held items are grouped per provider (the kind counts by provider).
-- 1. pipeline.gpa_scale_reviews (new): one open review per criterion.
-- 2. security.gate_gpa_scale_tg on scholarship.criteria (BEFORE insert or update), switch gates.gpa_scale_on (G2). Logged in
--    pipeline.preadmission_gate_events (s1020).
-- 3. Layer 4 Inbox kind scholarship_gpa_scale (pipeline.layer4_inbox_kind_hooks, the existing plug-in contract): choices GPA out of 4,
--    GPA out of 7, another scale (the person enters it), or not a GPA threshold. Setting a scale writes value_json.scale and re-admits the
--    criterion only when its threshold fits the scale; the decision is logged in pipeline.admin_control_events.
-- G1: no job. G2: the switch is a setting. G3: no consumer object changed (consumer reads filter criteria on status = 'active'; checked).
-- Manual locks and active cron checked unchanged. Nothing dropped or deleted.
-- Replaces: silent admission of a course-linked GPA threshold with no scale.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the trigger change

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if to_regclass('pipeline.preadmission_gate_events') is null then raise exception 'guard: s1020 (pipeline.preadmission_gate_events) is not live'; end if;
end $g$;
create temp table s1021_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1021_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'gates.gpa_scale_on', 'Pre-admission gate: scholarship GPA scale',
        'On (1): a machine-read GPA threshold on a scholarship linked to a course is admitted only when its scale is stated (for example out of 4 or out of 7) and the threshold fits it; otherwise it waits in Layer 4 (Scholarship GPA scale) for a person to set the scale. Thresholds already admitted are never withdrawn by this gate.',
        'number', to_jsonb(1), 0, 1, 'on/off', 3344, 'Pre-admission gates', 'security.gate_gpa_scale_tg (scholarship.criteria)', 'CF-247 s1021: slice 6 pre-admission gates (Platform Admin 24 Nov 2026)')
on conflict do nothing;

create table if not exists pipeline.gpa_scale_reviews (
  id uuid primary key default gen_random_uuid(),
  criterion_id uuid not null,
  scholarship_id uuid not null,
  provider_id uuid,
  threshold numeric,
  stated_scale numeric,
  human_text text,
  evidence_id uuid,
  problem text not null,
  status text not null default 'open',
  opened_at timestamptz not null default now(),
  decision text,
  decided_scale numeric,
  reason text,
  decided_by uuid,
  decided_at timestamptz
);
comment on table pipeline.gpa_scale_reviews is 'CF-247 s1021: course-linked scholarship GPA thresholds held for a person to set their scale (Layer 4 kind scholarship_gpa_scale).';
create unique index if not exists gpa_scale_reviews_open_uq on pipeline.gpa_scale_reviews (criterion_id) where status = 'open';
create index if not exists gpa_scale_reviews_provider_idx on pipeline.gpa_scale_reviews (provider_id, opened_at) where status = 'open';
alter table pipeline.gpa_scale_reviews enable row level security;
revoke all on pipeline.gpa_scale_reviews from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.gpa_scale_of_v1(p_value_json jsonb, p_text text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    case when jsonb_typeof(p_value_json -> 'scale') = 'number' then (p_value_json ->> 'scale')::numeric end,
    (select m[1]::numeric from regexp_matches(coalesce(p_text, ''), '(?:out of|/)\s*([0-9]+(?:\.[0-9]+)?)', 'i') m limit 1))
$function$;

CREATE OR REPLACE FUNCTION security.gate_gpa_scale_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_scale numeric; v_refresh boolean; v_problem text; v_provider uuid;
begin
  if new.status is distinct from 'active' or new.criterion_type is distinct from 'academic_minimum' or coalesce(new.value_text, '') !~* '^GPA' then return new; end if;
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('gates.gpa_scale_on', 1) < 1 then return new; end if;
  if not exists (select 1 from scholarship.course_mappings m where m.scholarship_id = new.scholarship_id and m.mapping_state = 'mapped') then return new; end if;
  v_refresh := tg_op = 'UPDATE' and old.status = 'active';
  if v_refresh and old.value_number is not distinct from new.value_number and old.value_json is not distinct from new.value_json and old.human_text is not distinct from new.human_text then return new; end if;
  v_scale := security.gpa_scale_of_v1(new.value_json, new.human_text);
  v_problem := case when v_scale is null then 'the GPA threshold states no scale'
                    when new.value_number is not null and new.value_number > v_scale then format('the threshold %s is above its scale %s', new.value_number, v_scale) end;
  if v_problem is null then return new; end if;
  if not v_refresh then new.status := 'unverified'; end if;
  select s.provider_id into v_provider from scholarship.scholarships s where s.id = new.scholarship_id;
  insert into pipeline.gpa_scale_reviews(criterion_id, scholarship_id, provider_id, threshold, stated_scale, human_text, evidence_id, problem)
  values (new.id, new.scholarship_id, v_provider, new.value_number, v_scale, left(new.human_text, 600), new.evidence_id, v_problem)
  on conflict (criterion_id) where status = 'open' do nothing;
  insert into pipeline.preadmission_gate_events(gate, entity_type, entity_id, row_ref, outcome, reason, detail)
  values ('gpa_scale', 'scholarship', new.scholarship_id, new.id::text, case when v_refresh then 'notice_active_kept' else 'held' end, v_problem,
          jsonb_build_object('threshold', new.value_number, 'scale', v_scale));
  return new;
end $function$;
revoke all on function security.gate_gpa_scale_tg() from public, anon, authenticated;

-- Layer 4 Inbox kind
CREATE OR REPLACE FUNCTION security.layer4_gpa_scale_kind_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{"label": "Scholarship GPA scale", "order": 38, "choices": [
     {"key": "scale_4", "label": "GPA out of 4", "rank": 4, "returns": "The threshold is recorded as out of 4 and admitted if it fits the scale"},
     {"key": "scale_7", "label": "GPA out of 7", "rank": 4, "returns": "The threshold is recorded as out of 7 and admitted if it fits the scale"},
     {"key": "scale_other", "label": "Another scale (enter it)", "rank": 4, "returns": "The threshold is recorded with the scale you enter and admitted if it fits"},
     {"key": "not_gpa", "label": "Not a GPA threshold", "rank": 4, "returns": "Recorded; the criterion stays held and is not shown to counsellors"}]}'::jsonb
$function$;

CREATE OR REPLACE FUNCTION security.layer4_gpa_scale_inbox_counts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select * from pipeline.gpa_scale_reviews where status = 'open')
  select jsonb_build_object('kind', 'scholarship_gpa_scale', 'n', (select count(*) from o), 'oldest', (select min(o.opened_at) from o),
    'late', (select count(*) from o where o.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.opened_at) oldest from o group by 1) z), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_gpa_scale_inbox_page_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select r.* from pipeline.gpa_scale_reviews r
              where r.status = 'open' and (nullif(p_args->>'provider_id', '') is null or r.provider_id = (p_args->>'provider_id')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.opened_at, o.id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.opened_at, o.id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'scholarship_gpa_scale',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.opened_at, o.id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'scholarship_gpa_scale', 'ref', x.id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce((select s.name from scholarship.scholarships s where s.id = x.scholarship_id), 'Scholarship') || ' · GPA ' || coalesce(x.threshold::text, '?'),
           'why', x.problem, 'suggestion', 'Set the scale the scholarship page states',
           'created_at', x.opened_at,
           'late', x.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.opened_at, x.id::text) from x), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_gpa_scale_inbox_detail_v1(p_ref text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'criterion', 'title', 'GPA threshold', 'body', jsonb_build_object('Scholarship', s.name, 'Threshold', r.threshold, 'Scale stated', coalesce(r.stated_scale::text, 'none'),
                         'Text on the page', coalesce(r.human_text, '(no text)'), 'Stored copy (evidence)', r.evidence_id)),
      jsonb_build_object('key', 'why', 'title', 'Why it is held', 'body', r.problem),
      jsonb_build_object('key', 'rule', 'title', 'The rule',
        'body', 'A GPA threshold is shown to counsellors only with the scale the scholarship states (for example out of 4 or out of 7). Nothing is assumed from the number alone.')),
    'actions', jsonb_build_array(jsonb_build_object('key', 'scale_4', 'allowed', true), jsonb_build_object('key', 'scale_7', 'allowed', true),
                                 jsonb_build_object('key', 'scale_other', 'allowed', true), jsonb_build_object('key', 'not_gpa', 'allowed', true)))
    from pipeline.gpa_scale_reviews r left join scholarship.scholarships s on s.id = r.scholarship_id
   where r.id::text = p_ref and r.status = 'open'
$function$;

CREATE OR REPLACE FUNCTION security.layer4_gpa_scale_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.gpa_scale_reviews; v_scale numeric; v_n int := 0; v_ev bigint; v_returns text; v_status text;
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Layer 4 Inbox: ' || p_choice);
begin
  select * into r from pipeline.gpa_scale_reviews where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'scholarship_gpa_scale', 'choice', p_choice, 'ref', p_ref, 'request', 'This threshold has already been settled; refresh the Inbox.');
  end if;
  v_scale := case p_choice when 'scale_4' then 4 when 'scale_7' then 7
                           when 'scale_other' then case when coalesce(p_value, '') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then btrim(p_value)::numeric end end;
  if p_choice = 'scale_other' and (v_scale is null or v_scale <= 0) then
    return jsonb_build_object('ok', false, 'kind', 'scholarship_gpa_scale', 'choice', p_choice, 'ref', p_ref, 'request', 'Enter the scale as a number, for example 4 or 7.');
  end if;
  if v_scale is not null then
    if r.threshold is not null and r.threshold > v_scale then
      return jsonb_build_object('ok', false, 'kind', 'scholarship_gpa_scale', 'choice', p_choice, 'ref', p_ref, 'request', format('The threshold %s is above a scale of %s; choose the scale the page states.', r.threshold, v_scale));
    end if;
    perform set_config('cf.manual_edit', 'on', true);
    update scholarship.criteria set value_json = coalesce(value_json, '{}'::jsonb) || jsonb_build_object('scale', v_scale, 'scale_set_by', 'layer4'), status = 'active'
     where id = r.criterion_id;
    get diagnostics v_n = row_count;
    perform set_config('cf.manual_edit', '', true);
    v_status := 'scale_set';
    v_returns := case when v_n = 1 then format('The threshold is now shown as GPA %s out of %s.', r.threshold, v_scale) else 'The criterion no longer exists; nothing changed.' end;
  elsif p_choice = 'not_gpa' then
    v_status := 'not_gpa'; v_returns := 'Recorded; the criterion stays held.';
  else
    raise exception 'unknown choice %', p_choice using errcode = '22023';
  end if;
  update pipeline.gpa_scale_reviews set status = v_status, decision = p_choice, decided_scale = v_scale, reason = v_reason, decided_by = auth.uid(), decided_at = now() where id = r.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'scholarship_gpa_scale:' || p_ref, jsonb_build_object('kind', 'scholarship_gpa_scale', 'ref', p_ref, 'choice', p_choice, 'scale', v_scale, 'reason', v_reason,
          'criterion_id', r.criterion_id, 'scholarship_id', r.scholarship_id, 'provider_id', r.provider_id, 'evidence_id', r.evidence_id, 'admitted', v_n = 1), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'kind', 'scholarship_gpa_scale', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'returns', v_returns);
end $function$;

revoke all on function security.layer4_gpa_scale_inbox_decide_v1(text, text, text, text) from public, anon;
insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('scholarship_gpa_scale', 'kind', 'security.layer4_gpa_scale_kind_v1()', 'security.layer4_gpa_scale_inbox_counts_v1()', 'security.layer4_gpa_scale_inbox_page_v1(jsonb)',
        'security.layer4_gpa_scale_inbox_detail_v1(text)', 'security.layer4_gpa_scale_inbox_decide_v1(text,text,text,text)', true,
        'Pre-admission gates (CF-247 s1021)', 'Course-linked scholarship GPA thresholds held until a person sets their scale (Platform Admin 24 Nov 2026, UI-UX plan v1.2 slice 6)')
on conflict do nothing;

do $t$
declare v_try int := 0;
begin
  loop
    begin
      perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
      execute 'create trigger criteria_gpa_scale_gate before insert or update on scholarship.criteria for each row execute function security.gate_gpa_scale_tg()';
      exit;
    exception when lock_not_available then
      v_try := v_try + 1;
      if v_try >= 5 then raise exception 'could not take the lock for the GPA gate trigger'; end if;  -- fixed: tries before giving up
      perform pg_sleep(2);  -- fixed: pause between tries
    end;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $t$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1021_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1021_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'criteria_gpa_scale_gate' and not tgisinternal) then raise exception 'post-check: the GPA gate trigger is missing'; end if;
  if not exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'scholarship_gpa_scale' and enabled) then raise exception 'post-check: the Inbox kind is not registered'; end if;
  if security.gpa_scale_of_v1('{"scale": 7}'::jsonb, null) <> 7 or security.gpa_scale_of_v1('{}'::jsonb, 'a GPA of 5.0 out of 7') <> 7
     or security.gpa_scale_of_v1('{}'::jsonb, 'GPA 3.0/4.0') <> 4 or security.gpa_scale_of_v1('{}'::jsonb, 'a GPA of 4.0') is not null then
    raise exception 'post-check: the scale reader does not read the stated scale';
  end if;
end $post$;
