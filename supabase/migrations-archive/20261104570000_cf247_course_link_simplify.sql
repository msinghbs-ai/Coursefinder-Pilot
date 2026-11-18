-- CF-247 Course Link admission, first Layer 4 simplification pilot (Platform Admin mandate 4 Nov 2026 16:32 AEDT §3, §9, §10, §11; admin
-- docs/platform/2026-11-04-layer4-simplification-course-link-aer-recovery-mandate-1632.md; findings
-- docs/platform/2026-11-04-course-link-admission-investigation.md).
-- Why (production, read-only, 4 Nov 2026 17:10-17:28 AEDT; 2,958 waiting official_course_url items):
--   * 2,323 are binding-check refusals of a course with no held page and no active page, the refusal recorded in pipeline.page_rejections. Decision
--     179 (Platform Admin 3 Nov 2026 20:29) moves them to the Course page needed list; security.course_page_needed_convert_v1 exists for it
--     (decision pack 2150 item 3, approved ready at 07:05: one university at a time, after the Inbox performance release, with a review pause).
--     It has never been run (0 calls). New arrivals of this class already stop (layer4.page_needed_on 1 since v2.15.447).
--   * 91 are CRICOS-differs items at the three Decision 263 rule universities; all 44 Adelaide and Canberra items fail the approved validator now,
--     and the 47 Simon Fraser items are the ones the rule does not cover. None is newly settleable.
--   * 28 belong to a provider that is no longer active (Humber); 160 have a stored copy of their page that is not linked; 15 have none.
--   * The existing platform settlement (security.layer4_resolution_for_v1, switch layer4.reconcile_supersede_on, arrival guard
--     layer4.arrival_guard_on; both off) would class 252 genuine questions as "already the active page": 55 where the binding check refused the
--     page the course shows, 188 old-year addresses (housekeeping H13 proposes the held page by design) and 9 E16 two-page cases.
--   * security.binding_refusal_route_v1 does not raise a page a person already decided for the course again, but compares raw addresses, so an
--     http/https, www or trailing-slash variant of a decided page is raised again.
-- What (no new admission authority; nothing decides an item here):
--   1 security.course_link_route_class_v1(item): the Course Link class of one waiting item for the Layer 4 operational groups (A automatic under an
--     existing authority, B technical recovery, C a person decides, D information needed), with the authority, a plain reason, a recommended
--     decision and the evidence (official domain, identity, CRICOS, held and active pages, refusals, manual bindings, stored copy, rules).
--   2 security.course_link_reconcile_v1(provider, limit, apply): the backlog reconciliation, one university at a time, counting first. It
--     supersedes items whose course or provider is retired, repeats and pages already decided (pipeline.layer4_supersessions, reversible by
--     security.layer4_supersession_reverse_v1); links the stored copy where one exists (as security.layer4_evidence_backfill_v1 does); moves the
--     Decision 179 class through the existing security.course_page_needed_convert_v1; reports items an approved Decision 263 rule would decide
--     (executed only by security.layer4_course_link_rule_execute_v1); leaves everything else in Layer 4. Run by the Integration Controller.
--   3 security.course_link_backlog_report_v1(provider): the mandate §11 Course Link row and the classes per university.
--   4 md5-guarded edits: security.layer4_resolution_for_v1 never calls a course-link question about the page the course shows "already active"
--     (refused for the course, an old-year address or an E16 two-page case); security.binding_refusal_route_v1 compares page keys for "decided
--     before", so a variant of a decided page is not raised again.
-- Edited live functions (md5-guarded, before -> after):
--   security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone) 487fc2ec6283c95c4961255a860aa9fa -> c5ec24cb4c1be5cc8d832a6c9e89dc19
--   security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)                                     717fb44dd693550cb58f41a400aff455 -> 54070a80e26df9c7aed12deb0c50bec7
-- Replaces: security.layer4_resolution_for_v1, security.binding_refusal_route_v1 (same names and signatures; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). No job, no switch is turned on, no Firecrawl or AI spend. Manual locks and
-- manual bindings are never touched; no item is approved or rejected here.

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

