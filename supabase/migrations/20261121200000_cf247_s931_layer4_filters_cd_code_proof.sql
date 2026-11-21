-- CF-247 s931 (session S1-Impl-Layer4-Human-UI-Guide; Decision 279, Platform Admin 21 Nov 2026 10:53; fixes 12:28 AEDT): the server part of the Layer 4
-- human review UI release (v2.16.76). Spec: admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md (D3, §4.2).
--
-- What changes (each live on deploy):
--   (D3) read-only Layer 4 filter arguments: security.layer4_rule_groups_v1 takes source_country and country (provider_id was already read);
--        public.admin_layer4_grid_read_v1 takes source_country. Both md5-guarded. New read security.layer4_item_source_country_v1: whether a waiting
--        entry-requirements item carries a row for a source country (the student's country of prior education).
--   (fix 1) public.admin_layer4_cd_provider_verified_v1: the exact count "Approve all verified for provider" admits, read before the person confirms.
--        Found live: the box was typed with the queue's count while decide checks the provider's verified count ("Type 2 in the box").
--   (fix 3) security.course_description_machine_check_v1 (md5-guarded): a description read from a page that the course's own CRICOS or NZQA code proves
--        is not held as "Page match not clear enough" because the page was first found by an AI match or shares its address; every later check
--        (page kind, evidence, quotes, 1 to 2 sentences, words, duplicates, manual locks and holds) still applies. The waiting ones are admitted now through
--        the same machine admission. Rolled-back dry run: 19 waiting with a code proof; 12 admitted, 3 held (newer page copy), 4 held (refused word).
-- G1: no new job. G2: no new value. G3 stays 75/48 (admin functions only). Locks and active cron compared before and after. Spend: none ($0 AI, $0 Firecrawl).
-- Parity: head 20261121190000 read 21 Nov 2026 13:20 AEDT; no open migration; this file is numbered strictly above it.
-- Replaces: the cut Layer 4 filter arguments and the identity-margin rule of the course description machine check (for code-proved pages).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the post-check reads the consumer API check and the immediate admission runs the machine check per item

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s931_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s931_cron on commit drop as select count(*) n from cron.job where active;

-- (D3, Decision 279) read-only Layer 4 filter arguments: provider_id (already read), source_country and country on rule_groups; source_country on the grid
create or replace function pg_temp.edit_re(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    select count(*) into v_c from regexp_matches(v_def, p_edits[i][1], 'g');
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2], 'g');
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

-- the one read both lists use: does a waiting item carry a row for this source country (the student's country of prior education)?
create or replace function security.layer4_item_source_country_v1(p_kind text, p_ref text, p_country text) returns boolean
language sql stable security definer set search_path to '' as $f$
  select p_kind = 'aer_review' and p_ref ~ '^[0-9a-f-]{36}$' and (
           exists (select 1 from pipeline.entry_matrix_runs er join catalogue.provider_entry_matrix m on m.run_id = er.id
                    where er.review_item_id = p_ref::uuid and m.country_code = upper(p_country))
        or exists (select 1 from catalogue.course_entry_requirements x join ref.countries k on k.id = x.country_id
                    where x.provenance->>'review_item_id' = p_ref and k.iso_alpha2::text = upper(p_country)))
$f$;
revoke all on function security.layer4_item_source_country_v1(text, text, text) from public, anon, authenticated;
comment on function security.layer4_item_source_country_v1(text, text, text) is 'CF-247 s931 (Decision 279 D3): whether a waiting Layer 4 entry-requirements item carries a row for a source country (the student''s country of prior education). Read only; used by the Source country filter of Layer 4 Review (rule_groups and the grid).';

select pg_temp.edit_re('security.layer4_rule_groups_v1(text,jsonb,jsonb,integer)', 'bc44180df893137e80ff98dc109b972c', 'e0f40bd31849b05555071bf416f79565', array[
  array[$o$v_prov\s+uuid\s+:=\s+nullif\(p_args->>'provider_id',\s+''\)::uuid;$o$,
        $n$v_prov uuid := nullif(p_args->>'provider_id', '')::uuid; v_src text := nullif(upper(btrim(p_args->>'source_country')), ''); v_cty text := nullif(upper(btrim(p_args->>'country')), '');$n$],
  array[$o$from\s+security\.layer4_inbox_items_v2\(v_prov,\s+v_kind,\s+null,\s+v_kind\s+=\s+'provider_description'\)\s+r\),$o$,
        $n$from security.layer4_inbox_items_v2(v_prov, v_kind, null, v_kind = 'provider_description') r
          where (v_cty is null or exists (select 1 from catalogue.providers p9 join ref.countries k9 on k9.id = p9.country_id where p9.id = r.provider_id and k9.iso_alpha2::text = v_cty))
            and (v_src is null or security.layer4_item_source_country_v1(v_kind, r.ref, v_src))),$n$],
  array[$o$select\s+jsonb_build_object\('kind',\s+v_kind,\s+'built_in',\s+true,\s+'provider_id',\s+v_prov,\s+'total',$o$,
        $n$select jsonb_build_object('kind', v_kind, 'built_in', true, 'provider_id', v_prov, 'source_country', v_src, 'country', v_cty, 'total',$n$]
], array[1, 1, 1]);

select pg_temp.edit_re('public.admin_layer4_grid_read_v1(jsonb)', '44854a2ab12b21593c2891d7069daf29', 'c880b723a057b5abe9fe0b2fc07ff9bb', array[
  array[$o$v_prov\s+uuid\s+:=\s+nullif\(a->>'provider_id',\s+''\)::uuid;$o$,
        $n$v_prov uuid := nullif(a->>'provider_id', '')::uuid; v_src text := nullif(upper(btrim(a->>'source_country')), '');$n$],
  array[$o$if\s+v_pt\s+is\s+not\s+null\s+and\s+v_pt\s+<>\s+all$o$,
        $n$if v_src is not null and not exists (select 1 from ref.countries c where c.iso_alpha2::text = v_src) then raise exception 'source_country must be a country code such as IN or NP' using errcode = '22023'; end if;
  if v_pt is not null and v_pt <> all$n$],
  array[$o$where\s+v_why\s+is\s+null\s+or\s+i\.why\s+ilike\s+'%'\s+\|\|\s+v_why\s+\|\|\s+'%'\),$o$,
        $n$where (v_why is null or i.why ilike '%' || v_why || '%') and (v_src is null or security.layer4_item_source_country_v1(v_kind, i.ref, v_src))),$n$]
], array[1, 1, 1]);

