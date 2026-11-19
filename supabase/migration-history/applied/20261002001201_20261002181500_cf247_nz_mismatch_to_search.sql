-- CF-247 (Decision 217, 2 Oct 2026): a New Zealand course whose earlier page is read again and still is not the course's
-- page goes to the course-page search by title (each minute, up to 200). Only courses without a CRICOS-shaped code
-- (Australian courses keep their own queueing rules). The direct-send path drops "(Level N)" from title searches,
-- like the worker path. md5 guard on security.course_link_search_tick_v1.
do $p$
declare s text; d text; o text[]; n text[]; i int;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'course_link_search_tick_v1';
  if md5(s) is distinct from '7895c1193a3cae89d5c5bb4c0319c62a' then raise exception 'course_link_search_tick_v1 changed (md5 %); not replacing', md5(s); end if;
  o := array[
    $o$  -- 3. Send the next batch, inside the monthly credit cap.$o$,
    $o$else '"' || replace(r.canonical_title, '"', '') || '" site:' || r.search_domain end;$o$];
  n := array[
    $n$  -- 2b. Decision 217: courses without a CRICOS code whose earlier page was read again and is not theirs are searched by title.
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
  select p.course_id, p.provider_id, 'title', 'queued', now()
    from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
   where p.status = 'mismatch' and p.basis not in ('cricos_search', 'title_search')
     and coalesce(c.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$'
     and exists (select 1 from pipeline.course_link_recipes rc where rc.provider_id = p.provider_id and rc.active)
     and not exists (select 1 from pipeline.course_link_search s where s.course_id = p.course_id)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field = 'official_url')
   limit 200
  on conflict (course_id) do nothing;

  -- 3. Send the next batch, inside the monthly credit cap.$n$,
    $n$else '"' || replace(regexp_replace(r.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || r.search_domain end;$n$];
  for i in 1..array_length(o, 1) loop
    if (length(d) - length(replace(d, o[i], ''))) / length(o[i]) <> 1 then raise exception 'tick piece % not found once', i; end if;
    d := replace(d, o[i], n[i]);
  end loop;
  execute d;
end $p$;