-- 1 settings (G2; Settings > Pipeline settings, section Layer 4 readiness) -----------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.course_link_reconcile_batch', 'Course Link reconciliation: items examined in one call',
  'At most this many waiting Course Link items of one university are classified (and, when applied, settled under an existing authority) in one call of the reconciliation.',
  'number', to_jsonb(500), 10, 5000, 'items', 1240, 'Layer 4 readiness', 'security.course_link_reconcile_v1',
  'Platform Admin mandate 4 Nov 2026 16:32 §3 (reconcile the historical Course Link backlog with guarded, auditable transitions)')
on conflict do nothing;

-- 2 the class of one item ---------------------------------------------------------------------------------------------------------------------
create or replace function security.course_link_site_v1(p_host text) returns text
language sql immutable set search_path to '' as $function$
-- The registrable site of a host (monash.edu.au, sfu.ca, whitireiaweltec.ac.nz), so a page on a sub-domain counts as the provider's own site.
  select coalesce(substring(lower(p_host) from '([^.]+\.(edu|ac|com|co|org|gov|net|school|govt)\.[a-z]{2})$'), substring(lower(p_host) from '([^.]+\.[a-z]+)$'))
$function$;
revoke all on function security.course_link_site_v1(text) from public, anon, authenticated;

create or replace function security.course_link_route_class_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- The Course Link class of one waiting official_course_url item (mandate 16:32 §2, §3), for the Layer 4 operational groups and the backlog
-- reconciliation. {item, group, class, action, authority, reason, recommended, evidence}. In order:
--   C claimed                     a reviewer has claimed it (never touched)
--   C reopened_by_admin           the Platform Admin reversed an earlier settlement of it (never settled again)
--   A entity_retired              its course or provider is no longer active                          (action supersede)
--   A duplicate_pending           an earlier waiting item asks the same question                      (action supersede)
--   A decided_before              the same page was decided before with no new evidence               (action supersede)
--   C manual_binding              the page was set by hand, or the course record is locked            (never touched)
--   A page_needed_d179            refused page, no page held when raised and none now (Decision 179)  (action convert_d179)
--   C refused_page_course_has_page  refused page, no page held when raised, the course has another page now
--   B refusal_not_recorded        a binding refusal with no recorded refusal                           (action record_refusal)
--   A covered_by_active           the proposal is already the course's page, not refused and not a question about that page (action supersede)
--   A rule_d263_pass / C rule_d263_fail   an approved Decision 263 rule university: its validator decides (action rule_d263)
--   B evidence_not_linked / evidence_missing   the stored copy of the page exists but is not linked / is not held (action link_evidence / read_page)
--   C active_page_refused         the binding check refused the page the course shows
--   C off_domain                  the proposed page is not on the provider's site
--   C held_page_dispute, cricos_page_differs, old_year_address, record_names_other_page, e16_unclear, other
-- Group D (information needed) has no Course Link class yet: a person supplies a page through Course page needed or Enter.
declare i pipeline.layer4_review_items; c record; v_src text; v_rule_l2 text; v_url text; v_key text; v_nheld int; v_held text;
        v_act text[]; v_act_keys text[]; v_refused boolean; v_ref_reason text; v_lock boolean; v_bind record; v_res jsonb; v_older uuid;
        r pipeline.layer4_course_link_rules; w record; v_copy uuid; v_copy_row record; v_site text; v_psite text; v_alias boolean; v_ev jsonb;
        v_d179 text := 'Decision 179 (Platform Admin 3 Nov 2026 20:29; admin nz-enrichment-brief/2026-11-03-layer4-course-link-growth-review.md, decision 1) and decision pack 2150 item 3 (approved ready 4 Nov 07:05: one university at a time through security.course_page_needed_convert_v1, review pause per university)';
        v_close text := 'Platform Admin mandate 4 Nov 2026 16:32 §3 (close superseded and repeated items with a recorded reason; not an admission); reason as security.layer4_resolution_for_v1';
