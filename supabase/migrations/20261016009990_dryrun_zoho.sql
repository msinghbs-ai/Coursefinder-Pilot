-- CF-247 (24 Oct 2026). Platform Admin 07:32: "make sure cricos is only applicable for au and no other country. Cricos code should not
-- be in any logic to admit data other than au. We have learnt yesterday data was not getting admitted because of its logic on nz fees
-- admission." (Item 8a's identity part, pulled forward; the per-country proof lists already live in
-- pipeline.coverage_admission_countries.identities, so no new table.)
-- Found: the worker labelled any page that printed the course's own code "cricos_code" whatever the country (identity-v0.5.12), so 286
-- NZ and 63 CA bound pages carry an Australian proof label and 57 CA pages a New Zealand one; the CA tuition list accepted cricos_code; the
-- NZ English and intake lists accepted it (item 10, 23 Oct); svc_coverage_read_record auto-bound an ambiguous page on a cricos_code label
-- in any country; coverage_bind_v2 labelled a code match cricos_code in any country. 147 NZ and 2 CA fees were admitted on those labels
-- and were quarantined at 00:35 (identity_basis_reverify).
-- 1 security.coverage_identity_allowed: a cricos_code proof is accepted only for an Australian provider, whatever any list says (CRICOS is
--   the Australian register; this is a fact about the register, not a tunable). -- fixed: the register is Australian
-- 2 The proof lists: cricos_code removed from every non-Australian country's lists (CA tuition; NZ english, intakes).
-- 3 svc_coverage_read_record: the ambiguous-page auto-bind on a cricos_code label now asks the policy (Australian pages only).
-- 4 coverage_bind_v2: a code match is labelled by country (AU cricos_code, NZ nzqa_code, otherwise adapter_code), never cricos_code elsewhere.
-- 5 Re-verification (the 8a query): the 406 non-Australian bound pages with an Australian or wrong-country proof label go back to
--   mismatch / identity_mismatch (count-guarded), which removes them from admission at once and hands them to the reidentify lane, which
--   re-verifies each stored copy once under identity-v0.6.0 (worker v0.45.0, deployed with this release) and re-binds only with the
--   country's own proof. The 149 quarantined courses get a fee request and a first-in-line read so their fee re-admits through the normal
--   path once the page is re-bound. Manual bindings are never touched.
-- Replaces: nothing (coverage_identity_allowed, svc_coverage_read_record, coverage_bind_v2 edited in place, md5-guarded)
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

-- 1 the policy function: CRICOS proofs are Australian
select pg_temp.edit_once('security.coverage_identity_allowed(uuid,text,text)', '9509a4103b6257e30310e48effe04c52', array[
  array[$o$select case when p_basis in ('adapter_code', 'adapter_title')$o$,
        $n$select case when p_basis in ('cricos_code', 'cricos_code_on_page', 'cricos_search') and not exists (select 1 from catalogue.providers p0 join ref.countries k0 on k0.id = p0.country_id where p0.id = p_provider_id and k0.iso_alpha2 = 'AU') then false -- 24 Oct 2026: a CRICOS proof exists only in Australia -- fixed: the register is Australian
            when p_basis in ('adapter_code', 'adapter_title')$n$]]);

-- 2 the lists: no cricos_code outside Australia
update pipeline.coverage_admission_countries a
   set identities = (select coalesce(jsonb_object_agg(e.key, (select coalesce(jsonb_agg(b order by b), '[]'::jsonb) from jsonb_array_elements_text(e.value) b where b <> 'cricos_code')), '{}'::jsonb) from jsonb_each(a.identities) e)
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 <> 'AU' and a.identities::text like '%cricos_code%';
do $g$ declare v int; begin
  select count(*) into v from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id where k.iso_alpha2 <> 'AU' and a.identities::text like '%cricos_code%';
  if v > 0 then raise exception '% non-Australian proof lists still name cricos_code', v; end if;
end $g$;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('pipeline', 'identity_lists', 'coverage_admission_countries.identities',
        jsonb_build_object('removed', 'cricos_code from every non-AU list (CA tuition; NZ english, intakes)', 'reason', 'Platform Admin 24 Oct 2026 07:32: CRICOS is Australian only (migration 20261024002000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

-- 3 the read record: an ambiguous page auto-binds on a CRICOS label only where the policy allows it
select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', '8f84bea190b10b532399943a38695e20', array[
  array[$o$when status='ambiguous' and p_identity_basis='cricos_code' then 'bound' else status end,$o$,
        $n$when status='ambiguous' and p_identity_basis='cricos_code' and security.coverage_identity_allowed(provider_id, 'cricos_code', 'official_url') then 'bound' else status end,$n$],
  array[$o$basis=case when status='ambiguous' and p_identity_basis='cricos_code' then 'cricos_code_on_page' else basis end$o$,
        $n$basis=case when status='ambiguous' and p_identity_basis='cricos_code' and security.coverage_identity_allowed(provider_id, 'cricos_code', 'official_url') then 'cricos_code_on_page' else basis end$n$]]);

