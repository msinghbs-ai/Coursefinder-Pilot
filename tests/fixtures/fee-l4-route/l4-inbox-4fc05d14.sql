-- CF-247 IQ-00111 D12 fixture: the Layer 4 owner's edit of security.layer4_inbox_items_v1 (a56bc331 -> 4fc05d14), copied byte for byte from
-- origin/cf247-l4-course-link dccd27e0, supabase/migrations/20261104150000_cf247_l4_course_link.sql (lines 413-453), with its edit helper. The fee
-- re-check items render through this version; this change does not edit the inbox.
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;
select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'a56bc3313e02ac0611deb5657da95ce0', '4fc05d14f4ba49335ff90496a20f582d', array[
 array[$o$         coalesce(nullif(r.escalation_reason, ''), 'Needs a decision'), null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,$o$,
       $n$         -- mandate 3 Nov 2026 20:47 §5: a CRICOS code is named only for Australian providers
         case when coalesce(kc.iso_alpha2, 'AU') <> 'AU' and r.escalation_reason ilike '%CRICOS%'
              then replace(replace(r.escalation_reason, 'this course''s CRICOS code', 'this course''s code'), 'CRICOS code', 'course code')
              else coalesce(nullif(r.escalation_reason, ''), 'Needs a decision') end, null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,$n$],
 array[$o$    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
   where r.status = 'pending'$o$,
       $n$    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
    left join catalogue.providers pv on pv.id = coalesce(c.provider_id, s.provider_id)
    left join ref.countries kc on kc.id = pv.country_id
   where r.status = 'pending'$n$],
 array[$o$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key$o$,
       $n$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code,
                            -- mandate 3 Nov 2026 20:47 §5: the stored copy of the course's bound page, so a fee or course hold shows its evidence
                            'evidence_id', g.evidence_id, 'captured_at', gev.captured_at, 'source_url', gev.source_url)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
    left join pipeline.coverage_course_pages g on g.course_id = c.id
    left join pipeline.evidence_artifacts gev on gev.id = g.evidence_id$n$],
 array[$o$  union all
  -- counsellor reports from Zoho$o$,
       $n$  union all
  -- Decision 179 (Platform Admin 3 Nov 2026 20:29): courses that need a correct page, while open and still without an official page
  select 'course_page_needed', n.course_id::text, n.provider_id, coalesce(nullif(c.display_title, ''), c.canonical_title),
         'No page of this course has been verified. ' || n.refused || ' page' || case when n.refused = 1 then ' was' else 's were' end || ' found and refused, the last: '
           || coalesce(n.last_refused_reason, 'not proved to be this course''s page'),
         null, n.created_at,
         jsonb_build_object('course_id', c.id, 'course_code', c.course_code, 'code_label', case when coalesce(kc.iso_alpha2, 'AU') = 'AU' then 'CRICOS' else 'Course code' end,
                            'proposed', jsonb_build_object('course_url', n.last_refused_url), 'refused', n.refused, 'lane', n.last_refused_lane, 'converted_items', to_jsonb(n.converted_items),
                            'searches_requested', n.searches_requested, 'evidence_id', n.last_refused_evidence, 'captured_at', nev.captured_at, 'source_url', nev.source_url)
    from pipeline.course_page_needed n join catalogue.courses c on c.id = n.course_id
    left join catalogue.providers pv on pv.id = n.provider_id left join ref.countries kc on kc.id = pv.country_id
    left join pipeline.evidence_artifacts nev on nev.id = n.last_refused_evidence
   where n.state = 'open' and c.lifecycle_status = 'active'
     and not exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active')
  union all
  -- counsellor reports from Zoho$n$]], array[1, 1, 1, 1]);
