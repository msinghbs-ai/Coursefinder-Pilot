-- CF-247 IQ-00043: a replaced, rejected or held course link is never made active again by a background writer (Workstream E; Platform Admin
-- decision 3 Nov 2026 08:44 §5, admin docs/platform/nz-enrichment-brief/2026-11-03-morning-decision-pack-0844.md: "Do not reactivate a
-- previously rejected or replaced source merely because a background reader rediscovers it").
-- Why (live, read-only, 3 Nov 2026 08:50-08:58 AEDT): 13 of the 101 courses of the 2 Nov link tranche (event #28622, 112 links set inactive)
--   have their superseded link active again, each the La Trobe spelling "<kept page>#/overview?studentType=int" (the same page under security.course_link_norm_v1
--   and the existing security.coverage_norm_url). Every hour at :37 job exit-awards-apply (security.exit_awards_hourly_v1 -> security.exit_awards_apply_v2, md5
--   e7080925ba79eef320f361bf236cb072) passes the award's page address with its fragment as course_url to security.coverage_apply_course_v1
--   (md5 c2cbc9ab616a77487d447991f33daaeb), whose link write is
--     on conflict (course_id, link_type, url) do update set status = 'active', ...
--   so any inactive link at that exact address becomes active again (updated_at 2 Nov 21:37 UTC and again each hour since). The same upsert
--   "status = 'active'" is in public.svc_coursefacts_apply_record and security.cf245_admit_official_url_record_v1 (background admission), and
--   security.layer4_course_link_apply_impl is called by the Decision 263 "take" rule (security.coverage_admission_apply_v1) with no person.
--   Nothing in any writer asked whether the address had been set aside.
-- What:
--   1 security.course_link_hold_basis_v1(course, link type, url, source): the one rule. It returns why an address must not become active
--     again, or null: superseded (the link is inactive), retired (deprecated, or written from a retired source), a new spelling of a page set
--     aside (same address under security.course_link_norm_v1, query kept), held (an open remediation hold; a pending Layer 4 course-link review on a link that
--     is not active), rejected (a page rejection or block, or a Layer 4 decision that kept the page we hold, not approved since), or replaced by
--     a later approved Layer 4 decision. An active link is never held (a re-read of the shown page goes on as before).
--   2 Trigger reactivation_guard on catalogue.course_links (BEFORE INSERT OR UPDATE OF status; after manual_lock_guard by name, so a locked
--     course is still skipped first): when a background writer would make a held address active, the row is left as it was (an update keeps
--     the old row; an insert is not made) and the attempt is recorded in pipeline.course_link_rediscoveries (evidence; counted per address and
--     route). A person decides: cf.manual_edit on (course record, link editor, paste files) or a signed-in user (Layer 4 review) is never held.
--     The first time an address is held, one integration-queue issue is updated by fingerprint 'course-link:reactivation-held' (never a
--     duplicate; a queue error never stops the writer).
--   3 security.coverage_admission_apply_v1 (md5-guarded edit): the Decision 263 "take" rule does not take a held page; the row waits for a
--     person, as a row no rule decides.
--   4 security.coverage_apply_course_v1 (md5-guarded edit): a held link is not counted as applied (links_applied 0, link_held true).
--   5 security.course_link_reactivated_v1(): read-only listing of active official links whose address was set aside by a governed decision
--     and made active later by a background writer (the reconciliation set; paste file docs/paste/PASTE-20261103-iq43-reactivated-links.sql).
--   6 Settings (G2): course_link.reactivation_guard (on/off) and course_link.reactivated_list_max (the listing's row limit).
-- Routes and cover: every writer of catalogue.course_links passes through the trigger, including the live-only ones (exit awards v1/v2,
--   coverage admission, Layer 3 admission, coursefacts, CF-245 official URL admission, Layer 4 rule, link refresh). Locked courses: the
--   existing manual_lock_guard already skips every background write (unchanged). catalogue.courses.course_url is not consumer-visible; its
--   background writers (course_url_fill_v1 from the proven binding, exit_awards_apply_v1 unused since v2) are unchanged.
-- Replaces: security.coverage_admission_apply_v1, security.coverage_apply_course_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped, deleted or switched off. No data is changed (the 13 are restored by the paste file, with the Platform Admin). No consumer
-- API object changes (G3): no column, type or name of catalogue.course_links changes; a trigger is added beside it.

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

-- 6 settings (G2) ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'course_link.reactivation_guard', 'Official link: replaced links stay replaced',
  '1 keeps a course link that a person, a governed tranche or a rule set aside (inactive, retired, rejected, held) from being made active again by a background reader; the attempt is recorded as a rediscovery. 0 lets background writers re-activate as before. A person always decides.',
  'number', '1'::jsonb, '0', '1', 'on/off', 606, 'Official link', 'trigger reactivation_guard on catalogue.course_links; security.course_link_reactivation_guard_trg_v1; security.coverage_admission_apply_v1 (rule take)',
  'Platform Admin decision 3 Nov 2026 08:44 §5 (IQ-00043): 13 superseded links re-activated by exit-awards-apply'),
 ('pipeline', 'course_link.reactivated_list_max', 'Official link: re-activated links listed',
  'The reconciliation listing (security.course_link_reactivated_v1) returns at most this many links.',
  'number', '2000'::jsonb, '100', '50000', 'links', 607, 'Official link', 'security.course_link_reactivated_v1',
  'Platform Admin decision 3 Nov 2026 08:44 §5 (IQ-00043): reconciliation listing')
on conflict (toolset_key, key) do nothing;

-- the evidence of rediscoveries ---------------------------------------------------------------------------------------------------------
create table if not exists pipeline.course_link_rediscoveries (
  id bigserial primary key,
  course_id uuid not null,
  link_id uuid,
  link_type text not null,
  url text not null,
  url_norm text not null,
  route text not null check (route in ('superseded', 'retired', 'rejected', 'held')),
  basis jsonb not null default '{}'::jsonb,
  attempted text not null check (attempted in ('insert', 'update')),
  writer text,
  source_id uuid,
  evidence_id uuid,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  seen_count int not null default 1,
  unique (course_id, link_type, url, route)
);
comment on table pipeline.course_link_rediscoveries is 'CF-247 IQ-00043 (Platform Admin decision 3 Nov 2026 08:44 §5): one row per course link address that a background writer tried to make active again after a person, a governed tranche or a rule set it aside (route superseded, retired, rejected or held; security.course_link_hold_basis_v1). Written by the trigger reactivation_guard on catalogue.course_links; the link itself stays as it was. Evidence only: last writer, source and evidence, first and last attempt, count. Never read by the consumer API.';
alter table pipeline.course_link_rediscoveries enable row level security;
revoke all on pipeline.course_link_rediscoveries from public, anon, authenticated;
revoke all on sequence pipeline.course_link_rediscoveries_id_seq from public, anon, authenticated;

-- 1 the rule ---------------------------------------------------------------------------------------------------------------------------
-- The address comparison: scheme, www, case, the fragment and a trailing slash do not make a different page (La Trobe '#/overview?studentType=int'
-- is the page). The query is kept: on query-addressed catalogues (Auckland '.../catalogue/program?p5_code=MC') it names the page, and
-- security.coverage_norm_url, which drops it, would make every Auckland programme the same page (measured 3 Nov 2026 09:07: 8 false matches
-- against the rejected bare listing '.../catalogue/program').
create or replace function security.course_link_norm_v1(p text) returns text language sql immutable set search_path to '' as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(btrim(coalesce(p, ''))), '^https?://(www\.)?', ''), '#.*$', ''), '/+(\?|$)', '\1'), '\?$', '')
$$;
comment on function security.course_link_norm_v1(text) is 'IQ-00043: a course link address for comparison (lower case, no scheme, www, fragment or trailing slash; the query kept, as it names the page on query-addressed catalogues).';

