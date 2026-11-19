do $mig$
declare d text;
  a text := $q$when b.field_code<>'provider_current_tuition_validation' then jsonb_build_object('action','check','text','Check the page, then decide.')$q$;
  b text := $q$when b.field_code='official_course_url' and b.course_title ~* 'exit award' then jsonb_build_object('action','reject','text','Exit award: students cannot enrol in it directly, so there is no course page to link.')
      when b.field_code='official_course_url' and b.course_title ~* '^(study abroad|research exchange|exchange)\M' then jsonb_build_object('action','reject','text','Study abroad or exchange programme: not a standalone course, so there is no course page to link.')
      when b.field_code='official_course_url' and b.course_title ~* '^(doctor|master) of philosophy' then jsonb_build_object('action','check','text','Research degree: use the provider''s page for this research degree, then approve.')
      when b.field_code<>'provider_current_tuition_validation' then jsonb_build_object('action','check','text','Check the page, then decide.')$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'Exit award: students cannot enrol')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'suggestion anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;
