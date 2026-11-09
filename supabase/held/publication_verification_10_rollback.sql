-- Reversal of supabase/migrations/20261110110000_cf247_publication_verification_10.sql (nothing is dropped or deleted).
-- Sets the same ten courses back to 'unpublished' through the existing function, marks their approvals 'revoked', and asks for one Search refresh.
-- Paste into the Supabase SQL editor (project fxcwkweaxjtknorudmwp) only if the Platform Admin decides to withdraw the verification.
do $rb$
declare
  v_keys constant text[] := array[   -- fixed: the same bounded set as the publication
    'course:cricos:00120c:028147f','course:cricos:00026a:058180a','course:cricos:03389e:090275e','course:cricos:00591e:107756m','course:cricos:03687f:104369b',
    'course:nzqa:7006:li0681','course:nzqa:7002:wi0893','course:nzqa:7006:li3670','course:nzqa:6025:2206','course:nzqa:6013:2715'];
  r record;
begin
  for r in select c.id from catalogue.courses c where c.stable_key = any(v_keys) loop
    perform publishing.set_course_publication_v1(r.id, 'unpublished', 'pilot-course-positive-v1', 'Withdrawn: reversal of the bounded publication verification (Platform Admin).');
  end loop;
  update publishing.publication_approvals pa set approval_status = 'revoked', revoked_at = now(), updated_at = now()
    where pa.profile_code = 'pilot-course-positive-v1' and pa.entity_id in (select c.id from catalogue.courses c where c.stable_key = any(v_keys));
  insert into search.refresh_requests(requested_by) values ('publication verification reversal (10 courses, Platform Admin)');
end
$rb$;
