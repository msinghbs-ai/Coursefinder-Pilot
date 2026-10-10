CREATE OR REPLACE FUNCTION public.admin_fee_rule_preview(p_provider_id uuid, p_phrase text, p_url_pattern text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_phrase, ''))) < 6 then raise exception 'type at least 6 characters of the words that come before the fee'; end if;
  return (select jsonb_build_object(
      'would_admit', count(*) filter (where amounts = 1 and not has_fee and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition')),
      'ambiguous', count(*) filter (where amounts > 1), 'already_had_fee', count(*) filter (where amounts = 1 and has_fee),
      'amount_range', jsonb_build_object('min', min(amount), 'max', max(amount)),
      'samples', (select coalesce(jsonb_agg(s), '[]'::jsonb) from (
          select jsonb_build_object('course_id', m2.course_id, 'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', m2.amount,
                 'fee_year', m2.fee_year, 'text', m2.matched_text, 'url', m2.url, 'has_fee', m2.has_fee, 'amounts', m2.amounts) s
            from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m2 join catalogue.courses c on c.id = m2.course_id
           order by m2.amounts desc, m2.amount limit 15) z))
    from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m);
end $function$
