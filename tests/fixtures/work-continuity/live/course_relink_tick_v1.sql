CREATE OR REPLACE FUNCTION security.course_relink_tick_v1(p_batch integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(1, coalesce(p_batch, 200)); v_pid uuid; v_r jsonb; v_found int; v_absent int; v_prov int := 0;
begin
  perform security.page_refind_settle_v1();  -- 19 Oct 2026: re-finds on a provider's current website
  -- settle: a candidate the reader accepted, or every candidate refused
  update pipeline.course_relink x set state = 'found', decided_at = now(), result_url = s.bound_url, reason = 'the reader confirmed the page'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state = 'verified';
  get diagnostics v_found = row_count;
  update pipeline.course_relink x set state = 'absent', decided_at = now(), reason = 'every candidate address was refused by the reader or did not answer'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state in ('none', 'error');
  get diagnostics v_absent = row_count;
  -- next universities with refused pages not yet relinked
  for v_pid in select p.provider_id from pipeline.coverage_course_pages p
                where p.read_status = any (security.course_relink_statuses_v1()) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
                  and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                group by 1 order by count(*) desc loop
    exit when v_left <= 0;
    v_r := security.course_relink_provider_v1(v_pid, v_left);
    v_left := v_left - (v_r->>'trying')::int - (v_r->>'absent')::int;
    v_prov := v_prov + 1;
  end loop;
  return jsonb_build_object('found', v_found, 'absent', v_absent, 'providers', v_prov);
end $function$
