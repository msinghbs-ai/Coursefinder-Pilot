-- CF-247 (23 Oct 2026). Read with AI on the University of Auckland diplomas still gave no campus (Platform Admin 12:52 "Still no city"):
-- the page names ["City","South Auckland"], and a campus list made from one course's page is never admitted, because a campus needs
-- enrich.campus_min_pages (2) course pages naming it, and Read with AI reads one course at a time. A campus the university already has
-- (active, same name) is now linked from one course page that names it; a new campus still needs enrich.campus_min_pages pages or a person.
-- Worker v0.42.4 keeps a campus name found inside a name given as a list.
-- Replaces: nothing (security.enrich_campus_list_apply_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.enrich_campus_list_apply_v1(bigint)', '2617420b455dea68f7cb2cbed8271088', array[
  array[$o$    if v_pages < v_min then v_review := v_review || (x || jsonb_build_object('pages', v_pages)); continue; end if;
    select ca.id into v_cid from catalogue.campuses ca where ca.provider_id = i.provider_id and lower(ca.name) = lower(x->>'name') limit 1;$o$,
        $n$    select ca.id into v_cid from catalogue.campuses ca where ca.provider_id = i.provider_id and lower(ca.name) = lower(x->>'name') limit 1;
    -- 23 Oct 2026: a campus the university already has (active) is linked from one course page that names it; a new campus needs v_min pages
    if v_pages < 1 or (v_pages < v_min and not exists (select 1 from catalogue.campuses ca where ca.id = v_cid and ca.status = 'active')) then
      v_cid := null; v_review := v_review || (x || jsonb_build_object('pages', v_pages)); continue;
    end if;$n$]]);

do $d$ declare r jsonb; c jsonb;
begin
  update pipeline.field_enrich_items set value = jsonb_build_object('campuses', '[{"name":"City","raw":["City"],"city":"Auckland","street":null,"postcode":null},{"name":"South Auckland","raw":["South Auckland"],"city":"Auckland","street":null,"postcode":null}]'::jsonb), state = 'ai' where id = 172686;
  update pipeline.field_enrich_items set state = 'waiting', reason = null where job_id = '915df9bd-1f99-405f-aa40-a2f113ceebd5' and field = 'campus';
  r := security.enrich_campus_list_apply_v1(172686);
  perform security.enrich_campus_link_v1('915df9bd-1f99-405f-aa40-a2f113ceebd5');
  select jsonb_agg(jsonb_build_object('campus', k.name, 'city', k.city, 'mode', cc.delivery_mode)) into c from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id where cc.course_id = 'ecae5b4f-0b13-4ef0-ad37-64f7ba208576';
  raise exception 'DRYRUN OK apply % | campus_item % | links %', r,
    (select state || ' ' || coalesce(reason,'') || ' ' || coalesce(value::text,'') from pipeline.field_enrich_items where job_id = '915df9bd-1f99-405f-aa40-a2f113ceebd5' and field = 'campus'), c;
end $d$;
