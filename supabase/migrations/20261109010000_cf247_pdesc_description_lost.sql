-- CF-247 F-PDESC (Platform Admin data population mandate 9 Nov 2026, section 2 and the 9 Nov 06:53 addition: the platform fills a provider that qualifies, with no hand-kept list).
--
-- Finding (read only, live 8 Nov 2026 ~20:00 UTC, project fxcwkweaxjtknorudmwp; security.provider_description_selection_v1(jsonb) md5 1fd3fcde2fcafed6fadf4f6337c0482c):
--   A provider whose description is cleared (a person empties the field, a correction, a rollback) while its latest read is 'admitted' or 'verified' is answered
--   'description_current' by selection_v1 for pdesc.recheck_days (180 days), because that branch looks at the read and not at the catalogue value. The reader then never
--   queues the provider again although it has no description. (enqueue_v1 and svc_provider_description_next only admit a provider whose description is null or that has an
--   admitted read, so they accept it; only the selection refuses it.)
-- Change: selection_v1 answers 'description_current' only when a description is held. A provider with no description and an admitted or verified read now falls through
--   to every later check (identity, recovery knowledge, stored copy) and, if they pass, is answered 'description_lost', which is eligible like 'eligible' and
--   'invalid_description'. Nothing else in the function changes: manual lock, hidden, inactive, manual description, existing work, dead letter, cost reservation, held and
--   rejected waits (pdesc.recheck_days, pdesc.retry_minutes) come earlier in the same CASE and still apply. A cleared description that a person then rejects again for the new
--   proposal waits the normal 180 days; a manual lock on description stops the re-read. Layer 4 is unchanged: the new proposal is an individual human decision.
-- No setting, flag, job, Layer 4 item or consumer API object is created or changed; no number is added (the settings used already exist). The edit is guarded: it applies only to
--   the live definition (md5 above), once, and a second run is a no-op.
--
-- Live definition this change edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.provider_description_selection_v1(jsonb) 1fd3fcde2fcafed6fadf4f6337c0482c -> eaebe3d0a6c188f0b4f6b6c3fcf659ba
-- Replaces: the 'description_current' branch of security.provider_description_selection_v1 for a provider with no description (edited in place; the function is not replaced)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_selection_v1(jsonb)'), ('security.provider_description_identity_v1(uuid,text)'), ('security.provider_description_page_v1(uuid,text)'),
                                 ('security.provider_description_approved_lineage_v1(uuid,text)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int; i int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', '1fd3fcde2fcafed6fadf4f6337c0482c', 'eaebe3d0a6c188f0b4f6b6c3fcf659ba',
array[
-- 1 a held description is current; an empty one is not (it falls through to the identity, recovery and source checks)
$old$  when r.state in ('admitted','verified') and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'
$old$,
-- 2 after every guard has passed, a provider with an admitted or verified read and no description is named description_lost
$old$  else 'eligible' end eligibility_reason
$old$,
-- 3 description_lost is eligible, in the row
$old$ 'eligible',eligibility_reason in ('eligible','invalid_description'),'eligibility_reason',eligibility_reason,$old$,
-- 4 and in the two orderings (eligible first)
$old$ ) select coalesce(jsonb_agg(row order by eligibility_reason in ('eligible','invalid_description') desc,active_course_count desc,nm),'[]'::jsonb) into v_rows
$old$,
$old$ from (select * from shaped order by eligibility_reason in ('eligible','invalid_description') desc,active_course_count desc,nm limit v_size) b;
$old$],
array[
$new$  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'
$new$,
$new$  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is null then 'description_lost'
  else 'eligible' end eligibility_reason
$new$,
$new$ 'eligible',eligibility_reason in ('eligible','invalid_description','description_lost'),'eligibility_reason',eligibility_reason,$new$,
$new$ ) select coalesce(jsonb_agg(row order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm),'[]'::jsonb) into v_rows
$new$,
$new$ from (select * from shaped order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm limit v_size) b;
$new$]);
