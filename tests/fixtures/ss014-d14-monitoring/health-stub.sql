-- SS-014 P2 fixtures: a skeleton of security.platform_health_check_v1 holding only its coverage page reading rule. Lines 122 to 129 of
-- the live definition (md5 964db44f, read 2 Nov 2026) are copied exactly; run.sh checks lines 126, 127 and 129 against their live md5s
-- (5b390eac, 88439930, e52e47dc). The stall helper here returns the count and the stall start, so fixtures.sql can compare them with the reader.
create function security.platform_health_stall_v1(p_key text, p_area text, p_label text, p_job text, p_since timestamptz, p_sql text) returns jsonb language plpgsql as $f$
declare n bigint; begin execute p_sql into n; return jsonb_build_array(jsonb_build_object('queue', p_key, 'waiting', n, 'since', p_since)); end $f$;
CREATE OR REPLACE FUNCTION security.platform_health_check_v1(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_t timestamptz; v_q jsonb; v_ts timestamptz;
begin
    v_t:=clock_timestamp(); v_q:='[]'::jsonb;
    begin
      -- SS-004 (1 Nov 2026): waiting is measured from the later of the last read and the moment the oldest waiting page became due, so a page that
      -- has only just become due after a quiet spell is not reported as hours of stall; a page left waiting still ages and goes critical
      select greatest(max(read_at), (select min(coalesce(q.next_read_at, q.bound_at)) from pipeline.coverage_course_pages q
                                      where q.status in ('bound','ambiguous') and coalesce(q.next_read_at,now())<=now() and q.read_attempts<3)) into v_ts from pipeline.coverage_course_pages;
      v_q:=v_q||security.platform_health_stall_v1('coverage_queues:read','coverage sweep','Coverage page reading','coverage-read',v_ts,
        $q$select count(*) from pipeline.coverage_course_pages p where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and p.read_attempts<3$q$);
    end;
  return v_q;
end $function$;
