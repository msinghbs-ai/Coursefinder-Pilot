-- F-AER.08 s1041: CA AER is gated off by the AU/NZ scheduled-country eligibility.
-- Platform Admin 24 Nov 2026 explicitly delegated CA source reading to S3-AER-ChatGPT.
-- Replace only security.entry_matrix_enabled_v1(uuid) with a narrow CA provider allowlist
-- in EXISTING entry.providers; no schedule country-wide CA activation.
-- Replaces: security.entry_matrix_enabled_v1(uuid), md5 guarded.
-- Retires: nothing; 0 UI, Consumer API, cron, or manual lock changes.
-- Rollback: restore original function and restore entry.providers JSON value from pre-change migration evidence.
do $s1041ca$
declare
  v_sig constant text := 'security.entry_matrix_enabled_v1(uuid)';
  v_old_md5 constant text := '582a5024ffeca0ac3c5446a903b39b3f';
  v_def text := pg_get_functiondef('security.entry_matrix_enabled_v1(uuid)'::regprocedure);
  v_old text; v_new text;
begin
  if md5(v_def) <> v_old_md5 then
    raise exception 's1041 CA gate md5 changed (%): rebase, do not replace', md5(v_def);
  end if;
  v_old := $old$
                    and coalesce(security.toolset_setting('pipeline', 'entry.countries'), '["AU","NZ"]'::jsonb) ? k.iso_alpha2::text)$old$;
  v_new := $new$
                    and (coalesce(security.toolset_setting('pipeline', 'entry.countries'), '["AU","NZ"]'::jsonb) ? k.iso_alpha2::text
                      or (k.iso_alpha2 = 'CA'
                          and coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text
                          and exists (select 1 from pipeline.entry_matrix_sources src where src.provider_id = p_provider)))$new$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 's1041 CA gate country anchor absent or duplicated';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old2$
     and (case when security.aer_schedule_active_v1()$old2$;
  v_new := $new2$
     and ((exists (select 1 from catalogue.providers ca join ref.countries ck on ck.id = ca.country_id
                     where ca.id = p_provider and ck.iso_alpha2 = 'CA')
           and coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text
           and exists (select 1 from pipeline.entry_matrix_sources src where src.provider_id = p_provider))
          or (case when security.aer_schedule_active_v1()$new2$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 's1041 CA gate schedule anchor absent or duplicated';
  end if;
  v_def := replace(v_def,v_old,v_new);
  v_old := $old3$or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text end)
$old3$;
  v_new := $new3$or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text end))
$new3$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 's1041 CA gate closing anchor absent or duplicated';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end $s1041ca$;

-- Only the four Canadian providers whose official academic source pages were verified;
-- the pre-existing AU/NZ provider list is retained unchanged.
update pipeline.platform_toolset_settings s set
  value = (select to_jsonb(array(select distinct val from (
     select jsonb_array_elements_text(s.value) val
     union all
     select unnest(array[
       'db436563-4650-4820-bd76-0695afcc953d',
       '7b35d38d-08da-4aec-9110-c60e29dc0b45',
       '98e591df-d272-481e-9054-2b85a66261be',
       'd47b6006-396a-4785-b2ae-15186c3e7709'
     ]::text[])
     ) x order by val))),
  reason = 's1041 NZ/CA AER delegated lane (24 Nov 2026): four verified Canadian academic entry providers; CA scheduled country stays OFF; no blanket CA eligibility'
where s.toolset_key = 'pipeline' and s.key = 'entry.providers' and jsonb_typeof(s.value)='array';

do $post$
declare v_missing int;
begin
 select count(*) into v_missing from (values
 ('db436563-4650-4820-bd76-0695afcc953d'::uuid),
 ('7b35d38d-08da-4aec-9110-c60e29dc0b45'::uuid),
 ('98e591df-d272-481e-9054-2b85a66261be'::uuid),
 ('d47b6006-396a-4785-b2ae-15186c3e7709'::uuid)) ids(id)
 where not security.entry_matrix_enabled_v1(ids.id);
 if v_missing <> 0 then raise exception 's1041: % CA provider(s) still disabled',v_missing; end if;
 if (security.aer_schedule_country_v1('CA')->>'on')::boolean then
   raise exception 's1041: CA was globally enabled (not permitted)';
 end if;
end $post$;
