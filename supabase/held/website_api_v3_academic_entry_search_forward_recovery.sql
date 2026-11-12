-- HELD forward recovery for migration 20261113230000_cf247_website_api_v3_academic_entry_search.sql. Not applied by deploy.
-- Puts public.website_v3_course_search back to the definition that
-- migration edited (reverse edit, md5-guarded against the definition it left). The functions it added stay (nothing calls them after
-- this); they are dropped by paste file. v2 is not touched. Safe to run twice: the second run stops at the md5 guard and changes nothing.
-- Replaces: the definition named above. Retires: nothing.

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
