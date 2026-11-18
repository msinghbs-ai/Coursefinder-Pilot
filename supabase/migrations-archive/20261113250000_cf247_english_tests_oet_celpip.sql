-- CF-247 Website API v3 build brief WP-2.1 (register O14, REQ-55; Platform Admin 12 Nov 2026 22:37): OET and CELPIP are English tests.
-- 1 Two rows in ref.english_tests. OET is held as its numeric score (0 to 500 in steps of 10); CELPIP as its level (1 to 12).
-- 2 The policy parser (coverage-sweep policy.ts provider-policy-v0.3.1, worker v0.82.0) reads them: OET only where the page prints the numeric
--   score (a letter grade such as "B in each sub-test" is never turned into a number), CELPIP as a whole level. New readings carry them.
-- 3 Approved policies: the existing hourly job policy-add-tests (catalogued; batch.policy_add_tests) reads each approved policy's stored page once
--   more because its parser key changed, and svc_provider_english_add_tests_v1 adds a test for a level only where this reading's IELTS equals the
--   approved IELTS (its existing rule; that function takes every active test in ref.english_tests, so it is not changed).
-- The website and Zoho APIs need no change: english_requirements[], english_test_codes and the reference list take every test held, so OET and
-- CELPIP appear as data (test_code OET / CELPIP) in v2 and v3 alike. No function, setting, job or consumer object is created or changed.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

insert into ref.english_tests(code, name, status, score_scale) values
  ('OET', 'Occupational English Test', 'active', '{"min": 0, "max": 500, "step": 10}'::jsonb),
  ('CELPIP', 'CELPIP', 'active', '{"min": 1, "max": 12, "step": 1}'::jsonb)
on conflict (code) do nothing;

do $check$
begin
  if (select count(*) from ref.english_tests where code in ('OET', 'CELPIP') and status = 'active') <> 2 then
    raise exception 'WP-2.1 post-check: OET and CELPIP must both be active English tests';
  end if;
end $check$;
