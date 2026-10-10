CREATE OR REPLACE FUNCTION public.admin_fee_rules_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_create', v_rank >= 4, 'can_approve', v_rank >= 5,
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'provider_id', r.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
                'label', r.label, 'phrase', r.phrase, 'basis', r.basis, 'url_pattern', r.url_pattern, 'status', r.status, 'admitted', r.admitted,
                'created_at', r.created_at, 'created_by', cu.email, 'approved_at', r.approved_at, 'approved_by', au.email, 'last_run_at', r.last_run_at, 'note', r.note)
                order by r.status = 'active' desc, r.created_at desc), '[]'::jsonb)
                from pipeline.fee_wording_rules r left join catalogue.providers p on p.id = r.provider_id
                left join auth.users cu on cu.id = r.created_by left join auth.users au on au.id = r.approved_by),
    'suggestions', (select coalesce(jsonb_agg(s order by (s->>'pages')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('provider_id', w.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'phrase', w.phrase,
              'pages', count(distinct w.course_id), 'example', min(w.example),
              'has_rule', exists (select 1 from pipeline.fee_wording_rules r where r.provider_id = w.provider_id and lower(r.phrase) = lower(w.phrase))) s
         from (select g.provider_id, g.course_id, security.fee_suggest_phrase(c->>'context', (c->>'amount')::numeric) phrase, left(c->>'context', 240) example
                 from pipeline.coverage_course_pages g
                 join pipeline.provider_priority pp on pp.provider_id = g.provider_id and pp.rank <= 100
                 cross join lateral jsonb_array_elements(coalesce(g.candidates->'fee'->'candidates', '[]'::jsonb)) c
                where g.read_status = 'read' and g.identity_basis in ('cricos_code','manual') and coalesce(g.candidates->'fee'->>'safe', 'false') <> 'true'
                  and coalesce((c->>'domestic')::boolean, false) = false
                  and not exists (select 1 from catalogue.course_fees f where f.course_id = g.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active')) w
         join catalogue.providers p on p.id = w.provider_id
        where w.phrase is not null
        group by w.provider_id, p.display_name, p.canonical_name, w.phrase
       having count(distinct w.course_id) >= 10
        order by count(distinct w.course_id) desc limit 25) z),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', a.admitted_at, 'rule_id', a.rule_id, 'course_id', a.course_id,
                'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', a.amount, 'fee_year', a.fee_year, 'basis', a.basis, 'text', a.matched_text)
                order by a.admitted_at desc), '[]'::jsonb)
                from (select * from pipeline.fee_rule_admissions order by admitted_at desc limit 30) a join catalogue.courses c on c.id = a.course_id));
end $function$
