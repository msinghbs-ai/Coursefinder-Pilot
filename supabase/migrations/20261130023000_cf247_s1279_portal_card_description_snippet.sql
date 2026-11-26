-- CF-247 s1279 (S2-Data-Gaps; Atlas brief 26 Nov 2026 22:25 AEDT, Platform Admin live UAT of the StudySearch Portal): a short course description on the search cards.
-- Version above the live head 20261130010000 (s1277). Read-only: the cards function gains one key; nothing is written to a course.
-- Measured live 26 Nov 2026 (rolled-back reads): 16,112 of 44,743 courses hold a description (S1-Data-Gaps backfills the rest and owns the writers; this change
-- only reads catalogue.courses.description). 13,345 of them are longer than 220 characters; 11 carry the entity &#039; (an apostrophe).
-- catalogue.portal_course_cards_v1 (read by catalogue.portal_course_search_v1 and public.portal_course_search_v1) returns description_snippet: the description with
-- its white space collapsed and &#039; &amp; &quot; read as the characters they stand for, cut at the last whole word within the card length with an ellipsis, or
-- null when the course holds no description (the Portal then shows nothing, never "Not recorded"). The length is the setting portal.card_description_chars (G2).
-- The cards function is changed by one anchored edit of its live text, applied only if its live body is the one read back (md5) and the anchor is found once.
-- The search function, Entry Requirements, saved courses and course details are not touched. Not the consumer API (G3 checked).
-- G1: no job. G2: the length is a setting. Locks untouched. Nothing dropped. No AI call. US$0.
-- Replaces: the s1275 body of catalogue.portal_course_cards_v1 (one key added).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

create temp table s1279_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb)'::regprocedure) <> '2880886cc930e17946614e76057afe11' then
    raise exception 'pre-check: the cards function is not the s1275 body this change was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('portal', 'card_description_chars', 'Course cards: description length',
        'How many characters of a course''s description a search card shows (cut at the last whole word, with an ellipsis). A card whose course holds no description shows none.',
        'number', to_jsonb(220), 80, 400, 'characters', 6171, 'Portal', 'public.portal_course_search_v1 (cards: description_snippet)',
        'CF-247 s1279 (Atlas brief 26 Nov 2026 22:25 AEDT): concise description on the Portal cards')
on conflict do nothing;

-- the one wording of a card's description: tidy, then cut at a whole word
create or replace function portal.description_snippet_v1(p_text text)
returns text language sql stable set search_path = '' as $function$
  select case when t = '' then null
              when char_length(t) <= n then t
              else rtrim(regexp_replace(left(t, n), '\s+\S*$', ''), ' ,;:.-') || '…' end
    from (select btrim(regexp_replace(replace(replace(replace(coalesce(p_text, ''), '&#039;', ''''), '&amp;', '&'), '&quot;', '"'), '\s+', ' ', 'g')) t,
                 least(greatest(coalesce(security.portal_setting_v1('card_description_chars'), 220), 80), 400) n) s  -- fixed: the setting's own default and range
$function$;
comment on function portal.description_snippet_v1(text) is 'CF-247 s1279: the short description a Portal search card shows: white space collapsed, a few HTML entities read, cut at the last whole word within portal.card_description_chars with an ellipsis; null when no description is held.';
revoke all on function portal.description_snippet_v1(text) from public, anon, authenticated;

create function pg_temp.s1279_patch(p_def text, p_old text, p_new text, p_expect integer) returns text language plpgsql as $p$
begin
  if (length(p_def) - length(replace(p_def, p_old, ''))) <> length(p_old) * p_expect then
    raise exception 'guard: anchor "%" is not present exactly % time(s); rebase and re-verify', left(p_old, 60), p_expect;
  end if;
  return replace(p_def, p_old, p_new);
end $p$;

do $f$
declare v_def text; v_fn regprocedure := 'catalogue.portal_course_cards_v1(uuid[], text[], numeric, jsonb)'::regprocedure;
begin
  v_def := pg_get_functiondef(v_fn);
  v_def := pg_temp.s1279_patch(v_def,
    $a$      'level', sl.name, 'country_code', d.country_code,
$a$,
    $b$      'level', sl.name, 'country_code', d.country_code,
      'description_snippet', portal.description_snippet_v1(c.description),  -- s1279: a short description, null when none is held
$b$, 1);
  execute v_def;
  if strpos(pg_get_functiondef(v_fn), 'portal.description_snippet_v1') = 0 then raise exception 'post-check: the cards edit was not applied'; end if;
end $f$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; a_course uuid; b_course uuid; n_with integer; n_without integer;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1279_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1279_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'portal.description_snippet_v1(text)', 'execute') or has_function_privilege('authenticated', 'portal.description_snippet_v1(text)', 'execute') then
    raise exception 'post-check: portal.description_snippet_v1 must not be callable from outside';
  end if;
  -- the wording
  if portal.description_snippet_v1(null) is not null or portal.description_snippet_v1('   ') is not null then raise exception 'post-check: an empty description must give null'; end if;
  if portal.description_snippet_v1(E'It\r\n  is  a   course') <> 'It is a course' then raise exception 'post-check: white space is not collapsed'; end if;
  if portal.description_snippet_v1('people&#039;s lives &amp; health') <> 'people''s lives & health' then raise exception 'post-check: entities are not read'; end if;
  x := to_jsonb(portal.description_snippet_v1(repeat('word ', 200)));
  if char_length(x #>> '{}') > security.portal_setting_v1('card_description_chars') + 1 or right(x #>> '{}', 1) <> '…' or (x #>> '{}') like '%wor…' then
    raise exception 'post-check: a long description is not cut at a whole word with an ellipsis: %', x;
  end if;
  -- the cards: a course with a description carries a snippet, one without carries null (and the key is present)
  create temp table if not exists portal_search_rank (course_id uuid primary key, pos integer, fts real, sim real) on commit drop;  -- the cards read the search's rank table
  select d.course_id into a_course from search.course_documents d join catalogue.courses c on c.id = d.course_id
   where nullif(btrim(c.description), '') is not null and char_length(c.description) > 400 order by d.course_id limit 1;
  select d.course_id into b_course from search.course_documents d join catalogue.courses c on c.id = d.course_id
   where nullif(btrim(c.description), '') is null order by d.course_id limit 1;
  if a_course is not null then
    x := catalogue.portal_course_cards_v1(array[a_course], '{}'::text[], 1, jsonb_build_object('states', '[]'::jsonb)) -> 0;
    if nullif(x->>'description_snippet', '') is null or char_length(x->>'description_snippet') > security.portal_setting_v1('card_description_chars') + 1 then
      raise exception 'post-check: a course with a description has no usable snippet: %', x;
    end if;
  end if;
  if b_course is not null then
    x := catalogue.portal_course_cards_v1(array[b_course], '{}'::text[], 1, jsonb_build_object('states', '[]'::jsonb)) -> 0;
    if not (x ? 'description_snippet') or x->'description_snippet' <> 'null'::jsonb then raise exception 'post-check: a course with no description must carry a null snippet: %', x; end if;
  end if;
end $post$;
