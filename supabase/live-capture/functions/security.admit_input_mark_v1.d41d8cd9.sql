CREATE OR REPLACE FUNCTION security.admit_input_mark_v1()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the newest change any admit job depends on: pages read, adapters and their admission, checked values, exclusions, locks, review decisions,
  -- courses and providers (lifecycle, Published switch)
  select greatest(
    (select max(pg.read_at) from pipeline.coverage_course_pages pg),
    (select max(greatest(u.updated_at, u.admit_changed_at)) from pipeline.uni_adapters u),
    (select max(i.created_at) from pipeline.layer3_interpretations i where i.status = 'validated'),
    (select max(x.set_at) from pipeline.uni_adapter_exclusions x),
    (select max(x.set_at) from pipeline.uni_adapter_delivery_exclusions x),
    (select max(k.set_at) from pipeline.manual_locks k),
    (select max(r.decided_at) from pipeline.layer4_review_items r),
    (select max(c.updated_at) from catalogue.courses c),
    (select max(p.updated_at) from catalogue.providers p),
    '-infinity'::timestamptz)
$function$