create or replace function security.course_link_hold_basis_v1(p_course uuid, p_link_type text, p_url text, p_source uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_norm text := security.course_link_norm_v1(p_url); v_status text; v_r jsonb;
begin
  if p_course is null or coalesce(btrim(p_url), '') = '' then return null; end if;
  select l.status into v_status from catalogue.course_links l where l.course_id = p_course and l.link_type = p_link_type and l.url = p_url;
  -- an active link is never held: a re-read of the shown page goes on as before
  if v_status = 'active' then return null; end if;
  -- superseded or retired: the address itself was set aside (a person, the link tranche, a Layer 4 decision or rule, an award clean-up)
  if v_status in ('inactive', 'deprecated') then
    return jsonb_build_object('route', case v_status when 'deprecated' then 'retired' else 'superseded' end, 'status', v_status);
  end if;
  -- a new spelling of a page set aside (La Trobe '#/overview?studentType=int': the same page under security.course_link_norm_v1)
  if v_status is null then
    select jsonb_build_object('route', case l.status when 'deprecated' then 'retired' else 'superseded' end, 'same_page_as', l.url, 'status', l.status) into v_r
      from catalogue.course_links l
     where l.course_id = p_course and l.link_type = p_link_type and l.status in ('inactive', 'deprecated') and security.course_link_norm_v1(l.url) = v_norm
     limit 1;
    if v_r is not null then return v_r; end if;
  end if;
  -- retired: written from a retired source
  if p_source is not null and exists (select 1 from pipeline.sources s where s.id = p_source and s.status = 'retired') then
    return jsonb_build_object('route', 'retired', 'source_id', p_source);
  end if;
  if p_link_type is distinct from 'official_course' then return null; end if;
  -- held: an open binding remediation hold (SS-007, E16 containment)
  if security.course_held_v1(p_course) then return jsonb_build_object('route', 'held', 'hold', 'course_remediation_holds'); end if;
  -- held: a link that is not active waits while a Layer 4 course-link review is pending on the course
  if v_status is not null then
    select jsonb_build_object('route', 'held', 'layer4_item', i.id, 'status', v_status) into v_r
      from pipeline.layer4_review_items i
     where i.entity_id = p_course and i.field_code = 'official_course_url' and i.status = 'pending' and i.entity_type = 'course'
     limit 1;
    if v_r is not null then return v_r; end if;
  end if;
  -- rejected: a page rejection or block for the course at the same page
  select jsonb_build_object('route', 'rejected', 'page_rejection', r.source, 'rejected_at', r.rejected_at) into v_r
    from pipeline.page_rejections r where r.course_id = p_course and security.course_link_norm_v1(r.url) = v_norm limit 1;
  if v_r is not null then return v_r; end if;
  select jsonb_build_object('route', 'rejected', 'page_block', b.reason, 'blocked_at', b.created_at) into v_r
    from pipeline.course_page_blocks b where b.course_id = p_course and security.course_link_norm_v1(b.url) = v_norm limit 1;
  if v_r is not null then return v_r; end if;
  -- rejected: a Layer 4 decision kept the page we hold instead of this one, and no later decision approved it
  select jsonb_build_object('route', 'rejected', 'layer4_item', i.id, 'decided_at', i.decided_at) into v_r
    from pipeline.layer4_review_items i
   where i.entity_id = p_course and i.field_code = 'official_course_url' and i.status = 'rejected' and i.entity_type = 'course'
     and security.course_link_norm_v1(coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url')) = v_norm
     and not exists (select 1 from pipeline.layer4_review_items a
                      where a.entity_id = p_course and a.field_code = 'official_course_url' and a.status in ('approved', 'edited_approved') and a.entity_type = 'course'
                        and security.course_link_norm_v1(coalesce(a.proposed_value->>'course_url', a.proposed_value->>'url')) = v_norm
                        and coalesce(a.decided_at, a.created_at) > coalesce(i.decided_at, i.created_at))
   order by i.decided_at desc nulls last limit 1;
  if v_r is not null then return v_r; end if;
  -- superseded: a later approved Layer 4 decision replaced this page with another one
  select jsonb_build_object('route', 'superseded', 'layer4_item', i.id, 'decided_at', i.decided_at) into v_r
    from pipeline.layer4_review_items i
   where i.entity_id = p_course and i.field_code = 'official_course_url' and i.status = 'approved' and i.entity_type = 'course'
     and jsonb_typeof(i.before_value) = 'array'
     and exists (select 1 from jsonb_array_elements_text(i.before_value) b where security.course_link_norm_v1(b) = v_norm)
     and security.course_link_norm_v1(coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url')) <> v_norm
     and not exists (select 1 from pipeline.layer4_review_items a
                      where a.entity_id = p_course and a.field_code = 'official_course_url' and a.status in ('approved', 'edited_approved') and a.entity_type = 'course'
                        and security.course_link_norm_v1(coalesce(a.proposed_value->>'course_url', a.proposed_value->>'url')) = v_norm
                        and coalesce(a.decided_at, a.created_at) > coalesce(i.decided_at, i.created_at))
   order by i.decided_at desc nulls last limit 1;
  return v_r;
end $$;
comment on function security.course_link_hold_basis_v1(uuid, text, text, uuid) is 'IQ-00043 (Platform Admin 3 Nov 2026 08:44 §5): why a course link address must not become active again (route superseded, retired, rejected or held, with its basis), or null. An active link is never held. Addresses compare under security.course_link_norm_v1 (query kept).';
revoke all on function security.course_link_hold_basis_v1(uuid, text, text, uuid) from public, anon, authenticated;

-- 2 the central guard -------------------------------------------------------------------------------------------------------------------
create or replace function security.course_link_reactivation_guard_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
declare v_basis jsonb; v_new boolean; v_iq jsonb;
begin
  if new.status is distinct from 'active' then return new; end if;
  if TG_OP = 'UPDATE' and old.status = 'active' and old.url = new.url then return new; end if;
  -- a person decides: the course record, the link editor and paste files set cf.manual_edit; a Layer 4 reviewer is signed in
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('course_link.reactivation_guard', 1) < 1 then return new; end if;
  v_basis := security.course_link_hold_basis_v1(new.course_id, new.link_type, new.url, new.source_id);
  if v_basis is null then return new; end if;
  -- the attempt is evidence; the link stays as it was
  begin
    insert into pipeline.course_link_rediscoveries as d(course_id, link_id, link_type, url, url_norm, route, basis, attempted, writer, source_id, evidence_id)
    values (new.course_id,
            case when TG_OP = 'UPDATE' then old.id
                 else (select l.id from catalogue.course_links l where l.course_id = new.course_id and l.link_type = new.link_type and l.url = new.url) end,
            new.link_type, new.url, security.course_link_norm_v1(new.url), v_basis->>'route', v_basis,
            lower(TG_OP), left(coalesce(nullif(current_setting('application_name', true), ''), current_user::text), 120), new.source_id, new.evidence_id)
    on conflict (course_id, link_type, url, route) do update
      set last_seen_at = now(), seen_count = d.seen_count + 1, basis = excluded.basis, attempted = excluded.attempted, writer = excluded.writer,
          source_id = excluded.source_id, evidence_id = excluded.evidence_id, link_id = coalesce(excluded.link_id, d.link_id)
    returning (d.xmax = 0) into v_new;
    if v_new and to_regprocedure('security.integration_issue_upsert_v1(jsonb,text)') is not null then
      begin
        execute 'select security.integration_issue_upsert_v1($1, $2)' into v_iq
          using jsonb_build_object('fingerprint', 'course-link:reactivation-held',
                  'title', 'A background writer tried to make a replaced, rejected or held course link active again (held)',
                  'layer', 'Catalogue', 'subsystem', 'course-links', 'workstream', 'A4', 'severity', 'P2', 'root_cause_class', 'code_defect',
                  'validation_layer', 'V4', 'source', 'trigger reactivation_guard',
                  'failure', 'A background writer tried to re-activate ' || new.url || ' (' || (v_basis->>'route') || '); the link was left as it was',
                  'expected', 'Background readers record a rediscovered page as evidence only; a person decides whether a replaced, rejected or held page comes back',
                  'course_ids', jsonb_build_array(new.course_id),
                  'evidence', jsonb_build_object('basis', v_basis, 'url', new.url, 'writer', current_setting('application_name', true), 'table', 'pipeline.course_link_rediscoveries')),
                'reactivation-guard';
      exception when others then null;  -- fixed: the queue never stops a writer; the rediscovery row is the record
      end;
    end if;
  exception when others then null;  -- fixed: the evidence row never stops a writer; the link is still held below
  end;
  if TG_OP = 'UPDATE' then return old; end if;
  return null;
end $$;
comment on function security.course_link_reactivation_guard_trg_v1() is 'IQ-00043 (Platform Admin 3 Nov 2026 08:44 §5): trigger reactivation_guard on catalogue.course_links. A background writer never makes a superseded, retired, rejected or held address active (security.course_link_hold_basis_v1): an update keeps the old row, an insert is not made, and the attempt is recorded in pipeline.course_link_rediscoveries. A person (cf.manual_edit on, or signed in) decides. Switch: course_link.reactivation_guard.';
revoke all on function security.course_link_reactivation_guard_trg_v1() from public, anon, authenticated;

do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'reactivation_guard' and tgrelid = 'catalogue.course_links'::regclass) then
    create trigger reactivation_guard before insert or update of status on catalogue.course_links
      for each row execute function security.course_link_reactivation_guard_trg_v1();
  end if;
end $t$;

-- 3 the Decision 263 rule does not take a held page ---------------------------------------------------------------------------------------
select pg_temp.edit_once('security.coverage_admission_apply_v1(integer,text,text[])', '7dea1ac5a96edc31ec4dd152d612aae1', '2e85e6cbb5d2e64ea1b50fe490c4da76', array[
  array[$o$    if v_rule like 'take:%' and coalesce(r.proposed->>'course_url', '') !~* '^https://' then v_rule := null; end if;$o$,
        $n$    if v_rule like 'take:%' and coalesce(r.proposed->>'course_url', '') !~* '^https://' then v_rule := null; end if;
    -- IQ-00043 (Platform Admin 3 Nov 2026 08:44 §5): a rule never takes a page that was replaced, rejected or held; the row waits for a person
    if v_rule like 'take:%' and security.course_link_hold_basis_v1(r.course_id, 'official_course', r.proposed->>'course_url', null) is not null then v_rule := null; end if;$n$]
], array[1]);

-- 4 the common admission write reports a held link ---------------------------------------------------------------------------------------
select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', 'c2cbc9ab616a77487d447991f33daaeb', '66dbfd0739ce75f9ef0e20ca2d5975bd', array[
  array[$o$    v_links := 1;$o$,
        $n$    -- IQ-00043: a link held by the reactivation guard (trigger reactivation_guard) or a lock is not counted as applied
    v_links := case when exists (select 1 from catalogue.course_links l where l.course_id = p_course_id and l.link_type = 'official_course'
                                    and l.url = btrim(p_payload->>'course_url') and l.status = 'active') then 1 else 0 end;$n$],
  array[$o$'fee_quarantined_identity', v_ident is not null);$o$,
        $n$'fee_quarantined_identity', v_ident is not null,
                            'link_held', nullif(btrim(p_payload->>'course_url'), '') is not null and v_links = 0);$n$]
], array[1, 1]);

