-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08 decision 4, and 10:10: "every genuine page conflict reaches Layer 4 › Inbox").
-- Refused Boost study-load readings go to Layer 4 as their own Inbox kind, "Boost study load". A reading is sent when the page had study-load
-- text (the worker only calls the model for a page that says full-time or part-time) and the answer failed the page check. Readings that
-- found nothing ("not stated") and calls that failed for a technical reason are never sent.
-- What it does:
--   1. Table pipeline.boost_study_load_reviews: one row per refused reading sent to review, with its answer, the check's reasons, the page and
--      the decision. At most one open review per course.
--   2. security.boost_study_load_review_feed_v1(): opens reviews for refused readings under the prompt the route now runs (the route
--      qualification's prompt_version), for courses that still have no study load and no manual lock, up to setting boost.layer4_open_max
--      open at a time; closes as superseded any open review whose course gained a study load elsewhere. It runs after each Boost result file
--      is loaded (statement trigger on pipeline.boost_inbound_staging) and after each decision, so the Inbox refills as items are decided.
--      The 150-item cap of the human-assisted recovery lanes (har.open_max_per_lane) is for those lanes; this kind has its own cap, 400, so
--      today's 376 refused readings all reach the Inbox.
--   3. The Inbox kind (pipeline.layer4_inbox_kind_hooks): label, counts, page, detail and decision. Choices (Pipeline Operator or above):
--      Full-time, Part-time or Both (fills the course's study load only while it is empty and unlocked: source manual, evidence the stored
--      page, updated_at untouched); Not stated on the page; Dismiss the reading. Each decision writes an admin_control_events row.
-- What it does not do: it admits nothing by itself, changes no existing function and nothing the consumer API reads in shape.
-- G1: no new job (the feed runs from a trigger and from decisions). G2: the cap is a setting. G3: no consumer API object is changed; a
-- reviewer's decision fills catalogue.courses.study_load only where it is empty, as Boost promotion does.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118100000') then raise exception 'migration 20261118100000 (Boost study load qualified) is not applied'; end if;
  if to_regprocedure('public.admin_layer4_inbox(text,jsonb)') is null or to_regprocedure('security.layer4_inbox_hooks_v1()') is null then raise exception 'the Layer 4 Inbox is not present'; end if;
  if exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'boost_study_load') then raise exception 'Inbox kind boost_study_load already exists'; end if;
end $pre$;

-- 1. The reviews
create table if not exists pipeline.boost_study_load_reviews (
  id             bigserial primary key,
  staging_id     bigint not null unique references pipeline.boost_inbound_staging(id),
  course_id      uuid not null references catalogue.courses(id),
  provider_id    uuid,
  evidence_id    uuid,
  source_url     text,
  prompt_version text not null,
  answer         jsonb,
  problems       jsonb not null default '[]'::jsonb,
  status         text not null default 'open' check (status in ('open', 'accepted', 'not_stated', 'dismissed', 'superseded')),
  decision       text,
  decided_value  text check (decided_value is null or decided_value in ('full_time', 'part_time', 'both')),
  reason         text,
  decided_by     uuid,
  decided_at     timestamptz,
  opened_at      timestamptz not null default now()
);
create unique index if not exists boost_study_load_reviews_one_open on pipeline.boost_study_load_reviews (course_id) where status = 'open';
create index if not exists boost_study_load_reviews_open_at on pipeline.boost_study_load_reviews (opened_at, id) where status = 'open';
comment on table pipeline.boost_study_load_reviews is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 4): refused Boost study-load readings sent to Layer 4 › Inbox, kind boost_study_load (the page had study-load text and the answer failed the page check). One open review per course; the decision, its reason and who made it.';
alter table pipeline.boost_study_load_reviews enable row level security;

-- 2. Setting
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.layer4_open_max', 'Boost study load: open Layer 4 reviews at most',
  'How many refused Boost study-load readings may wait in Layer 4 › Inbox at a time. More are opened as items are decided. 0 stops sending new ones; open items stay.',
  'number', to_jsonb(400), 0, 2000, 'items', 958, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 4 and 10:10 (every genuine page conflict reaches the Inbox; 376 refused readings today)', 'Boost',
  'security.boost_study_load_review_feed_v1 (Layer 4 Inbox kind boost_study_load)')
on conflict (toolset_key, key) do nothing;

