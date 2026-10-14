CREATE OR REPLACE FUNCTION security.provider_english_apply_all_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r record; v jsonb; v_total int := 0; v_n int := 0; v_failed int := 0;
begin
  for r in select id from pipeline.provider_policy_proposals where kind = 'english_policy' and status = 'approved' order by decided_at loop
    begin
      v := security.provider_english_apply_v1(r.id); v_total := v_total + coalesce((v->>'written')::int, 0); v_n := v_n + 1;
    exception when others then
      v_failed := v_failed + 1;
      update pipeline.provider_policy_proposals set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('last_error', left(sqlerrm, 200), 'last_failed_at', now()), updated_at = now() where id = r.id;
    end;
  end loop;
  return jsonb_build_object('proposals', v_n, 'written', v_total, 'not_applied', v_failed);
end $function$
