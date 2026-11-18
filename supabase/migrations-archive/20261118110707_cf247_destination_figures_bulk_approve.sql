-- CF-247 Destination data: Bulk Approve Drafts for city figures, and the ILEP draft note brought up to date (Platform Admin 18 Nov 2026 10:05, chat S1-RM-Design).
--   * public.admin_destination_figures_bulk_approve(dataset edition, reason) mirrors the localities action of 20261118090707: Platform Admin only, a reason
--     is required, one control event. It approves every clean draft figure (destination.locality_metrics) of one dataset edition. A draft is clean when it
--     has a value and attribution text; a draft without one is left as it is and counted. Each approved row carries who, when and the reason.
--     Only draft figures change: no locality, rule or edition is changed. A figure is returned by the API only once its locality is approved too.
--   * The ILEP induction draft: its note said the scheme ie_ilep was still to be registered. S2-Build registered it (Pilot #1240, 20261118080000), so that
--     sentence is taken out. The note is rewritten only while it is still the text 20261118073000 wrote (a person's later edit is left alone).
-- Replaces: nothing
-- Retires: nothing

do $pre$ begin
  if to_regclass('destination.locality_metrics') is null or to_regclass('pipeline.admin_control_events') is null or to_regprocedure('security.current_role_rank()') is null
     or to_regprocedure('public.admin_destination_localities_bulk_approve(text,text)') is null or to_regclass('pipeline.layer1_source_inductions') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

create or replace function public.admin_destination_figures_bulk_approve(p_dataset_edition text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_ed text := nullif(btrim(coalesce(p_dataset_edition, '')), '');
        v_drafts int; v_done int; v_left int; v_ev bigint;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data' using errcode = '42501'; end if; -- fixed: approval is the Platform Admin's (REQ-68)
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if v_ed is null then raise exception 'the dataset edition is required' using errcode = '22023'; end if;
  -- the edition's draft figures are locked first, so the count and the change are of the same rows
  select count(*) into v_drafts from (select 1 from destination.locality_metrics m where m.dataset_edition = v_ed and m.status = 'draft' for update) x;
  if v_drafts = 0 then raise exception 'no draft figure is held for edition %', v_ed using errcode = 'P0002'; end if;
  with done as (
    update destination.locality_metrics m set status = 'approved', status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now(), updated_at = now()
     where m.dataset_edition = v_ed and m.status = 'draft' and nullif(btrim(m.attribution_text), '') is not null and m.numeric_value is not null
    returning 1)
  select count(*) into v_done from done;
  v_left := v_drafts - v_done;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'figures_bulk_approve', v_ed,
          jsonb_build_object('dataset_edition', v_ed, 'drafts', v_drafts, 'approved', v_done, 'left_without_value_or_attribution', v_left, 'reason', v_reason), v_uid)
  returning id into v_ev;
  return jsonb_build_object('ok', true, 'kind', 'figures', 'dataset_edition', v_ed, 'drafts', v_drafts, 'approved', v_done, 'left_without_value_or_attribution', v_left, 'event_id', v_ev);
end $$;
comment on function public.admin_destination_figures_bulk_approve(text, text) is 'Destination data (20261118110707): approves every clean draft city figure (value and attribution present) of one dataset edition. Platform Admin, with a reason; one control event.';
revoke all on function public.admin_destination_figures_bulk_approve(text, text) from public, anon;
grant execute on function public.admin_destination_figures_bulk_approve(text, text) to authenticated;

-- the ILEP draft's note, without the sentence that is no longer true
update pipeline.layer1_source_inductions i
   set payload = i.payload || jsonb_build_object('notes', 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026): inducted now so current eligible Irish programmes are covered; move this source to the TrustEd Ireland list of eligible programmes when it replaces the ILEP (expected about the end of 2026). The ILEP is closed to new programmes (final update 20 June 2025). Field names are not known yet: upload the Excel list before AI Auto-Map.'),
       updated_at = now()
 where i.country_code = 'IE' and i.payload->>'source_label' = 'Interim List of Eligible Programmes (ILEP)'
   and i.payload->>'notes' like 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026):%Scheme ie_ilep is to be registered in ref.registration_schemes (with S2-Build) before step 1 can finish.';

do $post$ begin
  if has_function_privilege('anon', 'public.admin_destination_figures_bulk_approve(text, text)', 'execute') then raise exception 'post-check: anon can run the bulk approval of figures'; end if;
  if exists (select 1 from pipeline.layer1_source_inductions i where i.payload->>'source_label' = 'Interim List of Eligible Programmes (ILEP)' and i.payload->>'notes' like '%Scheme ie_ilep is to be registered%'
               and i.payload->>'notes' like 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026):%') then
    raise exception 'post-check: the ILEP note still says the scheme is to be registered';
  end if;
end $post$;
