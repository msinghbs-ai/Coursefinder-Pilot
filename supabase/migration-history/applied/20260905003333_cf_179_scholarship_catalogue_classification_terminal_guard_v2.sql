do $$
declare d text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='scholarship_international_detail_batch_service';
 d:=replace(d,'coalesce(c.classification,'''') not in(''external_or_out_of_scope'',''support_or_navigation'')','coalesce(c.classification,'''') not in(''external_or_out_of_scope'',''support_or_navigation'',''catalogue_or_filter'')');
 execute d;
end $$;

update pipeline.layer2_scholarship_discovery_candidates
set classification='catalogue_or_filter',classification_reason='CF-179 catalogue page retained as terminal catalogue Evidence; never auto-promote to detail',classified_at=now()
where status='discovered' and scholarship_url='https://www.cdu.edu.au/international/how-apply/scholarships';
