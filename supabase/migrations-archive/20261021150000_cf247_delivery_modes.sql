-- CF-247 (21 Oct 2026). Platform Admin 08:42 on "blended" against "on campus and online": "this should be University abbreviation how do
-- they define and might be different for different univ. recommended choice and context where is this been seen"; choice "Keep two, fix
-- reader (Recommended)".
-- Found: course pages use the words two ways. A choice of modes ("On campus, Online, Blended": Torrens, Collarts, Canberra, ACPE, Royal
-- Roads, UVic) is on_campus_and_online; a mix inside one course ("14 hours face to face and 6 hours online", "67% face-to-face / 33%
-- online", "online with on-campus block modules": Rockford, Entrepreneur Education, Berkeley, SGSCC, Abbey, SIT) is blended. The old reader
-- took the word "blended" first, so a list of options became blended. Some universities use their own wording (UNSW "Face-to-face
-- (includes blended)" is taught on campus).
--   1 security.enrich_parse_delivery_v1 (whole): shares or hours each way, or online with block, onsite or residential weeks, are blended; a
--     list of two or more modes (split at commas, bars, slashes, semicolons and "or") is on_campus_and_online; a single mode is that mode;
--     online that the page says is for domestic students only is left out (international students study on campus).
--   2 pipeline.delivery_wording: a university's (or every university's) own phrase and the mode it means, applied before the reader;
--     PIM Admin and above add or switch off phrases on Coverage › Attributes, with a reason. Seeded: UNSW "Face-to-face (includes blended)"
--     = on campus. security.delivery_mode_read_v1(text, provider) applies them, then the reader.
--   3 Enrich fields (security.enrich_fields_slice_v1, one line) and the cross-check (security.field_crosscheck_v1, whole) read delivery with
--     security.delivery_mode_read_v1; an open cross-check difference that no longer differs closes itself. The AI prompt (coverage-sweep
--     worker v0.34.2) gets the same two meanings.
--   4 public.admin_field_coverage: 'wording_list', 'wording_set', 'wording_off' (two lines added, md5-guarded).
-- Held course values are not changed.
-- Replaces: security.enrich_parse_delivery_v1 (whole); security.field_crosscheck_v1 (whole); security.enrich_fields_slice_v1 (one
--   line); public.admin_field_coverage (three actions)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"security.enrich_parse_delivery_v1(text)": "947815ac95487a730566eb84585b5455",
                              "security.field_crosscheck_v1()": "33e8c34471da416f78e39ae6b600a9d9"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 The reader -----------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.enrich_parse_delivery_v1(p text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare t text := lower(coalesce(p, '')); v_dom boolean; tok text; v_modes text[] := '{}'; v_m text;
begin
  if btrim(t) = '' then return null; end if;
  -- online that is for domestic students only does not apply to international students
  v_dom := t ~ '(online|distance)[^.]{0,80}(only|available)[^.]{0,40}(domestic|non[- ]?international|australian|new zealand|canadian|local)'
        or t ~ 'not (available|offered) (to|for) international';
  -- a mix inside one course: a share or hours each way
  if (t ~ '\d+(\.\d+)?\s*%[^|;]{0,40}(face|campus|class|person|onsite|on-site)' or t ~ '(face|campus|class|person)[^|;%]{0,20}\d+(\.\d+)?\s*%')
     and t ~ '(online|distance|remote|virtual)' then return 'blended'; end if;
  if t ~ '\d+(\.\d+)?\s*(hours?|hrs?)' and t ~ '(face|campus|class|person|onsite)' and t ~ '(online|distance|remote|virtual)' then return 'blended'; end if;
  -- otherwise each listed item is one mode; two or more different modes are a choice
  foreach tok in array regexp_split_to_array(t, '\s*(,|\||/|;|\mor\M)\s*') loop
    v_m := case
      when tok ~ '(blended|hybrid|mixed[- ]mode|multi[- ]?modal)' then 'blended'
      when tok ~ '(online|distance|remote)[^.]{0,25}(with|plus|and)[^.]{0,25}(face[- ]to[- ]face|on[- ]?campus|onsite|on-site|in[- ]person|block|residential|intensive)' then 'blended'
      when tok ~ '(face[- ]to[- ]face|on[- ]?campus)\s*\+\s*online' then 'blended'
      when tok ~ '(on[- ]?campus|\mcampus\M|face[- ]to[- ]face|in[- ]class|in[- ]person|classroom|internal)' and tok ~ '(online|distance|external|remote)' and not v_dom then 'both'
      when tok ~ '(on[- ]?campus|\mcampus\M|face[- ]to[- ]face|in[- ]class|in[- ]person|classroom|internal)' then 'on_campus'
      when tok ~ '(100\s*%\s*online|fully online|online|distance|external|remote)' and not v_dom then 'online'
      else null end;
    if v_m is not null and not v_m = any (v_modes) then v_modes := v_modes || v_m; end if;
  end loop;
  if cardinality(v_modes) = 0 then return case when v_dom and t ~ '(on[- ]?campus|face[- ]to[- ]face|in[- ]class|in[- ]person)' then 'on_campus' end; end if;
  if cardinality(v_modes) > 1 or v_modes[1] = 'both' then return 'on_campus_and_online'; end if;
  return v_modes[1];
end $function$;

-- 2 A university's own wording ------------------------------------------------------------------------------------------------------
create table if not exists pipeline.delivery_wording (
  id bigserial primary key,
  provider_id uuid references catalogue.providers(id) on delete cascade,
  phrase text not null,
  mode text not null check (mode in ('on_campus', 'online', 'blended', 'on_campus_and_online')),
  active boolean not null default true,
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now(),
  unique nulls not distinct (provider_id, phrase));
alter table pipeline.delivery_wording enable row level security;
comment on table pipeline.delivery_wording is 'CF-247 21 Oct 2026: a university''s own delivery wording (a phrase, matched without regard to case) and the mode it means; provider_id null applies to every university. Applied before the delivery reader (security.delivery_mode_read_v1). Changed on Coverage › Attributes by a PIM Admin or above, with a reason.';
insert into pipeline.delivery_wording(provider_id, phrase, mode, reason)
values ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'Face-to-face (includes blended)', 'on_campus', 'CF-247 21 Oct 2026: UNSW labels programs taught on campus "Face-to-face (includes blended)" (315 cross-check differences); Platform Admin "Keep two, fix reader"')
on conflict do nothing;

create or replace function security.delivery_mode_read_v1(p text, p_provider uuid)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare t text := coalesce(p, ''); w record;
begin
  if btrim(t) = '' then return null; end if;
  -- the university's own phrases first, then phrases for every university; each becomes the plain words of its mode
  for w in select d.phrase, d.mode from pipeline.delivery_wording d where d.active and (d.provider_id = p_provider or d.provider_id is null)
            order by (d.provider_id is null), length(d.phrase) desc loop
    t := regexp_replace(t, regexp_replace(w.phrase, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'),
                        case w.mode when 'on_campus' then 'on campus' when 'online' then 'online' when 'blended' then 'blended' else 'on campus or online' end, 'gi');
  end loop;
  return security.enrich_parse_delivery_v1(t);
end $function$;
revoke execute on function security.delivery_mode_read_v1(text, uuid) from public, anon, authenticated;

-- 3 Enrich fields and the cross-check read delivery with the wording ----------------------------------------------------------------
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '3002e0974f8e3abaac0bd2f6a9f61e79', array[
  array[$x$security.enrich_parse_delivery_v1(left(v_txt, 120))$x$, $x$security.delivery_mode_read_v1(left(v_txt, 300), it.provider_id)$x$]]);

create or replace function security.field_crosscheck_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_new int; v_closed int; v_tol numeric := security.pipeline_num_v1('crosscheck.duration_tolerance_pct', 10);
begin
  -- the latest adapter reading of each course page (the same reading Enrich fields uses), compared with the held value
  drop table if exists _cc;
  create temp table _cc on commit drop as
  select y.id, y.provider_id, y.field, y.held_value, y.page_value, 'adapter'::text source, left(y.txt, 300) quote, y.ev
    from (
      select x.id, x.provider_id, f.field, f.held_value, f.page_value, f.txt, x.ev, f.differs
        from (select c.id, c.provider_id, c.duration_value, c.duration_unit, c.study_level_id, c.delivery_mode,
                     (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = c.id) ev,
                     coalesce((select r.fields->'extra' from pipeline.uni_adapter_results r where r.course_id = c.id order by r.at desc limit 1), '{}'::jsonb)
                     || coalesce((select g.candidates->'adapter_extra' from pipeline.coverage_course_pages g
                                   where g.course_id = c.id and g.read_status = 'read' and g.identity_basis is not null), '{}'::jsonb) ex
                from catalogue.courses c where c.lifecycle_status = 'active') x
        cross join lateral (
          select 'duration' field, jsonb_build_object('value', x.duration_value, 'unit', x.duration_unit) held_value, d page_value, x.ex->>'duration' txt,
                 abs(w1 - w2) * 100 > v_tol * greatest(w1, w2) differs
            from (select security.enrich_parse_duration_v1(nullif(btrim(x.ex->>'duration'), '')) d) p,
                 lateral (select case x.duration_unit when 'years' then x.duration_value * 52 when 'months' then x.duration_value * 52 / 12 when 'weeks' then x.duration_value end w1,
                                 case p.d->>'unit' when 'years' then (p.d->>'value')::numeric * 52 when 'months' then (p.d->>'value')::numeric * 52 / 12 when 'weeks' then (p.d->>'value')::numeric end w2) w
           where p.d is not null and x.duration_value is not null and w.w1 > 0 and w.w2 > 0
             and coalesce(x.ex->>'duration', '') !~* '\d\s*(-|–|to|or)\s*\d'
          union all
          select 'level', jsonb_build_object('level_id', x.study_level_id, 'name', (select l.name from ref.study_levels l where l.id = x.study_level_id)),
                 jsonb_build_object('level_id', p.l, 'name', (select l.name from ref.study_levels l where l.id = p.l)), x.ex->>'study_level', p.l <> x.study_level_id
            from (select security.enrich_parse_level_v1(nullif(btrim(x.ex->>'study_level'), '')) l) p
           where p.l is not null and x.study_level_id is not null
          union all
          select 'delivery', jsonb_build_object('mode', x.delivery_mode), jsonb_build_object('mode', p.m), x.ex->>'mode', p.m <> x.delivery_mode
            from (select security.delivery_mode_read_v1(left(nullif(btrim(x.ex->>'mode'), ''), 300), x.provider_id) m) p
           where p.m is not null and nullif(btrim(x.delivery_mode), '') is not null) f
       where x.ex <> '{}'::jsonb) y
   where y.differs
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = y.id and l.field in (y.field, 'all'))
  ;
  insert into pipeline.field_crosscheck_findings(course_id, provider_id, field, held_value, page_value, source, quote, evidence_id)
  select c.id, c.provider_id, c.field, c.held_value, c.page_value, c.source, c.quote, c.ev from _cc c
  on conflict (course_id, field, page_value) do nothing;
  get diagnostics v_new = row_count;
  -- CF-247 21 Oct 2026 (delivery reader): an open finding that no longer differs (the held value or the page reading changed) closes itself
  update pipeline.field_crosscheck_findings f set state = 'resolved', decided_at = now(), note = 'no longer differs: the held value or the page reading changed'
   where f.state = 'open' and not exists (select 1 from _cc c where c.id = f.course_id and c.field = f.field and c.page_value = f.page_value);
  get diagnostics v_closed = row_count;
  return jsonb_build_object('new', v_new, 'resolved', v_closed, 'open', (select count(*) from pipeline.field_crosscheck_findings where state = 'open'));
