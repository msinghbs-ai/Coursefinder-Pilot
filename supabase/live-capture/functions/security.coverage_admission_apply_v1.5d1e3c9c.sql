CREATE OR REPLACE FUNCTION security.coverage_admission_apply_v1(p_limit integer DEFAULT 300, p_extractor text DEFAULT 'coverage-sweep-v0.5.4'::text, p_attributes text[] DEFAULT ARRAY['official_url'::text, 'english'::text])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare r record; v_src uuid; v_ok int:=0; v_err int:=0; v_l4 int:=0; v_courses uuid[]:='{}'; v_before jsonb; v_after jsonb; v_payload jsonb; v_last text;
        v_auto int:=0; v_item uuid; v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; v_rule text;  -- fixed: the system automation account (Decision 263)
        v_lock int := 0; v_held int := 0; v_skip int := 0; v_stop boolean := false;
        v_cap int := greatest(1, security.pipeline_num_v1('admit.item_error_limit', 25)::int);
        v_recheck interval := make_interval(hours => security.pipeline_num_v1('admit.refused_recheck_hours', 24)::int);
begin
  drop table if exists _adm;
  create temp table _adm on commit drop as select * from security.coverage_admission_plan_v1(p_extractor) where action in ('write','differs') and attribute=any(p_attributes);
  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;

  -- IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): a course whose page, English requirement or intakes were set by hand is never offered to
  -- apply. Its rows are held with the named reason manual_lock (pipeline.coverage_admission_holds) and leave the batch: not written, not raised
  -- to Layer 4, not decided by rule. The lock rule itself (security.layer4_course_link_apply_impl) is unchanged.
  insert into pipeline.coverage_admission_holds as h(course_id, attribute, proposed_md5, proposed, page_url, plan_action, reason, detail)
  select distinct on (a.course_id, a.attribute, md5(a.proposed::text)) a.course_id, a.attribute, md5(a.proposed::text), a.proposed, a.page_url, a.action,
         'manual_lock', jsonb_build_object('lock_fields', k.f, 'current', a.current)
    from _adm a cross join lateral (select array_agg(l.field order by l.field) f from pipeline.manual_locks l
                                     where l.entity = 'course' and l.entity_id = a.course_id and l.field = any (security.coverage_admission_lock_fields_v1(a.attribute))) k
   where k.f is not null
  on conflict (course_id, attribute, proposed_md5) do update
     set last_seen_at = now(), seen_count = h.seen_count + 1, reason = excluded.reason, detail = excluded.detail, plan_action = excluded.plan_action;
  get diagnostics v_lock = row_count; delete from _adm a where exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = a.course_id
                                      and l.field = any (security.coverage_admission_lock_fields_v1(a.attribute)));
  -- IQ-00067: a proposal the apply refused waits admit.refused_recheck_hours before it is tried again, unless it changes
  v_skip := 0; delete from _adm a where exists (select 1 from pipeline.coverage_admission_holds h where h.course_id = a.course_id and h.attribute = a.attribute
                                      and h.proposed_md5 = md5(a.proposed::text) and h.reason = 'apply_refused' and h.last_seen_at > now() - v_recheck);
  get diagnostics v_skip = row_count;
  if not exists (select 1 from _adm) then
    return jsonb_build_object('written',0,'layer4',0,'held_manual_lock',v_lock,'refused_waiting',v_skip);
  end if;

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
      -- IQ-00067: the refused item is held with its reason and the batch goes on, up to admit.item_error_limit refusals a run
      perform security.coverage_admission_hold_v1(r.course_id, r.props, r.page_url, 'write', 'apply_refused',
                jsonb_build_object('error', left(sqlerrm, 500), 'sqlstate', sqlstate));
      v_held := v_held + 1;
      if v_held >= v_cap then v_stop := true; end if;
    end;
    exit when v_stop;
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
    exit when v_stop;
    begin
    v_rule := case when r.attribute = 'official_url' then security.course_page_rule_v1(r.current->>0, r.proposed->>'course_url') end;
    -- 24 Oct 2026 (UI audit Phase 0): a "take" rule never applies a plain http:// address (the link apply refuses it and the whole
    -- batch failed, every run since 23 Oct 11:40 UTC); the row waits for a person instead, like any row no rule decides
    if v_rule like 'take:%' and coalesce(r.proposed->>'course_url', '') !~* '^https://' then v_rule := null; end if;
    -- IQ-00043 (Platform Admin 3 Nov 2026 08:44 §5): a rule never takes a page that was replaced, rejected or held; the row waits for a person
    if v_rule like 'take:%' and security.course_link_hold_basis_v1(r.course_id, 'official_course', r.proposed->>'course_url', null) is not null then v_rule := null; end if;
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
    exception when others then
      -- IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): one item never aborts the batch. Its Layer 4 item, link and decision roll back together;
      -- the item is held with the refusal named, and the batch goes on, up to admit.item_error_limit refusals a run
      v_err := v_err + 1; v_last := left(sqlerrm, 200);
      perform security.coverage_admission_hold_v1(r.course_id, jsonb_build_object(r.attribute, r.proposed), r.page_url, 'differs', 'apply_refused',
                jsonb_build_object('error', left(sqlerrm, 500), 'sqlstate', sqlstate, 'rule', v_rule, 'current', r.current));
      v_held := v_held + 1;
      if v_held >= v_cap then v_stop := true; end if;
    end;
  end loop;

  if cardinality(v_courses)>0 then
    -- 20261119104500 (s720): never wait for the search-document writer; when it is busy the courses go to the search refresh queue, as
    -- security.intake_dates_apply_v1 does (search.refresh_requests, processed by the search refresh job's next run)
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
      perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    else
      insert into search.refresh_requests(requested_by) values ('coverage admission: ' || cardinality(v_courses) || ' courses (search writer busy)');
    end if;
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label,snapshot) values
      ('before coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_before),
      ('after coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_after);
  end if;
  return jsonb_build_object('written',v_ok,'errors',v_err,'last_error',v_last,'layer4',v_l4,'decided_by_rule',v_auto,
                            'held_manual_lock',v_lock,'held_refused',v_held,'refused_waiting',v_skip,'stopped_at_limit',v_stop);
end $function$
