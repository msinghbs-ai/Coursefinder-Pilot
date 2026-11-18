-- CF-247 F-INT: the course-page identity check (E16) finds the stored title of the page it is asked about when the address differs only by a
-- trailing slash or by another of the provider's own hosts (Platform Admin 12 Nov 2026 20:57 "proceed with all steps": course-page identity for
-- Adelaide and Southern Cross).
-- Found: security.course_page_check_v1 looks up the page's stored title and h1 (pipeline.coverage_course_pages) by exact address. The course's address
--   is often the same page with a trailing slash (Southern Cross, Wollongong: ".../bachelor-of-early-childhood-education-3007003/" against the read
--   ".../bachelor-of-early-childhood-education-3007003"), or the same path on the provider's other approved host (Adelaide University: course address on
--   adelaide.edu.au, page read on adelaideuni.edu.au; adelaide.edu.au is its approved alias in binding.provider_host_aliases). With no title the check
--   has nothing to prove the page and refuses it: of 3,005 Australian intakes held "page not proved to be the course's own (E16 refuse)" on 12 Nov,
--   667 had their page read under the slash variant and 374 under another own host.
-- What:
--   1. security.course_page_url_variants_v1(provider, url): the address with and without its trailing slash and, when its host is one of the
--      provider's own hosts (website, binding.provider_host_aliases, pipeline.provider_extra_domains), the same path on each own host (with and without
--      www). Read only.
--   2. md5-guarded text edits of security.course_page_check_v1: (a) the title lookup and (b) the identity-proof lookup (the course's own read page
--      with an identity basis) also match those variants; (a) for the same provider and a read page only, (b) for the same course only. Every
--      identity rule after the lookups is unchanged; a page of another provider is never matched.
-- Guards: G1 (no job), G2 (no operational value: hosts come from the existing settings and tables), G3 (no consumer API object), G4 (cf-247-s539).
-- Replaces: security.course_page_check_v1 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: reverse the one edit (body f6d135b669c6a1d64533d691080a708e); drop the helper by paste file.

create or replace function security.course_page_url_variants_v1(p_provider uuid, p_url text)
returns text[] language sql stable security definer set search_path = '' as $$
  with u as (
    select regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '') host,
           coalesce(substring(p_url from '^https?://[^/?#]+(/[^#]*)'), '/') pth),
  own as (
    select distinct h from (
      select regexp_replace(lower(coalesce(substring(pr.website from '^https?://([^/?#:]+)'), '')), '^www\.', '') h from catalogue.providers pr where pr.id = p_provider
      union all
      select regexp_split_to_table(lower(btrim(substr(e, strpos(e, '=') + 1))), '\s+')
        from catalogue.providers pr, jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'binding.provider_host_aliases'), '[]'::jsonb)) e
       where pr.id = p_provider and split_part(e, '=', 1) = pr.stable_key
      union all
      select regexp_replace(lower(d.domain), '^(https?://)?(www\.)?', '') from pipeline.provider_extra_domains d where d.provider_id = p_provider) z
    where h <> ''),
  base as (
    select rtrim(p_url, '/') b
    union all
    select pre || o.h || rtrim(u.pth, '/') from u, own o, unnest(array['https://', 'https://www.']) pre
     where u.host <> '' and exists (select 1 from own o2 where o2.h = u.host))
  select array(select distinct v from base, unnest(array[b, b || '/']) v where b <> '' order by 1)
$$;
comment on function security.course_page_url_variants_v1(uuid, text) is
  'E16 title lookup (12 Nov 2026): a course address with and without its trailing slash and, on the provider''s own hosts, the same path on each own host.';
revoke all on function security.course_page_url_variants_v1(uuid, text) from public, anon, authenticated;

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

select pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', 'f6d135b669c6a1d64533d691080a708e', '554d95af03219a28a2b7274914a46af6',
  array[$o$where (g.url = p_url or g.candidates->>'final_url' = p_url) and g.read_status = 'read'$o$,
        $o$where g.course_id = t.id and (g.url = p_url or g.candidates->>'final_url' = p_url)$o$],
  array[$n$where (g.url = p_url or g.candidates->>'final_url' = p_url
                      -- 12 Nov 2026 (F-INT, E16): the same page with or without its trailing slash, or the same path on another of the provider's own hosts
                      or g.url = any (security.course_page_url_variants_v1(c.provider_id, p_url))) and g.read_status = 'read'$n$,
        $n$where g.course_id = t.id and (g.url = p_url or g.candidates->>'final_url' = p_url
                                                        or g.url = any (security.course_page_url_variants_v1(t.provider_id, p_url)))$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_page_check_v1(uuid,text,text,text)'::regprocedure)) <> '554d95af03219a28a2b7274914a46af6' then
    raise exception 'post-check: security.course_page_check_v1 does not have the recorded body'; end if;
end $post$;
