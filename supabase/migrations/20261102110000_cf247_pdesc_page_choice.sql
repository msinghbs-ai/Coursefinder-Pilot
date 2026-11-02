-- CF-247 P1 provider descriptions: the right page (pilot finding, 2 Nov 2026 16:16 AEDT; v2.15.406 pilot enabled 16:10, event #28623).
-- What the first pilot run read (3 of 5 universities, all held, nothing proposed, US$0.0018 of AI):
--   * Charles Darwin University: https://www.cdu.edu.au/about-cdu, the right page; held on length (916 characters, 4 sentences, every
--     quote on the page). The length limit is a setting (pdesc.max_chars, 900) and is not changed here; a value is proposed to the Platform Admin.
--   * Monash University: a stored copy of a Pharmacy news article (monash.edu/pharm/about/news/...), chosen because "about" was one of its
--     path parts. Held on unsupported_sentence.
--   * Australian Catholic University: https://staff.acu.edu.au/our_university/research, the home page's "our university" link on a staff
--     subdomain (two Firecrawl reads). Held on not_stated.
-- What: one page rule, security.provider_description_page_v1(provider, address), used for every source the reader may read (a stored copy,
--   a central page finder suggestion, a page the worker read) and repeated by the worker for the home page's links:
--   * the page is on one of the provider's own hosts, and not on a subdomain whose first label is refused (pdesc.refused_host_labels:
--     staff, intranet, ...); the provider's main site host (its website or an approved other website, with or without www) ranks first;
--   * no path part is, or is made of, a refused word (pdesc.refused_path_words: news, events, media, research, staff, faculty, school, ...);
--   * the About part is the first part of the path (after a two-letter language part such as /en/), as an About page name
--     (pdesc.about_patterns) or a name starting with an About prefix (pdesc.about_prefixes: about-cdu, about_us), and the path has at most
--     pdesc.about_max_segments parts.
--   A stored copy is used only when its address passes (a held news article is never used because it is held). The validation refuses a
--   source that does not pass (rule not_about_page), so a wrong page can never be proposed.
-- Held reads: nothing is re-queued here. A PIM Admin sends the held pilot universities back with a reason (Coverage › Provider descriptions,
--   "Read these again", public.admin_provider_descriptions 'retry'); each new read stays inside the pilot ceilings (pdesc.ai_usd_max from the
--   shared AI ledger, pdesc.firecrawl_reads_max counting the reads already made) and the shared AI rule.
-- md5 (before = live v2.15.406, read 2 Nov 2026 16:46 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/p1-provider-descriptions/run.sh):
--   security.provider_description_stored_v1(uuid)                                d9f9244ea3dd37c511b0ff75f04d5e30 -> 6ddc25869e9865c9aeebf11c819feee2
--   public.svc_provider_description_next(integer)                                d4fd17854056f1ad69c0d1dc0e0abf11 -> 33d735da514a7d37e2815bbb0073af03
--   security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)       9a3fbd7f15f5cf30d1a13359d6062280 -> 6efb0237726f004fe85c1aa778a35052
-- Worker coverage-sweep v0.58.0: the home page's About links pass the same rule (description.ts aboutLinks), with the lists from the lease;
--   the model is told the sentence and character limits the validation applies (lease 'length'; prompt provider-description-v2). The limits
--   themselves (pdesc.max_chars 900) are not changed.
-- Replaces: security.provider_description_stored_v1, public.svc_provider_description_next, security.provider_description_validate_v1 (same names; md5-guarded edits)
-- Retires: nothing (the old rule "About name anywhere in the path" is switched off by these edits)
-- Nothing dropped, deleted or renamed. No setting value is changed and nothing is switched on. Consumer API untouched (G3).