-- 4 the binder: a code match is labelled by country
select pg_temp.edit_once('security.coverage_bind_v2(uuid)', '847f5fb963493f637a056fed74366843', array[
  array[$o$case when by_code then 'cricos_code' else 'title_match' end, case when mutual then 'bound' else 'ambiguous' end$o$,
        $n$case when by_code then (case security.coverage_country(p_provider_id) when 'AU' then 'cricos_code' when 'NZ' then 'nzqa_code' else 'adapter_code' end) else 'title_match' end, case when mutual then 'bound' else 'ambiguous' end$n$]]);

-- 5 re-verification of the mislabelled bindings (count-guarded)
create temp table _wrong on commit drop as
select p.course_id, p.provider_id, k.iso_alpha2 cc, p.identity_basis
  from pipeline.coverage_course_pages p
  join catalogue.providers pr on pr.id = p.provider_id
  join ref.countries k on k.id = pr.country_id
 where p.status = 'bound' and coalesce(p.basis, '') <> 'manual' and k.iso_alpha2 <> 'AU'
   and (p.identity_basis = 'cricos_code' or (k.iso_alpha2 <> 'NZ' and p.identity_basis = 'nzqa_code'));
do $g$ declare v int; begin
  select count(*) into v from _wrong;
  if v <> 406 then raise exception 'expected 406 mislabelled non-Australian bindings, found %', v; end if;
end $g$;
update pipeline.coverage_course_pages p
   set status = 'mismatch', read_status = 'identity_mismatch', leased_until = null, next_read_at = now(), read_attempts = 0
  from _wrong w where p.course_id = w.course_id;
-- the quarantined fees re-admit through the normal path once the page is re-bound and read again
insert into pipeline.fee_course_requests(course_id, requested_at, requested_by, reason)
select l.entity_id, now(), '63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'identity re-verification 24 Oct 2026: fee quarantined at 00:35 re-admits once the page is re-bound under identity-v0.6.0'
  from pipeline.layer4_review_items l
 where l.layer2_state->>'source' = 'identity_basis_reverify' and l.status = 'pending'
on conflict (course_id) do update set requested_at = excluded.requested_at, requested_by = excluded.requested_by, reason = excluded.reason, queued_at = null, outcome = null;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('pipeline', 'identity_reverify', 'coverage_course_pages',
        jsonb_build_object('pages', (select count(*) from _wrong), 'by', (select jsonb_object_agg(cc || ':' || identity_basis, n) from (select cc, identity_basis, count(*) n from _wrong group by 1, 2) z),
                           'fee_requests', (select count(*) from pipeline.layer4_review_items l where l.layer2_state->>'source' = 'identity_basis_reverify' and l.status = 'pending'),
                           'reason', 'Platform Admin 24 Oct 2026 07:32: CRICOS is Australian only; re-verify under identity-v0.6.0 (migration 20261024002000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

do $t$ declare nz uuid; au uuid; ca uuid; begin
  select p.id into nz from catalogue.providers p join ref.countries k on k.id=p.country_id where k.iso_alpha2='NZ' and p.canonical_name='University of Auckland';
  select p.id into au from catalogue.providers p join ref.countries k on k.id=p.country_id where k.iso_alpha2='AU' limit 1;
  select p.id into ca from catalogue.providers p join ref.countries k on k.id=p.country_id where k.iso_alpha2='CA' and p.canonical_name='College of the North Atlantic';
  raise exception 'DRYRUN OK %', jsonb_build_object(
    'nz_cricos_english', security.coverage_identity_allowed(nz,'cricos_code','english'), 'nz_nzqa_tuition', security.coverage_identity_allowed(nz,'nzqa_code','tuition'),
    'au_cricos_english', security.coverage_identity_allowed(au,'cricos_code','english'), 'ca_cricos_tuition', security.coverage_identity_allowed(ca,'cricos_code','tuition'), 'ca_adapter_code_official', security.coverage_identity_allowed(ca,'adapter_code','official_url'),
    'lists', (select jsonb_object_agg(k.iso_alpha2, a.identities->'tuition') from pipeline.coverage_admission_countries a join ref.countries k on k.id=a.country_id),
    'now_mismatch', (select count(*) from pipeline.coverage_course_pages p join catalogue.providers pr on pr.id=p.provider_id join ref.countries k on k.id=pr.country_id where k.iso_alpha2<>'AU' and p.status='mismatch' and p.read_status='identity_mismatch' and p.next_read_at>now()-interval '1 minute'),
    'reidentify_would_pick', (select count(*) from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id=p.evidence_id where p.status='mismatch' and p.read_status='identity_mismatch' and e.storage_path is not null and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id=p.course_id and d.evidence_id=p.evidence_id and d.rule='identity-v0.6.0')),
    'fee_requests', (select count(*) from pipeline.fee_course_requests where reason like 'identity re-verification%'),
    'bind_v2_ok', pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure) like '%when ''NZ'' then ''nzqa_code''%',
    'read_record_ok', pg_get_functiondef('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure) like '%coverage_identity_allowed(provider_id, ''cricos_code'', ''official_url'')%'); end $t$;
