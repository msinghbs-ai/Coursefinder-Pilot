-- CF-247 Destination data: Bulk Approve Drafts (Platform Admin 18 Nov 2026 07:39, chat S1-RM-Design). One action approves every clean draft locality of a
-- dataset edition (18 Nov 2026: 102 draft localities of "ABS Regional population 2024-25", each needing its own Approve click).
--   * public.admin_destination_localities_bulk_approve(dataset edition, reason): Platform Admin only, a reason is required, as for one locality
--     (public.admin_destination_set_status). A draft is clean when it has a name and attribution text. A draft without attribution is left as it is and
--     counted. Each approved row carries who, when and the reason, as a single approval does; one control event records the whole action.
--   * Only draft localities change. Localities in review, withdrawn or already approved are not touched, and no figure, rule or edition is changed.
-- Replaces: nothing
-- Retires: nothing

do $pre$ begin
  if to_regclass('destination.localities') is null or to_regclass('pipeline.admin_control_events') is null or to_regprocedure('security.current_role_rank()') is null
     or to_regprocedure('public.admin_destination_set_status(text,uuid,text,text)') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

create or replace function public.admin_destination_localities_bulk_approve(p_dataset_edition text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_ed text := nullif(btrim(coalesce(p_dataset_edition, '')), '');
        v_drafts int; v_done int; v_left int; v_ev bigint;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data' using errcode = '42501'; end if; -- fixed: approval is the Platform Admin's (REQ-68)
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if v_ed is null then raise exception 'the dataset edition is required' using errcode = '22023'; end if;
  -- the edition's drafts are locked first, so the count and the change are of the same rows
  select count(*) into v_drafts from (select 1 from destination.localities l where l.dataset_edition = v_ed and l.status = 'draft' for update) x;
  if v_drafts = 0 then raise exception 'no draft locality is held for edition %', v_ed using errcode = 'P0002'; end if;
  with done as (
    update destination.localities l set status = 'approved', status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now(), updated_at = now()
     where l.dataset_edition = v_ed and l.status = 'draft' and nullif(btrim(l.attribution_text), '') is not null and nullif(btrim(l.name), '') is not null
    returning 1)
  select count(*) into v_done from done;
  v_left := v_drafts - v_done;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'localities_bulk_approve', v_ed,
          jsonb_build_object('dataset_edition', v_ed, 'drafts', v_drafts, 'approved', v_done, 'left_without_attribution', v_left, 'reason', v_reason), v_uid)
  returning id into v_ev;
  return jsonb_build_object('ok', true, 'dataset_edition', v_ed, 'drafts', v_drafts, 'approved', v_done, 'left_without_attribution', v_left, 'event_id', v_ev);
end $$;
comment on function public.admin_destination_localities_bulk_approve(text, text) is 'Destination data (20261118090707): approves every clean draft locality (name and attribution present) of one dataset edition. Platform Admin, with a reason; one control event.';
revoke all on function public.admin_destination_localities_bulk_approve(text, text) from public, anon;
grant execute on function public.admin_destination_localities_bulk_approve(text, text) to authenticated;

do $post$ begin
  if has_function_privilege('anon', 'public.admin_destination_localities_bulk_approve(text, text)', 'execute') then raise exception 'post-check: anon can run the bulk approval'; end if;
end $post$;
