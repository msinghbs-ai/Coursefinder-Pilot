-- CF-247 (Decision 227, 2 Oct 2026). Platform Admin, 16:42: "We should concentrate on intakes and English
-- requirements", and by multiple choice: English from the university's own policy, semesters to months.
-- The provider-facts search has already found English language policy pages for 142 providers and academic calendars
-- for 140, but the reader only read fee schedules. This change: the reader also reads English policy and academic
-- calendar pages (stored as evidence; nothing is written to the catalogue by reading). Larger providers are read
-- first. Patch behind an md5 guard on the current source.

do $p$
declare s text; d text;
  o1 text := $o$where f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id)$o$;
  n1 text := $n$where ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))$n$;
  o2 text := $o$order by (f.linked_from is null), f.rank, f.created_at$o$;
  n2 text := $n$order by (f.linked_from is null), f.rank,
              (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.created_at$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'svc_provider_facts_read_next';
  if md5(s) is distinct from '08626bd03d652647b2fc8c49b08c8ac2' then raise exception 'svc_provider_facts_read_next changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece 1 not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'piece 2 not found once'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $p$;
