CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_provider_finish(p_run_id uuid, p_provider_id uuid, p_evidence_id uuid, p_status text, p_outcome jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare
  v_status text:=lower(coalesce(nullif(trim(p_status),''),'blocked'));
  v_remaining integer;
  v_summary jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if v_status not in ('source_pattern_candidate','source_limited','blocked','layer3_required','layer4_required') then
    raise exception 'invalid qualification provider status' using errcode='22023';
  end if;

  update pipeline.layer2_scale_qualification_items
  set status=v_status,
      evidence_id=coalesce(p_evidence_id,evidence_id),
      outcome=coalesce(outcome,'{}'::jsonb)||coalesce(p_outcome,'{}'::jsonb)||
        jsonb_build_object(
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
  where run_id=p_run_id and provider_id=p_provider_id and status='qualifying';

  select count(*) into v_remaining
  from pipeline.layer2_scale_qualification_items
  where run_id=p_run_id and status in ('selected','qualifying');

  if v_remaining=0 then
    select jsonb_build_object(
      'source_pattern_candidate',count(distinct provider_id) filter(where status='source_pattern_candidate'),
      'source_limited',count(distinct provider_id) filter(where status='source_limited'),
      'layer3_required',count(distinct provider_id) filter(where status='layer3_required'),
      'layer4_required',count(distinct provider_id) filter(where status='layer4_required'),
      'blocked',count(distinct provider_id) filter(where status='blocked'),
      'course_samples',count(*),
      'evidence_backed_samples',count(*) filter(where evidence_id is not null)
    ) into v_summary
    from pipeline.layer2_scale_qualification_items
    where run_id=p_run_id;

    update pipeline.layer2_scale_qualification_runs
    set status=case when coalesce((v_summary->>'blocked')::integer,0)>0 then 'partial' else 'completed' end,
        completed_at=now(),
        result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
          'source_seed_results',v_summary,
          'next_step','course_page_source_pattern_validation',
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
    where id=p_run_id;
  end if;

  return jsonb_build_object('ok',true,'run_id',p_run_id,'provider_id',p_provider_id,'status',v_status,'remaining',v_remaining);
end $function$
