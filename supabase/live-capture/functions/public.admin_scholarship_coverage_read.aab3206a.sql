CREATE OR REPLACE FUNCTION public.admin_scholarship_coverage_read(p_scope text DEFAULT 'watch'::text, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_rows jsonb; v_total int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  with ids as (
    select p.id, coalesce(p.display_name, p.canonical_name) n from catalogue.providers p
     where p.lifecycle_status = 'active'
       and (case when coalesce(p_scope, 'watch') = 'watch' then exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active)
                 else exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')
                   or exists (select 1 from pipeline.scholarship_listing_pages l where l.provider_id = p.id and l.active)
                   or exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active) end)
       and (v_q is null or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
  select (select count(*) from ids), coalesce(jsonb_agg(security.scholarship_coverage_row_v1(x.id) order by x.n), '[]'::jsonb)
    into v_total, v_rows from (select * from ids order by n limit greatest(1, least(coalesce(p_limit, 100), 300)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('scope', coalesce(p_scope, 'watch'), 'total', v_total, 'rows', v_rows, 'can_manage', v_rank >= 6, 'can_watch', v_rank >= 5,
    'auto_publish', jsonb_build_object('on', security.scholarship_setting('auto_publish', 0) >= 1,
      'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name), 'at', b.created_at,
                    'status', s.publication_status, 'value', s.award_value_text, 'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'))
                    order by b.created_at desc, s.name), '[]'::jsonb)
                   from pipeline.scholarship_publication_batches b cross join lateral unnest(b.scholarship_ids) sid
                   join scholarship.scholarships s on s.id = sid join catalogue.providers p on p.id = s.provider_id
                  where b.kind = 'publish' and b.approval_ref like 'auto-publish%' and b.created_at > now() - interval '3 days')),
    'totals', jsonb_build_object(
      'watch', (select count(*) from pipeline.scholarship_watch w where w.active),
      'with_listing', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.active and l.source <> 'suggested'),
      'suggested', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.source = 'suggested' and not exists (select 1 from pipeline.scholarship_listing_pages a where a.provider_id = l.provider_id and a.active and a.source <> 'suggested')),
      'checked', (select count(*) from pipeline.scholarship_coverage_checks),
      'active', (select count(*) from scholarship.scholarships where lifecycle_status = 'active'),
      'published', (select count(*) from scholarship.scholarships where lifecycle_status = 'active' and publication_status = 'published')));
end $function$