begin
  select * into i from pipeline.layer4_review_items x where x.id = p_item;
  if i.id is null or i.status <> 'pending' or i.field_code <> 'official_course_url' or i.entity_type <> 'course' then
    return jsonb_build_object('item', p_item, 'group', null, 'class', 'not_a_waiting_course_link');
  end if;
  select k.id, k.course_code, k.lifecycle_status, k.provider_id, p.lifecycle_status plife, p.stable_key, p.website, cy.iso_alpha2 country
    into c from catalogue.courses k left join catalogue.providers p on p.id = k.provider_id left join ref.countries cy on cy.id = p.country_id where k.id = i.entity_id;
  v_src := coalesce(i.layer2_state->>'source', '');
  v_rule_l2 := coalesce(i.layer2_state->>'rule', '');
  v_url := security.layer4_item_page_v1(i.field_code, i.proposed_value, i.layer2_state);
  v_key := security.layer4_url_key_v1(v_url);
  v_nheld := case when jsonb_typeof(i.before_value) = 'array' then jsonb_array_length(i.before_value) else 0 end;
  v_held := case when v_nheld > 0 then i.before_value->>0 end;
  select array_agg(l.url order by l.is_primary desc, l.url), array_agg(security.layer4_url_key_v1(l.url) order by l.is_primary desc, l.url) into v_act, v_act_keys
    from catalogue.course_links l where l.course_id = i.entity_id and l.link_type = 'official_course' and l.status = 'active';
  select true, x.reason into v_refused, v_ref_reason from pipeline.page_rejections x
   where x.course_id = i.entity_id and security.layer4_url_key_v1(x.url) = v_key order by x.rejected_at desc nulls last limit 1;
  v_refused := coalesce(v_refused, false);
  v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('official_url', 'course_url'));
  select g.url, g.basis, g.identity_basis into v_bind from pipeline.coverage_course_pages g where g.course_id = i.entity_id;
  v_copy := coalesce(i.evidence_id, security.layer4_stored_copy_v1(v_url));
  select e.id, e.captured_at, e.metadata->>'identity_basis' basis, e.metadata->>'course_id' course into v_copy_row from pipeline.evidence_artifacts e where e.id = v_copy;
  v_site := security.course_link_site_v1(split_part(coalesce(v_key, ''), '/', 1));
  v_psite := security.course_link_site_v1(regexp_replace(regexp_replace(lower(coalesce(c.website, '')), '^https?://(www\.)?', ''), '/.*$', ''));
  v_alias := exists (select 1 from unnest(security.pipeline_list_v1('binding.provider_host_aliases', '[]'::jsonb)) a(v)
                      where split_part(a.v, '=', 1) = c.stable_key
                        and v_site = any (array(select security.course_link_site_v1(h) from unnest(string_to_array(split_part(a.v, '=', 2), ' ')) h)));
  v_ev := jsonb_build_object('source', v_src, 'rule', nullif(v_rule_l2, ''), 'proposed', v_url, 'held_when_raised', i.before_value, 'active_pages', to_jsonb(v_act),
            'proposed_refused', v_refused, 'refusal_reason', v_ref_reason, 'manual_lock', v_lock, 'binding', case when v_bind.url is null then null else
            jsonb_build_object('url', v_bind.url, 'basis', v_bind.basis, 'identity_basis', v_bind.identity_basis) end,
            'stored_copy', case when v_copy_row.id is null then null else jsonb_build_object('id', v_copy_row.id, 'captured_at', v_copy_row.captured_at,
            'identity_basis', v_copy_row.basis, 'read_for_this_course', v_copy_row.course = i.entity_id::text, 'linked', i.evidence_id is not null) end,
            'course_code', c.course_code, 'country', c.country, 'official_site', v_psite, 'proposed_site', v_site, 'raised_at', i.created_at);

  if i.claimed_at is not null or i.assigned_to is not null then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'claimed', 'action', 'keep', 'authority', null,
      'reason', 'A reviewer has claimed this item.', 'recommended', null, 'evidence', v_ev);
  end if;
  if exists (select 1 from pipeline.layer4_supersessions s where s.item_id = i.id and s.reversed_at is not null) then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'reopened_by_admin', 'action', 'keep', 'authority', null,
      'reason', 'The Platform Admin put this item back after the platform settled it, so a person decides it.', 'recommended', null, 'evidence', v_ev);
  end if;
  -- A: closes under the existing settlement reasons (never an approval or a refusal)
  if c.id is null or c.lifecycle_status is distinct from 'active' or c.plife is distinct from 'active' then
    return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'entity_retired', 'action', 'supersede', 'authority', v_close,
      'reason', 'The course or its provider is no longer active, so its page is no longer asked for.', 'recommended', null,
      'evidence', v_ev || jsonb_build_object('course_status', coalesce(c.lifecycle_status, 'missing'), 'provider_status', coalesce(c.plife, 'missing')));
  end if;
  select o.id into v_older from pipeline.layer4_review_items o
   where o.entity_type = 'course' and o.entity_id = i.entity_id and o.field_code = 'official_course_url' and o.status = 'pending' and o.id <> i.id
     and (o.created_at, o.id) < (i.created_at, i.id) and security.layer4_url_key_v1(security.layer4_item_page_v1(o.field_code, o.proposed_value, o.layer2_state)) is not distinct from v_key
   order by o.created_at, o.id limit 1;
  if v_older is not null then
    return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'duplicate_pending', 'action', 'supersede', 'authority', v_close,
      'reason', 'An earlier waiting item asks the same question about the same page.', 'recommended', null, 'evidence', v_ev || jsonb_build_object('covered_by_item', v_older));
  end if;
  v_res := security.layer4_resolution_for_v1(i.id, i.entity_type, i.entity_id, i.field_code, i.proposed_value, i.layer2_state, i.evidence_id, i.created_at);
  if v_res->>'reason' = 'decided_before' then
    return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'decided_before', 'action', 'supersede', 'authority', v_close,
      'reason', 'The same page was decided for this course before, and this item brings no new evidence.', 'recommended', null,
      'evidence', v_ev || jsonb_build_object('covered_by_item', v_res->'covered_by_item', 'earlier', v_res->'evidence'));
  end if;
  if v_lock or v_bind.basis = 'manual' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'manual_binding', 'action', 'keep', 'authority', null,
      'reason', 'The course''s page was set by hand. The platform never changes it.', 'recommended', 'Keep the page we hold. Change it only on the course record.', 'evidence', v_ev);
  end if;
  if v_src = 'binding check' and v_nheld = 0 then
    if coalesce(cardinality(v_act), 0) = 0 and v_refused then
      return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'page_needed_d179', 'action', 'convert_d179', 'authority', v_d179,
        'reason', 'The page found was refused by the binding check and the course has no page. The course goes to Course page needed; the refusal stays recorded.',
        'recommended', null, 'evidence', v_ev);
    elsif coalesce(cardinality(v_act), 0) > 0 and v_refused and not (v_key = any (v_act_keys)) then
      return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'refused_page_course_has_page', 'action', 'keep', 'authority', null,
        'reason', 'The page found was refused by the binding check; the course has since got another page.',
        'recommended', 'Refuse this proposal (the course keeps its current page).', 'evidence', v_ev);
    elsif not v_refused then
      return jsonb_build_object('item', i.id, 'group', 'B', 'class', 'refusal_not_recorded', 'action', 'record_refusal', 'authority', null,
        'reason', 'The binding check raised this item but its refusal is not recorded.', 'recommended', null, 'evidence', v_ev);
    end if;
  end if;
  if v_key = any (coalesce(v_act_keys, '{}')) and not v_refused and v_rule_l2 not in ('address_year', 'e16_unclear')
     and v_src not in ('housekeeping H13', 'e16 unclear') then
    return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'covered_by_active', 'action', 'supersede', 'authority', v_close,
      'reason', 'The proposed page is already the course''s page.', 'recommended', null, 'evidence', v_ev);
  end if;
  -- an approved Decision 263 rule university: only its validator decides
  select * into r from pipeline.layer4_course_link_rules x where x.provider_id = c.provider_id and i.escalation_reason ilike x.reason_like order by x.code limit 1;
  if r.code is not null then
    select x.pass, x.reasons into w from security.layer4_course_link_rule_validate_v1(r.code, i.id) x;
    if coalesce(w.pass, false) then
      return jsonb_build_object('item', i.id, 'group', 'A', 'class', 'rule_d263_pass', 'action', 'rule_d263', 'rule', r.code, 'authority', r.approval_ref,
        'reason', 'The approved rule for this university covers this item and every check passes.', 'recommended', case r.choice when 'keep' then 'Keep the page we hold' else 'Use the new page' end,
        'evidence', v_ev);
    end if;
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'rule_d263_fail', 'action', 'keep', 'rule', r.code, 'authority', null,
      'reason', 'This university has an approved rule, but this item does not pass it: ' || coalesce(array_to_string(w.reasons, '; '), 'not in the rule''s scope') || '.',
      'recommended', 'Decide by hand: ' || case r.choice when 'keep' then 'keep the page we hold if it is this course''s own page' else 'use the new page if it is this course''s own page' end || '.',
      'evidence', v_ev || jsonb_build_object('rule_reasons', to_jsonb(w.reasons)));
  end if;
  -- B: technical, before a person is asked
  if i.evidence_id is null then
    if v_copy is not null then
      return jsonb_build_object('item', i.id, 'group', 'B', 'class', 'evidence_not_linked', 'action', 'link_evidence', 'authority', 'layer4.evidence_link_on (records only; mandate 3 Nov 20:47 §5)',
        'reason', 'A stored copy of the proposed page exists but is not linked to the card.', 'recommended', null, 'evidence', v_ev);
    end if;
    return jsonb_build_object('item', i.id, 'group', 'B', 'class', 'evidence_missing', 'action', 'read_page', 'authority', null,
      'reason', 'No stored copy of the proposed page is held, so the card cannot show the page.', 'recommended', null, 'evidence', v_ev);
  end if;
  -- C: a person decides
  if v_refused and v_key = any (coalesce(v_act_keys, '{}')) then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'active_page_refused', 'action', 'keep', 'authority', null,
      'reason', 'The binding check refused the page this course shows: ' || coalesce(v_ref_reason, 'not proved to be this course''s page') || '.',
      'recommended', 'Check the page. If it is not this course''s own page, Enter the correct page; otherwise keep it.', 'evidence', v_ev);
  end if;
  if v_site is not null and v_psite is not null and v_site <> v_psite and not v_alias then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'off_domain', 'action', 'keep', 'authority', null,
      'reason', 'The proposed page is on ' || v_site || ', not on the provider''s site ' || v_psite || '.',
      'recommended', 'Keep the page we hold unless the provider confirms this site is its own.', 'evidence', v_ev);
  end if;
  if v_src = 'binding check' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'held_page_dispute', 'action', 'keep', 'authority', null,
      'reason', 'A new page was found but refused by the binding check: ' || coalesce(v_ref_reason, 'not proved to be this course''s page') || '. The course keeps its page.',
      'recommended', 'Keep the page we hold.', 'evidence', v_ev);
  elsif v_src = 'coverage sweep' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'cricos_page_differs', 'action', 'keep', 'authority', null,
      'reason', 'The page that shows this course''s code is a different address from the page we hold.',
      'recommended', case when v_copy_row.basis in ('cricos_code', 'nzqa_code') and v_copy_row.course = i.entity_id::text and coalesce(v_bind.identity_basis, '') not in ('cricos_code', 'nzqa_code')
                          then 'Use the new page: its stored copy shows this course''s code and the page we hold was not bound by the code.'
                          else 'Keep the page we hold unless the new page is this course''s own page.' end, 'evidence', v_ev);
  elsif v_src = 'housekeeping H13' or v_rule_l2 = 'address_year' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'old_year_address', 'action', 'keep', 'authority', null,
      'reason', 'The page we show has an old year in its address and may be an archived handbook.',
      'recommended', 'Keep it if it is still the current page; otherwise Enter the current page.', 'evidence', v_ev);
  elsif v_src = 'housekeeping H05' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'record_names_other_page', 'action', 'keep', 'authority', null,
      'reason', 'The course record names a different page from the one we show.', 'recommended', 'Use the new page if it is this course''s own page; otherwise keep the page we hold.', 'evidence', v_ev);
  elsif v_src = 'e16 unclear' or v_rule_l2 = 'e16_unclear' then
    return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'e16_unclear', 'action', 'keep', 'authority', null,
      'reason', 'The course holds two pages and this one does not name the award.', 'recommended', 'Keep the page that names this course''s award.', 'evidence', v_ev);
  end if;
  return jsonb_build_object('item', i.id, 'group', 'C', 'class', 'other', 'action', 'keep', 'authority', null,
    'reason', coalesce(i.escalation_reason, 'A person decides this page.'), 'recommended', null, 'evidence', v_ev);
