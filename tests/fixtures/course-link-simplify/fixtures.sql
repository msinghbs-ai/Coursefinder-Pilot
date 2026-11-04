-- CF-247 Course Link simplification (migration 20261104570000): every case on the production-shaped backlog of seed.sql. Each block raises
-- '<code> ok' or fails. Scratch PostgreSQL only.

-- C1 every item gets the class planned for it, with its group, authority and evidence
do $$
declare r record; v jsonb; n int := 0;
begin
  for r in select p.name, p.expect, g from fx.plan p, generate_series(1, p.n) g loop
    v := security.course_link_route_class_v1(fx.u('i-' || r.name || '-' || r.g));
    if v->>'class' is distinct from r.expect then raise exception 'C1 % %: expected %, got %', r.name, r.g, r.expect, v; end if;
    if (v->>'group') not in ('A', 'B', 'C', 'D') or v->'evidence' is null then raise exception 'C1 % has no group or evidence: %', r.name, v; end if;
    n := n + 1;
  end loop;
  if (security.course_link_route_class_v1(fx.u('i-cbr-pass'))->>'class') <> 'rule_d263_pass' then raise exception 'C1 rule pass: %', security.course_link_route_class_v1(fx.u('i-cbr-pass')); end if;
  v := security.course_link_route_class_v1(fx.u('i-cbr-fail'));
  if v->>'class' <> 'rule_d263_fail' or v->>'reason' not like '%exact_title is not an exact-course basis%' or v->>'group' <> 'C' then raise exception 'C1 rule fail: %', v; end if;
  if security.course_link_route_class_v1(fx.u('i-decided-old'))->>'group' is not null then raise exception 'C1 a decided item has a group'; end if;
  v := security.course_link_route_class_v1(fx.u('i-d179-1'));
  if v->>'authority' not like 'Decision 179 (Platform Admin 3 Nov 2026 20:29%' or v->>'action' <> 'convert_d179' then raise exception 'C1 Decision 179 authority: %', v; end if;
  if security.course_link_route_class_v1(fx.u('i-covc-1'))->>'recommended' not like 'Use the new page%' then raise exception 'C1 code-backed recommendation'; end if;
  if security.course_link_route_class_v1(fx.u('i-held-1'))->>'recommended' <> 'Keep the page we hold.' then raise exception 'C1 held recommendation'; end if;
  raise notice 'C1 ok: % items classed as planned (A automatic, B technical, C a person), with authority, reason, recommendation and evidence', n + 2;
end $$;

create temp table snap as
select (select md5(string_agg(i.id || i.status || coalesce(i.evidence_id::text, '') || coalesce(i.change_control_ref, ''), '|' order by i.id)) from pipeline.layer4_review_items i) items,
       (select md5(coalesce(string_agg(l.course_id || l.url || l.status || l.is_primary, '|' order by l.course_id, l.url), '')) from catalogue.course_links l) links,
       (select md5(coalesce(string_agg(m.entity_id || m.field || m.mode, '|' order by m.entity_id, m.field), '')) from pipeline.manual_locks m) locks,
       (select count(*) from pipeline.layer4_decisions) decisions, (select count(*) from pipeline.layer4_supersessions) sups,
       (select count(*) from pipeline.admin_control_events) events, (select count(*) from pipeline.course_page_needed) needed;

-- R1 counting writes nothing, and reports the classes of one university
do $$
declare v jsonb; s record;
begin
  v := security.course_link_reconcile_v1(fx.u('p-north'), 500, false);
  select * into s from snap;
  if (select md5(string_agg(i.id || i.status || coalesce(i.evidence_id::text, '') || coalesce(i.change_control_ref, ''), '|' order by i.id)) from pipeline.layer4_review_items i) <> s.items
     or (select count(*) from pipeline.admin_control_events) <> s.events or (select count(*) from pipeline.layer4_supersessions) <> s.sups
     or (select count(*) from pipeline.course_page_needed) <> s.needed then raise exception 'R1 counting wrote something: %', v; end if;
  if (v->'by_class'->>'page_needed_d179')::int <> 60 or (v->'page_needed'->'convert'->>'moved')::int <> 60 or (v->'by_class'->>'evidence_not_linked')::int <> 5
     or (v->>'examined')::int <> 88 then raise exception 'R1 counts: %', v; end if;
  raise notice 'R1 ok: counting only: %', v->'by_group';
end $$;