-- 5 the reconciliation listing (read only) ----------------------------------------------------------------------------------------------
create or replace function security.course_link_reactivated_v1()
returns table(course_id uuid, link_id uuid, url text, route text, basis jsonb, link_updated_at timestamptz, source_type text, shown_url text)
language sql stable security definer set search_path to '' as $$
  with human as (select s.id from pipeline.sources s where s.source_type in ('layer4_human_review', 'manual', 'manual_entry', 'admin_manual')),
  ev as (
    -- links a governed tranche set inactive (made_inactive) or contained (before[].link_id)
    select x::uuid link_id, e.id event_id, e.action, e.created_at
      from pipeline.admin_control_events e cross join lateral jsonb_array_elements_text(e.detail->'made_inactive') x
     where e.target = 'catalogue.course_links' and jsonb_typeof(e.detail->'made_inactive') = 'array'
    union all
    select (b->>'link_id')::uuid, e.id, e.action, e.created_at
      from pipeline.admin_control_events e cross join lateral jsonb_array_elements(e.detail->'before') b
     where e.action = 'e16_course_link_containment' and jsonb_typeof(e.detail->'before') = 'array' and b ? 'link_id'
  ),
  found as (
    select l.course_id, l.id link_id, l.url, case when ev.action = 'e16_course_link_containment' then 'held' else 'superseded' end route,
           jsonb_build_object('event', ev.event_id, 'action', ev.action, 'at', ev.created_at) basis, l.updated_at, l.source_id
      from ev join catalogue.course_links l on l.id = ev.link_id
     where l.status = 'active' and l.updated_at > ev.created_at and not exists (select 1 from human hu where hu.id = l.source_id)
    union all
    -- a page a Layer 4 decision or a page rejection set aside, active again from a background source after the decision
    select l.course_id, l.id, l.url, 'rejected', jsonb_build_object('layer4_item', i.id, 'decided_at', i.decided_at), l.updated_at, l.source_id
      from pipeline.layer4_review_items i
      join catalogue.course_links l on l.course_id = i.entity_id and l.link_type = 'official_course' and l.status = 'active'
     where i.entity_type = 'course' and i.field_code = 'official_course_url' and i.status = 'rejected' and i.decided_at is not null
       and security.course_link_norm_v1(l.url) = security.course_link_norm_v1(coalesce(i.proposed_value->>'course_url', i.proposed_value->>'url'))
       and l.updated_at > i.decided_at and not exists (select 1 from human hu where hu.id = l.source_id)
       and not exists (select 1 from pipeline.layer4_review_items a
                        where a.entity_id = i.entity_id and a.field_code = 'official_course_url' and a.status in ('approved', 'edited_approved') and a.entity_type = 'course'
                          and security.course_link_norm_v1(coalesce(a.proposed_value->>'course_url', a.proposed_value->>'url')) = security.course_link_norm_v1(l.url)
                          and coalesce(a.decided_at, a.created_at) > i.decided_at)
    union all
    select l.course_id, l.id, l.url, 'rejected', jsonb_build_object('page_rejection', r.source, 'rejected_at', r.rejected_at), l.updated_at, l.source_id
      from pipeline.page_rejections r
      join catalogue.course_links l on l.course_id = r.course_id and l.link_type = 'official_course' and l.status = 'active'
     where security.course_link_norm_v1(l.url) = security.course_link_norm_v1(r.url) and l.updated_at > r.rejected_at
       and not exists (select 1 from human hu where hu.id = l.source_id)
    union all
    select l.course_id, l.id, l.url, 'held', jsonb_build_object('remediation_hold', h.id, 'held_at', h.held_at), l.updated_at, l.source_id
      from pipeline.course_remediation_holds h
      join catalogue.course_links l on l.course_id = h.course_id and l.link_type = 'official_course' and l.status = 'active'
     where h.lifted_at is null and security.course_link_norm_v1(l.url) = security.course_link_norm_v1(h.url) and l.updated_at > h.held_at
  )
  select distinct on (f.link_id) f.course_id, f.link_id, f.url, f.route, f.basis, f.updated_at, s.source_type, d.official_course_url
    from found f left join pipeline.sources s on s.id = f.source_id left join search.course_documents d on d.course_id = f.course_id
   order by f.link_id, f.route
   limit security.pipeline_num_v1('course_link.reactivated_list_max', 2000)::int
