-- CF-247 (22 Oct 2026). Platform Admin 11:50: "Bug/fix - why the course is showing as "not published" - Published is now toggle field
-- for providers and not for courses".
-- The course detail showed the course's own publication field, which is no longer used (every course is "unpublished"; the provider's
-- Published switch decides what the website shows). The course detail now also returns its provider's switch, and the screen shows that.
-- Replaces: security.admin_read_impl (course_detail returns provider_publication_status). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('security.admin_read_impl(text,jsonb)'::regprocedure)) <> '2c2da9acdacaa6a99b37e527718aec6c' then
    raise exception 'live security.admin_read_impl differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.admin_read_impl(text,jsonb)', '2c2da9acdacaa6a99b37e527718aec6c', array[
  [$o$      'country_code',(select k.iso_alpha2 from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.countries k on k.id=p2.country_id where c2.id=v_id),$o$,
   $n$      'country_code',(select k.iso_alpha2 from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.countries k on k.id=p2.country_id where c2.id=v_id),
      -- 22 Oct 2026 (Platform Admin 11:50): the provider's Published switch decides whether the course is on the website
      'provider_publication_status',(select p2.publication_status from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id where c2.id=v_id),$n$]]);