-- (s931 fix 3, Platform Admin 21 Nov 2026 12:28) a course description read from a page that the course's own CRICOS or NZQA code proves is not held as
-- "Page match not clear enough" because the page was first found by an AI match or another course is bound to the same address: the code on the page is the
-- proof. Every later check (page kind, evidence, quotes, 1 to 2 sentences, words, duplicates, manual locks and holds) still applies.
select pg_temp.edit_re('security.course_description_machine_check_v1(uuid)', 'c09a0345410bd82bde15502814800b11', 'de1d932aaa90c1d5243ea4cc4473a046', array[
  array[$o$  if not v_proof and \(g\.basis = 'ai_match'$o$,
        $n$  v_proof := v_proof or coalesce(g.identity_basis in ('cricos_code', 'nzqa_code'), false);  -- s931: the course's own CRICOS or NZQA code on its page proves it
  if not v_proof and (g.basis = 'ai_match'$n$]
], array[1]);

-- (s931 fix 1) the exact count "Approve all verified for provider" admits, read before the person confirms (the decide action counts the same way)
create or replace function public.admin_layer4_cd_provider_verified_v1(p_ref uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_pid uuid; v_name text; v_n int;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select c.provider_id, coalesce(p.display_name, p.canonical_name) into v_pid, v_name
    from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id join catalogue.providers p on p.id = c.provider_id
   where q.id = p_ref and q.entity_type = 'course' and q.field_code = 'course_description_first_read';
  if v_pid is null then return jsonb_build_object('eligible', 0, 'provider_id', null); end if;
  select count(*) into v_n
    from pipeline.layer4_review_items q
    join catalogue.courses cq on cq.id = q.entity_id and cq.provider_id = v_pid and cq.lifecycle_status = 'active' and nullif(btrim(cq.description), '') is null
    join pipeline.coverage_course_pages gq on gq.course_id = cq.id and gq.status = 'bound' and gq.provider_id = cq.provider_id and gq.evidence_id is not distinct from q.evidence_id
    join pipeline.field_enrich_items fq on fq.id::text = q.proposed_value->>'item_id' and fq.course_id = cq.id and fq.field = 'description' and fq.state = 'review'
   where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
     and q.proposed_value->>'source_url' is not distinct from gq.url
     and gq.identity_basis in ('cricos_code', 'nzqa_code', 'exact_title')
     and not exists (select 1 from pipeline.manual_locks lq where lq.entity = 'course' and lq.entity_id = cq.id and lq.field in ('description', 'course_description', 'all'))
     and coalesce((security.course_description_check_v1(cq.id, fq.value)->>'ok')::boolean, false);
  return jsonb_build_object('eligible', v_n, 'provider_id', v_pid, 'provider', v_name);
end $f$;
revoke all on function public.admin_layer4_cd_provider_verified_v1(uuid) from public, anon;
grant execute on function public.admin_layer4_cd_provider_verified_v1(uuid) to authenticated;
comment on function public.admin_layer4_cd_provider_verified_v1(uuid) is 'CF-247 s931 (Platform Admin 21 Nov 2026 12:28): how many waiting course descriptions of the provider of one Layer 4 item pass the quote check on the course''s own page: the count "Approve all verified for provider" admits (public.admin_layer4_inbox decide approve_provider counts the same way and asks for it). Read only; not part of the consumer API.';

-- (s931 fix 3, immediate) the waiting course descriptions the code proves are admitted now through the same machine admission (each check still applies)
create temp table s931_cd on commit drop as
select q.id, security.course_description_machine_admit_v1(q.id, 'settle') r
  from pipeline.layer4_review_items q
  join pipeline.coverage_course_pages g on g.course_id = q.entity_id and g.status = 'bound'
 where q.status = 'pending' and q.field_code = 'course_description_first_read' and q.entity_type = 'course' and g.identity_basis in ('cricos_code', 'nzqa_code');

do $c$
declare v_api jsonb; v_admin uuid; r jsonb; v_ok int; v_all int;
begin
  select count(*) filter (where coalesce((x.r->>'ok')::boolean, false)), count(*) into v_ok, v_all from s931_cd x;
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  r := public.admin_layer4_inbox('rule_groups', '{"kind":"aer_review","source_country":"IN"}');
  if (r->>'source_country') is distinct from 'IN' then raise exception 'post-check: rule_groups did not take source_country'; end if;
  r := public.admin_layer4_grid_read_v1('{"kind":"aer_review","source_country":"IN"}');
  if r->'total' is null then raise exception 'post-check: the grid did not answer with source_country'; end if;
  perform set_config('request.jwt.claims', '', true);
  if (select count(*) from cron.job where active) <> (select n from s931_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s931_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's931: course descriptions proved by their code admitted now: % of %', v_ok, v_all;
end $c$;
