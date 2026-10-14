CREATE OR REPLACE FUNCTION security.exit_awards_apply_v2(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_src uuid; v_hash text; v_fee record; v_itk text[]; v_payload jsonb; v_mode text; v_done int := 0; v_err int := 0; v_skipped int := 0; v_last text; v_courses uuid[] := '{}'; v_af text[];
begin
  select u.admit_fields into v_af from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and 'exit_awards' = any (u.admit_fields);
  if v_af is null then
    return jsonb_build_object('ok', false, 'note', 'exit awards are not admitted for this university'); end if;
  v_src := security.coverage_sweep_source(p_provider_id);
  for r in
    select x.*, pc.course_url parent_url, pc.delivery_mode parent_mode, ch.delivery_mode child_mode
      from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id join catalogue.courses ch on ch.id = x.child_course_id and ch.lifecycle_status = 'active'
     where x.provider_id = p_provider_id and x.active and x.evidence_id is not null
       and not security.layer4_entity_or_parent_blocked('course', x.child_course_id, 'operational')
  loop
    if r.register_check = 'fail' and r.set_by <> 'hand' then v_skipped := v_skipped + 1; continue; end if;
    begin
      select e.content_hash into v_hash from pipeline.evidence_artifacts e where e.id = r.evidence_id;
      v_payload := jsonb_build_object('course_url', r.page_url);
      select null::numeric amount, null::int fee_year, null::text currency_code into v_fee;
      if 'fee' = any (v_af) then
        select f.amount, f.fee_year, f.currency_code into v_fee from catalogue.course_fees f
         where f.course_id = r.parent_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount > 0
         order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
      end if;
      if v_fee.amount is not null and not security.uni_adapter_excluded(r.child_course_id, 'fee')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('tuition', 'fee', 'fees'))
         and (select f.amount from catalogue.course_fees f where f.course_id = r.child_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fee.fee_year, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee.amount then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.child_course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fee.fee_year, 0) and amount <> v_fee.amount;
        v_payload := v_payload || jsonb_build_object('fee_amount', v_fee.amount, 'fee_year', v_fee.fee_year, 'currency_code', v_fee.currency_code, 'fee_basis', 'annual', 'audience', 'international',
                       'fee_notes', case r.link_type when 'nested_award' then 'Award within the course on this page (' || r.exit_years || ' years of full-time study): annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')'
                                    else 'Exit award after ' || r.exit_years || ' years of full-time study in the course on this page: annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')' end);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'fee', null, jsonb_build_object('amount', v_fee.amount, 'year', v_fee.fee_year, 'exit_award_of', r.parent_course_id, 'link_type', r.link_type, 'years', r.exit_years, 'whole_fee', round(v_fee.amount * r.exit_years, 2), 'register_check', r.register_check), r.evidence_id, r.page_url);
      end if;
      v_itk := null;
      if 'intakes' = any (v_af) then
        v_itk := (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.parent_course_id and i.status = 'active');
      end if;
      if v_itk is not null and not security.uni_adapter_excluded(r.child_course_id, 'intakes')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('intakes', 'intake'))
         and (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.child_course_id and i.status = 'active') is distinct from v_itk then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.child_course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', 'exit-award:' || r.child_course_id || ':' || lower(m))) from unnest(v_itk) m));
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'intakes', null, jsonb_build_object('months', to_jsonb(v_itk), 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload);
      v_mode := case when 'delivery' = any (v_af) then r.parent_mode end;
      if v_mode is not null and r.child_mode is distinct from v_mode and not security.uni_adapter_excluded(r.child_course_id, 'delivery')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('delivery_mode', 'delivery')) then
        update catalogue.courses set delivery_mode = v_mode, updated_at = now() where id = r.child_course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'delivery', to_jsonb(r.child_mode), jsonb_build_object('mode', v_mode, 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      update pipeline.course_exit_awards set applied_at = now(), annual_fee = v_fee.amount, fee_year = v_fee.fee_year, total_fee = round(v_fee.amount * r.exit_years, 2) where child_course_id = r.child_course_id;
      v_done := v_done + 1; v_courses := v_courses || r.child_course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('ok', true, 'applied', v_done, 'skipped_check_failed', v_skipped, 'errors', v_err, 'last_error', v_last);
end $function$
