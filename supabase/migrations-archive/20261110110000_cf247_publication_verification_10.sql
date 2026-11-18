-- CF-247 bounded production publication verification (Platform Admin, 10 Nov 2026 09:05 AEDT: "supports a bounded, reversible production publication verification of up to 10
-- already eligible, fully source-validated courses ... Use the existing authorised publication path ... not authority to open the whole catalogue").
-- Path used: the existing controlled profile pilot-course-positive-v1 (CF-CHG-20260823-024). An explicit publishing.publication_approvals row is written for each of the ten courses below,
-- then publishing.set_course_publication_v1 publishes each one (canonical + Website + Zoho channel state + publication_events), then one Search refresh is requested through
-- search.refresh_requests (the existing 10-minute job search-refresh-requested applies it). No new function, endpoint, job, table or setting.
-- The ten (stable keys; 5 AU, 5 NZ; each machine-admitted by cdesc-machine-v1 from its own official course page, provider published, lifecycle active, 7-23 evidence links, only blocker = not_explicitly_approved):
--   course:cricos:00120c:028147f  Bachelor of Actuarial Studies (ANU)             course:nzqa:7006:li0681  Bachelor of Viticulture and Oenology (Lincoln)
--   course:cricos:00026a:058180a  Graduate Certificate in Publishing (Sydney)     course:nzqa:7002:wi0893  Master of Disability and Inclusion Studies (Waikato)
--   course:cricos:03389e:090275e  Bachelor of Business (Torrens)                  course:nzqa:7006:li3670  Diploma in Applied Science (Lincoln)
--   course:cricos:00591e:107756m  Diploma of Renewable Energy Engineering (TAFE NSW)   course:nzqa:6025:2206  NZ Diploma in Tourism and Travel (Toi Ohomai)
--   course:cricos:03687f:104369b  Diploma of Leadership and Management (ACCHS)    course:nzqa:6013:2715  NZ Certificate in Mechanical Engineering L3 (Otago Polytechnic)
-- Guards: the migration does nothing on a database that does not hold these courses (a rebuilt or isolated database); it refuses unless all ten are present, none is published, and each one's only blocker is the missing approval.
-- Reversal (not a drop or delete): supabase/held/publication_verification_10_rollback.sql sets the ten back to 'unpublished' through the same function and marks the approvals 'revoked'.
-- The consumer API (G3) is not touched: no function, view, column or edge function changes; only the data the Website and Zoho already read (publication status) changes for these ten courses.
-- A passing qualification does not switch anything on by itself: this publication is the Platform Admin's decision of 10 Nov 2026; the rest of the catalogue stays unpublished.
-- Replaces: nothing
-- Retires: nothing

do $pub$
declare
  v_keys constant text[] := array[   -- fixed: the bounded set the Platform Admin authorised on 10 Nov 2026 (up to 10 courses); not an operating value
    'course:cricos:00120c:028147f','course:cricos:00026a:058180a','course:cricos:03389e:090275e','course:cricos:00591e:107756m','course:cricos:03687f:104369b',
    'course:nzqa:7006:li0681','course:nzqa:7002:wi0893','course:nzqa:7006:li3670','course:nzqa:6025:2206','course:nzqa:6013:2715'];
  v_profile constant text := 'pilot-course-positive-v1';
  v_ids uuid[];
  v_id uuid;
  v_ready jsonb;
  v_res jsonb;
  v_n int;
begin
  select array_agg(c.id order by c.stable_key) into v_ids from catalogue.courses c where c.stable_key = any(v_keys);
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n = 0 then
    raise notice 'publication verification skipped: none of the ten courses exists in this database';
    return;
  end if;
  if v_n <> cardinality(v_keys) then raise exception 'publication verification refused: % of % courses found', v_n, cardinality(v_keys); end if;
  if exists (select 1 from catalogue.courses c where c.id = any(v_ids) and c.publication_status = 'published') then
    raise exception 'publication verification refused: a course in the set is already published';
  end if;
  if not exists (select 1 from publishing.publication_profiles pp where pp.profile_code = v_profile and pp.entity_type = 'course' and pp.profile_status = 'active') then
    raise exception 'publication verification refused: profile % is not active', v_profile;
  end if;

  foreach v_id in array v_ids loop
    v_ready := publishing.course_publication_readiness_v1(v_id, v_profile);
    if v_ready->'blockers' is distinct from '["not_explicitly_approved"]'::jsonb then
      raise exception 'publication verification refused: course % has blockers other than the approval: %', v_id, v_ready->'blockers';
    end if;
    if not exists (select 1 from pipeline.course_description_machine_admissions a where a.course_id = v_id and a.outcome = 'admitted' and a.withdrawn_at is null) then
      raise exception 'publication verification refused: course % has no live machine admission', v_id;
    end if;
  end loop;

  insert into publishing.publication_approvals(profile_code, entity_id, approval_status, approval_reason, approved_by_ref, approved_at, updated_at)
  select v_profile, x, 'approved', 'Bounded production publication verification: machine-admitted, source-validated course description; one of ten courses authorised by the Platform Admin.',
         'Platform Admin 10 Nov 2026 09:05 AEDT (bounded publication verification)', now(), now()
  from unnest(v_ids) x
  on conflict (profile_code, entity_id) do update set approval_status = 'approved', approval_reason = excluded.approval_reason, approved_by_ref = excluded.approved_by_ref,
    approved_at = excluded.approved_at, revoked_at = null, updated_at = now();

  foreach v_id in array v_ids loop
    v_res := publishing.set_course_publication_v1(v_id, 'published', v_profile, 'Bounded production publication verification (Platform Admin, 10 Nov 2026): canonical, Website and Zoho read-back.');
    if not coalesce((v_res->>'canonical_changed')::boolean, false) then raise exception 'publication verification failed for %: %', v_id, v_res; end if;
  end loop;

  insert into search.refresh_requests(requested_by) values ('publication verification (10 courses, Platform Admin 10 Nov 2026)');
end
$pub$;
