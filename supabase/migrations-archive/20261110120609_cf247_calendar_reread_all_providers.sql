-- CF-247 F-INT calendar re-read for every eligible provider, not only the 5 Nov 2026 pilot (Platform Admin decision 10 Nov 2026 ~23:40, "Re-read and column fix first";
-- Decision 273 supersedes R2's top-10 scope; design reference Decisions 270a, 273, 274).
-- ROOT CAUSE (live, SELECT only, 10 Nov 2026): security.calendar_reread_relevant_v1() counts only the providers of security.intake_ui_scopes_v1() (the 10 pilot universities of
--   5 Nov 2026). The calendar re-read (job calendar-reread, public.svc_calendar_reread_next_v2) therefore set every other provider's stored calendars aside as "not needed: no intake
--   row of this university in the intake scope misses a date", although they miss dates: Deakin, Torrens, Curtin, La Trobe, QUT and UWA calendars were never read by the current reader
--   (calendar-v2.1). 337 stored main-teaching calendar copies at 136 providers are set aside this way; 500 providers in calendar.countries have 29,026 intake rows missing a year or start.
-- WHAT THIS CHANGES (no new job, table or setting; nothing is switched on or off; md5-guarded):
--   1 security.calendar_reread_relevant_v2() NEW, read-only: the same count for every provider in calendar.countries (AU, NZ, CA), not only the pilot scope.
--   2 public.svc_calendar_reread_next_v2(integer,text): reads v2 instead of v1 (one call). Its existing "needed again" step then wakes the set-aside calendars of those providers;
--     the hourly job reads them at its existing size (batch.calendar_reread) with the existing reader and AI guards. Stored copies only: no Firecrawl credit is spent.
--   security.calendar_reread_relevant_v1() is unchanged and still bounds the Firecrawl paths (public.svc_calendar_refresh_v1) until Decision 273's safeguards are released.
--   A new reading still goes through the calendar qualifier and approval before it can fill a date; no qualifier rule, threshold, blocked or excluded word changes.
-- Cost: about US$0.002 of AI per document read (live average of calendar reads), about US$0.72 for the 337 documents; no Firecrawl.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   public.svc_calendar_reread_next_v2(integer,text) 755ef3b77c797c89fa2caa215e33d4ee -> 6bede79de2f656b4bc9de6ea783696b6
--   security.calendar_reread_relevant_v2() (new) -> 42e2c5a73dbfbf6cacc333ffb92a9b61
-- The edit is guarded: the migration stops, and nothing is applied, if the live body is neither the one it replaces nor the one it writes; applying it twice changes nothing.
-- The earlier text is restored by supabase/held/calendar_reread_all_providers_forward_recovery.sql.
-- Consumer API (G3): not touched. No operational value is written into code (G2): countries are calendar.countries, the run size is batch.calendar_reread. No job is added (G1).
-- Tested: tests/fixtures/calendar-reread-all-providers/run.sh (isolated PostgreSQL; never a Supabase project).
-- Replaces: in public.svc_calendar_reread_next_v2, the pilot-scope relevance (security.calendar_reread_relevant_v1, kept for the Firecrawl refresh path)
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_calendar_reread_next_v2(integer,text)'), ('security.calendar_reread_relevant_v1()'), ('security.toolset_setting(text,text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('ref.countries') is null or to_regclass('pipeline.calendar_reread_state') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- 1 the relevance for every provider in calendar.countries (read only; applying again writes the same text)
create or replace function security.calendar_reread_relevant_v2() returns table(provider_id uuid, missing integer)
language sql stable security definer set search_path to '' as $f$
  select c.provider_id, count(*)::int
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
    join catalogue.providers pv on pv.id = c.provider_id join ref.countries k on k.id = pv.country_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.start_date is null or i.intake_year is null)
     and k.iso_alpha2 in (select jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'calendar.countries')) = 'array'
                                                                 then security.toolset_setting('pipeline', 'calendar.countries') else '[]'::jsonb end))
   group by c.provider_id
$f$;
comment on function security.calendar_reread_relevant_v2() is 'CF-247 F-INT (Platform Admin 10 Nov 2026; Decisions 273, 274): every provider in calendar.countries whose active intake rows still miss a year or start date, with how many. The calendar re-read of stored copies reads their calendars (no Firecrawl). security.calendar_reread_relevant_v1 (the 5 Nov pilot scope) still bounds the Firecrawl refresh until Decision 273''s safeguards.';
revoke all on function security.calendar_reread_relevant_v2() from public, anon, authenticated;

-- 2 the re-read picker reads v2 (md5-guarded edit, one call)
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('public.svc_calendar_reread_next_v2(integer,text)', '755ef3b77c797c89fa2caa215e33d4ee', '6bede79de2f656b4bc9de6ea783696b6',
  array[$o$from security.calendar_reread_relevant_v1() x;$o$], array[$n$from security.calendar_reread_relevant_v2() x;$n$]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.calendar_reread_relevant_v2', 'Platform', 'F-INT: providers in calendar.countries whose intake rows miss a date; bounds the calendar re-read of stored copies (no Firecrawl)', 'active', '{}', 'cf247_calendar_reread_all_providers')
on conflict do nothing;

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'public.svc_calendar_reread_next_v2(integer,text)'::regprocedure)) <> '6bede79de2f656b4bc9de6ea783696b6' then raise exception 'post-check: public.svc_calendar_reread_next_v2 does not have the recorded body md5'; end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.calendar_reread_relevant_v2()'::regprocedure)) <> '42e2c5a73dbfbf6cacc333ffb92a9b61' then raise exception 'post-check: security.calendar_reread_relevant_v2 does not have the recorded body md5'; end if;
end $post$;