-- R2 a signed-in reviewer below Platform Admin is refused; one university at a time
do $$
begin
  perform set_config('fx.uid', '11111111-1111-4111-8111-111111111111', false); perform set_config('fx.rank', '3', false);
  begin perform security.course_link_reconcile_v1(fx.u('p-north'), 10, true); raise exception 'R2 a curator ran it';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  begin perform security.course_link_reconcile_v1(null, 10, false); raise exception 'R2 ran for every university';
  exception when invalid_parameter_value then null; end;
  raise notice 'R2 ok: Platform Admin or the Integration Controller only, one university per call';
end $$;

-- R3 applied for Northbank: Decision 179 through the existing conversion, stored copies linked, nothing approved or refused, no lock or page touched
do $$
declare v jsonb; s record;
begin
  select * into s from snap;
  v := security.course_link_reconcile_v1(fx.u('p-north'), 500, true);
  if (v->'page_needed'->'convert'->>'moved')::int <> 60 or (v->>'evidence_linked')::int <> 5 or (v->>'superseded')::int <> 0 then raise exception 'R3 result: %', v; end if;
  if (select count(*) from pipeline.layer4_review_items i where i.id in (select fx.u('i-d179-' || g) from generate_series(1, 60) g) and i.status = 'superseded'
        and i.change_control_ref like '%Decision 179 (Platform Admin 3 Nov 2026 20:29): moved to Course page needed%') <> 60 then raise exception 'R3 Decision 179 items not moved with the reason'; end if;
  if (select count(*) from pipeline.course_page_needed n where n.provider_id = fx.u('p-north') and cardinality(n.converted_items) = 1) <> 60 then raise exception 'R3 Course page needed rows'; end if;
  if (select count(*) from pipeline.layer4_review_items i where i.id in (select fx.u('i-nolink-' || g) from generate_series(1, 5) g) and i.status = 'pending' and i.evidence_id is not null) <> 5 then raise exception 'R3 stored copies not linked'; end if;
  if (select status from pipeline.layer4_review_items where id = fx.u('i-claimed-1')) <> 'pending' then raise exception 'R3 a claimed item moved'; end if;
  if (select count(*) from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id where c.provider_id = fx.u('p-north') and i.status = 'pending') <> 28 then raise exception 'R3 left waiting: %',
     (select count(*) from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id where c.provider_id = fx.u('p-north') and i.status = 'pending'); end if;
  if (select count(*) from pipeline.layer4_decisions) <> s.decisions then raise exception 'R3 a decision was saved'; end if;
  if (select md5(coalesce(string_agg(l.course_id || l.url || l.status || l.is_primary, '|' order by l.course_id, l.url), '')) from catalogue.course_links l) <> s.links then raise exception 'R3 a page changed'; end if;
  if (select md5(coalesce(string_agg(m.entity_id || m.field || m.mode, '|' order by m.entity_id, m.field), '')) from pipeline.manual_locks m) <> s.locks then raise exception 'R3 a lock changed'; end if;
  if not exists (select 1 from pipeline.admin_control_events e where e.action = 'course_link_reconcile' and e.target = fx.u('p-north')::text) then raise exception 'R3 not audited'; end if;
  raise notice 'R3 ok: 60 moved to Course page needed (Decision 179), 5 stored copies linked, 28 left for a person; no decision, page or lock changed';
end $$;

-- R4 applied for Kauri and Lakeshore: repeats, decided-before, already-active and retired items superseded with the reason (reversible); the
-- old-year, E16 and refused-active questions never settled as "already active"
do $$
declare v jsonb; v2 jsonb;
begin
  v := security.course_link_reconcile_v1(fx.u('p-kauri'), 500, true);
  v2 := security.course_link_reconcile_v1(fx.u('p-lake'), 500, true);
  if (v->>'superseded')::int <> 3 or (v2->>'superseded')::int <> 2 or (v->'page_needed'->'convert'->>'moved')::int <> 56 then raise exception 'R4 result: % %', v, v2; end if;
  if (select string_agg(s.reason, ',' order by s.reason) from pipeline.layer4_supersessions s where s.mode = 'reconcile') <> 'covered_by_active,decided_before,duplicate_pending,entity_retired,entity_retired'
     then raise exception 'R4 reasons: %', (select string_agg(s.reason, ',' order by s.reason) from pipeline.layer4_supersessions s); end if;
  if (select covered_by_item from pipeline.layer4_supersessions where item_id = fx.u('i-dupe-1')) <> fx.u('i-cov-1') then raise exception 'R4 repeat not linked to the item that covers it'; end if;
  if exists (select 1 from pipeline.layer4_review_items where id in (fx.u('i-cov-1'), fx.u('i-h05-1'), fx.u('i-offdom-1'), fx.u('i-heldk-1')) and status <> 'pending') then raise exception 'R4 a question was closed'; end if;
  raise notice 'R4 ok: 5 superseded with their reasons (repeat, decided before, already active, retired x2); questions stay waiting';
