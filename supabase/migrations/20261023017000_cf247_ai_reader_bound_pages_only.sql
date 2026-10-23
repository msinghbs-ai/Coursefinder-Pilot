-- CF-247 (23 Oct 2026). Read with AI on the University of Auckland diplomas (13:13): the Diploma in Dance Studies took its delivery from the
-- Master of Dance Studies page. The AI reader for every attribute (Enrich fields, source ai_stored) read whatever page was last tried for
-- a course, also a page the platform had already found to be another course's (status mismatch: 3,364 values on 2,369 courses in AU, CA
-- and NZ since 14 Oct). It now reads only the page bound to the course (or an ambiguous page with an identity proof), as the adapter
-- path already does; a course whose only page is another course's says so ("no correct course page"). The values already taken from
-- such pages are taken back (Platform Admin 23 Oct 2026: "Take them all back"): each is recorded in pipeline.enrich_value_retractions with
-- its value, quote and page, the course field is emptied only where it still holds that value (a field a person locked is kept), and the
-- item says why; intakes read from those pages are withdrawn. The AI reads the field again once the course's own page is bound.
-- Campus links read from those pages are removed by the admin-repo paste file
-- docs/platform/wrong-page-values/PASTE-20261023-wrong-page-campus-links.sql (no delete in a migration).
-- Replaces: nothing (security.enrich_fields_slice_v1 edited in place, md5-guarded)
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

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'dc7176b941a17f0df7991c676ecd8ce1', array[
  array[$o$          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;$o$,
        $n$          -- 23 Oct 2026: only the course's own page: bound, or ambiguous with an identity proof; never a page found to be another course's
          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id
           where g.course_id = it.course_id and g.status in ('bound', 'ambiguous') and (g.status = 'bound' or g.identity_basis is not null);
          if v_path is null then
            update pipeline.field_enrich_items set reason = 'no correct course page: the page found is for another course'
             where id = it.id and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.status = 'mismatch');
          end if;$n$]]);

-- 2 values already taken from another course's page: recorded, then taken back --------------------------------------------------------
create table pipeline.enrich_value_retractions (
  item_id bigint primary key references pipeline.field_enrich_items(id) on delete cascade,
  course_id uuid not null,
  provider_id uuid not null,
  field text not null,
  value jsonb,
  quote text,
  evidence_id uuid,
  page_url text,
  page_heading text,
  cleared boolean not null default false,
  reason text not null,
  retracted_at timestamptz not null default now()
);
comment on table pipeline.enrich_value_retractions is 'CF-247 23 Oct 2026: values the AI reader filled from a page found to be another course''s (status mismatch), taken back with the Platform Admin''s approval; value, quote and page kept so each can be checked or restored. cleared: the course field held that value and was emptied.';
alter table pipeline.enrich_value_retractions enable row level security;
revoke all on pipeline.enrich_value_retractions from public, anon, authenticated;

insert into pipeline.enrich_value_retractions(item_id, course_id, provider_id, field, value, quote, evidence_id, page_url, page_heading, reason)
select i.id, i.course_id, i.provider_id, i.field, i.value, i.quote, i.evidence_id, g.url, g.candidates->>'h1',
       'the page read was another course''s page (status mismatch); Platform Admin 23 Oct 2026: take them all back'
  from pipeline.field_enrich_items i
  join pipeline.coverage_course_pages g on g.course_id = i.course_id and g.evidence_id = i.evidence_id
 where i.source = 'ai_stored' and i.state = 'filled' and g.status = 'mismatch';

update catalogue.courses c set delivery_mode = null, updated_at = now()
  from pipeline.enrich_value_retractions r
 where r.field = 'delivery' and c.id = r.course_id and c.delivery_mode = r.value->>'mode';
update catalogue.courses c set duration_value = null, duration_unit = null, updated_at = now()
  from pipeline.enrich_value_retractions r
 where r.field = 'duration' and c.id = r.course_id and c.duration_value = (r.value->>'value')::numeric and c.duration_unit is not distinct from r.value->>'unit';
update catalogue.courses c set open_to_international = null, updated_at = now()
  from pipeline.enrich_value_retractions r
 where r.field = 'international' and c.id = r.course_id and c.open_to_international = (r.value->>'open')::boolean;

update catalogue.course_intakes ci set status = 'withdrawn'
  from pipeline.enrich_value_retractions r
 where r.field = 'intakes' and ci.course_id = r.course_id and ci.evidence_id = r.evidence_id and ci.status = 'active'
   and ci.source_intake_key like r.course_id::text || ':ai:%';

-- cleared where the field is now empty (a field a person locked keeps its value)
update pipeline.enrich_value_retractions r set cleared = true
  from catalogue.courses c
 where c.id = r.course_id and ((r.field = 'delivery' and nullif(btrim(c.delivery_mode), '') is null)
     or (r.field = 'duration' and c.duration_value is null) or (r.field = 'international' and c.open_to_international is null)
     or (r.field = 'intakes' and not exists (select 1 from catalogue.course_intakes ci where ci.course_id = r.course_id and ci.evidence_id = r.evidence_id
                                              and ci.status = 'active' and ci.source_intake_key like r.course_id::text || ':ai:%')));

update pipeline.field_enrich_items i set state = 'skipped', reason = 'taken back: the page read was another course''s page', updated_at = now()
  from pipeline.enrich_value_retractions r where r.item_id = i.id;

insert into search.refresh_requests(requested_by) select 'Wrong-page values taken back'
 where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'Wrong-page values taken back');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.enrich_value_retractions', 'Layer 2', 'Values the AI reader took from another course''s page, taken back (23 Oct 2026); kept to check or restore', 'active', '{}', '20261023017000')
on conflict (kind, name) do nothing;

select 'AI reader reads only the course''s own page; ' || (select count(*) from pipeline.enrich_value_retractions) || ' wrong-page values taken back' ok;
