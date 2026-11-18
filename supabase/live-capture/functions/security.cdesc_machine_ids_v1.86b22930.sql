CREATE OR REPLACE FUNCTION security.cdesc_machine_ids_v1(p_ids uuid[])
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid[]; v_rel regclass := to_regclass('pipeline.course_description_machine_admissions');
begin
  -- the ledger exists once the machine admission change is applied (20261110060000): course_id, outcome ('admitted' | 'declined') and withdrawn_at.
  -- Not there, or not that shape: unknown (null), which the screen shows as "not known", never as "no machine admission".
  if v_rel is null or (select count(*) from pg_attribute a where a.attrelid = v_rel and a.attname in ('course_id', 'outcome', 'withdrawn_at') and not a.attisdropped) <> 3 then return null; end if;
  -- only a live admission counts: a declined row, or an admission a person later withdrew, is not "Machine-admitted" (a declined course a person then approved is "Human decision")
  execute 'select coalesce(array_agg(distinct m.course_id), ''{}''::uuid[]) from pipeline.course_description_machine_admissions m where m.course_id = any ($1) and m.outcome = ''admitted'' and m.withdrawn_at is null' into v using p_ids;
  return v;
end $function$
