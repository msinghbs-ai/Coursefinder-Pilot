-- CF-247 hotfix (Platform Admin 26 Oct 2026 12:50: "make the inbox fix NOW, as a hotfix release under rule 9 … Scope, exactly: first-run
-- items (no-page + conjoint) carry their university in the Layer 4 inbox, appear under 'By university', and expose approve / edit / reject
-- actions on the card. Nothing else in this release.")
-- Found 26 Oct 12:4x (Waikato triage, admin docs/platform/ui-audit/2026-10-26-waikato-triage-followups.md section 3): the 60 waiting first
-- runs (pipeline.layer4_review_items, entity_type 'provider', field codes no_page_first_run / conjoint_rule_first_run) reached the Inbox
-- with no university, so they never showed under "By university", and as kind "course_link" they offered the course-link choices.
-- 1 security.layer4_inbox_items_v1: a provider-entity first run takes its university from the item and its own kind
--   (no_page_first_run, conjoint_first_run), with a readable subject. Every other row is unchanged.
-- 2 security.layer4_inbox_kinds_v1: the two kinds, each with approve / edit and approve / reject.
-- 3 public.admin_layer4_inbox (decide): the two kinds go to public.layer4_review_decide (approve, edit_and_approve, reject), which already
--   applies first runs through security.no_page_review_apply_v1 (60% rule unchanged). Edit for no page: the sample courses that do have a page
--   (has_page_course_ids, each checked to be in the item's sample). Edit for conjoint: the shared conjoint page (parent_url).
-- md5-guarded edits; nothing else changes.
-- Replaces: nothing (security.layer4_inbox_items_v1, security.layer4_inbox_kinds_v1, public.admin_layer4_inbox edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 items: university, kind and subject for provider-entity first runs
select pg_temp.edit_n('security.layer4_inbox_items_v1()', 'c5f4f34cd2ea79b3a3aff8ef3617b4a6', array[
  array[$o$  select 'course_link'::text, r.id::text, coalesce(c.provider_id, s.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title, s.name, r.field_code),$o$,
        $n$  -- hotfix 26 Oct 2026: a first run for a university (no page published, conjoint rule) carries its university and its own kind
  select case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'no_page_first_run'
              when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'conjoint_first_run'
              else 'course_link' end::text,
         r.id::text, coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
         coalesce(nullif(c.display_title, ''), c.canonical_title, s.name,
                  case when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'No page published: first run'
                       when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'Conjoint or double degrees: first run' end,
                  r.field_code),$n$]], array[1]);

-- 2 kinds: the two first-run kinds with approve / edit and approve / reject
select pg_temp.edit_n('security.layer4_inbox_kinds_v1()', '1703346f9f602cce922aaea2d6f11450', array[
  array[$o$   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$o$,
        $n$   "no_page_first_run": {"label": "No page published: first run", "order": 15, "choices": [
     {"key": "approve", "label": "Approve: none has its own page", "returns": "The sample is recorded as no page published; at the 60% rule the university is trusted and its later cases are recorded without a person; any page found later re-opens a course"},
     {"key": "has_page", "label": "Approve, except courses that have a page", "input": "courses", "returns": "The ticked courses keep looking for their page; the others are recorded; the university is trusted only at the 60% rule"},
     {"key": "reject", "label": "Reject", "returns": "Nothing is recorded and the university is not trusted; its courses keep looking for their pages"}]},
   "conjoint_first_run": {"label": "Conjoint or double degrees: first run", "order": 16, "choices": [
     {"key": "approve", "label": "Approve: no page of their own", "returns": "The conjoint degrees of this university leave the course search, recorded as conjoint; any page found later re-opens a course"},
     {"key": "parent", "label": "Approve with their shared page", "input": "url", "returns": "Recorded as conjoint, with this address as their shared conjoint page"},
     {"key": "reject", "label": "Reject", "returns": "Nothing is recorded; the conjoint degrees keep looking for their pages"}]},
   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$n$]], array[1]);

-- 3 decide: the two kinds go to layer4_review_decide
select pg_temp.edit_n('public.admin_layer4_inbox(text,jsonb)', '2e2225b03af3a206ea3aa126354f023b', array[
  array[$o$  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide($o$,
        $n$  elsif v_kind in ('no_page_first_run', 'conjoint_first_run') then
    -- hotfix 26 Oct 2026: a university's first run (no page published / conjoint rule); applied by security.no_page_review_apply_v1
    if v_choice = 'has_page' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the sample courses that have their own page';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the sample courses that have their own page'; end if;
      if exists (select 1 from unnest(v_ids) x(id) where not exists (select 1 from pipeline.course_no_page n where n.review_item_id = v_ref::uuid and n.course_id = x.id)) then
        raise exception 'a ticked course is not in this sample';
      end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid,
             case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case v_choice when 'has_page' then jsonb_build_object('has_page_course_ids', to_jsonb(v_ids))
                           when 'parent' then jsonb_build_object('parent_url', v_value) end);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide($n$]], array[1]);
