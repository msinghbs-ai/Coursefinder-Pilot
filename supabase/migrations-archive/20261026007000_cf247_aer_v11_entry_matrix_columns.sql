-- CF-247 AER v1.1 schema (Platform Admin 26 Oct 2026 21:39, 21:45, 21:50: "Schema approved"): six additive columns, three indexes and the
-- row-identity fill on catalogue.provider_entry_matrix (live, 0 rows, reader off). Record: admin docs/platform/aer-v1.1-build-log.md.
-- 1 Columns: routes jsonb, valid_to date, withdrawal_reason varchar(500), row_hash char(64), version integer default 1, aer_level varchar(20).
-- 2 Indexes: row_hash unique among active rows (partial; a changed page supersedes the old rows while the new ones arrive with the same
--   identity), status, and the lookup (provider_id, country_code, study_level_id, benchmark_band, status). Existing column names are kept.
-- 3 Row identity (approved 21:50): row_hash = lowercase hex SHA-256 of provider_id | course_id ('' when provider-wide) | country_code |
--   study_level_id ('' when none) | benchmark_band ('' when none) | the condition keys (board / era names from conditions, sorted, joined
--   with '|'). The row's own qualification_name counts as one of its condition keys: the live reader writes one row per qualification
--   (India: "CBSE (AISSC)" and "State Board HSC" as two rows), and without it two qualifications of one country and level would share an
--   identity and could not both be active (agent's note to the Platform Admin, 26 Oct 22:2x). Grade values are not part of the identity: an edit that keeps the identity bumps version (delta); a new board is a new
--   identity (seed). Filled by trigger provider_entry_matrix_identity on insert and on update.
-- Status mapping (decision 7, 21:39): quarantined = 'unverified' with provenance->>'aer_flag' = 'quarantined'; withdrawn = 'inactive' with
-- valid_to and withdrawal_reason. The status check is unchanged.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, renamed, deleted or updated. The consumer API is not touched (no consumer function reads this table yet).

alter table catalogue.provider_entry_matrix add column if not exists routes jsonb;
alter table catalogue.provider_entry_matrix add column if not exists valid_to date;
alter table catalogue.provider_entry_matrix add column if not exists withdrawal_reason varchar(500);
alter table catalogue.provider_entry_matrix add column if not exists row_hash char(64);
alter table catalogue.provider_entry_matrix add column if not exists version integer default 1;
alter table catalogue.provider_entry_matrix add column if not exists aer_level varchar(20);

create unique index if not exists provider_entry_matrix_row_hash_uq on catalogue.provider_entry_matrix (row_hash) where status = 'active';
create index if not exists provider_entry_matrix_status_ix on catalogue.provider_entry_matrix (status);
create index if not exists provider_entry_matrix_lookup_ix on catalogue.provider_entry_matrix (provider_id, country_code, study_level_id, benchmark_band, status);

create or replace function security.entry_matrix_row_hash_v1(p_provider uuid, p_course uuid, p_country text, p_level uuid, p_band text, p_qualification text, p_conditions jsonb)
returns char(64) language sql immutable set search_path = '' as $f$
  select encode(sha256(convert_to(
    p_provider::text || '|' || coalesce(p_course::text, '') || '|' || coalesce(upper(p_country), '') || '|' || coalesce(p_level::text, '') || '|' ||
    coalesce(p_band, '') || '|' ||
    coalesce((select string_agg(k, '|' order by k)
                from (select distinct lower(btrim(coalesce(e->>'board', e->>'era', e->>'key'))) k
                        from jsonb_array_elements(case when jsonb_typeof(p_conditions) = 'array' then p_conditions else '[]'::jsonb end) e
                       where jsonb_typeof(e) = 'object' and nullif(btrim(coalesce(e->>'board', e->>'era', e->>'key')), '') is not null
                      union
                      select lower(btrim(p_qualification)) where nullif(btrim(p_qualification), '') is not null) z), ''),
    'UTF8')), 'hex')::char(64)
$f$;
comment on function security.entry_matrix_row_hash_v1(uuid, uuid, text, uuid, text, text, jsonb) is 'CF-247 AER v1.1 (Platform Admin 26 Oct 2026 21:50): stable row identity of an entry-matrix row: provider, course, country, level, band and the sorted condition keys (board / era names and the row''s qualification), not their grade values';

create or replace function security.entry_matrix_identity_tg()
returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  new.row_hash := security.entry_matrix_row_hash_v1(new.provider_id, new.course_id, new.country_code, new.study_level_id, new.benchmark_band, new.qualification_name, new.conditions);
  if tg_op = 'INSERT' then
    new.version := coalesce(new.version, 1);
  elsif new.row_hash is not distinct from old.row_hash
        and (new.min_grade, new.min_value, new.grade_scale, new.conditions, new.routes, new.qualification_name, new.quote, new.edition)
            is distinct from (old.min_grade, old.min_value, old.grade_scale, old.conditions, old.routes, old.qualification_name, old.quote, old.edition) then
    new.version := coalesce(old.version, 1) + 1;  -- same identity, changed content: a delta
  end if;
  return new;
end $f$;
comment on function security.entry_matrix_identity_tg() is 'CF-247 AER v1.1: fills row_hash on every insert and update of catalogue.provider_entry_matrix; a content change under the same identity bumps version';
revoke all on function security.entry_matrix_identity_tg() from public, anon, authenticated;

create trigger provider_entry_matrix_identity before insert or update on catalogue.provider_entry_matrix
  for each row execute function security.entry_matrix_identity_tg();

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.entry_matrix_row_hash_v1', 'Catalogue', 'AER v1.1: entry-matrix row identity (provider, course, country, level, band, condition keys)', 'active', '{}', '20261026007000'),
 ('function', 'security.entry_matrix_identity_tg', 'Catalogue', 'AER v1.1: fills row_hash and bumps version on catalogue.provider_entry_matrix', 'active', '{}', '20261026007000')
on conflict do nothing;
