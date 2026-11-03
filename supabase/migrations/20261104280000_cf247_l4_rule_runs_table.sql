-- CF-247 Layer 4 Course Link (v2.15.447) production defect, found by the first call at 23:43 AEDT 3 Nov 2026: the rule executor
-- security.layer4_course_link_rule_execute_v1 fails ("column apply of relation layer4_rule_runs does not exist").
-- Why: a table pipeline.layer4_rule_runs already existed live (columns id, rule, at, raised; 78 rows, last 03:27 UTC 3 Nov; written by the Layer 4
--   automatic rules security.l4_rule6_apply_v1, l4_rule_fee_year_align_v1, l4_rule_low_agreement_v1, l4_rule_unofficial_source_v1 and read by
--   l4_shared_hosts_v1) with no create statement in any checked-in migration (a live-only object: governance gap, recorded). Migration
--   20261104260000 used "create table if not exists" with the same name, so it kept the old table, then replaced its comment and created
--   pipeline.layer4_rule_run_items with a foreign key to it. The fixture had no such table, so it passed.
-- What: the executor gets its own tables, pipeline.layer4_course_link_rule_runs and pipeline.layer4_course_link_rule_run_items, and is edited
--   (md5-guarded) to use them; nothing else in it changes. The old table keeps its rows and its writers; its comment is restored to what it holds.
--   pipeline.layer4_rule_run_items (0 rows, created by 20261104260000, never written) is marked retiring, to be dropped by a paste file.
--   No rule has been executed (the first call failed before writing anything).
-- Replaces: pipeline.layer4_rule_run_items (by pipeline.layer4_course_link_rule_run_items; marked retiring); security.layer4_course_link_rule_execute_v1 (same name; md5-guarded edit)
-- Retires: pipeline.layer4_rule_run_items (empty; dropped later by a paste file)
-- Nothing is dropped, deleted or switched on. No spend. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before -> after:
--   security.layer4_course_link_rule_execute_v1(text,integer,boolean)  d4aa914546830dd299ace2b000725643 -> 86e1089a5e93e1e2cce9a0ffd29aa22b

create table if not exists pipeline.layer4_course_link_rule_runs (
  id bigserial primary key,
  rule text not null references pipeline.layer4_course_link_rules(code),
  apply boolean not null,
  invoked_by uuid,
  approval_ref text not null,
  at timestamptz not null default now(),
  examined int not null default 0,
  decided int not null default 0,
  would_decide int not null default 0,
  failed int not null default 0,
  result jsonb not null default '{}'::jsonb
);
comment on table pipeline.layer4_course_link_rule_runs is 'CF-247 Decision 263: every call of security.layer4_course_link_rule_execute_v1 (counting or applying): the rule, who invoked it, the approval reference, and how many items were examined, decided, would be decided and failed. Items are in pipeline.layer4_course_link_rule_run_items. Never read by the consumer API.';
alter table pipeline.layer4_course_link_rule_runs enable row level security;
revoke all on pipeline.layer4_course_link_rule_runs from public, anon, authenticated;
revoke all on sequence pipeline.layer4_course_link_rule_runs_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_course_link_rule_run_items (
  run_id bigint not null references pipeline.layer4_course_link_rule_runs(id),
  item_id uuid not null,
  course_id uuid,
  outcome text not null check (outcome in ('decided', 'would_decide', 'failed')),
  reasons text[] not null default '{}',
  decision_id uuid,
  action text,
  at timestamptz not null default now(),
  primary key (run_id, item_id)
);
comment on table pipeline.layer4_course_link_rule_run_items is 'CF-247 Decision 263: each item a course-link rule run examined: decided (with the Layer 4 decision it saved through the existing decision path), would_decide (a counting run) or failed (left waiting, with the reasons found at execution time). Never read by the consumer API.';
create index if not exists layer4_course_link_rule_run_items_item_idx on pipeline.layer4_course_link_rule_run_items (item_id);
alter table pipeline.layer4_course_link_rule_run_items enable row level security;
revoke all on pipeline.layer4_course_link_rule_run_items from public, anon, authenticated;

comment on table pipeline.layer4_rule_runs is 'Runs of the Layer 4 automatic rules (security.l4_rule6_apply_v1, l4_rule_fee_year_align_v1, l4_rule_low_agreement_v1, l4_rule_unofficial_source_v1): the rule, when, and what it raised. Read by security.l4_shared_hosts_v1. Created live before 3 Nov 2026 with no checked-in migration (recorded 3 Nov 2026, migration 20261104280000). The course-link rule executor uses pipeline.layer4_course_link_rule_runs. Never read by the consumer API.';

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.layer4_course_link_rule_execute_v1(text,integer,boolean)', 'd4aa914546830dd299ace2b000725643', '86e1089a5e93e1e2cce9a0ffd29aa22b',
  array[
    array['pipeline.layer4_rule_run_items', 'pipeline.layer4_course_link_rule_run_items'],
    array['pipeline.layer4_rule_runs', 'pipeline.layer4_course_link_rule_runs']
  ], array[4, 2]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_course_link_rule_runs', 'Layer 4', 'Runs of the course-link rule executor', 'active', '{}', '20261104280000'),
 ('table', 'pipeline.layer4_course_link_rule_run_items', 'Layer 4', 'Items of each course-link rule run: decided, would decide or failed with reasons', 'active', '{pipeline.layer4_rule_run_items}', '20261104280000')
on conflict do nothing;
update pipeline.component_register set purpose = 'Runs of the Layer 4 automatic rules (l4_rule_*); live-only before 3 Nov 2026, recorded by 20261104280000', updated_at = now()
 where kind = 'table' and name = 'pipeline.layer4_rule_runs';
update pipeline.component_register set status = 'retiring', replaced_by = 'pipeline.layer4_course_link_rule_run_items',
       retire_after = (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, updated_at = now()
 where kind = 'table' and name = 'pipeline.layer4_rule_run_items' and status = 'active';
