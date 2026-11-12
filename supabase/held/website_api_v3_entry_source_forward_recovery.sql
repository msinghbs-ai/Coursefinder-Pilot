-- HELD forward recovery for migration 20261113220000_cf247_website_api_v3_entry_source_academic_filter.sql. Not applied by deploy.
-- Puts public.website_v3_course_search, website_v3_course(text,text) and website_v3_provider (both forms) back to the definitions that
-- migration edited (reverse edits, md5-guarded against the definitions it left). The functions it added stay (nothing calls them after
-- this); they are dropped by paste file. v2 is not touched. Safe to run twice: the second run stops at the md5 guard and changes nothing.
-- Replaces: the four definitions named above. Retires: nothing.

create or replace function pg_temp.v3_edit(p_sig text, p_md5 text, p_olds text[], p_news text[]) returns void language plpgsql as $$
declare d text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(d) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(d); end if;
  for i in 1 .. cardinality(p_olds) loop
    if (length(d) - length(replace(d, p_olds[i], ''))) <> length(p_olds[i]) then raise exception '%: edit % must match exactly once', p_sig, i; end if;
    d := replace(d, p_olds[i], p_news[i]);
  end loop;
  execute d;
end $$;

select pg_temp.v3_edit('public.website_v3_course_search(jsonb,integer,integer,text)', '9d9b5a19e68fd84755a05b3efc6de27a',
  array['public.website_v3_course_search_core(p_filters, p_page, p_page_size, p_sort)',
        $n$public.website_v3_course_search_item(x, nullif(upper(btrim(coalesce(p_filters->>'edu_country', ''))), ''))$n$],
  array['public.website_v2_course_search(p_filters, p_page, p_page_size, p_sort)', 'public.website_v3_course_search_item(x)']);
select pg_temp.v3_edit('public.website_v3_course(text,text)', '7ac0239f26c0e1ebb3bd2466e5932aff',
  array[$n$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  -- O20: the same resolution with source_url on each row (the course is the one the v2 answer names)
  if jsonb_typeof(v #> '{item,entry,resolution}') = 'object' then
    v := jsonb_set(v, '{item,entry,resolution}', security.entry_resolve_v3(
           (select d.course_id from search.course_documents d
             where lower(d.course_stable_key) = lower(v #>> '{item,course_id}') and d.course_stable_key is not null limit 1), p_edu_country));
  end if;$n$],
  array[$o$  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;$o$]);
select pg_temp.v3_edit('public.website_v3_provider(text)', 'a24dfbce8997e88145a0ccbf90deaedf',
  array[$n$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  -- O20: the same matrix with quote and source_url on each row
  if jsonb_typeof(v #> '{item,entry_matrix}') = 'array' then
    v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(
           (select p.id from catalogue.providers p where p.stable_key = v #>> '{item,provider_id}'), null));
  end if;$n$],
  array[$o$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;$o$]);
select pg_temp.v3_edit('public.website_v3_provider(text,text)', '46a7e222f6d3758456d3929246301181',
  array[$n$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  -- O20: the same matrix (for the country asked) with quote and source_url on each row
  if jsonb_typeof(v #> '{item,entry_matrix}') = 'array' then
    v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(
           (select p.id from catalogue.providers p where p.stable_key = v #>> '{item,provider_id}'), upper(btrim(p_edu_country))));
  end if;$n$],
  array[$o$  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;$o$]);
