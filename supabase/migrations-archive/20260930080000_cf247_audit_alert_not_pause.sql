-- CF-247 cost leak (Platform Admin, 30 Sep 2026 02:49 IST: "Something is still leaking"). At 01:46 and 01:57 IST the
-- spot-check rule in layer3_fact_complete_ladder_service switched the cheapest step (Qwen3 30B) off for intakes and
-- English after 3 disagreements in its last 60 spot checks. Every page then went straight to the paid final step
-- (Claude Haiku 4.5 for intakes): about US$4.80 in the next hour, until the OpenRouter credit floor stopped Layer 3 at
-- 02:13 IST. The rule now never switches a step off by itself: it records one 'tier_audit_alert' (at most one an hour
-- per model) for the Platform Admin, who decides on the Layer 3 Control screen. Edited in place from the live
-- definition, only if unchanged since 20260930061000 (md5).
do $g$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb)'::regprocedure)<>'ded3755dc880899dfa690654aa5dd906' then
    raise exception 'cf247_audit_alert_not_pause: layer3_fact_complete_ladder_service changed since 20260930061000; review first';
  end if;
  d:=pg_get_functiondef('public.layer3_fact_complete_ladder_service(uuid,uuid,jsonb,jsonb)'::regprocedure);
  n:=replace(d,'if v_disagree>=3 and not v_tier.is_final then',
    $s$if v_disagree>=3 and not v_tier.is_final and not exists (select 1 from pipeline.layer3_route_events e where e.kind='tier_audit_alert' and e.detail->>'profile_id'=v_tier.profile_id::text and e.created_at>now()-interval '1 hour') then$s$);
  n:=replace(n,E'      update pipeline.layer3_route_tiers set active=false, updated_at=now() where id=v_tier.id;\n','');
  n:=replace(n,$s$values ('tier_paused_audit',$s$,$s$values ('tier_audit_alert',$s$);
  if position('set active=false' in n)>0 or position('tier_audit_alert' in n)=0 or position('interval ''1 hour''' in n)=0 then
    raise exception 'audit edit did not apply exactly';
  end if;
  execute n;
end $g$;
