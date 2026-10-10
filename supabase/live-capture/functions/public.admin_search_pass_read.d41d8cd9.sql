CREATE OR REPLACE FUNCTION public.admin_search_pass_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'status_note', r.status_note, 'credits_used', r.credits_used, 'created_at', r.created_at, 'reason', r.reason,
               'courses', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id), 'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done')) order by r.created_at desc), '[]'::jsonb)
             from pipeline.toolset_sample_runs r where r.applies),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'refind', z.refind, 'state', z.state, 'n', z.n)), '[]'::jsonb)
              from (select k.iso_alpha2 cc, l.refind, l.state, count(*) n from pipeline.search_pass_links l join catalogue.providers p on p.id = l.provider_id join ref.countries k on k.id = p.country_id group by 1, 2, 3) z),
    'reading', (select coalesce(jsonb_agg(jsonb_build_object('read_status', z.rs, 'n', z.n)), '[]'::jsonb)
                from (select coalesce(p.read_status, 'waiting') rs, count(*) n from pipeline.search_pass_links l join pipeline.coverage_course_pages p on p.course_id = l.course_id and p.url = l.bound_url where l.state = 'found' group by 1) z),
    'repairs', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n, 'last_at', z.last_at)), '[]'::jsonb)
                from (select reason, count(*) n, max(at) last_at from pipeline.page_link_repairs group by 1) z));
end $function$
