-- CF-247 F-PDESC follow-up to 20261112010000 (Platform Admin 11 Nov 2026 17:39 AEDT: "deliver according to plan"; goal 14:51 "prompt based ...
-- rather than stringent rules that keeps failing").
--
-- Finding (live, 11 Nov 2026 17:42 AEDT, the first 40 minutes of prompt p3): 94 AI answers, 55 passed. Two holds were the platform's own fault:
--   * first_sentence_no_name (9): the check wanted the whole registered name, so "The Institute of Management Learning (IML) is ..." failed
--     against "INSTITUTE OF MANAGEMENT LEARNING PTY LTD"; likewise "... Limited", "&" for "and", and a comma list of trading names.
--   * quote_not_on_page (9): the model shortened a page passage with "..." or joined two, so the passage was no longer on the page.
--
-- What this does:
--   1 security.pdesc_name_forms_v1(text[]): the forms a provider's name is written in: each comma-separated name, without a parenthesised
--     part, without a legal suffix (Pty Ltd, Proprietary Limited, Limited, Ltd, Inc, Incorporated, LLC), with "&" read as "and". The first
--     sentence check in security.provider_description_validate_v1 accepts any of them (still a whole-word match on the provider's own name).
--   2 Prompt version 4 = version 3 plus one line on copying each passage whole (never shortened, never joined, no "..."). Added only while
--     version 3 is the active prompt (a version the Platform Admin saved on screen is never replaced). Being a new version, self-heal (c)
--     reads each held answer again once with it (pdesc.prompt_reoffer_rules), so the held p3 answers clear by themselves.
-- Consumer API (G3): not touched. Nothing is dropped or deleted. No description is written by applying this migration.
-- Forward recovery: the Platform Admin saves version 3's text again on Models & services › AI & OpenRouter (a new version); the name forms
-- only widen which spelling of the provider's own name counts.
-- Replaces: prompt version 3 as the active prompt (retired, kept); the whole-name-only first sentence check.
-- Retires: nothing (prompt version 3 stays in the table as retired history).

do $g$
begin
  if md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) <> '250c16ac119f7e16f48487dcc977970b' then raise exception 'validate_v1 is not the reviewed body'; end if;
end $g$;

create or replace function pg_temp.pdesc_swap(p_fn regprocedure, p_old text, p_new text) returns void language plpgsql as $s$
declare d text := pg_get_functiondef(p_fn);
begin
  if (length(d) - length(replace(d, p_old, ''))) / length(p_old) <> 1 then raise exception '%: anchor not found exactly once: %', p_fn, left(p_old, 80); end if;
  execute replace(d, p_old, p_new);
end $s$;

-- 1 -------------------------------------------------------------------------------------------------------------- name forms
create or replace function security.pdesc_name_forms_v1(p_names text[]) returns text[]
language sql immutable set search_path to '' as $f$
  -- CF-247 F-PDESC (20261112023700): the forms a provider's own name is written in, for the first-sentence check
  select coalesce(array_agg(distinct f) filter (where length(f) >= 3), '{}'::text[])
    from (select btrim(regexp_replace(replace(v, '&', ' and '), '\s+', ' ', 'g')) f
            from unnest(coalesce(p_names, '{}'::text[])) n
            cross join lateral unnest(array[n] || string_to_array(n, ',')) part
            cross join lateral (select btrim(regexp_replace(part, '\s*\([^)]*\)', '', 'g')) bare) b
            cross join lateral unnest(array[btrim(part), b.bare,
                 btrim(regexp_replace(b.bare, '(\s*,?\s+(pty\.?\s*ltd\.?|proprietary\s+limited|limited|ltd\.?|inc\.?|incorporated|llc))+\s*$', '', 'i'))]) v
           where nullif(btrim(coalesce(part, '')), '') is not null) z
$f$;
comment on function security.pdesc_name_forms_v1(text[]) is 'CF-247 F-PDESC (20261112023700): a provider''s name forms (each comma-separated name, no parenthesised part, no legal suffix, & as and) for the first-sentence check in provider_description_validate_v1.';
revoke all on function security.pdesc_name_forms_v1(text[]) from public, anon, authenticated;

select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$cross join lateral unnest(array[p.canonical_name, p.display_name, p.short_name]) nm$o$,
  $n$cross join lateral unnest(security.pdesc_name_forms_v1(array[p.canonical_name, p.display_name, p.short_name])) nm /* 20261112023700: name forms */$n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$security.pdesc_has_term_v1((select btrim(x->>'text') from jsonb_array_elements(case when v_drop and jsonb_array_length(v_dropped) > 0 then v_keep else v_s end) with ordinality e(x, o) order by o limit 1), btrim(nm))) then$o$,
  $n$security.pdesc_has_term_v1(replace((select btrim(x->>'text') from jsonb_array_elements(case when v_drop and jsonb_array_length(v_dropped) > 0 then v_keep else v_s end) with ordinality e(x, o) order by o limit 1), '&', ' and '), btrim(nm))) then$n$);

-- 2 -------------------------------------------------------------------------------------------------------------- prompt version 4
do $p$
declare v3 text; v4 text;
  old_line constant text := 'For each sentence, list the exact page passage or passages that support it, each copied character for character from the page text, in the order they appear on the page.';
begin
  select system_prompt into v3 from pipeline.provider_description_prompts where version = 3 and status = 'active';
  if v3 is null then raise notice 'prompt version 3 is not active (the Platform Admin saved another): version 4 not added'; return; end if;
  if position(old_line in v3) = 0 then raise exception 'prompt version 3 does not hold the passage line'; end if;
  v4 := replace(v3, old_line, old_line || E'\nCopy each passage whole: never shorten it, never join two passages into one, and never use "…" or "..." inside a passage. Give two short passages rather than one shortened passage.');
  update pipeline.provider_description_prompts set status = 'retired' where version = 3;
  insert into pipeline.provider_description_prompts(version, system_prompt, status, reason, activated_at)
  values (4, v4, 'active', 'CF-247 F-PDESC 20261112023700: passages copied whole (first 40 minutes of version 3: 9 of 94 answers held because a passage was shortened with "..." or joined)', now());
end $p$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.pdesc_name_forms_v1', 'Layer 2', 'Provider descriptions', 'F-PDESC: provider name forms for the first-sentence check', 'active', '{}', '20261112023700')
on conflict do nothing;

-- post-checks
do $post$
begin
  if not ('INSTITUTE OF MANAGEMENT LEARNING' = any(security.pdesc_name_forms_v1(array['INSTITUTE OF MANAGEMENT LEARNING PTY LTD']))) then raise exception 'post-check: Pty Ltd'; end if;
  if not ('Leaders Institute' = any(security.pdesc_name_forms_v1(array['Leaders Institute Pty Ltd, Australian Agribusiness Institute, Australian Business Institute']))) then raise exception 'post-check: comma list'; end if;
  if not ('Elite Hairstyling and Esthetics Training Center' = any(security.pdesc_name_forms_v1(array['Elite Hairstyling & Esthetics Training Center']))) then raise exception 'post-check: ampersand'; end if;
  if not ('Nelson Marlborough Institute of Technology' = any(security.pdesc_name_forms_v1(array['Nelson Marlborough Institute of Technology (NMIT)']))) then raise exception 'post-check: parenthesis'; end if;
  if position('pdesc_name_forms_v1' in pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: validate'; end if;
  if (select count(*) from pipeline.provider_description_prompts where status = 'active') <> 1 then raise exception 'post-check: one active prompt'; end if;
end $post$;
