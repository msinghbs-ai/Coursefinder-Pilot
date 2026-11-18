-- Intake Preview timeout, reported after PR #872 / v2.15.478.
-- Replaces: security.course_page_check_v1(uuid,text,text,text) access path; security.intake_ui_selection_v1(text,integer) explicit preview work bound.
-- Retires: nothing.
-- No reader, scheduler, consumer API, source identity rule, spending budget, timeout or admission authority change.
-- The immutable ASCII title key contains no LIKE wildcards. A prefix match is equivalently an equality
-- to one of the URL slug's prefixes. Add that redundant restriction so an index can avoid normalising
-- every sibling title for every candidate. Keep the original LIKE and every other guard unchanged.
do $guard$ begin
 if md5(pg_get_functiondef('security.course_title_key(text)'::regprocedure)) <> '6dbf332766b47f5bdd09032fc78d3707' then
 raise exception 'course_title_key changed; reconcile prefix-index equivalence before applying'; end if;
end $guard$;

create index if not exists courses_provider_title_slug_active_idx
 on catalogue.courses(provider_id,(replace(security.course_title_key(canonical_title),' ','-')))
 where lifecycle_status='active';
create index if not exists coverage_course_pages_provider_base_url_idx
 on pipeline.coverage_course_pages(provider_id,(split_part(url,'#',1)))
 where status in('bound','ambiguous');

-- The page-title lookup tests stored URL OR redirected final URL among read pages.
-- Give each OR arm an indexed provider-scoped equality path (also avoids fetching unrelated JSON).
create index if not exists coverage_course_pages_provider_url_read_idx
 on pipeline.coverage_course_pages(provider_id,url) where read_status='read';
create index if not exists coverage_course_pages_provider_final_url_read_idx
 on pipeline.coverage_course_pages(provider_id,(candidates->>'final_url')) where read_status='read';

do $patch$
declare sig text:='security.course_page_check_v1(uuid,text,text,text)'; d text:=pg_get_functiondef(sig::regprocedure);
 old_clause text:=$old$               and t.slug like replace(security.course_title_key(o.canonical_title), ' ', '-') || '%'$old$;
 new_clause text:=$new$               and replace(security.course_title_key(o.canonical_title), ' ', '-') = any (array(select left(t.slug, n) from generate_series(0, length(t.slug)) n))
               and t.slug like replace(security.course_title_key(o.canonical_title), ' ', '-') || '%'$new$;
begin
 if position(new_clause in d)>0 then return; end if;
 if md5(d)<>'c8bf35fe4b04c9ccff62ceefd6da0dd0' then raise exception 'course_page_check changed; Integration Controller must reconcile before applying'; end if;
 if (length(d)-length(replace(d,old_clause,'')))/length(old_clause)<>1 then raise exception 'expected one sibling prefix predicate'; end if;
 execute replace(d,old_clause,new_clause);
end $patch$;
-- Indexes are access paths, not replacement components. Existing function stays in its register.

-- Bound synchronous preview work explicitly; cohort size, total scan budget and role timeout are unchanged.
insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason)
values('pipeline','run_now.preview_rows_per_university','Run now: preview rows per university',
 'Most candidate intake rows evaluated per university in a synchronous preview, also bounded by its share of run_now.cohort_scan_rows. Counts are limited to evaluated rows. Raise only after checking the authenticated RPC time budget; this never changes the fixed cohort size.',
 'number','5',1,1000,'rows',1107,'Run now','security.intake_ui_selection_v1',
 'Post-release preview timeout: bound expensive identity/evidence checks while preserving the twenty-course cohort and existing admission rules')
on conflict(toolset_key,key) do nothing;

do $preview$
declare sig text:='security.intake_ui_selection_v1(text,integer)';d text:=pg_get_functiondef(sig::regprocedure);
 old_bound text:=$b$greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int / greatest(jsonb_array_length(unis),1))$b$;
 new_bound text:=$b$least(greatest(1,security.pipeline_num_v1('run_now.preview_rows_per_university',5)::int),greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int / greatest(jsonb_array_length(unis),1)))$b$;
begin
 if position(new_bound in d)>0 then return;end if;
 if md5(d)<>'629006a819416ebaa61b7702da9c927c' then raise exception 'intake UI selector changed; Integration Controller must reconcile before applying';end if;
 if (length(d)-length(replace(d,old_bound,'')))/length(old_bound)<>2 then raise exception 'expected plan and displayed scan bounds to match';end if;
 execute replace(d,old_bound,new_bound);
end $preview$;
