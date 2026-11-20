-- CF-247 s901 (Platform Admin 21 Nov 2026 07:48 AEDT, chat S1-Coverage-Unlock-UI-Notes): Entry requirements › Provider entry matrix filters by
-- Destination country (where the provider is: AU, NZ, CA) beside Source country (the student's country of prior education, which the filter
-- called "Country" always was: catalogue.provider_entry_matrix.country_code), and by Applies to (university-wide rows, which have no course,
-- or one course's rows). Course detail › Entry requirements uses the same list to show the university-wide table that applies to the course.
-- One md5-guarded edit of the admin workspace function public.admin_aer (admin only; never part of the consumer API):
--   'options' also returns destinations; 'matrix_list' accepts destination and scope. Every existing filter and output is unchanged.
-- Live read 21 Nov 2026 08:55 AEDT (rolled back): admin_aer md5 0593747b; each edit applies exactly once; after the edit
--   destinations AU and NZ; Charles Sturt University-wide proposed 7; AU university-wide active 1,134; NZ active 251.
-- Replaces: public.admin_aer (same name and arguments; md5-guarded edit).
-- Retires: nothing.
-- G1: no job. G2: no number written into a rule. G3: no consumer object (75/48). Nothing dropped or deleted. No spend.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('public.admin_aer(text,jsonb)', '0593747bb6ddd55c785fc445a06eb242', '0f4af8394ea36e6ef96df2e9130e0cc9', array[
  -- 1 'options' also lists the destination countries: where the providers with entry rows are
  array[$o$'all_countries', (select coalesce($o$,
        $n$'destinations', (select coalesce(jsonb_agg(jsonb_build_object('code', z.cc, 'name', z.n) order by z.n), '[]'::jsonb) from (  -- CF-247 s901: destination country (where the provider is)
                     select distinct k0.iso_alpha2 cc, k0.name n from catalogue.provider_entry_matrix m0 join catalogue.providers p0 on p0.id = m0.provider_id
                       join ref.countries k0 on k0.id = p0.country_id) z),
      'all_countries', (select coalesce($n$],
  -- 2 'matrix_list' filters by destination country and by university-wide or course rows
  array[$o$and ($1->>'country' is null or m.country_code = upper($1->>'country'))$o$,
        $n$and ($1->>'country' is null or m.country_code = upper($1->>'country'))
           and ($1->>'destination' is null or p.country_id = (select k9.id from ref.countries k9 where k9.iso_alpha2 = upper($1->>'destination')))  -- CF-247 s901
           and ($1->>'scope' is null or ($1->>'scope' = 'university' and m.course_id is null) or ($1->>'scope' = 'course' and m.course_id is not null))  -- CF-247 s901$n$]
], array[1, 1]);
