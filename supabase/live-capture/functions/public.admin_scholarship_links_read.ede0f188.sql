CREATE OR REPLACE FUNCTION public.admin_scholarship_links_read(p_view text DEFAULT 'waiting'::text, p_q text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_decide', v_rank >= 4,
    'summary', (select jsonb_build_object('waiting_links', count(*) filter (where c.status = 'needs_review'),
                   'waiting_scholarships', count(distinct c.scholarship_id) filter (where c.status = 'needs_review'),
                   'decided_scholarships', (select count(*) from pipeline.scholarship_scope_decisions),
                   'accepted_links', count(*) filter (where c.status = 'accepted'), 'rejected_links', count(*) filter (where c.status = 'rejected'))
                  from scholarship.course_mapping_candidates c),
    'items', (select coalesce(jsonb_agg(x order by (x->>'waiting')::int desc, x->>'name'), '[]'::jsonb) from (
       select jsonb_build_object('scholarship_id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name),
              'award_type', s.award_value_type, 'award', coalesce(s.award_value_text, case when s.award_percentage is not null then s.award_percentage || '%' end,
                        case when s.award_amount is not null then s.award_currency_code || ' ' || s.award_amount end),
              'source_url', s.source_url, 'waiting', count(*) filter (where c.status = 'needs_review'), 'proposed', count(*),
              'accepted', count(*) filter (where c.status = 'accepted'),
              'decision', (select jsonb_build_object('decision', d.decision, 'at', d.decided_at, 'by', u.email, 'accepted', d.accepted, 'rejected', d.rejected)
                             from pipeline.scholarship_scope_decisions d left join auth.users u on u.id = d.decided_by where d.scholarship_id = s.id),
              'suggestion', security.scholarship_scope_suggest(s.id)) x
         from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id = c.scholarship_id
         left join catalogue.providers p on p.id = s.provider_id
        where (p_q is null or s.name ilike '%' || p_q || '%' or coalesce(p.display_name, p.canonical_name) ilike '%' || p_q || '%')
        group by s.id, s.name, p.display_name, p.canonical_name
       having case coalesce(p_view, 'waiting') when 'waiting' then count(*) filter (where c.status = 'needs_review') > 0
                                                 when 'decided' then exists (select 1 from pipeline.scholarship_scope_decisions d where d.scholarship_id = s.id)
                                                 else true end
        limit 300) y));
end $function$
