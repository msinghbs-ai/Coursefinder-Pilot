CREATE OR REPLACE FUNCTION security.scholarship_ai_backfill_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record; v_ids uuid[]; v_n int; v_per int;
begin
  select * into a from security.scholarship_ai_active_v1();
  if not coalesce(a.ai_admission, false) or a.model_code is null then return jsonb_build_object('skipped', 'AI admission is off'); end if;
  select backfill_providers_per_night into v_per from pipeline.scholarship_ai_extract_settings where id = 1;
  v_ids := array(select c.provider_id from pipeline.scholarship_page_candidates c
                  where c.admit_status = 'rejected' and c.source <> 'register'
                    and not exists (select 1 from pipeline.scholarship_ai_extractions e where e.candidate_id = c.id and e.model_code = a.model_code and e.prompt_version = a.prompt_version)
                  group by c.provider_id order by count(*) desc limit v_per);
  if cardinality(v_ids) = 0 then return jsonb_build_object('done', 'every university read'); end if;
  v_n := security.scholarship_ai_enqueue_v1('admit', v_ids, null, true);
  return jsonb_build_object('providers', cardinality(v_ids), 'pages', v_n);
end $function$