-- 3. The feed
create or replace function security.boost_study_load_review_feed_v1()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_cap int := security.pipeline_num_v1('boost.layer4_open_max', 400)::int;
  v_prompt text := (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' order by q.prompt_version desc limit 1);
  v_closed int := 0; v_opened int := 0; v_room int;
begin
  perform pg_advisory_xact_lock(hashtext('cf247:boost_study_load_review_feed'));  -- fixed: one writer
  update pipeline.boost_study_load_reviews r set status = 'superseded', decided_at = now(), reason = 'the course gained a study load or a manual lock elsewhere'
   where r.status = 'open'
     and (exists (select 1 from catalogue.courses c where c.id = r.course_id and c.study_load is not null)
          or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')));
  get diagnostics v_closed = row_count;
  v_room := v_cap - (select count(*) from pipeline.boost_study_load_reviews where status = 'open');
  if v_room > 0 and v_prompt is not null then
    insert into pipeline.boost_study_load_reviews (staging_id, course_id, provider_id, evidence_id, source_url, prompt_version, answer, problems)
    select d.id, d.entity_id, c.provider_id, d.evidence_id, d.source_url, d.prompt_version, d.answer, coalesce(d.verdict->'problems', '[]'::jsonb)
      from (select distinct on (s.entity_id) s.* from pipeline.boost_inbound_staging s
             where s.lane = 'study_load' and s.worker_status = 'rejected' and s.prompt_version = v_prompt
             order by s.entity_id, s.id desc) d
      join catalogue.courses c on c.id = d.entity_id
     where c.study_load is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = d.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
       -- a course already reviewed for this page (any status) is not sent again; a course with an open review waits for it
       and not exists (select 1 from pipeline.boost_study_load_reviews r where r.course_id = d.entity_id and (r.status = 'open' or r.evidence_id is not distinct from d.evidence_id))
     order by d.id
     limit v_room;
    get diagnostics v_opened = row_count;
  end if;
  return jsonb_build_object('opened', v_opened, 'superseded', v_closed, 'open', (select count(*) from pipeline.boost_study_load_reviews where status = 'open'), 'cap', v_cap, 'prompt_version', v_prompt);
end $function$;
revoke all on function security.boost_study_load_review_feed_v1() from public, anon, authenticated;
grant execute on function security.boost_study_load_review_feed_v1() to service_role;
comment on function security.boost_study_load_review_feed_v1() is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 4): opens Layer 4 reviews for refused Boost study-load readings under the prompt the route runs, up to boost.layer4_open_max; closes reviews whose course gained a value.';

create or replace function security.boost_study_load_review_feed_trg_v1()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  perform security.boost_study_load_review_feed_v1();
  return null;
end $function$;
revoke all on function security.boost_study_load_review_feed_trg_v1() from public, anon, authenticated;
comment on function security.boost_study_load_review_feed_trg_v1() is 'CF-247 Boost: runs the Layer 4 study-load review feed after a Boost result file is loaded or settled.';

do $t$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.boost_inbound_staging'::regclass and tgname = 'boost_study_load_review_feed') then
    create trigger boost_study_load_review_feed after insert or update of promotion_state on pipeline.boost_inbound_staging
      for each statement execute function security.boost_study_load_review_feed_trg_v1();
  end if;
end $t$;

-- 4. The Inbox kind
create or replace function security.layer4_boost_study_load_kind_v1()
returns jsonb language sql immutable set search_path to '' as $function$
  select '{"label": "Boost study load", "order": 37, "choices": [
     {"key": "accept_full_time", "label": "Full-time", "rank": 4, "returns": "The course''s study load becomes Full-time (source manual, evidence the stored page), only if it is still empty"},
     {"key": "accept_part_time", "label": "Part-time", "rank": 4, "returns": "The course''s study load becomes Part-time (source manual, evidence the stored page), only if it is still empty"},
     {"key": "accept_both", "label": "Both full-time and part-time", "rank": 4, "returns": "The course''s study load becomes Both (source manual, evidence the stored page), only if it is still empty"},
     {"key": "not_stated", "label": "Not stated on the page", "rank": 4, "returns": "Recorded; the course keeps no study load and this page is not sent again"},
     {"key": "dismiss", "label": "Dismiss the reading", "rank": 4, "returns": "Recorded; nothing changes on the course and this page is not sent again"}]}'::jsonb
