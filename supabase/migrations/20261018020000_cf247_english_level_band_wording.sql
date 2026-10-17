-- CF-247 Decision 265 follow-up (18 Oct 2026), from the first companion run (207 Melbourne entry requirement pages read): the handbook also writes
-- "performance band 7.0" (the same as band 7) and "performance band 7+" (an IELTS overall of 7.0 under the older wording). The level name now
-- reads "7.0" as "7", the Melbourne companion pattern takes "7+", and the proposed Melbourne policy gives "band 7+" the overall scores of the
-- levels with IELTS 7.0 overall (no skill minimums, as for the other bands). Pages read without a level are read again with the new pattern.
-- Replaces: security.english_level_key (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.english_level_key(text)'::regprocedure)) <> 'ed73353d0ca703f59f1cd74f46f830ee' then
    raise exception 'live security.english_level_key differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.english_level_key(p text)
returns text language sql immutable set search_path = '' as $function$
  select nullif(btrim(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p, '')), '[“”"''’‘`:;,()]', ' ', 'g'), '\s+', ' ', 'g'), '(\d)\.0(?![0-9])', '\1', 'g')), '')
$function$;

update pipeline.uni_adapter_companions
   set patterns = jsonb_build_object('english_level', '((?:band [6-8](?:\.[05])?\+?(?= is required))|(?:Level [1-5][ab]?(?= English scores are required)))'),
       reason = reason || ' 18 Oct 2026: "band 7+" read too.', updated_at = now()
 where provider_id = 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2';

update pipeline.provider_policy_proposals
   set proposal = jsonb_set(jsonb_set(proposal, '{levels,band 7+}', proposal->'levels'->'band 7'), '{level_names,band 7+}', to_jsonb('performance band 7+'::text)),
       updated_at = now()
 where id = 'a4ecfd06-da91-4c37-a51b-97e9626bb73e' and status = 'proposed';

update pipeline.course_companion_pages set next_read_at = now(), updated_at = now()
 where provider_id = 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2' and status = 'read' and coalesce("values"->>'english_level', '') = '';

do $post$
begin
  if security.english_level_key('Band 7.0') <> 'band 7' or security.english_level_key('band 7+') <> 'band 7+' or security.english_level_key('Band 6.5') <> 'band 6.5'
     or security.english_level_key('”Band 3a”') <> 'band 3a' or security.english_level_key('Level 10') <> 'level 10' then
    raise exception 'Decision 265 follow-up post-check: level key';
  end if;
  if not exists (select 1 from pipeline.provider_policy_proposals where id = 'a4ecfd06-da91-4c37-a51b-97e9626bb73e' and proposal->'levels' ? 'band 7+') then
    raise exception 'Decision 265 follow-up post-check: band 7+';
  end if;
end $post$;
