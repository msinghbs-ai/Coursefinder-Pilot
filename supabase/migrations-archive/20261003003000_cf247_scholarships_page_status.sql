-- CF-247 (3 Oct 2026, 23:40 AEST). Platform Admin, 23:27: the live Scholarships list "doesn't match up with the
-- mockup". The list read now gives what the mockup shows: each scholarship's status — Published, Ready to publish,
-- Held (with the reasons from the publishing check) or Inactive — and the counts for the status pills. A status filter
-- (p_args->>'status') narrows the list; with none, inactive scholarships are left out (they have their own pill).
-- Replaced under an md5 guard on the live text; each patched line must be found exactly once.
do $g$ declare v_oid oid; v_def text; v_old text; v_new text; begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_scholarships_page';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'a8cbedd3e953d24a076d28f27eef5d60' then raise exception 'admin_scholarships_page changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);

  v_old := $x$    with base as ($x$;
  v_new := $x$    with pub as materialized (select scholarship_id, publishable, missing from security.scholarship_publishability_v1()),
    base as ($x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'base CTE not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $x$scholarship.value_label(s.id) value_label,$x$;
  v_new := $x$scholarship.value_label(s.id) value_label,
        case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce(pb.publishable, false) then 'ready' else 'held' end status,
        coalesce(pb.missing, '{}'::text[]) held_reasons,$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'value_label column not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $x$      left join ref.countries co on co.id=p.country_id
      where$x$;
  v_new := $x$      left join ref.countries co on co.id=p.country_id
      left join pub pb on pb.scholarship_id=s.id
      where$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'countries join not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $x$      select *,count(*) over() total_count from base
$x$;
  v_new := $x$      select *,count(*) over() total_count from base
       where case when coalesce(p_args->>'status','') = '' then status <> 'inactive' else status = p_args->>'status' end
$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'numbered CTE not found exactly once'; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $x$'sort',v_sort,'direction',v_dir)$x$;
  v_new := $x$'sort',v_sort,'direction',v_dir,'status_counts',(select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select b.status, count(*) n from base b group by 1) z))$x$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'return object not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $g$;
