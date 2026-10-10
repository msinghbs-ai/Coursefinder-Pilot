-- CF-247 (Decision 223, 2 Oct 2026). Re-extraction of saved course pages (coverage-reextract) is told each page's country,
-- so New Zealand and Canadian pages are re-read in NZD and CAD (it read every page in AUD). Reader v0.5.5 re-extracts
-- every saved page once: fees follow the page's own domestic or international view, course totals and part-year fees
-- are no longer taken as annual fees. Patch behind an md5 guard on the current source.
do $p$
declare s text; d text;
  o1 text := $o$'status',cp.status,'url',cp.url)$o$;
  n1 text := $n$'status',cp.status,'url',cp.url,'country',security.coverage_country(cp.provider_id))$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'svc_coverage_reextract_next';
  if md5(s) is distinct from 'a9617910c957420c8c641b75fd0eec21' then raise exception 'svc_coverage_reextract_next changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;
