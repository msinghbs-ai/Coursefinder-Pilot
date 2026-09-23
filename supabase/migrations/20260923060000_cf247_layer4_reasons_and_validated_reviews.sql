-- CF-CHG-20260915-247: plain-English Layer 4 reasons end to end.
-- 1. layer3_complete_interpretation_service (15-arg) no longer opens a Layer 4 review
--    for a VALIDATED provider_current_tuition_validation result: admission decides, and
--    admission holds open their own review. Other task classes are unchanged.
-- 2. layer3_route_work_item_layer4_service updates an existing pending review with the
--    caller's plain-English reason (previously it kept the old wording), and its fallback
--    reasons are plain English.
-- Guarded: each edit aborts unless its anchor is found exactly once; re-running is a no-op.
do $mig$
declare
  sig_c regprocedure := 'public.layer3_complete_interpretation_service(uuid,jsonb,jsonb,numeric,text,jsonb,jsonb,boolean,text,integer,integer,numeric,timestamp with time zone,integer,integer)'::regprocedure;
  sig_r regprocedure := 'public.layer3_route_work_item_layer4_service(uuid,uuid,text)'::regprocedure;
  d text; a text; b text; n int;
begin
  -- 1. completion step
  d := pg_get_functiondef(sig_c);
  a := $q$if p_valid and v_i.task_class<>'source_pattern' then$q$;
  b := $q$if p_valid and v_i.task_class<>'source_pattern' and not (v_i.task_class='provider_current_tuition_validation' and v_status='validated') then$q$;
  if strpos(d, b) = 0 then
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    if n <> 1 then raise exception 'completion anchor found % times; aborting', n; end if;
    execute replace(d, a, b);
  end if;

  -- 2. routing step: update an existing pending review with the caller's reason
  d := pg_get_functiondef(sig_r);
  a := E'  if v_review is null then\n    insert into pipeline.layer4_review_items(';
  b := E'  if v_review is not null and nullif(trim(p_reason),\'\') is not null then\n    update pipeline.layer4_review_items set escalation_reason=trim(p_reason)\n    where id=v_review and status=\'pending\';\n  end if;\n\n  if v_review is null then\n    insert into pipeline.layer4_review_items(';
  if strpos(d, 'set escalation_reason=trim(p_reason)') = 0 then
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    if n <> 1 then raise exception 'routing anchor found % times; aborting', n; end if;
    d := replace(d, a, b);
    d := replace(d, $q$'Layer 3 safely abstained; human resolution or more Evidence required'$q$,
                    $q$'The page doesn''t clearly support this fee. Please check the page and confirm the fee, or mark it as not available.'$q$);
    d := replace(d, $q$'Layer 3 result is below the governed confidence threshold'$q$,
                    $q$'The AI wasn''t confident enough (below 90%). Please check the page and confirm the fee.'$q$);
    d := replace(d, $q$'Layer 3 provider/transport retries exhausted; human resolution or later retry required'$q$,
                    $q$'The AI service couldn''t be reached after several attempts. Please check the page and confirm the fee, or retry later.'$q$);
    d := replace(d, $q$'Layer 3 deterministic validation rejected the model result'$q$,
                    $q$'The AI''s answer couldn''t be accepted automatically. Please check the page and confirm the fee.'$q$);
    execute d;
  end if;
end $mig$;
