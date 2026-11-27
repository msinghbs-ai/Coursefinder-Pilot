-- CF-247 s1325 (S1-Build; SS-Programme-Control 27 Nov 2026 22:36 AEDT: "Verify actual canonical admission"; Standing Mandate 21 Nov 2026:
-- a verified fix ships live).
-- Found live 27 Nov 2026 (read only): the rule aer-partial-admit (admission-rule-runner, :14 :29 :44 :59) runs three passes on one clock:
-- entry tables (fire guard 40 s, checked only at the start of each item, whose checks take 3 to 5 s each), then course entry first reads
-- (aer-course-partial-v1, s983) and source proofs (both 60 s on the same clock). The entry-table pass took 37 to 85 s on every recent tick, so
-- the course pass started past its 60 s guard and looked at nothing (course_looked_at 0 at 22:14 and 22:44). The one course read that waits
-- for it (DOT structured intake, Avondale 059850D, Layer 4 item 73b04bed, machine rule gate_incomplete at 22:48) is admitted by the same rule
-- when it runs (rolled back: course_rows_admitted 1).
-- The change (one anchored, md5-guarded edit): the course pass keeps its own clock with a 15 s fire guard, so it always runs after the
-- entry-table pass; every rule, check, ledger and the other passes are unchanged.
-- G1: no job. G2: the guard is a fire guard. G3: 75/48 checked. Locks, Layer 4 decisions and cron checked. $0. Nothing dropped or deleted.
-- Replaces: security.aer_partial_admit_v1 (md5 15ce951fb8d1d698302e1d457caeef25; the course pass's clock).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

create temp table s1325_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

do $e$
declare v jsonb := security.consumer_api_check_v1(); d text; n int;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  d := pg_get_functiondef('security.aer_partial_admit_v1()'::regprocedure);
  if position('s1325' in d) > 0 then raise notice 's1325: already applied'; return; end if;
  if md5(d) <> '15ce951fb8d1d698302e1d457caeef25' then raise exception 'guard: security.aer_partial_admit_v1 differs from the definition this change edits (live md5 %)', md5(d); end if;
  n := regexp_count(d, 'cr\s+record;\s+cc\s+jsonb;');
  if n <> 1 then raise exception 'guard: course pass declaration found % times', n; end if;
  d := regexp_replace(d, 'cr\s+record;\s+cc\s+jsonb;', 'cr record; cc jsonb; c_t0 timestamptz := clock_timestamp(); /* s1325: the course pass''s own clock */');
  n := regexp_count(d, '=\s*''gate_incomplete''\s+order\s+by\s+i\.created_at,\s*i\.id\s+limit\s+v_batch\s+loop\s+exit\s+when\s+clock_timestamp\(\)\s*-\s*v_t0\s*>\s*interval\s+''60 seconds'';');
  if n <> 1 then raise exception 'guard: course pass fire guard found % times', n; end if;
  d := regexp_replace(d, '(=\s*''gate_incomplete''\s+order\s+by\s+i\.created_at,\s*i\.id\s+limit\s+v_batch\s+loop\s+exit\s+when\s+clock_timestamp\(\)\s*-\s*)v_t0(\s*>\s*interval\s+)''60 seconds'';',
         '\1c_t0\2''15 seconds'';  /* s1325: own 15 s fire guard */');
  execute d;
end $e$;

do $post$
declare v jsonb := security.consumer_api_check_v1(); b record; d text := pg_get_functiondef('security.aer_partial_admit_v1()'::regprocedure);
begin
  select * into b from pg_temp.s1325_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from cron.job where active) <> b.cron_before then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided_before then raise exception 'post-check: a Layer 4 item was decided'; end if;
  if position('c_t0 timestamptz := clock_timestamp(); /* s1325' in d) = 0 or position('/* s1325: own 15 s fire guard */' in d) = 0 then raise exception 'post-check: the s1325 edit is missing'; end if;
end $post$;
