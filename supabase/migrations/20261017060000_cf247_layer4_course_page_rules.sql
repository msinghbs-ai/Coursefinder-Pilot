-- CF-247 Decision 263 (17 Oct 2026): course page rules run automatically; a decided proposal is never raised again. Platform Admin 17 Oct 2026
-- 16:19 ("Bring everything from layer 4 and assess either for rule or ai extraction and proceed or give me recomemded choices") and the choice
-- "Yes, automate": the course page reader applies these rules itself and records why; only real disagreements reach Layer 4.
-- Found: coverage_admission_apply_v1 raised a "course page that shows this course's CRICOS code is a different address" item again whenever a
-- person had rejected it (only superseded items were remembered): 63 items rejected at 16:2x were raised again at 16:40.
-- Now, for each differing value the coverage sweep finds:
--   * a proposal decided before (rejected, approved or edited and approved, same proposed value) is not raised again;
--   * official course page, decided by rule under the system automation account, with the rule as the reason (shown in Layer 4 history):
--       keep the held page (reject): the proposed page is a course directory or search site, a handbook page while the held page is the
--         course page, or a listing, not-found, index, scholarship, minor or domestic-only page;
--       take the proposed page (approve, link written): the held page is a handbook page and the proposed one the provider's course page; the
--         proposed page is the course's own page under the held listing page; the same program code in a newer handbook year;
--   * anything else reaches Layer 4 as before.
-- Replaces: security.coverage_admission_apply_v1 (same name, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure)) <> '9667b916c5a9bfce01409b1668b2558c' then
    raise exception 'live security.coverage_admission_apply_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.course_page_rule_v1(p_held text, p_prop text)
returns text language sql stable set search_path = '' as $function$
  -- Decision 263: which page wins when the coverage sweep proposes a different official course page; null = a person decides
  select case
    when p_prop is null or p_held is null then null
    when security.reference_url_has_use(p_prop, 'not_course_page') then 'keep:the proposed page is a course directory or search site, not the provider''s own site'
    when p_prop ~* '(^https?://handbook\.|programs-courses\.uq\.edu\.au)' and p_held !~* '(^https?://handbook\.|programs-courses\.uq\.edu\.au)'
      then 'keep:the provider''s course page stays official; the handbook page is a reference page'
    when p_prop ~* '(course-not-found|/index\.html$|find-a-study-option\.html$|/areas-of-study/|/postgraduate\.html$|/scholarships/|-minor/?$|/dom/?$)'
      then 'keep:the proposed page is a listing, not-found, scholarship, minor or domestic-only page'
    when p_held ~* '^https?://handbook\.' and p_prop !~* '^https?://handbook\.'
         and substring(p_held from '^https?://handbook\.([^/]+)') = regexp_replace(substring(p_prop from '^https?://([^/]+)'), '^www\.', '')
      then 'take:the held page is the handbook; the provider''s course page showing the CRICOS code becomes official'
    when p_prop like rtrim(p_held, '/') || '/%' then 'take:the held page is a listing; the course''s own page under it becomes official'
    when substring(p_held from '^https?://([^/]+)') = substring(p_prop from '^https?://([^/]+)')
         and (regexp_match(p_held, '/(20[0-9]{2})/'))[1] < (regexp_match(p_prop, '/(20[0-9]{2})/'))[1]
         and lower(regexp_replace(rtrim(p_held, '/'), '^.*/', '')) = lower(regexp_replace(rtrim(p_prop, '/'), '^.*/', ''))
      then 'take:the same program code in a newer handbook year'
    else null end
$function$;

CREATE OR REPLACE FUNCTION security.coverage_admission_apply_v1(p_limit integer DEFAULT 300, p_extractor text DEFAULT 'coverage-sweep-v0.5.4'::text, p_attributes text[] DEFAULT ARRAY['official_url'::text, 'english'::text])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare r record; v_src uuid; v_ok int:=0; v_err int:=0; v_l4 int:=0; v_courses uuid[]:='{}'; v_before jsonb; v_after jsonb; v_payload jsonb; v_last text;
        v_auto int:=0; v_item uuid; v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; v_rule text;  -- fixed: the system automation account (Decision 263)
