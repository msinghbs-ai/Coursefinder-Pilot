-- CF-247 (3 Oct 2026, 21:45 AEST). Scholarship plan step 7, first part: what counsellors see. The course and provider
-- scholarship selections carry the new facts (nationalities read from wording, whether the value is a maximum), and the
-- Zoho course API gets a service-role read that returns the selection for a course (by id or stable key), published
-- scholarships only, so a counsellor's tool can ask "for this course, what can this student get" and show the value,
-- who qualifies (audience, nationalities, criteria in the page's words), the saving per year where known, and the
-- close date and page link. The two selection functions are replaced under md5 guards; one line changes in each.
do $g$ declare r record; begin
  for r in select p.oid, n.nspname || '.' || p.proname fn, md5(p.prosrc) m from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'security' and p.proname in ('scholarship_selection_for_course_impl', 'scholarship_selection_for_provider_impl') loop
    if r.m not in ('7d3809a34107ca37bd34fe077f80464b', 'de88be3a210c5c1891b036036dcbb312') then raise exception '% changed (md5 %); not replacing', r.fn, r.m; end if;
    if (select count(*) from regexp_matches(pg_get_functiondef(r.oid), '''audience'',s\.audience,''award_value_text'',s\.award_value_text,', 'g')) <> 1 then raise exception '% source_fact line not found exactly once', r.fn; end if;
    execute replace(pg_get_functiondef(r.oid), $x$'audience',s.audience,'award_value_text',s.award_value_text,$x$,
      $x$'audience',s.audience,'nationalities',s.nationalities,'award_value_is_maximum',s.award_value_is_maximum,'award_value_text',s.award_value_text,$x$);
  end loop;
end $g$;

-- Zoho / website: published scholarships for a course, with the facts a counsellor needs, read as the service role
create or replace function public.zoho_edge_scholarships_v1(p_course text)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_course uuid; v_sel jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select c.id into v_course from catalogue.courses c where c.id::text = p_course or c.stable_key = p_course limit 1;
  if v_course is null then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  v_sel := security.scholarship_selection_for_course_impl(v_course);
  return jsonb_build_object(
    'course_id', v_course,
    'audience_filter', 'international',
    'scholarships', coalesce((
      select jsonb_agg(jsonb_build_object(
          'scholarship_id', s.id, 'stable_key', s.stable_key, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name),
          'audience', s.audience, 'nationalities', s.nationalities,
          'value', jsonb_build_object('text', s.award_value_text, 'type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'is_maximum', s.award_value_is_maximum,
                                      'tiers', (select jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code, 'basis', t.basis) order by t.display_order) from scholarship.award_tiers t where t.scholarship_id = s.id)),
          'saving', (select jsonb_build_object('year', fc.fee_year, 'currency', fc.currency_code, 'tuition', fc.fee_amount, 'saving', fc.scholarship_saving_amount, 'net', fc.net_fee_amount)
                       from scholarship.course_financial_calculations fc where fc.scholarship_id = s.id and fc.course_id = v_course and fc.calculation_status = 'calculated' order by fc.fee_year desc nulls last limit 1),
          'who_qualifies', (select jsonb_agg(jsonb_build_object('type', cr.criterion_type, 'text', cr.human_text, 'mandatory', cr.is_mandatory) order by cr.created_at) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
          'application', jsonb_build_object('required', s.application_required, 'opens', s.application_open_date, 'closes', s.application_close_date, 'academic_year', s.academic_year),
          'page', s.source_url,
          'match', e->'derived_score', 'selection_state', e->'selection_state', 'eligibility_state', e->'eligibility_state'))
        from jsonb_array_elements(coalesce(v_sel->'candidates', '[]'::jsonb)) e
        join scholarship.scholarships s on s.id = (e->>'scholarship_id')::uuid
        left join catalogue.providers p on p.id = s.provider_id
       where s.lifecycle_status = 'active' and s.publication_status = 'published'), '[]'::jsonb),
    'read_at', now());
end $f$;
revoke all on function public.zoho_edge_scholarships_v1(text) from public, anon, authenticated;
