-- CF-247 Decision 139 / 167: publication holds after a hand-check. A dry run of the second sweep batch (83 eligible,
-- 29 Sep 2026) found records that pass the automatic rules but should not be published yet:
--   * English-language-course bursaries (RMIT UP General English / IELTS preparation, COLFUTURO English programs) linked
--     to degree courses at "research and undergraduate" levels;
--   * a "research and undergraduate" level pair that looks like a systematic level-reading error (held until re-read);
--   * scholarships that are not open ("held in tenure until 2030", not currently offered).
-- A hold is a logged row with a reason; publishability reports it; the batch skips it and the nightly review
-- withdraws a published record that gains a hold. Releasing a hold is a deliberate update (released_at).
create table if not exists pipeline.scholarship_publication_holds (
  scholarship_id uuid primary key references scholarship.scholarships(id) on delete cascade,
  reason text not null, held_by text not null default 'hand-check', held_at timestamptz not null default now(),
  released_at timestamptz, release_note text);
alter table pipeline.scholarship_publication_holds enable row level security;
revoke all on pipeline.scholarship_publication_holds from public, anon, authenticated;

do $patch$
declare v text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.scholarship_publishability_v1()'::regprocedure)<>'01d14b534fdda592ca99cd9ee18e5a68' then
    raise exception 'scholarship_publishability_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.scholarship_publishability_v1()'::regprocedure);
  if (length(v)-length(replace(v,$o$        case when s.evidence_id is null then 'no evidence' end,$o$,'')))/length($o$        case when s.evidence_id is null then 'no evidence' end,$o$)<>1 then
    raise exception 'publishability anchor not found exactly once'; end if;
  execute replace(v,$o$        case when s.evidence_id is null then 'no evidence' end,$o$,
    $n$        case when s.evidence_id is null then 'no evidence' end,
        case when exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id=s.id and h.released_at is null) then 'held after hand-check' end,$n$);
end $patch$;

insert into pipeline.scholarship_publication_holds(scholarship_id,reason)
select s.id,
       case when (s.name||' '||coalesce(pg.facts->>'eligibility_excerpt','')) ~* '(held in tenure|not (currently )?(open|offered|available)|no longer (offered|available)|applications? (are|is) (now )?closed|discontinued)' then 'not open to applicants'
            when s.name ~* '(general english|ielts preparation|english programs)' then 'English language course bursary linked to degree courses'
            else 'research and undergraduate levels together; re-read before publishing' end
  from scholarship.scholarships s join pipeline.scholarship_pages pg on pg.scholarship_id=s.id
 where s.lifecycle_status='active' and coalesce(s.publication_status,'unpublished')<>'published'
   and ( (s.name||' '||coalesce(pg.facts->>'eligibility_excerpt','')) ~* '(held in tenure|not (currently )?(open|offered|available)|no longer (offered|available)|applications? (are|is) (now )?closed|discontinued)'
      or s.name ~* '(general english|ielts preparation|english programs)'
      or (pg.facts->'levels' ? 'research' and pg.facts->'levels' ? 'undergraduate'))
on conflict do nothing;