end $$;

-- R5 the settlement reasons no longer close a question about the page the course shows
do $$
begin
  if security.layer4_resolution_v1(fx.u('i-h13-1')) is not null then raise exception 'R5 old-year address settled: %', security.layer4_resolution_v1(fx.u('i-h13-1')); end if;
  if security.layer4_resolution_v1(fx.u('i-e16-1')) is not null then raise exception 'R5 E16 settled'; end if;
  if security.layer4_resolution_v1(fx.u('i-actref-1')) is not null then raise exception 'R5 refused active page settled'; end if;
  raise notice 'R5 ok: old-year, E16 and refused active pages are a person''s question, not "already active"';
end $$;

-- R6 a second run changes nothing; a reversed settlement is never settled again
do $$
declare v jsonb; n int; sid bigint;
begin
  select count(*) into n from pipeline.layer4_supersessions;
  v := security.course_link_reconcile_v1(fx.u('p-kauri'), 500, true);
  if (v->>'superseded')::int <> 0 or coalesce(jsonb_typeof(v->'page_needed'->'convert'), 'null') <> 'null' or (select count(*) from pipeline.layer4_supersessions) <> n then raise exception 'R6 second run acted: %', v; end if;
  select id into sid from pipeline.layer4_supersessions where item_id = fx.u('i-active-1');
  perform set_config('fx.uid', '22222222-2222-4222-8222-222222222222', false); perform set_config('fx.rank', '6', false);
  perform security.layer4_supersession_reverse_v1(sid, 'Platform Admin: check this one');
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  if security.course_link_route_class_v1(fx.u('i-active-1'))->>'class' <> 'reopened_by_admin' then raise exception 'R6 reversed item classed again'; end if;
  v := security.course_link_reconcile_v1(fx.u('p-kauri'), 500, true);
  if (select status from pipeline.layer4_review_items where id = fx.u('i-active-1')) <> 'pending' then raise exception 'R6 reversed item settled again'; end if;
  raise notice 'R6 ok: applied twice changes nothing; a reversed settlement stays with a person';
end $$;

-- R7 other providers continue untouched; the approved rule item is counted, never decided here
do $$
declare v jsonb;
begin
  if (select count(*) from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id where c.provider_id = fx.u('p-ctrl') and i.status = 'pending') <> 3 then raise exception 'R7 control provider touched'; end if;
  v := security.course_link_reconcile_v1('0e1532b8-de30-4761-87fe-460684608633', 500, true);
  if (v->'rule_d263_ready'->>'canberra_no_year')::int < 1 or (select status from pipeline.layer4_review_items where id = fx.u('i-cbr-pass')) <> 'pending' then raise exception 'R7 rule: %', v; end if;
  raise notice 'R7 ok: Control untouched; the rule item waits for the rule executor: %', v->'rule_d263_ready';
end $$;

-- R8 the binding check does not raise a page already decided for the course, however its address is written
do $$
declare v text; n int;
begin
  update pipeline.layer4_review_items set status = 'rejected', decided_at = now() where id = fx.u('i-heldk-2');
  select count(*) into n from pipeline.layer4_review_items where entity_id = fx.u('c-heldk-2');
  v := security.binding_refusal_route_v1(fx.u('c-heldk-2'), 'http://kauri.ac.nz/found/heldk-2/', '{"reason": "another level", "rule": "level"}', 'title_search', null);
  if v <> 'decided_before' or (select count(*) from pipeline.layer4_review_items where entity_id = fx.u('c-heldk-2')) <> n then raise exception 'R8 raised again: %', v; end if;
  raise notice 'R8 ok: an http/no-www/slash variant of a decided page is not raised again';
end $$;

-- R9 the §11 report
do $$
declare v jsonb;
begin
  v := security.course_link_backlog_report_v1(fx.u('p-north'));
  if (v->>'pending')::int <> 28 or (v->>'technical_holds')::int <> 1 or (v->>'automatically_resolved_7d')::int < 60 then raise exception 'R9 report: %', v; end if;
  raise notice 'R9 ok: %', v - 'per_university';
end $$;
