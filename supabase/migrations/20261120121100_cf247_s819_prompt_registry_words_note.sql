-- CF-247 S1-RM-Design (Platform Admin 20 Nov 2026 10:21, s819): the provider description worker now states the live promotional word list to the
-- model in the user message ("Words not allowed: …", from the setting enrich.course_description_marketing_words, the same list as pdesc.superlatives),
-- so the AI avoids those words up front. The system prompt (version 6) is unchanged. The prompt registry (pipeline.prompt_templates, shadow only:
-- nothing reads it, spec s553) keeps the user message in step: the v6 row is retired and v7 is registered with the same system text and a user
-- template that declares one more variable, words_note.
-- G1: no job. G2: the list is the existing setting. G3: no consumer API object; security.consumer_api_check_v1() is read before and after (75, 48).
-- Replaces: registry row provider_description v6 (retired, kept)
-- Retires: nothing is dropped or deleted
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

do $r$
begin
  if exists (select 1 from pipeline.prompt_templates where service_code = 'provider_description' and version = 'v7') then raise notice 'registry v7 exists: not added again'; return; end if;
  if not exists (select 1 from pipeline.prompt_templates where service_code = 'provider_description' and version = 'v6' and status = 'shadow') then
    raise exception 'guard: registry row provider_description v6 is not the shadow row';
  end if;
  insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, note)
  select 'provider_description', 'v7', t.system_text, t.system_sha256,
         E'Provider: {{provider}}\nPage: {{url}}\n{{length_note}}{{words_note}}\nPage text:\n<untrusted_source_text>\n{{page_text}}\n</untrusted_source_text>',
         array_append(t.variables, 'words_note'), t.answer_schema, t.pinned_models,
         'pipeline.provider_description_prompts version 6 (system text unchanged)',
         'user template: description.ts promptRequest (s819: wordsNote(words), the setting enrich.course_description_marketing_words; page text fenced by fenceSourceText); length_note is lengthNote(length)'
    from pipeline.prompt_templates t where t.service_code = 'provider_description' and t.version = 'v6';
  update pipeline.prompt_templates set status = 'retired', note = coalesce(note || ' ', '') || 'Retired 20 Nov 2026: the user message gained the words note (v7).'
   where service_code = 'provider_description' and version = 'v6';
end $r$;

-- post-check: v7 renders with every variable, and refuses a missing one
do $$
declare v text; v_failed boolean := false;
begin
  v := security.prompt_render_v1('provider_description', 'v7', jsonb_build_object('provider', 'P', 'url', 'U', 'length_note', 'L\n', 'words_note', 'W\n', 'page_text', 'T'));
  if position('<untrusted_source_text>' in v) = 0 or position('W' in v) = 0 then raise exception 'post-check: v7 render %', v; end if;
  begin perform security.prompt_render_v1('provider_description', 'v7', jsonb_build_object('provider', 'P', 'url', 'U', 'length_note', 'L', 'page_text', 'T'));
  exception when others then v_failed := true; end;
  if not v_failed then raise exception 'post-check: a missing words_note did not fail'; end if;
  if (select count(*) from pipeline.prompt_templates where service_code = 'provider_description' and status = 'shadow') <> 1 then raise exception 'post-check: more than one shadow row'; end if;
end $$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API moved during this change: %', v;
  end if;
end $g$;