end $function$;
revoke all on function security.course_link_route_class_v1(uuid) from public, anon, authenticated;

-- 3 the backlog reconciliation, one university at a time --------------------------------------------------------------------------------------
create or replace function security.course_link_reconcile_v1(p_provider uuid, p_limit int, p_apply boolean) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Mandate 16:32 §3 "reconcile the historical Course Link backlog using guarded, auditable transitions". For the waiting Course Link items of one
-- university (security.course_link_route_class_v1, classified again on the locked item before any write):
--   supersede      entity_retired, duplicate_pending, decided_before, covered_by_active: status superseded with the reason, one row in
--                  pipeline.layer4_supersessions (mode reconcile; reversible by security.layer4_supersession_reverse_v1). Not an approval or a refusal.
--   link_evidence  the stored copy is linked (evidence_id only, as security.layer4_evidence_backfill_v1 does); the item stays waiting.
--   convert_d179   moved by the existing security.course_page_needed_convert_v1 (Decision 179; its own checks and audit).
--   rule_d263      counted only: the approved rule is executed by security.layer4_course_link_rule_execute_v1 (its own validation and audit).
--   everything else stays in Layer 4 with its class, reason and recommendation.
-- p_apply false counts only and writes nothing. An item another reviewer holds is skipped. Platform Admin or the Integration Controller (no
-- signed-in user); each applied call is audited in pipeline.admin_control_events.
declare r record; v jsonb; v2 jsonb; v_seen int := 0; v_sup int := 0; v_link int := 0; v_by jsonb := '{}'::jsonb; v_grp jsonb := '{}'::jsonb;
        v_rules jsonb := '{}'::jsonb; v_conv jsonb; v_d179 int := 0; v_skip int := 0; v_lock int; v_cls text;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_provider is null then raise exception 'one university at a time: give its provider id' using errcode = '22023'; end if;
  for r in select i.id from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
            where i.status = 'pending' and i.field_code = 'official_course_url' and i.entity_type = 'course' and c.provider_id = p_provider
            order by i.created_at, i.id
            limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.course_link_reconcile_batch', 500)::int) loop
    v_seen := v_seen + 1;
    v := security.course_link_route_class_v1(r.id);
    v_cls := v->>'class';
    v_by := jsonb_set(v_by, array[v_cls], to_jsonb(coalesce((v_by->>v_cls)::int, 0) + 1));
    v_grp := jsonb_set(v_grp, array[coalesce(v->>'group', '-')], to_jsonb(coalesce((v_grp->>coalesce(v->>'group', '-'))::int, 0) + 1));
    if v->>'action' = 'convert_d179' then v_d179 := v_d179 + 1; end if;
    if v->>'action' = 'rule_d263' then v_rules := jsonb_set(v_rules, array[v->>'rule'], to_jsonb(coalesce((v_rules->>(v->>'rule'))::int, 0) + 1)); end if;
    continue when not coalesce(p_apply, false) or v->>'action' not in ('supersede', 'link_evidence');
    -- the item, locked; one another reviewer holds is skipped, never waited for; then classified again
    begin
      v_lock := null;
      select 1 into v_lock from pipeline.layer4_review_items i where i.id = r.id and i.status = 'pending' and i.claimed_at is null and i.assigned_to is null for update nowait;
    exception when lock_not_available then v_lock := null;
    end;
    if v_lock is null then v_skip := v_skip + 1; continue; end if;
    v2 := security.course_link_route_class_v1(r.id);
    if v2->>'class' is distinct from v_cls then v_skip := v_skip + 1; continue; end if;
    if v2->>'action' = 'supersede' then
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
             change_control_ref = coalesce(change_control_ref || '; ', '') || 'CF-247 Course Link reconciliation (mandate 4 Nov 2026 16:32 §3): superseded (' || v_cls || ')'
       where id = r.id and status = 'pending';
      insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
      select i.id, i.field_code, i.entity_type, i.entity_id, v_cls, nullif(v2->'evidence'->>'covered_by_item', '')::uuid,
             (v2->'evidence') || jsonb_build_object('route', 'course_link_reconcile_v1', 'authority', v2->>'authority'), 'reconcile'
        from pipeline.layer4_review_items i where i.id = r.id;
      update pipeline.layer4_item_readiness set item_status = 'superseded', readiness = 'closed', classified_at = now() where item_id = r.id;
      v_sup := v_sup + 1;
    elsif v2->>'action' = 'link_evidence' then
      update pipeline.layer4_review_items set evidence_id = nullif(v2->'evidence'->'stored_copy'->>'id', '')::uuid
       where id = r.id and status = 'pending' and evidence_id is null and nullif(v2->'evidence'->'stored_copy'->>'id', '') is not null;
      if found then v_link := v_link + 1; end if;
    end if;
  end loop;
  -- Decision 179: the existing conversion, with its own checks (claimed, held page when raised or now, refusal recorded) and its own audit
  if v_d179 > 0 then
    v_conv := security.course_page_needed_convert_v1(p_provider, least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.course_link_reconcile_batch', 500)::int), coalesce(p_apply, false));
  end if;
  if coalesce(p_apply, false) then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'course_link_reconcile', p_provider::text,
            jsonb_build_object('examined', v_seen, 'by_class', v_by, 'by_group', v_grp, 'superseded', v_sup, 'evidence_linked', v_link, 'skipped', v_skip,
                               'page_needed_converted', v_conv, 'rule_d263_ready', v_rules, 'authority', 'mandate 4 Nov 2026 16:32 §3; Decision 179; Decision 263 (count only)'), auth.uid());
  end if;
  return jsonb_build_object('apply', coalesce(p_apply, false), 'provider_id', p_provider, 'examined', v_seen, 'by_class', v_by, 'by_group', v_grp,
                            'superseded', v_sup, 'evidence_linked', v_link, 'skipped', v_skip, 'page_needed', jsonb_build_object('classified', v_d179, 'convert', v_conv),
                            'rule_d263_ready', v_rules,
                            'next', case when v_rules <> '{}'::jsonb then 'approved rule items: security.layer4_course_link_rule_execute_v1(rule, n, true)' end);