end $function$;
revoke execute on function security.field_crosscheck_v1() from public, anon, authenticated;

-- 4 Wording on Coverage ------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.admin_field_coverage(text,jsonb)', 'd505decd0631f0a5adf95dd8118ba709', array[
  array[$x$  elsif p_action = 'run_now' then$x$,
        $x$  elsif p_action = 'wording_list' then
    -- CF-247 21 Oct 2026: a university's own delivery wording (Platform Admin "Keep two, fix reader")
    return jsonb_build_object('items', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'provider_id', d.provider_id,
               'provider', coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = d.provider_id), 'Every university'),
               'phrase', d.phrase, 'mode', d.mode, 'active', d.active, 'reason', d.reason, 'set_at', d.set_at) order by d.active desc, d.set_at desc), '[]'::jsonb)
             from pipeline.delivery_wording d), 'can_edit', v_rank >= 5);
  elsif p_action in ('wording_set', 'wording_off') then
    if v_rank < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the phrase)'; end if;
    if p_action = 'wording_off' then
      update pipeline.delivery_wording set active = false, reason = v_reason, set_by = auth.uid(), set_at = now() where id = (p_args->>'id')::bigint;
    else
      if length(btrim(coalesce(p_args->>'phrase', ''))) < 3 then raise exception 'give the phrase as the page writes it'; end if;
      insert into pipeline.delivery_wording(provider_id, phrase, mode, reason, set_by)
      values (nullif(p_args->>'provider_id', '')::uuid, btrim(p_args->>'phrase'), p_args->>'mode', v_reason, auth.uid())
      on conflict (provider_id, phrase) do update set mode = excluded.mode, active = true, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('delivery_wording', p_action, coalesce(p_args->>'phrase', p_args->>'id'), jsonb_build_object('mode', p_args->>'mode', 'provider_id', p_args->>'provider_id', 'reason', v_reason), auth.uid());
    return public.admin_field_coverage('wording_list', '{}'::jsonb) || jsonb_build_object('crosscheck', security.field_crosscheck_v1());
  elsif p_action = 'run_now' then$x$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.delivery_wording', 'Layer 2', 'A university''s own delivery wording and the mode it means', 'active', '20261021150000'),
 ('function', 'security.delivery_mode_read_v1', 'Layer 2', 'Reads a delivery mode with the university''s own wording first', 'active', '20261021150000')
on conflict (kind, name) do nothing;

select security.field_crosscheck_v1();