begin
  drop table if exists _adm;
  create temp table _adm on commit drop as select * from security.coverage_admission_plan_v1(p_extractor) where action in ('write','differs') and attribute=any(p_attributes);
  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;

  insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
  select distinct on (s.id) s.id, s.country_id, 'au_'||lower(a.provider_cricos)||'_coverage_sweep','provider_first_party',
         coalesce(p.display_name,p.canonical_name), upper(a.provider_cricos), array['official_course_url','english_requirement','intake'],
         'course page accepted only when it prints the course''s CRICOS code',
         'page stored gzipped as evidence with its SHA-256; values written only where the course has none',
         'bounded','Decision 163 admission rule (Platform Admin 29 Sep 2026)',
         jsonb_build_object('decision','Decision 163','apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
    from _adm a join catalogue.providers p on p.id=a.provider_id
    cross join lateral (select security.coverage_sweep_source(a.provider_id) id) x
    join pipeline.sources s on s.id=x.id
   where a.action='write' and a.provider_cricos is not null
     and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id and q.provider_cricos=upper(a.provider_cricos));

  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select distinct 'courses', d, security.coverage_sweep_source(a.provider_id), 'approved',
         'CF-CHG-20260915-247; Decision 163 admission rule; Platform Admin approval 29 Sep 2026 09:56 IST', now(), now(), now()
    from _adm a cross join unnest(array_remove(array['official_course_url', case when 'english'=any(p_attributes) then 'course_english' end, case when 'intakes'=any(p_attributes) then 'course_intake' end],null)) d
   where a.action='write'
     and not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code=d and g.source_id=security.coverage_sweep_source(a.provider_id));

  v_before:=security.consumer_api_snapshot_v1();
  for r in select a.course_id, a.provider_id, a.provider_cricos, a.course_cricos, a.evidence_id, a.content_hash, a.page_url,
                  jsonb_object_agg(a.attribute, a.proposed) props
             from _adm a where a.action='write'
            group by 1,2,3,4,5,6,7 order by md5(a.course_id::text||clock_timestamp()::text) limit greatest(1,least(coalesce(p_limit,300),1000)) loop
    v_payload:='{}'::jsonb;
    if r.props ? 'official_url' then v_payload:=v_payload||jsonb_build_object('course_url',r.props->'official_url'->>'course_url','link_type','official_course','audience','international'); end if;
    if r.props ? 'english' and not security.uni_adapter_excluded(r.course_id, 'english') then v_payload:=v_payload||jsonb_build_object('english_requirements',r.props->'english'->'english_requirements'); end if;
    if r.props ? 'intakes' and not security.uni_adapter_excluded(r.course_id, 'intakes') then v_payload:=v_payload||jsonb_build_object('intakes',r.props->'intakes'->'intakes'); end if;
    begin
      if r.provider_cricos is null or r.course_cricos is null then
        perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), r.evidence_id, r.page_url, r.content_hash, v_payload);
      else
      perform public.svc_coursefacts_apply_record(security.coverage_sweep_source(r.provider_id), r.evidence_id, r.provider_cricos, r.course_cricos,
              'coverage:'||r.course_id, r.page_url, r.content_hash, v_payload, true);
      end if;
      v_ok:=v_ok+1; v_courses:=v_courses||r.course_id;
    exception when others then v_err:=v_err+1; v_last:=left(sqlerrm,200);
    end;
  end loop;

  -- Decision 263: differing values; a proposal decided before is not raised again; official course pages are decided by rule where a rule applies
  for r in select a.*, case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end fc
             from _adm a
            where a.action='differs'
              and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id and i.status='pending'
                                and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end)
              -- CF-247 15 Oct (waste rules): the same proposal is not raised again while an identical one was superseded within the window (it was raised 144 times a day)
              and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id and i.status='superseded'
                                and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end
                                and i.proposed_value=a.proposed and i.decided_at > now() - make_interval(days => security.pipeline_num_v1('waste.flipflop_window_days', 7)::int))
              -- Decision 263: a proposal a person or a rule decided is never raised again
              and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id
                                and i.status in ('rejected','approved','edited_approved')
                                and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end
                                and i.proposed_value=a.proposed) loop
    v_rule := case when r.attribute = 'official_url' then security.course_page_rule_v1(r.current->>0, r.proposed->>'course_url') end;
    insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,before_value,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref,decided_at)
    values ('course', r.course_id, r.fc, r.evidence_id, r.current, r.proposed, jsonb_build_object('source','coverage sweep','page',r.page_url), '{}'::jsonb,
            case when v_rule like 'keep:%' then 'rejected' when v_rule like 'take:%' then 'approved' else 'pending' end,
            case r.attribute
              when 'official_url' then 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.'
              when 'english' then 'The course page gives a different English score from the one we hold. Please check the page and confirm the requirement.'
              else 'The course page lists different intake months from the ones we hold. Please check the page and confirm the intakes.' end,
            case when v_rule is null then 'CF-CHG-20260915-247' else 'CF-CHG-20260915-247; Decision 263 (decided by rule)' end,
            case when v_rule is not null then now() end)
    returning id into v_item;
    if v_rule is null then
      v_l4 := v_l4 + 1;
    else
      if v_rule like 'take:%' then
        perform security.layer4_course_link_apply_impl(v_sys, v_item, jsonb_build_object('url', r.proposed->>'course_url'), 'Rule: ' || substring(v_rule from 6));
        v_courses := v_courses || r.course_id;
      end if;
      insert into pipeline.layer4_decisions(review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,layer2_state,layer3_state,change_control_ref)
      values (v_item, case when v_rule like 'take:%' then 'approve' else 'reject' end, v_sys, 'Decided by rule (Decision 263): ' || substring(v_rule from 6),
              r.current, r.proposed, case when v_rule like 'take:%' then r.proposed end, r.evidence_id,
              jsonb_build_object('source','coverage sweep','page',r.page_url), '{}'::jsonb, 'CF-CHG-20260915-247; Decision 263 (decided by rule)');
      v_auto := v_auto + 1;
    end if;
  end loop;

  if cardinality(v_courses)>0 then
    perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label,snapshot) values
      ('before coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_before),
      ('after coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_after);
  end if;
  return jsonb_build_object('written',v_ok,'errors',v_err,'last_error',v_last,'layer4',v_l4,'decided_by_rule',v_auto);
end $function$;

revoke execute on function security.course_page_rule_v1(text, text) from public, anon, authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.course_page_rule_v1', 'Layer 2', 'Decision 263: which official course page wins when the coverage sweep proposes a different one (keep, take or a person decides)', 'active', '20261017060000')
on conflict (kind, name) do nothing;