end $function$;
revoke all on function security.course_link_reconcile_v1(uuid, int, boolean) from public, anon, authenticated;

-- 4 the §11 Course Link row ------------------------------------------------------------------------------------------------------------------
create or replace function security.course_link_backlog_report_v1(p_provider uuid default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- Mandate 16:32 §11 for Course Link: waiting items by group and class, per university (or one), and the 7-day outcomes: automatically resolved
-- (reconciliation supersessions and Decision 179 conversions), decided, admitted (approved decisions) and published (approvals whose admission
-- check found the page in the search projection), over layer4.lifecycle_report_days. Read only.
  with w as (select i.id, c.provider_id, coalesce(p.short_name, p.canonical_name) prov, security.course_link_route_class_v1(i.id) v
               from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id left join catalogue.providers p on p.id = c.provider_id
              where i.status = 'pending' and i.field_code = 'official_course_url' and i.entity_type = 'course' and (p_provider is null or c.provider_id = p_provider)),
  per as (select prov, jsonb_object_agg(cls, n) by_class, sum(n) n from (select prov, v->>'class' cls, count(*) n from w group by 1, 2) z group by prov)
  select jsonb_build_object(
    'pending', (select count(*) from w),
    'by_group', (select coalesce(jsonb_object_agg(g, n), '{}'::jsonb) from (select coalesce(v->>'group', '-') g, count(*) n from w group by 1) z),
    'by_class', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select v->>'class' k, count(*) n from w group by 1) z),
    'automatically_resolved_7d', (select count(*) from pipeline.layer4_supersessions s where s.field_code = 'official_course_url' and s.reversed_at is null and s.at > now() - make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int))
                                 + (select count(*) from pipeline.layer4_review_items i where i.field_code = 'official_course_url' and i.status = 'superseded' and i.decided_at > now() - make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int)
                                      and i.change_control_ref like '%Decision 179 (Platform Admin 3 Nov 2026 20:29): moved to Course page needed%'),
    'technical_holds', (select count(*) from w where v->>'group' = 'B'),
    'human_input', (select count(*) from w where v->>'group' = 'D'),
    'review_ready', (select count(*) from w where v->>'group' = 'C'),
    'decided_7d', (select count(*) from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
                    where i.field_code = 'official_course_url' and d.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int)),
    'admitted_7d', (select count(*) from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
                     where i.field_code = 'official_course_url' and d.action in ('approve', 'edit') and d.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int)),
    'per_university', (select coalesce(jsonb_object_agg(prov, jsonb_build_object('pending', n, 'by_class', by_class)), '{}'::jsonb) from per))
