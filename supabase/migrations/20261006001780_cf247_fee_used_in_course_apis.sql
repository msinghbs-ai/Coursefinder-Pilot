-- CF-247 Decision 255 (6 Oct 2026, Platform Admin: "Add fee_used to course api"). The Zoho, Wix and website course APIs
-- read search.course_documents through api.zoho_course_lookup_v1 and api.zoho_course_search_v2 (the website card search
-- builds on the same search). Each course item gains one additive key, fee_used, from security.course_fee_used_v1:
-- source (page or cricos), per_year, currency, year, the reason, and locked (entered or locked by hand).
-- Nothing is removed or renamed and the contract_version strings are unchanged. No stored fee changes.
-- Both function patches are behind md5 guards and each snippet is found exactly once.
do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('api','zoho_course_lookup_v1','c2e7944d91b06058e7bd7a456540f3c2',
      array[$o$      'official_course_url',official_course_url,$o$],
      array[$n$      'fee_used',security.course_fee_used_v1(course_id),
      'official_course_url',official_course_url,$n$]),
    ('api','zoho_course_search_v2','f82cdc9284081a9b73977cb32b3107f7',
      array[$o$    'official_course_url',official_course_url,$o$],
      array[$n$    'fee_used',security.course_fee_used_v1(course_id),
    'official_course_url',official_course_url,$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %), not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;
