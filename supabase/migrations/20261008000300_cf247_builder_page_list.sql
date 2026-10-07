-- CF-247, 8 Oct 2026: the builder's read lists the provider's stored course pages (up to 600) so a Platform Admin can pick any of them as a
-- sample in the Guided build, including for a university with no adapter yet.
do $p$
declare d text;
begin
  d := pg_get_functiondef('public.admin_adapter_builder(text,jsonb)'::regprocedure);
  if md5(d) <> '28b6ed40ba81390859ca0eb16de66c11' then raise exception 'admin_adapter_builder is not the version this migration expects'; end if;
  if strpos(d, $a$      'max_samples', 10,$a$) = 0 then raise exception 'anchor not found'; end if;
  d := replace(d, $a$      'max_samples', 10,$a$, $b$      'max_samples', 10,
      'pages', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('course', x.title, 'code', x.code, 'url', x.url, 'read', x.read_status = 'read') order by x.title) from (
                 select distinct on (pg.url) coalesce(c.display_title, c.canonical_title) title, pg.url, pg.read_status,
                        (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code
                   from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
                  where pg.provider_id = v_pid and pg.url is not null limit 600) x), '[]'::jsonb) else '[]'::jsonb end,$b$);
  execute d;
end $p$;
