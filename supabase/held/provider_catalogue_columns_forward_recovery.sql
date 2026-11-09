-- HELD, NOT A MIGRATION (do not move into supabase/migrations/ unless the Provider Catalogue columns change must be backed out).
-- CF-247 Provider Catalogue columns: forward recovery for migration 20261109200000.
-- It points providers_page back at security.admin_providers_page_v2 (which that migration leaves in place, marked retiring) by the same kind of exact,
-- md5-guarded text edit: the body md5 must still be the one 20261109200000 produced (109237d709578315e1acd9eefdb645cc) and the result must be the
-- body md5 the function had before it (7efb948272dc64abaac2bb141ccb50f6), or nothing is changed. It is a forward change, written as a new migration
-- if it is ever used; it drops and deletes nothing. The 32 'providers' rows of pipeline.admin_table_columns and the two v3 functions can stay (nothing
-- calls them); the screen then needs the previous build, because the new Columns control sends only filters and sorts v2 does not read.
-- Replaces: security.admin_providers_page_v3 as the providers_page implementation
-- Retires: security.admin_providers_page_v3 and security.provider_catalogue_facts_v1 (marked retiring; dropped later by a paste file, never by a migration)

create or replace function pg_temp.edit_one(p_sig text, p_before text, p_after text, p_old text, p_new text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int;
begin
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_one('security.admin_catalogue_page(text,jsonb)', '109237d709578315e1acd9eefdb645cc', '7efb948272dc64abaac2bb141ccb50f6',
$old$    -- CF-247 Provider Catalogue columns (directive 9 Nov 2026): the page, its new columns, filters and sorts (v2 is retiring)
    return security.admin_providers_page_v3(p_args);$old$,
$new$    return security.admin_providers_page_v2(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''),nullif(p_args->>'adapter',''));$new$);

update pipeline.component_register set status = 'active', replaced_by = null, retire_after = null
 where kind = 'function' and name like 'security.admin_providers_page_v2%' and status = 'retiring';
update pipeline.component_register set status = 'retiring', replaced_by = 'security.admin_providers_page_v2', retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int
 where kind = 'function' and name in ('security.admin_providers_page_v3', 'security.provider_catalogue_facts_v1') and status = 'active';