$$;
comment on function security.course_link_reactivated_v1() is 'IQ-00043 (Platform Admin 3 Nov 2026 08:44 §5): read-only reconciliation listing. Active official links whose address a governed tranche set inactive or contained (admin_control_events made_inactive, E16 before[]), a Layer 4 decision rejected, a page rejection refused, or an open remediation hold holds, and that a background (non-person) source made active after that decision. With the shown link (search.course_documents). At most course_link.reactivated_list_max rows.';
revoke all on function security.course_link_reactivated_v1() from public, anon, authenticated;

-- housekeeping: the register ------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_link_rediscoveries', 'Catalogue', 'IQ-00043: course link addresses a background writer tried to re-activate after they were set aside (evidence)', 'active', '{}', '20261103080000'),
 ('function', 'security.course_link_norm_v1', 'Catalogue', 'IQ-00043: course link address comparison (fragment, scheme, www, case and trailing slash ignored; query kept)', 'active', '{}', '20261103080000'),
 ('function', 'security.course_link_hold_basis_v1', 'Catalogue', 'IQ-00043: why a course link address must not become active again (superseded, retired, rejected, held)', 'active', '{}', '20261103080000'),
 ('function', 'security.course_link_reactivation_guard_trg_v1', 'Catalogue', 'IQ-00043: trigger reactivation_guard on catalogue.course_links (background writers never re-activate a held address)', 'active', '{}', '20261103080000'),
 ('function', 'security.course_link_reactivated_v1', 'Catalogue', 'IQ-00043: read-only reconciliation listing of re-activated course links', 'active', '{}', '20261103080000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '3 Nov 2026 (20261103080000): IQ-00043 reactivation guard', updated_at = now()
 where kind = 'function' and name in ('security.coverage_admission_apply_v1', 'security.coverage_apply_course_v1') and coalesce(note, '') not like '%20261103080000%';

select 'IQ-00043 link reactivation guard: settings, rule, trigger, two guarded edits, listing' ok;
