-- CF-247, 7 Oct 2026 (Platform Admin: close the UWA rollback). The coverage sweep's fill-empty path accepted an adapter's English and intake readings whenever
-- the adapter was admitting any field, without checking which fields were admitted (UWA: 17 English rows written with only intakes admitted). The two checks
-- now also require the field to be in the adapter's admitted fields. Readings from the general reader (not the adapter) are unchanged.
do $p$
declare d text; o oid;
begin
  select p.oid into o from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'coverage_admission_plan_v1';
  d := pg_get_functiondef(o);
  if md5(d) <> 'eac14551e23f73985b32dd32d8c2efd7' then raise exception 'coverage_admission_plan_v1 is not the version this migration expects'; end if;
  if strpos(d, $a$(coalesce(pg.c->>'english_by','')<>'adapter' or exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit))$a$) = 0
     or strpos(d, $b$pg.c->>'intakes_by'='adapter' and exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit))$b$) = 0 then
    raise exception 'anchors not found'; end if;
  d := replace(d, $a$(coalesce(pg.c->>'english_by','')<>'adapter' or exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit))$a$,
                  $a$(coalesce(pg.c->>'english_by','')<>'adapter' or exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit and 'english' = any (u.admit_fields)))$a$);
  d := replace(d, $b$pg.c->>'intakes_by'='adapter' and exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit))$b$,
                  $b$pg.c->>'intakes_by'='adapter' and exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit and 'intakes' = any (u.admit_fields)))$b$);
  execute d;
end $p$;