$function$;
revoke all on function security.layer4_boost_study_load_kind_v1() from public, anon, authenticated;

create or replace function security.layer4_boost_study_load_inbox_counts_v1()
returns jsonb language sql stable security definer set search_path to '' as $function$
  with o as (select * from pipeline.boost_study_load_reviews where status = 'open')
  select jsonb_build_object('kind', 'boost_study_load', 'n', (select count(*) from o), 'oldest', (select min(o.opened_at) from o),
    'late', (select count(*) from o where o.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.opened_at) oldest from o group by 1) z), '[]'::jsonb))
$function$;
revoke all on function security.layer4_boost_study_load_inbox_counts_v1() from public, anon, authenticated;

create or replace function security.layer4_boost_study_load_inbox_page_v1(p_args jsonb)
returns jsonb language sql stable security definer set search_path to '' as $function$
  with o as (select r.* from pipeline.boost_study_load_reviews r
              where r.status = 'open' and (nullif(p_args->>'provider_id', '') is null or r.provider_id = (p_args->>'provider_id')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.opened_at, o.id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.opened_at, o.id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'boost_study_load',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.opened_at, o.id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'boost_study_load', 'ref', x.id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce((select c.display_title from catalogue.courses c where c.id = x.course_id), 'Course') || ' · study load',
           'why', 'The page check refused the reading: ' || coalesce(x.problems->>0, 'no reason recorded'),
           'suggestion', case when x.answer->>'study_load' is not null then 'The model read ' || replace(x.answer->>'study_load', '_', '-') || '; check it against the page' end,
           'created_at', x.opened_at, 'course_id', x.course_id, 'source_url', x.source_url,
           'late', x.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.opened_at, x.id::text) from x), '[]'::jsonb))
$function$;
revoke all on function security.layer4_boost_study_load_inbox_page_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_boost_study_load_inbox_detail_v1(p_ref text)
returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'page', 'title', 'Course page', 'body', jsonb_build_object('Course', c.display_title, 'Page', r.source_url, 'Stored copy (evidence)', r.evidence_id)),
      jsonb_build_object('key', 'reading', 'title', 'What the model read',
        'body', jsonb_build_object('Study load', coalesce(replace(r.answer->>'study_load', '_', '-'), 'not stated'), 'Quoted from the page', coalesce(r.answer->>'quote', '(no quote)'))),
      jsonb_build_object('key', 'refused', 'title', 'Why the page check refused it', 'body', r.problems),
      jsonb_build_object('key', 'rule', 'title', 'The rule',
        'body', 'Report the study load the page states for international students when it states one (for example "International student visa holders can only study full-time"); otherwise the study load it states for the course. Never from delivery mode or duration alone. A decision fills the course only while its study load is empty.')),
    'actions', jsonb_build_array(jsonb_build_object('key', 'accept_full_time', 'allowed', true), jsonb_build_object('key', 'accept_part_time', 'allowed', true),
                                 jsonb_build_object('key', 'accept_both', 'allowed', true), jsonb_build_object('key', 'not_stated', 'allowed', true),
                                 jsonb_build_object('key', 'dismiss', 'allowed', true)))
    from pipeline.boost_study_load_reviews r join catalogue.courses c on c.id = r.course_id
   where r.id::text = p_ref and r.status = 'open'
$function$;
revoke all on function security.layer4_boost_study_load_inbox_detail_v1(text) from public, anon, authenticated;

