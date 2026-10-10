-- CF-247 Phase 2 (8 Oct 2026, Platform Admin: "Do nzqa then prism and qilt"): NZQA becomes the second register adapter, for a register
-- published as web pages. The spec (pipeline.register_adapters, code nz_nzqa, switched off) says where the provider number, name and
-- website are on the provider's details page and how each current qualification is read from the qualifications table (row, link,
-- status rule, NZQF level, credits, study-level mapping). Layer 1 (layer1-nz-live) keeps running unchanged.
-- Side-by-side replay on the stored Layer 1 batch files of three complete runs (21 files each, 415 providers): the worker (v0.17.21,
-- register_html.ts) reads each file with the adapter spec and with a verbatim copy of layer1-nz-live v1.2.1, three files a call.
-- A replay run may now list several files (paths); svc_register_replay_next_v3 returns them with the adapter code.
alter table pipeline.register_replay_runs add column if not exists paths text[];

insert into pipeline.register_adapters(source_id, code, label, country_code, spec, notes)
values ('e410b159-614e-45ef-b8f4-902c7b516257', 'nz_nzqa', 'NZQA Education Organisations', 'NZ', '{"format": "html_pages", "provider": {"code": {"source": "detailsHtml", "text_regex": ["Education Organisation number\\s+([0-9]{3,8})", "provider number\\s+([0-9]{3,8})"]}, "name": {"source": "detailsHtml", "html_regex": ["<h1[^>]*>([\\s\\S]*?)<\\/h1>", "<title[^>]*>([\\s\\S]*?)<\\/title>"], "fallback_field": "listingName", "strip": ["^Organisations\\s*>>\\s*NZQA\\s*-\\s*", "^Organisations\\s*>>\\s*"]}, "website": {"source": "detailsHtml", "html_regex": ["Website[\\s\\S]{0,400}?href=[\"'']([^\"'']+)[\"'']"], "https_prefix": true}, "copy": {"city": "city", "provider_type": "type"}}, "records": {"source": "qualsHtml", "row": "<tr[^>]*>([\\s\\S]*?)<\\/tr>", "link": "viewQualification\\.do\\?selectedItemKey=([^&\"'']+)[^>]*>([\\s\\S]*?)<\\/a>", "require": "(^|\\s)Current(\\s|$)", "status_value": "Current", "level_from_title": "\\(Level\\s+([1-9]|10)\\)", "credits_cell": {"regex": "^[0-9]{2,4}$", "min": 20, "max": 1000}, "level_map": [["doctor|phd", "doctorate"], ["master", "masters"], ["graduate certificate", "graduate_certificate"], ["graduate diploma", "graduate_diploma"], ["bachelor", "bachelor"], ["associate", "associate_degree"], ["diploma", "diploma"], ["certificate", "certificate"], ["foundation", "foundation"]]}}'::jsonb,
        'Phase 2 register adapter for a register published as web pages. Not switched on: layer1-nz-live stays in charge until the side-by-side replay passes and a Platform Admin switches it.')
on conflict (source_id) do nothing;

create or replace function public.svc_register_replay_next_v3()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype; v_pos int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.register_replay_runs where done_at is null and error is null and not (reference_done and adapter_done) order by created_at limit 1;
  if r.id is null then return null; end if;
  v_pos := case when not r.reference_done then r.reference_pos else r.adapter_pos end;
  return jsonb_build_object('run_id', r.id, 'engine', case when not r.reference_done then 'reference' else 'adapter' end, 'pos', v_pos,
                            'storage_path', r.storage_path, 'paths', to_jsonb(r.paths), 'zip_hash', r.zip_hash, 'keep_fields', r.keep_fields,
                            'code', (select a.code from pipeline.register_adapters a where a.source_id = r.source_id),
                            'spec', (select a.spec from pipeline.register_adapters a where a.source_id = r.source_id));
end $f$;
revoke all on function public.svc_register_replay_next_v3() from public, anon, authenticated;
grant execute on function public.svc_register_replay_next_v3() to service_role;

insert into pipeline.register_replay_runs(source_id, label, storage_path, paths, keep_fields, created_at)
select 'e410b159-614e-45ef-b8f4-902c7b516257', x.label, 'regulatory/NZ/nzqa/', array(
         select e.storage_path from pipeline.evidence_artifacts e
          where e.source_id = 'e410b159-614e-45ef-b8f4-902c7b516257' and e.storage_path like 'regulatory/NZ/nzqa/' || x.stamp || '%-offset-%'
          order by substring(e.storage_path from 'offset-([0-9]+)-batch')::int),
       false, now() + make_interval(secs => x.n)
  from (values ('NZQA 6 Oct 2026 13:34', '2026-10-06T13-3', 0),
               ('NZQA 8 Oct 2026 01:35', '2026-10-08T01-3', 1),
               ('NZQA 8 Oct 2026 07:34 (newest)', '2026-10-08T07-3', 2)) x(label, stamp, n);