-- ---------------------------------------------------------------- 1 settings (G2): the allowed and refused words
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.about_prefixes', 'Provider descriptions: About page name prefixes',
  'An About page whose first path part starts with one of these (for example about-cdu, about_us) is an About page, as well as the names in About page names.',
  'list', '["about-", "about_"]'::jsonb, null, null, 'prefixes', 983, 'Provider descriptions', 'security.provider_description_page_v1, worker provider_description', 'CF-247 P1 pilot 2 Nov 2026 16:16: About or Overview page on the main site (about-<abbr>)'),
 ('pipeline', 'pdesc.refused_path_words', 'Provider descriptions: refused page words',
  'A page whose address has a part that is, or is made of, one of these words is never a description source (news, events and other subpages).',
  'list', '["news", "newsroom", "events", "event", "media", "research", "staff", "faculty", "faculties", "school", "schools", "stories", "story", "blog", "blogs", "press", "library", "alumni", "giving", "careers", "jobs", "students", "student", "study", "courses", "course", "international"]'::jsonb,
  null, null, 'words', 984, 'Provider descriptions', 'security.provider_description_page_v1, worker provider_description', 'CF-247 P1 pilot 2 Nov 2026 16:16: refuse news, events, media, research, staff, faculty and school subpages'),
 ('pipeline', 'pdesc.refused_host_labels', 'Provider descriptions: refused subdomains',
  'A page on a subdomain whose first label is one of these (staff.uni.edu.au, intranet.uni.edu.au) is never a description source.',
  'list', '["staff", "intranet", "my", "portal", "students", "student", "library", "research", "news", "alumni", "lms", "login", "sso", "handbook", "events", "media", "jobs", "careers"]'::jsonb,
  null, null, 'labels', 985, 'Provider descriptions', 'security.provider_description_page_v1, worker provider_description', 'CF-247 P1 pilot 2 Nov 2026 16:16: refuse staff or intranet subdomains'),
 ('pipeline', 'pdesc.about_max_segments', 'Provider descriptions: About page path parts at most',
  'An About page address has at most this many path parts (a two-letter language part such as /en/ is not counted): /about-cdu is 1, /about/overview is 2.',
  'number', '2'::jsonb, 1, 4, 'parts', 986, 'Provider descriptions', 'security.provider_description_page_v1, worker provider_description', 'CF-247 P1 pilot 2 Nov 2026 16:16: the About page itself, not a subpage')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- 2 the page rule
-- {ok, rule, main_host}: rule wrong_host, refused_host, refused_word, not_about_page or about_page
create or replace function security.provider_description_page_v1(p_provider uuid, p_url text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_host text := regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '');
        v_path text := lower(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), ''));
        v_hosts text[] := security.provider_hosts_v1(p_provider); v_main boolean; v_segs text[]; v_first text; v_n int;
begin
  if v_host = '' or security.provider_page_host_v1(p_provider, p_url) <> 'own' then
    return jsonb_build_object('ok', false, 'rule', 'wrong_host', 'main_host', false);
  end if;
  v_main := v_host = any (v_hosts);
  if not v_main and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb)) l
                             where split_part(v_host, '.', 1) = lower(l)) then
    return jsonb_build_object('ok', false, 'rule', 'refused_host', 'main_host', false);
  end if;
  v_segs := array(select s from unnest(string_to_array(regexp_replace(v_path, '/+$', ''), '/')) s where s <> '');
  if cardinality(v_segs) > 0 and v_segs[1] ~ '^[a-z]{2}(-[a-z]{2})?$' then v_segs := v_segs[2:]; end if;  -- fixed: a language part (/en/, /en-au/) is not a path part
  if exists (select 1 from unnest(v_segs) s, regexp_split_to_table(s, '[-_.]+') t,
                  jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb)) w
              where t = lower(w) or s = lower(w)) then
    return jsonb_build_object('ok', false, 'rule', 'refused_word', 'main_host', v_main);
  end if;
  v_n := coalesce(cardinality(v_segs), 0); v_first := coalesce(v_segs[1], '');
  if v_n = 0 or v_n > security.pipeline_num_v1('pdesc.about_max_segments', 2)
     or not (exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) a where v_first = lower(a))
             or exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) x
                         where x <> '' and left(v_first, length(x)) = lower(x) and length(v_first) > length(x))) then
    return jsonb_build_object('ok', false, 'rule', 'not_about_page', 'main_host', v_main);
  end if;
  return jsonb_build_object('ok', true, 'rule', 'about_page', 'main_host', v_main);
