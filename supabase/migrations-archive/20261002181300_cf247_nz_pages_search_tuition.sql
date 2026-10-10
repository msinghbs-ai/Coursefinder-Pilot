-- CF-247 (Decision 217, 2 Oct 2026). Platform Admin, 09:21: "Nz is not running any jobs? Data Admissions is almost null?"
-- and, by multiple choice: NZ identity "title + same level" (and a labelled NZQA number); course-page search for all NZ
-- courses now; NZ tuition built and admitted like Australia (in NZD). Also: fee schedules show the country they belong to.
--  1. The page reader is told each course's country (NZ fees are read in NZD).
--  2. NZ admission rule: pages proven by "title_level" or "nzqa_code" are admitted for links, English and intakes;
--     tuition, like Australia, only from a page that prints the course's code (programme code or NZQA number).
--  3. The tuition hand-off to the qualified Layer 3 model follows each country's rule and currency (was Australia only).
--  4. Course-page search by title drops the NZQA "(Level N)" suffix; every NZ provider with a website gets the generic
--     recipe (any page on its own site, used only when the reader proves the page is the course's).
-- Every function patch is behind an md5 guard on its current source.

do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('public','svc_coverage_read_next','e8fce44b38f378aa79a88b05b5b6a6cb',
      array[$o$'title',c.canonical_title,'code',c.course_code,'status',u.status$o$],
      array[$n$'title',c.canonical_title,'code',c.course_code,'country',security.coverage_country(u.provider_id),'status',u.status$n$]),
    ('public','svc_coverage_tuition_handoff_next','2ec830f93d4dbd42193df2f1da1a3be6',
      array[$o$join ref.countries k on k.id=pr.country_id and k.iso_alpha2='AU'$o$,
            $o$p.identity_basis='cricos_code' and p.l3_work_item_id is null$o$],
      array[$n$join pipeline.coverage_admission_countries ca on ca.country_id=pr.country_id and ca.active$n$,
            $n$security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'tuition') and p.l3_work_item_id is null$n$]),
    ('public','svc_coverage_tuition_handoff_record','4bba0336ee8c63c54398d502f40b5c8f',
      array[$o$declare pg record;$o$,
            $o$if pg.course_id is null or pg.identity_basis is distinct from 'cricos_code' then return jsonb_build_object('queued',false,'reason','not a CRICOS-code page'); end if;$o$,
            $o$if v_target is null then return jsonb_build_object('queued',false,'reason','no single international fee candidate'); end if;$o$,
            $o$'currency_code','AUD',$o$,
            $o$'identity_basis','cricos_code'$o$],
      array[$n$declare v_cur text; pg record;$n$,
            $n$if pg.course_id is null or not security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, 'tuition') then return jsonb_build_object('queued',false,'reason','page identity not admitted for tuition'); end if;
  select a.currency_code into v_cur from catalogue.providers pv join pipeline.coverage_admission_countries a on a.country_id=pv.country_id and a.active where pv.id=pg.provider_id;
  if v_cur is null then return jsonb_build_object('queued',false,'reason','no admission rule for the course''s country'); end if;$n$,
            $n$if v_target is null then return jsonb_build_object('queued',false,'reason','no single international fee candidate'); end if;
  v_target:=v_target||jsonb_build_object('currency_code',v_cur);$n$,
            $n$'currency_code',v_cur,$n$,
            $n$'identity_basis',pg.identity_basis$n$]),
    ('public','svc_course_link_search_next','3ba55afcac79599090d3fbe6bde13eee',
      array[$o$else '"' || replace(p.canonical_title, '"', '') || '" site:' || p.search_domain end$o$],
      array[$n$else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end$n$]),
    ('public','admin_provider_fee_schedules_read','b7c9abd5921dcd27b0d97d751ad21386',
      array[$o$'provider', coalesce(p.display_name, p.canonical_name), 'url', f.url,$o$],
      array[$n$'provider', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(f.provider_id), 'url', f.url,$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;

-- 2. NZ admission rule (Decision 202 extended by Decision 217)
update pipeline.coverage_admission_countries a
   set identities = jsonb_build_object(
         'official_url', '["cricos_code","nzqa_code","exact_title","title_level"]'::jsonb,
         'english',      '["cricos_code","nzqa_code","exact_title","title_level"]'::jsonb,
         'intakes',      '["cricos_code","nzqa_code","exact_title","title_level"]'::jsonb,
         'tuition',      '["cricos_code","nzqa_code"]'::jsonb),
       approved_ref = 'Decision 202 (NZ programme code or exact title, NZD only; Platform Admin 1 Oct 2026 16:54 AEST); Decision 217 (NZQA title with the same level, labelled NZQA number; tuition in NZD from a page that prints the course''s code, like Australia; Platform Admin 2 Oct 2026)',
       updated_at = now()
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'NZ';

-- 4. generic course-page recipe for every NZ provider with a website and no recipe
insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
select x.id, x.dom,
       jsonb_build_array(jsonb_build_object(
         're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(x.dom, '\.', '\\.', 'g')
               || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
         'rep', '\&')),
       true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (NZ, Decision 217, 2 Oct 2026)', now()
  from (select p.id, lower(regexp_replace(substring(btrim(p.website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) dom
          from catalogue.providers p join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'NZ'
         where coalesce(btrim(p.website), '') <> '') x
 where x.dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
   and x.dom !~ '(^|\.)(facebook|linkedin|instagram|google|wixsite|weebly|squarespace|wordpress|blogspot)\.'
   and not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = x.id);
