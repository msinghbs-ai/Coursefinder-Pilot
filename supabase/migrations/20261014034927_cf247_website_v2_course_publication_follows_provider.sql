-- CF-247 (14 Oct 2026) Website API v2: a course's publication_status follows its provider's Published switch.
-- Platform Admin (14 Oct): the provider Published switch is the control for the consumer API. Switched off, the provider and
-- its courses are not returned to API queries (already in effect through security.provider_hidden_v1). Courses have no switch
-- of their own, so the API reported every course as unpublished. It now reports published for a course whose provider is
-- published and active, else unpublished. Additive in meaning only, the field name and values are unchanged.
-- md5-checked before. nothing is dropped or deleted.
do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('api.website_v2_course_item(uuid,text[],text[])'::regprocedure);
  if md5(v) <> '600bc47a31ae175894c62421a1673fba' then raise exception 'website_v2_course_item changed since the check'; end if;
  n := replace(v, $o$'publication_status', d.publication_status,$o$,
                  $o$'publication_status', case when d.provider_id in (select h.provider_id from security.provider_hidden_v1 h where h.provider_id is not null) then 'unpublished' else 'published' end,$o$);
  if n = v then raise exception 'course_item anchor not found'; end if;
  execute n;
end $d$