end $function$;
revoke all on function security.provider_description_page_v1(uuid, text) from public, anon, authenticated;
comment on function security.provider_description_page_v1(uuid, text) is 'CF-247 P1 provider descriptions (pilot 2 Nov 2026 16:16): may this address be a description source? The provider''s own host, not a refused subdomain (pdesc.refused_host_labels); no refused word in the path (pdesc.refused_path_words); an About page name (pdesc.about_patterns, pdesc.about_prefixes) as the first path part, at most pdesc.about_max_segments parts. main_host: on the website or an approved other website itself.';

-- ---------------------------------------------------------------- 3 md5-guarded edits
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 3a stored copy: only an address that passes the page rule; the main site first, then the newest
select pg_temp.edit_once('security.provider_description_stored_v1(uuid)', 'd9f9244ea3dd37c511b0ff75f04d5e30', '6ddc25869e9865c9aeebf11c819feee2', array[
  array[$o$     and security.provider_page_host_v1(p_provider, a.source_url) = 'own'
     and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) pat,
                      regexp_split_to_table(lower(coalesce(substring(a.source_url from '^https?://[^/]+(/[^?#]*)'), '')), '/') seg
                  where seg <> '' and seg = lower(pat))
   order by coalesce(a.captured_at, a.created_at) desc, a.id$o$,
        $n$     -- pilot 2 Nov 2026 16:16: the page rule (a held news article was used because "about" was one of its path parts)
     and (security.provider_description_page_v1(p_provider, a.source_url)->>'ok')::boolean
   order by (security.provider_description_page_v1(p_provider, a.source_url)->>'main_host')::boolean desc, coalesce(a.captured_at, a.created_at) desc, a.id$n$]], array[1]);

-- 3b lease: central page finder suggestions pass the page rule (main site first); the worker gets the lists for the home page's links
select pg_temp.edit_once('public.svc_provider_description_next(integer)', 'd4fd17854056f1ad69c0d1dc0e0abf11', '33d735da514a7d37e2815bbb0073af03', array[
  array[$o$                               and security.provider_page_host_v1(u.provider_id, e->>'url') = 'own') z))), '[]'::jsonb)$o$,
        $n$                               and (security.provider_description_page_v1(u.provider_id, e->>'url')->>'ok')::boolean) z))), '[]'::jsonb)$n$],
  array[$o$select coalesce(jsonb_agg(z.url order by z.score desc, length(z.url)), '[]'::jsonb) from ($o$,
        $n$select coalesce(jsonb_agg(z.url order by (security.provider_description_page_v1(u.provider_id, z.url)->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from ($n$],
  array[$o$    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb), 'items', v);$o$,
        $n$    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb),
    -- pilot 2 Nov 2026 16:16: the page rule's lists, for the home page's links (security.provider_description_page_v1 decides the same way)
    'page_rule', jsonb_build_object('about_prefixes', coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb),
                                    'refused_path_words', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb),
                                    'refused_host_labels', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb),
                                    'about_max_segments', security.pipeline_num_v1('pdesc.about_max_segments', 2)::int),
    -- pilot 2 Nov 2026 16:16 (CDU held at 916 characters): the model is told the limits the validation applies
    'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2)::int, 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5)::int,
                                 'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150)::int, 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int),
    'items', v);$n$]], array[1, 1, 1]);

-- 3c validation: a source that fails the page rule is refused (not_about_page, refused_word, refused_host), so a wrong page is never proposed
select pg_temp.edit_once('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)', '9a3fbd7f15f5cf30d1a13359d6062280', '6efb0237726f004fe85c1aa778a35052', array[
  array[$o$  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then$o$,
        $n$  -- pilot 2 Nov 2026 16:16: only the provider's own About or Overview page is a description source
  if not (security.provider_description_page_v1(p_provider, p_url)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', security.provider_description_page_v1(p_provider, p_url)->>'rule', 'checks', v_checks,
      'reason', 'the page is not the provider''s own About or Overview page');
  end if;
  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then$n$]], array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.provider_description_page_v1', 'Layer 2', 'P1 provider descriptions: which page may be a description source (pilot 2 Nov 2026)', 'active', '{}', '20261102110000')
on conflict do nothing;