$function$;
revoke all on function security.course_link_backlog_report_v1(uuid) from public, anon, authenticated;

-- 5 md5-guarded edits ------------------------------------------------------------------------------------------------------------------------
-- 5a a course-link question about the page the course shows is never "already the active page"
select pg_temp.edit_once('security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone)', '487fc2ec6283c95c4961255a860aa9fa', 'c5ec24cb4c1be5cc8d832a6c9e89dc19', array[
  array[$o$  if p_field = 'official_course_url' and v_key is not null then
$o$, $n$  -- CF-247 Course Link (mandate 4 Nov 2026 16:32 §3): a question about the page the course shows (refused for this course by the binding check, an
  -- old-year address, an E16 two-page case) is not settled as "already the active page"; a person answers it
  if p_field = 'official_course_url' and v_key is not null and coalesce(p_l2->>'rule', '') not in ('address_year', 'e16_unclear')
     and coalesce(p_l2->>'source', '') not in ('housekeeping H13', 'e16 unclear')
     and not exists (select 1 from pipeline.page_rejections r where r.course_id = p_entity_id and security.layer4_url_key_v1(r.url) = v_key) then
$n$]], array[1]);

-- 5b a page already decided for the course is not raised again however its address is written
select pg_temp.edit_once('security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)', '717fb44dd693550cb58f41a400aff455', '54070a80e26df9c7aed12deb0c50bec7', array[
  array[$o$                and i.proposed_value->>'course_url' = p_url) then$o$,
        $n$                and security.layer4_url_key_v1(i.proposed_value->>'course_url') = security.layer4_url_key_v1(p_url)) then$n$]], array[1]);

-- 6 component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_link_site_v1', 'Layer 4', 'Layer 4 review', 'Registrable site of a host (Course Link official-domain check)', 'active', '{}', '20261104570000'),
 ('function', 'security.course_link_route_class_v1', 'Layer 4', 'Layer 4 review', 'Course Link class, group, authority and recommendation of one item (mandate 16:32 §3)', 'active', '{}', '20261104570000'),
 ('function', 'security.course_link_reconcile_v1', 'Layer 4', 'Layer 4 review', 'Course Link backlog reconciliation, one university at a time (Integration Controller)', 'active', '{}', '20261104570000'),
 ('function', 'security.course_link_backlog_report_v1', 'Layer 4', 'Layer 4 review', 'Course Link §11 row and classes per university', 'active', '{}', '20261104570000')
on conflict do nothing;

-- 7 post-check -------------------------------------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values ('security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone)', 'c5ec24cb4c1be5cc8d832a6c9e89dc19'),
                                 ('security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)', '54070a80e26df9c7aed12deb0c50bec7')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'post-check: % has md5 %', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $$;
