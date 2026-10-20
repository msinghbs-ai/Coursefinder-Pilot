CREATE OR REPLACE FUNCTION security.enrichment_flags_log_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if coalesce(current_setting('cf.flag_fn', true), '') = '1' then return null; end if;  -- the flag functions write their own history
  if tg_op = 'INSERT' then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
    values (new.id, case when new.state = 'raised' then 'raised' else 'released' end, coalesce(new.source, 'unknown'), 'auto', new.reason, new.evidence);
  elsif new.state is distinct from old.state then
    insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence)
    values (new.id, case new.state when 'raised' then 're_raised' when 'released' then 'released' else 'counted' end, coalesce(new.source, 'unknown'), 'auto', new.reason, new.evidence);
  end if;
  return null;
end $function$
