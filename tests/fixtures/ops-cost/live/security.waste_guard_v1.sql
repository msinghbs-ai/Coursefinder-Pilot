CREATE OR REPLACE FUNCTION security.waste_guard_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return jsonb_build_object('idle', security.waste_idle_guard_v1(), 'frozen', security.waste_flipflop_guard_v1(), 'flags', security.enrichment_flags_refresh_v1());
end $function$
;
