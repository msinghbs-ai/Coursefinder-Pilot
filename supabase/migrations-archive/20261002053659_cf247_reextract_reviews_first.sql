-- CF-247 (Decision 224, 2 Oct 2026). Platform Admin, 15:35: "Review all other stuck in layer 4, tuition fees ... review
-- for international students rather getting confused on default page that open domestic students."
-- Re-extraction (reader v0.5.5) takes pages behind a waiting Layer 4 tuition review first, so those reviews can be
-- settled against the page's international view now rather than in about two hours. Patch behind an md5 guard.
do $p$
declare s text; d text;
  o1 text := $o$order by cp0.read_at limit$o$;
  n1 text := $n$order by exists (select 1 from pipeline.layer4_review_items r4 where r4.entity_id = cp0.course_id and r4.status = 'pending'
                          and r4.field_code = 'provider_current_tuition_validation') desc, cp0.read_at limit$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'svc_coverage_reextract_next';
  if md5(s) is distinct from '519ca7d0a304f4004a6300bcf662e668' then raise exception 'svc_coverage_reextract_next changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;
