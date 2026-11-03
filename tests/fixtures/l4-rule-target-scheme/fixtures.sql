-- CF-247 IQ-00189: every case after the migration (seed.sql). Each block raises on failure and prints "<id> ok".

-- T1 the validator returns the address the decision writes: http:// given https://; https:// unchanged; an address that is not a web address fails
do $f$
declare a record; b record; c record;
begin
  select * into a from security.layer4_course_link_rule_validate_v1('sfu_no_term', '10000000-0000-0000-0000-000000000050');
  select * into b from security.layer4_course_link_rule_validate_v1('sfu_no_term', '10000000-0000-0000-0000-000000000051');
  select * into c from security.layer4_course_link_rule_validate_v1('sfu_no_term', '10000000-0000-0000-0000-000000000052');
  if not a.pass or a.target_url <> 'https://www.sfu.ca/students/calendar/programs/c50/p.html' or a.proposed_url <> 'http://www.sfu.ca/students/calendar/programs/c50/p.html' then raise exception 'T1: c50 % %', a.target_url, a.reasons; end if;
  if not b.pass or b.target_url <> b.proposed_url then raise exception 'T1: c51 %', b.reasons; end if;
  if c.pass or array_to_string(c.reasons, '; ') <> 'the proposed page is not a full web address (http://www.sfu.ca/students/calendar/programs/c52/p q.html)' then raise exception 'T1: c52 %', c.reasons; end if;
  raise notice 'T1 ok: http:// proposed page targeted as https://; https:// unchanged; an address that cannot be written fails with a clear reason';
end $f$;

-- T2 counting and applying: c50 decided as an edited approval with the https:// address (link active), c51 a plain approval, c52 left waiting
do $f$
declare r jsonb;
begin
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, false);
  if (select action from pipeline.layer4_course_link_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000050') <> 'edit_and_approve'
    then raise exception 'T2: count action'; end if;
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, true);
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, true);
  raise notice 'T2 %', r;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000050') <> 'edited_approved'
     or (select action || ' ' || (final_value->>'course_url') from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000050')
        <> 'edit_and_approve https://www.sfu.ca/students/calendar/programs/c50/p.html'
     or not exists (select 1 from catalogue.course_links where course_id = 'c0000000-0000-0000-0000-000000000050' and url = 'https://www.sfu.ca/students/calendar/programs/c50/p.html' and status = 'active')
    then raise exception 'T2: c50'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000051') <> 'approved'
     or (select action from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000051') <> 'approve' then raise exception 'T2: c51'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000052') <> 'pending'
     or exists (select 1 from pipeline.layer4_course_link_rule_run_items where item_id = '10000000-0000-0000-0000-000000000052' and array_to_string(reasons, ' ') like 'decision refused%')
    then raise exception 'T2: c52'; end if;
  if (select count(*) from pipeline.layer4_decisions where review_item_id::text like '10000000-0000-0000-0000-00000000005%') <> 2 then raise exception 'T2: one decision per item'; end if;
  raise notice 'T2 ok: http:// item decided as an edited approval with the https:// address; https:// item a plain approval; the bad address never reaches the decision';
end $f$;
