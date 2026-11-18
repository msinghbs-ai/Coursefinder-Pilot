-- CF-247 RM1I / RM1C / RM1H / RM1D page facts: the reader keeps the page's content (S2-Build; Platform Admin 18 Nov 2026 15:32).
--
-- What was read live (18 Nov 2026 16:23 AEDT, first load, run 1e3b285f): both Home Affairs pages were read and stored (1.46 MB and 1.30 MB),
-- but every fact came back "pattern not found" with nothing around its anchor word: the visible text the patterns ran on was nearly empty.
-- The text reader removed <svg>, <template> and <noscript> elements with their content up to the next closing tag, so a self-closing
-- <svg/> ran on far down the page. The JSA data page gave no workbook link matching "OSCA Occupation data": JSA links its workbooks as
-- download routes ending /xlsx, and the reader took only addresses ending .xlsx in double quotes.
--
-- What it changes
--   * layer1-destination-geo-loader v1.2.1 (supabase/functions/_shared/cf247-page-facts.js): self-closing tags go first; only script, style
--     and the head are removed with their content; every other tag is stripped and its text kept. Workbook links are taken in any quoting,
--     ending .xlsx or /xlsx, and matched on their text and their address read as words. A miss on the JSA page lists the workbook links seen.
--   * security.destination_page_facts_load_v1 (md5-guarded edit): a fact not found records the page's size and visible-text length, so an
--     empty reading shows as such.
-- The second load is asked for by a follow-up migration once v1.2.1 is deployed (Deploy on merge applies migrations before functions).
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: the not-found item of security.destination_page_facts_load_v1.
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

select pg_temp.cf_edit('security.destination_page_facts_load_v1(jsonb)'::regprocedure, 'f6c8e940310ba8d8f5bef70a3e746348',
  $o$v_items := v_items || jsonb_build_object('title', f.title, 'status', case when pg ? 'error' then 'page_failed' else 'not_found' end, 'reason', coalesce(pg->>'error', x->>'reason'));$o$,
  $n$v_items := v_items || jsonb_build_object('title', f.title, 'status', case when pg ? 'error' then 'page_failed' else 'not_found' end, 'reason', coalesce(pg->>'error', x->>'reason'),
                                          'page_bytes', pg->'bytes', 'page_text_length', pg->'text_length');  -- 20261118191000: an empty reading shows as such$n$,
  '20261118191000: an empty reading shows as such');

do $$
begin
  if position('page_text_length' in (select prosrc from pg_proc where oid = 'security.destination_page_facts_load_v1(jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: the not-found item records the page text length';
  end if;
end $$;
