-- CF-247 (3 Oct 2026, 15:00 AEST). Decision 244. Platform Admin, 14:21: "needs a filter for only display for international
-- students … all scholarships under publishing are not available for search — make them available (international
-- students filter)". Found: every scholarship on record carried audience 'international' as a default never read from
-- the page (1,260 of 1,260). Multiple choice (14:50): "Read audience from wording, then publish international".
-- What this does: the audience is read from each active scholarship's own wording (name, description, criteria) by
-- fixed rules — international / domestic / international_and_domestic / not_stated — with the matched phrases kept as
-- the basis in scholarship.audience_readings; the scholarship's audience is set from the reading unless a person set it
-- by hand (manual lock). A scholarship whose page states nothing is 'not_stated' and so is held from publishing
-- ("not for international students") until a person decides; nothing is published here. The two selection functions
-- that served only audience = 'international' now also serve 'international_and_domestic' (replaced under md5 guards).
-- Job scholarship-audience re-reads hourly so newly admitted scholarships get an audience the same way.
create table if not exists scholarship.audience_readings(
  scholarship_id uuid primary key references scholarship.scholarships(id),
  audience text not null check (audience in ('international','domestic','international_and_domestic','not_stated')),
  phrase_international text, phrase_domestic text, phrase_both text,
  reader_version text not null, read_at timestamptz not null default now());
revoke all on scholarship.audience_readings from public, anon, authenticated;

create or replace function security.scholarship_audience_read_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline', 'security' as $f$
declare v_changed int := 0; v_read int := 0; v_counts jsonb;
  c_intl constant text := '\m(international students?|overseas students?|student visa|subclass 500|onshore|offshore|citizens? of (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|cambodia|kenya|nigeria|colombia|brazil|mexico|chile|peru|hong kong|singapore|japan|korea|taiwan|turkey|saudi|uae|iran|iraq|egypt|ghana|south africa|canada|usa|united states|uk|united kingdom|germany|france|italy|spain)|from (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|latin america|africa|asia|europe|the americas)|full[- ]fee[- ]paying international|global excellence|international (merit|excellence|academic))\M';
  c_dom constant text := '\m(domestic students?|australian citizens?|australian permanent residents?|permanent residen(t|cy) of australia|commonwealth supported|csp|hecs|fee[- ]help|home students?|new zealand citizens?|humanitarian visa|aboriginal|torres strait|indigenous|first nations)\M';
  c_both constant text := '\m(all students|domestic and international|international and domestic|regardless of (citizenship|residency|nationality)|open to all)\M';
begin
  with t as (
    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt
      from scholarship.scholarships s where s.lifecycle_status = 'active'),
  r as (
    select t.id, substring(t.txt from c_intl) p_intl, substring(t.txt from c_dom) p_dom, substring(t.txt from c_both) p_both from t),
  v as (
    select r.id, case when r.p_both is not null or (r.p_intl is not null and r.p_dom is not null) then 'international_and_domestic'
                      when r.p_intl is not null then 'international' when r.p_dom is not null then 'domestic' else 'not_stated' end audience,
           r.p_intl, r.p_dom, r.p_both from r),
  up as (
    insert into scholarship.audience_readings(scholarship_id, audience, phrase_international, phrase_domestic, phrase_both, reader_version, read_at)
    select v.id, v.audience, v.p_intl, v.p_dom, v.p_both, 'scholarship-audience-v1', now() from v
    on conflict (scholarship_id) do update set audience = excluded.audience, phrase_international = excluded.phrase_international, phrase_domestic = excluded.phrase_domestic, phrase_both = excluded.phrase_both, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id)
  select count(*) into v_read from up;
  update scholarship.scholarships s set audience = a.audience, updated_at = now() from scholarship.audience_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.audience is distinct from a.audience and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'audience');
  get diagnostics v_changed = row_count;
  select jsonb_object_agg(x.audience, x.n) into v_counts from (select a.audience, count(*) n from scholarship.audience_readings a group by 1) x;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'audience_read', 'Audience read from each scholarship''s wording', jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts, 'decision', 'Decision 244'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts);
end $f$;
revoke all on function security.scholarship_audience_read_v1() from public, anon, authenticated;

-- selection: scholarships open to everyone are offered to international students too
do $g$ declare r record; begin
  for r in select p.oid, n.nspname || '.' || p.proname fn, md5(p.prosrc) m from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'security' and p.proname in ('scholarship_selection_for_course_impl', 'scholarship_selection_for_provider_impl') loop
    if r.m not in ('0aac648f1fd0c5953e9e1afed30a584d', '45afb487beed3a878ed49944d50b2ccd') then raise exception '% changed (md5 %); not replacing', r.fn, r.m; end if;
    if (select count(*) from regexp_matches(pg_get_functiondef(r.oid), 'lower\(coalesce\(s\.audience,''''\)\)=''international''', 'g')) <> 1 then raise exception '% predicate not found exactly once', r.fn; end if;
    execute replace(pg_get_functiondef(r.oid), $x$lower(coalesce(s.audience,''))='international'$x$, $x$lower(coalesce(s.audience,'')) in ('international','international_and_domestic')$x$);
  end loop;
end $g$;

select cron.schedule('scholarship-audience', '41 * * * *', $$select security.scholarship_audience_read_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('scholarship-audience', 'Scholarships', 72, 'Scholarship audience from wording',
        'Hourly: reads who each active scholarship is for from its own name, description and criteria (international, domestic, both, or not stated) and keeps the matched phrases as the basis. A value set by hand is never changed. A scholarship whose page states nothing is held from publishing until a person decides (Decision 244).', 5, false)
on conflict (jobname) do nothing;

select security.scholarship_audience_read_v1();