create or replace function security.layer4_boost_study_load_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare r pipeline.boost_study_load_reviews; v_val text; v_status text; v_n int := 0; v_ev bigint; v_returns text;
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Layer 4 Inbox: ' || p_choice);
begin
  select * into r from pipeline.boost_study_load_reviews where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'request', 'This reading has already been settled; refresh the Inbox.');
  end if;
  v_val := case p_choice when 'accept_full_time' then 'full_time' when 'accept_part_time' then 'part_time' when 'accept_both' then 'both' end;
  if v_val is not null then
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')) then
      return jsonb_build_object('ok', false, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'request', 'A manual lock holds this course''s study load; it was not changed.');
    end if;
    update catalogue.courses set study_load = v_val, study_load_source = 'manual', study_load_evidence_id = r.evidence_id
     where id = r.course_id and study_load is null;
    get diagnostics v_n = row_count;
    v_status := case when v_n = 1 then 'accepted' else 'superseded' end;
    v_returns := case when v_n = 1 then 'The course''s study load is now ' || replace(v_val, '_', '-') || '.' else 'The course already had a study load; it was not changed.' end;
  elsif p_choice = 'not_stated' then
    v_status := 'not_stated'; v_returns := 'Recorded as not stated on the page.';
  elsif p_choice = 'dismiss' then
    v_status := 'dismissed'; v_returns := 'The reading is dismissed; nothing changed.';
  else
    raise exception 'unknown choice %', p_choice using errcode = '22023';
  end if;
  update pipeline.boost_study_load_reviews set status = v_status, decision = p_choice, decided_value = case when v_n = 1 then v_val end,
         reason = v_reason, decided_by = auth.uid(), decided_at = now() where id = r.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'boost_study_load:' || p_ref, jsonb_build_object('kind', 'boost_study_load', 'ref', p_ref, 'choice', p_choice, 'value', v_val, 'reason', v_reason,
          'course_id', r.course_id, 'provider_id', r.provider_id, 'evidence_id', r.evidence_id, 'filled', v_n = 1), auth.uid()) returning id into v_ev;
  perform security.boost_study_load_review_feed_v1();
  return jsonb_build_object('ok', true, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'returns', v_returns);
end $function$;
revoke all on function security.layer4_boost_study_load_inbox_decide_v1(text, text, text, text) from public, anon, authenticated;

insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('boost_study_load', 'kind', 'security.layer4_boost_study_load_kind_v1()', 'security.layer4_boost_study_load_inbox_counts_v1()', 'security.layer4_boost_study_load_inbox_page_v1(jsonb)',
        'security.layer4_boost_study_load_inbox_detail_v1(text)', 'security.layer4_boost_study_load_inbox_decide_v1(text,text,text,text)', true,
        'Boost (cf247_boost_study_load_layer4_review)', 'Refused Boost study-load readings where the page has study-load text (Platform Admin 18 Nov 2026 07:08 decision 4)')
on conflict (kind, mode) do nothing;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.boost_study_load_reviews', 'Layer 4', 'Boost', 'Refused Boost study-load readings sent to Layer 4 › Inbox and their decisions', 'active', '{}', '20261118111500'),
  ('function', 'security.boost_study_load_review_feed_v1', 'Layer 4', 'Boost', 'Opens Layer 4 reviews for refused Boost study-load readings up to the cap', 'active', '{}', '20261118111500'),
  ('function', 'security.layer4_boost_study_load_inbox_decide_v1', 'Layer 4', 'Boost', 'Layer 4 Inbox decision on a refused Boost study-load reading', 'active', '{}', '20261118111500')
on conflict do nothing;

-- 5. Backfill: today's refused readings
select security.boost_study_load_review_feed_v1();

-- 6. Post-checks
do $c$
declare v_eligible int; v_open int; v_hooks jsonb;
begin
  select count(distinct s.entity_id) into v_eligible from pipeline.boost_inbound_staging s join catalogue.courses c on c.id = s.entity_id
   where s.lane = 'study_load' and s.worker_status = 'rejected' and c.study_load is null
     and s.prompt_version = (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' order by q.prompt_version desc limit 1)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'));
  select count(*) into v_open from pipeline.boost_study_load_reviews where status = 'open';
  if v_open <> least(v_eligible, security.pipeline_num_v1('boost.layer4_open_max', 400)::int) then raise exception 'post-check: % reviews open for % eligible readings', v_open, v_eligible; end if;
  if exists (select 1 from pipeline.boost_study_load_reviews r join pipeline.boost_inbound_staging s on s.id = r.staging_id where s.worker_status <> 'rejected') then
    raise exception 'post-check: a reading that was not refused was sent to review';
  end if;
  v_hooks := security.layer4_inbox_hooks_v1();
  if exists (select 1 from jsonb_array_elements(coalesce(v_hooks->'failed', '[]'::jsonb) || coalesce(v_hooks->'missing', '[]'::jsonb)) x where x->>'id' like 'boost_study_load%') then
    raise exception 'post-check: the Inbox does not accept kind boost_study_load: %', v_hooks;
  end if;
  if (security.layer4_boost_study_load_inbox_counts_v1()->>'n')::int <> v_open then raise exception 'post-check: the Inbox count is not the open reviews'; end if;
  raise notice 'Boost study load to Layer 4: % reviews open of % eligible readings', v_open, v_eligible;
end $c$;
