-- CF-247 scholarship course links, fix (1 Oct 2026): the suggested course title kept the trailing words of the
-- scholarship's name ("Master of Global Medicines Development Pioneers Scholarship"), so it matched no course. Postgres
-- regular expressions take the greediness of the first quantifier, so the lazy match did not stop early. The title is
-- now taken whole and trailing words such as Scholarship, Award, Prize, Grant, Pioneers and Excellence are removed.
-- md5-guarded in-place edit of security.scholarship_scope_suggest.
do $$
declare d text; n text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scholarship_scope_suggest(uuid)'::regprocedure) <> '8585e3c95f386a721c9a33c19adad04e' then
    raise exception 'scholarship_scope_suggest changed; review first';
  end if;
  v_old := $x$v_title := substring(v_name from '((?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Doctor) of [A-Z][A-Za-z&'' ]+?)(?:\s+(?:Scholarship|Award|Prize|Bursary|Grant|Pioneers|International|Excellence)|$)');$x$;
  v_new := $x$v_title := nullif(btrim(regexp_replace(substring(v_name from '(?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Doctor) of [A-Z][A-Za-z&'' -]+'),
                   '(\s+(Scholarship|Scholarships|Award|Awards|Prize|Bursary|Grant|Pioneers|Excellence|Top-Up|Fund))+\s*$', '', 'i')), '');$x$;
  d := pg_get_functiondef('security.scholarship_scope_suggest(uuid)'::regprocedure);
  if position(v_old in d) = 0 then raise exception 'anchor not found'; end if;
  execute replace(d, v_old, v_new);
end $$;
