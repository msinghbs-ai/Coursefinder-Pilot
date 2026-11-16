#!/usr/bin/env python3
# Guards: REQ-76 API v3 field dictionary (Platform Admin 15 Nov 2026, combined build item 1). Rebuild: python3 scripts/api-v3-field-dictionary-build.py, then node scripts/api-v3-field-dictionary.mjs embed <migration>.
"""Builds docs/api/v3/field-dictionary.json from the live inventories (inv/*.txt) and the descriptions below.
Inventory lines are path:type[/type] taken from public.website_v3_* and public.zoho_v3_* responses on 15 Nov 2026.
The edge functions add api_version and request_id, drop contract_version, and replace logo.storage_path with logo.url and url_expires_at."""
import json, os, re, sys

INV = os.path.join(os.path.dirname(__file__), '..', 'docs', 'api', 'v3', 'inventory')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'docs', 'api', 'v3', 'field-dictionary.json')

START_DATE_STATUSES = ['known', 'no_official_calendar', 'month_only', 'not_on_course_page', 'course_page_not_verified', 'next_year_calendar_pending',
                       'not_yet_read', 'own_calendar', 'conflicting_evidence', 'held_for_review', 'rolling']
LOGO = ['attribution:string', 'content_hash:string', 'mime_type:string', 'source_url:string', 'terms_status:string', 'updated_at:string',
        'url:null/string', 'url_expires_at:null/string']
RANK = ['qs_wur:null/object', 'qs_wur.edition_year:number', 'qs_wur.rank_display:string', 'qs_wur.rank_low:null/number', 'qs_wur.terms_status:string',
        'the_wur:null/object', 'the_wur.edition_year:number', 'the_wur.rank_display:string', 'the_wur.rank_low:null/number', 'the_wur.terms_status:string']
ROWS = ['qualification:null/string', 'study_level:null/string', 'min_grade:null/string', 'scale:null/string', 'scale_stated:null/boolean', 'band:null/string',
        'conditions:null/object', 'quote:null/string', 'as_at:null/string', 'edition:null/string', 'case_by_case:boolean', 'source_url:null/string',
        'text:null/string', 'min_score:null/number', 'min_score_basis:null/string']
CONDITIONS = ['best_n:null/number', 'subject_minimums:array', 'subject_minimums[]:object', 'subject_minimums[].subject:string',
              'subject_minimums[].min_grade:null/string', 'alternatives:array', 'alternatives[]:object', 'alternatives[].route:string',
              'alternatives[].min_grade:null/string']
EXTRA_CONDITIONS = ['place:null/object', 'place.page:number', 'place.x:number', 'place.y:number', 'reader:null/string', 'section:null/string']

D = {
 # envelope
 'api_version': ('The API and version that answered: website-v3 or zoho-v3.', None),
 'request_id': ('Identifier of this request. Quote it when reporting a problem.', None),
 'total': ('Number of items that match, over all pages.', None),
 'page': ('This page number, from 1.', None),
 'page_size': ('Items per page asked for.', None),
 'sort': ('The order the items are in (the sort asked for, or the default).', None),
 'items': ('The items of this page.', None),
 'item': ('The requested record.', None),
 'filters_not_applied': ('Filter keys sent that the API does not recognise. They are listed, never silently ignored.', None),
 'not_found': ('Identifiers asked for that are not held or not published.', None),
 'kind': ('The statistics kind asked for: qilt or prisms.', ['qilt', 'prisms']),
 # course
 'course_id': ('StudySearch course identifier. The key to store; it never changes.', None),
 'title': ('Course title as published.', None),
 'display_code': ('The code to show visitors: the printed code (kind own, for example a CRICOS course code) or a StudySearch code such as UBC-MA-014 (kind studysearch). It never changes.', None),
 'display_code_kind': ('Whether display_code is the course\'s own printed code or a StudySearch code.', ['own', 'studysearch']),
 'display_code_label': ('Label to show with display_code, for example "CRICOS code".', None),
 'course_code': ('The source system\'s code. Do not show it to visitors; show display_code.', None),
 'cricos_course_code': ('CRICOS course code where the course is registered on CRICOS (Australia); null otherwise.', None),
 'country_code': ('ISO 3166-1 alpha-2 country code.', None),
 'campus_city': ('The first campus city of the course (the searched city first).', None),
 'campus_metro_area': ('Metro area of the first campus, where held (Australia).', None),
 'campuses': ('Campuses where the course is taught, the searched city first.', None),
 'campuses[].city': ('Campus city.', None),
 'campuses[].postcode': ('Campus postcode, where held (mostly Australia).', None),
 'campuses[].subdivision_code': ('State, province or region code (ISO 3166-2), for example AU-VIC.', None),
 'campuses[].metro_area': ('Metro area of the campus, where held (Australia).', None),
 'campuses[].regional_category': ('Australian Home Affairs regional category: 1 major city, 2 regional city, 3 regional centre and other regional area.', [1, 2, 3]),
 'campuses[].regional_category_name': ('Name of the regional category.', None),
 'campuses[].is_primary': ('True for the course\'s main campus where the course data names one.', None),
 'campuses[].campus_id': ('StudySearch campus identifier.', None),
 'campuses[].campus_name': ('Campus name as the provider gives it; null when not held.', None),
 'campuses[].course_count': ('Published courses linked to this campus.', None),
 'study_level': ('Study level of the course.', None),
 'study_level.code': ('Study level code from reference, for example bachelor or masters_coursework.', None),
 'study_level.name': ('Study level name.', None),
 'study_area': ('Field of study (ASCED narrow field in Australia).', None),
 'study_area.code': ('Study area code from reference, for example asced-0603.', None),
 'study_area.name': ('Study area name.', None),
 'duration_months': ('Course duration in months, from the register or the course page. A duration given in semesters is not converted (null).', None),
 'delivery_modes': ('How the course is delivered.', None),
 'delivery_modes[]': ('A delivery mode.', ['on_campus', 'online', 'blended', 'on_campus_and_online']),
 'tuition': ('The provider\'s current international tuition fee; null when not held. A whole-course total is never presented as per year.', None),
 'tuition.amount': ('The fee as published, in tuition.currency.', None),
 'tuition.currency': ('Currency of the fee: the course\'s own (AUD, NZD or CAD). There is no conversion.', None),
 'tuition.basis': ('What the amount covers.', ['annual', 'indicative_annual', 'course_total', 'per_session', 'unspecified']),
 'tuition.basis_label': ('The provider\'s own words for the basis.', None),
 'tuition.annual_amount': ('The stated annual figure, or one derived from a course total for courses of 12 months or more (then annual_is_derived is true). Null for per-session and unspecified figures.', None),
 'tuition.annual_is_derived': ('True when annual_amount was worked out from a whole-course total.', None),
 'tuition.year': ('The year the fee applies to, where stated.', None),
 'tuition.source': ('Where the fee comes from: the provider\'s current fee page (preferred) or the CRICOS registered course total.', ['provider_current', 'regulatory_registered']),
 'tuition_history': ('Every tuition year held, latest first.', None),
 'tuition_history[].amount': ('The fee as published.', None),
 'tuition_history[].currency': ('Currency of the fee.', None),
 'tuition_history[].basis': ('What the amount covers (as tuition.basis).', ['annual', 'indicative_annual', 'course_total', 'per_session', 'unspecified']),
 'tuition_history[].year': ('The year the fee applies to, where stated.', None),
 'tuition_history[].source': ('Where the fee comes from (as tuition.source).', ['provider_current', 'regulatory_registered']),
 'intakes': ('Intakes of the course. Months for most courses; dates mostly null.', None),
 'intakes[].label': ('The intake as the provider names it, for example "Semester 1".', None),
 'intakes[].month': ('Month the intake starts, 1 to 12.', None),
 'intakes[].year': ('Year of the intake, where stated.', None),
 'intakes[].start_date': ('Exact start date (YYYY-MM-DD), where published.', None),
 'intakes[].application_deadline': ('Application deadline (YYYY-MM-DD), where published.', None),
 'intakes[].start_date_status': ('Why the exact start date is or is not given (R28).', START_DATE_STATUSES),
 'entry_requirements': ('English entry summary. Academic entry is not implied here (see entry on course detail).', None),
 'entry_requirements.summary': ('Short summary of the English requirement.', None),
 'entry_requirements.basis': ('Where the summary comes from.', None),
 'english_requirements': ('English test requirements, one per test. An empty list means not held, not "no requirement".', None),
 'english_requirements[].test_code': ('English test code from reference, for example IELTS, PTE, TOEFL_IBT, CAE, DET, OET, CELPIP.', None),
 'english_requirements[].test_name': ('English test name.', None),
 'english_requirements[].min_overall_score': ('Minimum overall score on the test\'s own scale.', None),
 'english_requirements[].min_band_score': ('Lowest band or section score asked, where stated.', None),
 'english_requirements[].source': ('Where the requirement comes from.', None),
 'english_note': ('A note about the English requirement, where held.', None),
 'official_url': ('The provider\'s own page for this record; null when not verified.', None),
 'scholarship_count': ('Linked published scholarships.', None),
 'subdivision_codes': ('The states or provinces of the course\'s campuses; a Canadian course with no campus takes its provider\'s province.', None),
 'subdivision_codes[]': ('A state, province or region code (ISO 3166-2).', None),
 'publication_status': ('Publication state of the record. Every record returned is published.', None),
 'freshness': ('When the record was last updated.', None),
 'freshness.source_updated_at': ('When the source data behind this record last changed.', None),
 'freshness.projection_updated_at': ('When the API copy of this record was last rebuilt.', None),
 'description_excerpt': ('First part of the course description, cut at a whole word (O26). Null when no description is held.', None),
 'description': ('Description as published or source-grounded; null when not held.', None),
 'other_matches': ('Number of other courses sharing the same source code.', None),
 'scholarships': ('Scholarships linked to the course.', None),
 'scholarships[].scholarship_id': ('StudySearch scholarship identifier.', None),
 'scholarships[].name': ('Scholarship name.', None),
 'scholarships[].official_url': ('The scholarship\'s official page.', None),
 'scholarships[].amount_note': ('The amount as the provider words it.', None),
 'scholarships[].amount_is_maximum': ('True for "up to" amounts.', None),
 'scholarships[].application_deadline': ('Application deadline (YYYY-MM-DD), where the page states one.', None),
 'scholarships[].saving_per_year': ('Saving per year on this course, where it can be stated.', None),
 'scholarships[].saving_currency': ('Currency of saving_per_year.', None),
 'scholarships_top': ('Up to five linked scholarships, summarised for search lists (REQ-31).', None),
 'scholarships_top[].scholarship_id': ('StudySearch scholarship identifier.', None),
 'scholarships_top[].name': ('Scholarship name.', None),
 'scholarships_top[].amount_type': ('Kind of amount.', ['fixed_amount', 'percentage_tuition', 'full_tuition']),
 'scholarships_top[].amount_value': ('Amount or percentage, as amount_type says.', None),
 'scholarships_top[].amount_currency': ('Currency of a fixed amount.', None),
 'provider_outcomes_state': ('Whether QILT statistics are held for the provider.', None),
 'provider_outcomes': ('The provider\'s QILT statistics (Australia), by study level. Provider level only, never per course.', None),
 'outcomes_state': ('Whether QILT statistics are held for the provider.', None),
 'outcomes': ('QILT statistics for Australian providers, by study level. Provider level only. Empty for New Zealand and Canada.', None),
 'survey': ('QILT survey code.', None), 'survey_name': ('QILT survey name.', None),
 'metric_code': ('Measure code.', None), 'metric_name': ('Measure name.', None),
 'study_level_name': ('Study level name of the measure (UG, PGC, PGR, ALL).', None),
 'value': ('Value of the measure, in unit.', None), 'unit': ('Unit of the value.', None),
 'ci_low': ('Lower bound of the confidence interval.', None), 'ci_high': ('Upper bound of the confidence interval.', None),
 'national_benchmark': ('National figure for the same measure, where published.', None),
 'reference_year': ('Survey reference year.', None), 'responses': ('Number of responses, where published.', None),
 'grain': ('What the figure belongs to (for example provider and study level).', None),
 'recognition': ('Official registrations of the course (O29). CRICOS for Australia; empty when none is held.', None),
 'recognition[].scheme': ('Register, for example CRICOS.', None),
 'recognition[].code': ('Code on the register.', None),
 'recognition[].status': ('Status on the register.', ['registered']),
 'recognition[].authority': ('The body that keeps the register.', None),
 'recognition[].source_url': ('The register page.', None),
 'recognition[].evidence_date': ('Date of the register evidence.', None),
 'recognition[].checked_on': ('Date StudySearch last checked the register.', None),
 # academic entry
 'entry': ('Academic entry requirements of the course (always present; null fields mean not held). With edu_country it also carries resolution.', None),
 'entry.min_score': ('The course\'s minimum entry score, shown with min_score_basis.', None),
 'entry.min_score_basis': ('The words the course page prints with the score, for example "2027 Guaranteed ATAR".', None),
 'entry.min_scores': ('Every entry score the course publishes, one per route, as printed. [] when none is held.', None),
 'entry.min_scores[].score': ('The score as printed.', None),
 'entry.min_scores[].basis': ('Short label of the route.', None),
 'entry.min_scores[].audience': ('Who the score applies to.', ['international', 'all', 'domestic']),
 'entry.min_scores[].scale': ('Grading scale only where the provider states one; never worked out.', None),
 'entry.min_scores[].quote': ('The provider\'s own words; show it as the line.', None),
 'entry.min_scores[].source_url': ('The page the score is printed on.', None),
 'entry.min_scores[].as_at': ('Date the score was read (YYYY-MM-DD).', None),
 'entry.benchmark_band': ('The provider\'s band this course names, only where the course page prints one.', None),
 'entry.prerequisites': ('Prerequisites as published.', None),
 'entry.prerequisites[].text': ('The prerequisite.', None), 'entry.prerequisites[].quote': ('The provider\'s words.', None),
 'entry.selection_tasks': ('Selection tasks as published (interview, portfolio, test).', None),
 'entry.selection_tasks[].text': ('The selection task.', None), 'entry.selection_tasks[].quote': ('The provider\'s words.', None),
 'entry.requirements_note': ('Other published entry conditions.', None),
 'entry.resolution': ('The requirement that applies to a student from edu_country; null without edu_country.', None),
 'entry.resolution.country': ('The edu_country sent, in capitals.', None),
 'entry.resolution.step': ('The rule that applied, 1 to 5.', [1, 2, 3, 4, 5]),
 'entry.resolution.rule': ('Name of the rule that applied.', ['course_override', 'course_country_row', 'band_ladder', 'provider_minimum', 'contact_provider']),
 'entry.resolution.outcome': ('What to show.', ['minimum_published', 'case_by_case', 'contact_provider']),
 'entry.resolution.rows': ('The published requirement rows that apply.', None),
 'entry.resolution.note': ('Why no table row applied, when step is 5.', None),
 'entry.resolution.contact': ('The provider\'s website for the "contact the provider" link, when step is 5.', None),
 'rows[].qualification': ('Qualification as published.', None), 'rows[].study_level': ('The provider\'s own study level label.', None),
 'rows[].min_grade': ('Minimum grade exactly as printed; null when none is stated.', None), 'rows[].scale': ('Grading scale; "none" when the row states no minimum on a scale.', None),
 'rows[].scale_stated': ('False when the provider prints a grade without stating its scale.', None), 'rows[].band': ('Provider band, where printed.', None),
 'rows[].conditions': ('Extra conditions of the row.', None), 'rows[].quote': ('The provider\'s words.', None), 'rows[].as_at': ('Date the row was read.', None),
 'rows[].edition': ('Edition of the source document.', None), 'rows[].case_by_case': ('True when the row states no minimum on a scale: show "considered case by case".', None),
 'rows[].source_url': ('The page the row is printed on (O20).', None),
 'rows[].text': ('A course-page rule in the provider\'s words (step 1 only).', None), 'rows[].min_score': ('Minimum entry score of a course-page rule (step 1 only).', None),
 'rows[].min_score_basis': ('The words printed with min_score (step 1 only).', None), 'entry.resolution.band': ('The course band used to enter the provider\'s band table (step 3 only).', None),
 'conditions': ('Extra conditions of the row: best of N subjects, subject minimums and alternative routes.', None),
 'conditions.best_n': ('Best N subjects counted, where stated.', None),
 'conditions.subject_minimums': ('Subject minimums.', None), 'conditions.subject_minimums[].subject': ('Subject as printed.', None), 'conditions.subject_minimums[].min_grade': ('Minimum grade in the subject, as printed.', None),
 'conditions.alternatives': ('Alternative routes.', None), 'conditions.alternatives[].route': ('The alternative route as printed.', None), 'conditions.alternatives[].min_grade': ('Minimum grade for the route, as printed.', None),
 'conditions.place': ('Where the row was read in the source document.', None), 'conditions.place.page': ('Page number in the document.', None),
 'conditions.place.x': ('Horizontal position on the page.', None), 'conditions.place.y': ('Vertical position on the page.', None),
 'conditions.reader': ('The reader that took the row from the document.', None), 'conditions.section': ('The document section the row is in.', None),
 'entry_matrix': ('Academic entry requirements the provider publishes by country of prior education; narrowed to one country with edu_country.', None),
 'entry_matrix[].country': ('Country of prior education (ISO alpha-2).', None), 'entry_matrix[].study_level': ('The provider\'s own study level label.', None),
 'entry_matrix[].qualification': ('Qualification as published.', None), 'entry_matrix[].min_grade': ('Minimum grade as printed.', None),
 'entry_matrix[].scale': ('Grading scale; "none" means no minimum on a scale (case by case).', None), 'entry_matrix[].band': ('Provider band, where printed.', None),
 'entry_matrix[].course_code': ('Course code, only on rows for one course.', None), 'entry_matrix[].as_at': ('Date the row was read.', None),
 'entry_matrix[].scale_stated': ('False when the provider prints a grade without stating its scale.', None),
 'entry_matrix[].quote': ('The provider\'s words (O20).', None), 'entry_matrix[].source_url': ('The page the row is printed on (O20).', None),
 # provider
 'provider': ('The provider (institution) of the record.', None),
 'provider_id': ('StudySearch provider identifier, for example provider:cricos:00025b.', None),
 'name': ('Name as presented.', None),
 'legal_name': ('Legal name from the register.', None),
 'website': ('Official website.', None),
 'institution_type': ('Institution type from the regulators\' registers (TEQSA, CRICOS, NZQA); null for Canada and a few Australian providers.', None),
 'institution_type.code': ('Institution type code.', ['university', 'university_college', 'higher_education_institute', 'tafe_polytechnic', 'private_vet', 'school', 'wananga', 'other']),
 'institution_type.name': ('Institution type name.', None),
 'institution_type.basis': ('The register the type comes from.', None),
 'university_groups': ('University groups the provider belongs to.', None),
 'university_groups[]': ('A university group.', None),
 'university_groups[].code': ('Group code.', ['go8', 'atn', 'iru', 'run']),
 'university_groups[].name': ('Group name.', None),
 'ranking_summary': ('Latest edition of each world ranking; null where not ranked.', None),
 'qs_wur': ('QS World University Rankings, latest edition; null where not ranked.', None),
 'the_wur': ('Times Higher Education World University Rankings, latest edition; null where not ranked.', None),
 'edition_year': ('Ranking edition year.', None),
 'rank_display': ('Rank exactly as published, for example 201-250.', None),
 'rank_low': ('Best rank of the published range.', None),
 'rank_high': ('Worst rank of the published range.', None),
 'terms_status': ('Whether the publisher\'s terms allow the item to be shown.', None),
 'logo': ('Provider logo; null when not held. Copy the file and serve your copy.', None),
 'logo.attribution': ('Attribution to show with the logo.', None), 'logo.content_hash': ('Hash of the file; it changes when the file changes.', None),
 'logo.mime_type': ('File type.', None), 'logo.source_url': ('Where the logo was taken from.', None), 'logo.terms_status': ('Whether the logo may be shown.', None),
 'logo.updated_at': ('When the logo last changed.', None), 'logo.url': ('Signed link to the file; null if signing failed.', None),
 'logo.url_expires_at': ('When the signed link ends.', None),
 'course_count': ('Published courses.', None),
 'study_levels_offered': ('Study levels offered, with course counts.', None), 'study_areas_offered': ('Study areas offered, with course counts.', None),
 'study_levels_offered[].code': ('Study level code.', None), 'study_levels_offered[].name': ('Study level name.', None), 'study_levels_offered[].courses': ('Courses at this level.', None),
 'study_areas_offered[].code': ('Study area code.', None), 'study_areas_offered[].name': ('Study area name.', None), 'study_areas_offered[].courses': ('Courses in this area.', None),
 'rankings': ('Every ranking edition held, with indicators.', None),
 'system_code': ('Ranking system.', ['qs_wur', 'the_wur']), 'system_name': ('Ranking system name.', None), 'publisher': ('Ranking publisher.', None),
 'is_tied': ('True when the rank is shared.', None), 'overall_score_display': ('Overall score as published.', None),
 'indicators': ('Indicator scores as published.', None), 'indicators[].code': ('Indicator code.', None), 'indicators[].label': ('Indicator label.', None),
 'indicators[].value_display': ('Indicator score as published.', None), 'indicators[].rank_display': ('Indicator rank as published, where given.', None),
 'methodology_url': ('The publisher\'s methodology page.', None), 'attribution': ('Attribution to show with every ranking.', None),
 'scholarships_page_url': ('The provider\'s scholarships listing page StudySearch reads (R31).', None),
 'scholarships_last_reviewed_at': ('When that page was last read (R31).', None),
 'cricos_provider_code': ('CRICOS provider code (Australia).', None),
 'campus_count': ('Campuses held.', None), 'contact_count': ('Contacts held.', None),
 'city': ('City name.', None), 'postcode': ('Postal code.', None), 'subdivision_code': ('State, province or region code (ISO 3166-2).', None),
 'phone': ('Phone number, as published.', None), 'email': ('Email address, as published.', None), 'updated_at': ('When the record last changed.', None),
 'contacts': ('Contacts of the provider.', None),
 'campus_id': ('StudySearch campus identifier.', None), 'campus_code': ('Campus code from the register.', None), 'provider_name': ('Provider name.', None),
 'address_line1': ('Street address, first line.', None), 'address_line2': ('Street address, second line.', None),
 'latitude': ('Latitude, where held.', None), 'longitude': ('Longitude, where held.', None), 'metro_area': ('Metro area, where held (Australia).', None),
 'regional_category': ('Australian Home Affairs regional category, 1 to 3.', [1, 2, 3]), 'status': ('Record status.', None),
 'contact_id': ('StudySearch contact identifier.', None),
 'type': ('Contact type.', ['head_of_institution', 'general', 'team', 'staff']),
 'team': ('Team, where held.', None), 'source': ('Where the record comes from.', None), 'source_url': ('The source page.', None),
 'checked_at': ('When the contact was last checked.', None),
 # scholarship
 'scholarship_id': ('StudySearch scholarship identifier.', None),
 'official_scholarship_url': ('The scholarship\'s official page.', None),
 'university_id': ('Provider identifier of the scholarship.', None),
 'amount_value': ('Amount or percentage, as amount_type says.', None),
 'amount_type': ('Kind of amount.', ['fixed_amount', 'percentage_tuition', 'full_tuition']),
 'amount_type_detail': ('Finer kind of amount.', None),
 'amount_currency': ('Currency of a fixed amount.', None),
 'amount_is_maximum': ('True for "up to" amounts.', None),
 'amount_note': ('The amount as the provider words it.', None),
 'scholarship_percentage': ('Percentage of tuition, where stated.', None),
 'value_classification': ('Value class of the award.', None),
 'scholarship_type': ('Scholarship type.', None), 'scholarship_type_bucket': ('Scholarship type group.', None),
 'application_deadline': ('Application deadline (YYYY-MM-DD), only where the page states one.', None),
 'application_open_date': ('Application opening date, where stated.', None),
 'application_closing_date': ('Application closing date, where stated.', None),
 'deadline_is_rolling': ('True when applications are taken on a rolling basis.', None),
 'current_status': ('Application status.', ['open', 'closed', 'opening_soon', 'check_provider']),
 'study_levels': ('Study levels, from the linked courses.', None), 'study_levels[]': ('A study level code.', None),
 'study_levels_list': ('Study levels as the scholarship lists them.', None), 'study_levels_list[]': ('A study level.', None),
 'study_levels_source': ('Where the study levels come from.', None),
 'study_area_codes': ('Study area codes, from the linked courses.', None), 'study_area_codes[]': ('A study area code.', None),
 'study_stages': ('Study stages the scholarship is for.', None), 'study_stages[]': ('A study stage.', ['commencing', 'current']),
 'student_type': ('Students the scholarship is for.', ['international', 'domestic', 'both']),
 'study_load': ('Study load the award requires, where stated.', None),
 'academic_minimum': ('Academic minimum with its scale (ATAR, GPA and percentages stay on their own scale).', None),
 'academic_minimum.value': ('The academic minimum.', None), 'academic_minimum.scale': ('Scale of the minimum (for example ATAR, GPA, percent).', None), 'academic_minimum.text': ('The provider\'s words.', None),
 'min_academic_score': ('Minimum academic score 0-100, only where the provider states a percentage or WAM.', None),
 'automatic_consideration': ('True when students are considered without applying.', None),
 'citizenship_eligibility': ('Citizenship groups eligible.', None), 'citizenship_eligibility[]': ('A citizenship group.', None),
 'eligible_countries_list': ('Eligible countries as stated.', None), 'eligible_countries_list[]': ('A country.', None),
 'gender': ('Gender restriction, where stated.', None), 'age_min': ('Minimum age, where stated.', None), 'age_max': ('Maximum age, where stated.', None),
 'renewable': ('True when the award can be renewed.', None), 'eligibility_summary': ('Eligibility in short.', None),
 'reference_code': ('Not held (always null).', None),
 'last_verified_date': ('Date the scholarship was last verified.', None),
 'award_type': ('Kind of award.', ['scholarship', 'bursary', 'tuition_waiver', 'fee_discount', 'research_funding', 'grant', 'stipend', 'other']),
 'sponsor': ('Sponsor of the award.', None), 'programme': ('Programme the award belongs to.', None), 'award_code': ('The award\'s own code.', None),
 'benefits': ('What the award gives, one item per benefit.', None),
 'benefits[].type': ('Kind of benefit.', None), 'benefits[].amount': ('Amount of the benefit.', None), 'benefits[].currency': ('Currency of the benefit amount.', None),
 'benefits[].percentage': ('Percentage of tuition the benefit covers.', None), 'benefits[].is_maximum': ('True for "up to" amounts.', None),
 'application': ('How to apply.', None),
 'application.method': ('How the award is given.', ['separate_application', 'automatic_consideration', 'nomination']),
 'application.url': ('Application page.', None), 'application.rolling': ('True when applications are rolling.', None),
 'award_duration': ('How long the award lasts.', None), 'award_duration.value': ('Number of units the award lasts.', None), 'award_duration.unit': ('Unit of the duration (for example year).', None),
 'academic_year': ('Academic year of the award.', None),
 'nationality_eligibility_status': ('Whether eligibility is limited by nationality. An empty list is never unrestricted.', ['restricted', 'unrestricted', 'under_review', 'unknown']),
 'excluded_nationality_codes': ('Nationalities excluded (ISO alpha-2).', None), 'excluded_nationality_codes[]': ('A country code.', None),
 'nationality_regions': ('Regions as the source names them (never expanded).', None), 'nationality_regions[]': ('A region.', None),
 'award_tiers': ('Award tiers.', None), 'award_tiers[].label': ('Tier label.', None), 'award_tiers[].amount': ('Amount of the tier.', None),
 'award_tiers[].currency': ('Currency of the tier amount.', None), 'award_tiers[].percentage': ('Percentage of tuition the tier covers.', None), 'award_tiers[].basis': ('Basis of the amount.', None),
 'award_tiers[].maximum_amount': ('Maximum amount of the tier.', None), 'award_tiers[].notes': ('Notes on the tier, as published.', None),
 'linked_courses': ('Linked courses, paged (courses_page, courses_page_size).', None),
 'linked_courses[].course_id': ('StudySearch course identifier.', None), 'linked_courses[].course_code': ('Course code.', None), 'linked_courses[].title': ('Course title.', None),
 'linked_courses[].saving_per_year': ('Saving per year on this course.', None), 'linked_courses[].saving_currency': ('Currency of the saving.', None),
 'linked_courses[].saving_basis': ('How the saving was worked out.', None),
 'linked_courses_page': ('Page of linked courses (R29).', None), 'linked_courses_page_size': ('Linked courses per page (R29).', None),
 'linked_courses_total': ('Linked courses in all (R29).', None), 'linked_courses_truncated': ('True when more linked courses exist than this page holds.', None),
 'provider.cities': ('Provider cities.', None), 'provider.cities[]': ('A city.', None),
 # reference
 'generated_at': ('When the reference lists were built.', None),
 'countries': ('Countries held, with their vocabularies and course counts.', None),
 'countries[].courses': ('Courses held for the country.', None),
 'countries[].cities': ('Campus cities with course counts.', None), 'countries[].cities[].city': ('Campus city name.', None), 'countries[].cities[].courses': ('Courses with a campus in the city.', None),
 'countries[].cities[].metro_area': ('Metro area, where held.', None),
 'countries[].english_tests': ('English tests held for the country.', None), 'countries[].english_tests[].code': ('English test code.', None), 'countries[].english_tests[].courses': ('Courses holding a requirement for the test.', None),
 'countries[].intake_months': ('Intake months with course counts.', None), 'countries[].intake_months[].month': ('Month, 1 to 12.', None), 'countries[].intake_months[].courses': ('Courses with an intake in the month.', None),
 'countries[].study_areas': ('Study areas with course counts.', None), 'countries[].study_levels': ('Study levels with course counts.', None),
 'countries[].subdivisions': ('States and regions with course counts.', None), 'countries[].subdivisions[].code': ('Subdivision code.', None), 'countries[].subdivisions[].courses': ('Courses in the state or region.', None),
 'countries[].study_areas[].code': ('Study area code.', None), 'countries[].study_areas[].name': ('Study area name.', None), 'countries[].study_areas[].courses': ('Courses in the study area.', None),
 'countries[].study_levels[].code': ('Study level code.', None), 'countries[].study_levels[].name': ('Study level name.', None), 'countries[].study_levels[].courses': ('Courses at the level.', None),
 'course_sorts': ('Sorts the search action takes.', None), 'course_sorts[]': ('A sort.', None),
 'provider_sorts': ('Sorts the providers action takes.', None), 'provider_sorts[]': ('A sort.', None),
 'institution_types': ('Institution types with provider counts.', None), 'institution_types[].code': ('Institution type code.', None), 'institution_types[].name': ('Institution type name.', None),
 'institution_types[].description': ('What the type covers.', None), 'institution_types[].providers': ('Providers of the type.', None),
 'ranking_systems': ('Ranking systems held.', None), 'ranking_systems[].code': ('System code.', ['qs_wur', 'the_wur']), 'ranking_systems[].name': ('Ranking system name.', None),
 'ranking_systems[].publisher': ('Ranking publisher.', None), 'ranking_systems[].editions': ('Edition years held, latest first.', None), 'ranking_systems[].terms_status': ('Whether the publisher\'s terms allow display.', None),
 'regional_categories': ('Australian regional categories.', None), 'regional_categories[].code': ('Category, 1 to 3.', [1, 2, 3]), 'regional_categories[].name': ('Regional category name.', None),
 'scholarship_amount_types': ('Scholarship amount types.', None), 'scholarship_amount_types[]': ('An amount type.', ['fixed_amount', 'percentage_tuition', 'full_tuition']),
 'scholarship_student_types': ('Scholarship student types.', None), 'scholarship_student_types[]': ('A student type.', ['international', 'domestic', 'both']),
 'scholarship_study_stages': ('Scholarship study stages.', None), 'scholarship_study_stages[]': ('A study stage.', ['commencing', 'current']),
 'university_groups[].members': ('Member providers held.', None),
 'sync': ('What the Zoho sync carries: entities, countries and item counts.', None), 'sync.countries': ('Countries in the sync feed (zoho.sync_countries).', None),
 'sync.countries[]': ('A country code.', None), 'sync.entities': ('Entities in the sync feed.', None), 'sync.entities[]': ('An entity.', ['provider', 'campus', 'contact', 'course']),
 'sync.items': ('Items held per entity.', None), 'sync.items.provider': ('Providers in the feed.', None), 'sync.items.campus': ('Campuses in the feed.', None),
 'sync.items.contact': ('Contacts in the feed.', None), 'sync.items.course': ('Courses in the feed.', None), 'sync.checked_through': ('When every item was last checked for changes.', None),
 # statistics
 'metric': ('Measure counted.', None), 'period_start': ('Start of the period.', None), 'period_end': ('End of the period.', None), 'period_type': ('Kind of period.', None),
 'region_code': ('Region code.', None), 'region_name': ('Region name.', None), 'region_type': ('Kind of region.', None), 'sector': ('Education sector.', None),
 'suppressed': ('True when the figure is suppressed for privacy.', None),
}

CONTEXT = [
 (lambda e, r: r.startswith('contacts[].title') or (e == 'contacts' and r == 'title'), ('Job title of the contact, where held.', None)),
 (lambda e, r: r.startswith('contacts[].name') or (e == 'contacts' and r == 'name'), ('Name of the contact person, where held.', None)),
 (lambda e, r: e in ('provider', 'providers') and r == 'campuses', ('Campuses of the provider, one item per campus.', None)),
 (lambda e, r: e == 'campuses' and r == 'name', ('Campus name.', None)),
 (lambda e, r: (r.endswith('outcomes[].study_level') or e.startswith('statistics')) and r.endswith('study_level'), ('Study level of the measure: UG, PGC, PGR or ALL.', None)),
 (lambda e, r: e.startswith('statistics') and r == 'study_area', ('Study area of the count.', None)),
 (lambda e, r: e == 'report_status' and r == 'items', ('One item per report asked about.', None)),
]
NULL_ONLY = {'latitude': 'number', 'longitude': 'number', 'national_benchmark': 'number', 'responses': 'number', 'age_min': 'number', 'age_max': 'number',
             'best_n': 'number', 'academic_year': 'number'}

def lookup(rel, endpoint=''):
    for test, val in CONTEXT:
        if test(endpoint, rel): return val
    segs = rel.split('.')
    for i in range(len(segs)):
        k = '.'.join(segs[i:])
        if k in D: return D[k]
    leaf = segs[-1]
    if leaf in D: return D[leaf]
    return None

def parse(fn):
    out = {}
    for tok in open(os.path.join(INV, fn)).read().split():
        p, t = tok.rsplit(':', 1)
        out[p] = set(t.split('/'))
    return out

def expand(inv):
    """add logo and ranking children, resolution rows and conditions, and apply the edge function's changes"""
    inv = dict(inv)
    for p in list(inv):
        if p.endswith('logo') and 'object' in inv[p]:
            for k in list(inv):
                if k.startswith(p + '.storage_path'): del inv[k]
            for c in LOGO:
                cp, ct = c.split(':'); inv.setdefault(p + '.' + cp, set(ct.split('/')))
        if p.endswith('ranking_summary') and 'object' in inv[p]:
            for c in RANK:
                cp, ct = c.split(':'); inv.setdefault(p + '.' + cp, set(ct.split('/')))
        if p.endswith('entry.resolution.rows'):
            inv.setdefault(p + '[]', {'object'})
            for c in ROWS:
                cp, ct = c.split(':'); inv.setdefault(p + '[].' + cp, set(ct.split('/')))
            for c in CONDITIONS + EXTRA_CONDITIONS:
                cp, ct = c.split(':'); inv.setdefault(p + '[].conditions.' + cp, set(ct.split('/')))
            inv.setdefault(p[:-len('.rows')] + '.band', {'null', 'string'})
        if p.endswith('entry.selection_tasks'):
            inv.setdefault(p + '[]', {'object'}); inv.setdefault(p + '[].text', {'string'}); inv.setdefault(p + '[].quote', {'null', 'string'})
        if p.endswith('entry_matrix[].conditions'):
            for c in CONDITIONS + EXTRA_CONDITIONS:
                cp, ct = c.split(':'); inv.setdefault(p + '.' + cp, set(ct.split('/')))
    inv.pop('contract_version', None)
    return inv

ID_NOT_NULL = re.compile(r'(^|\.)(course_id|provider_id|scholarship_id|campus_id|contact_id|title|name|total|page|page_size|items|item|filters_not_applied|api_version|request_id|not_found|display_code|display_code_kind|country_code|test_code|code|label|month|system_code|edition_year|rank_display|flag_id|entity|id|seq|change|has_more|next_cursor|mode|kind|rows|pages|total_rows|complete)$')

def dtype(path, ts):
    t = ts - {'null'}
    if 'array' in t:
        return None  # decided from children
    if 'object' in t: return 'object'
    if 'boolean' in t: return 'boolean'
    if 'number' in t: return 'number'
    return 'string'

INTEGER_LEAVES = {'total', 'page', 'page_size', 'course_count', 'scholarship_count', 'month', 'year', 'duration_months', 'regional_category', 'edition_year',
                  'rank_low', 'rank_high', 'other_matches', 'courses', 'providers', 'members', 'reference_year', 'responses', 'step', 'campus_count', 'contact_count',
                  'linked_courses_page', 'linked_courses_page_size', 'linked_courses_total', 'age_min', 'age_max', 'best_n', 'code_regional', 'academic_year', 'page_no',
                  'seq', 'rows', 'pages', 'total_rows', 'campus', 'contact', 'course', 'provider'}
DATE_LEAVES = {'start_date', 'application_deadline', 'application_open_date', 'application_closing_date', 'as_at', 'evidence_date', 'checked_on', 'last_verified_date'}
TS_LEAVES = {'generated_at', 'updated_at', 'source_updated_at', 'projection_updated_at', 'scholarships_last_reviewed_at', 'checked_at', 'url_expires_at', 'checked_through',
             'as_of', 'reported_at', 'closed_at'}

def build(surface, endpoint, inv, overrides=None):
    inv = expand(inv)
    rows = []
    for p in sorted(inv):
        if p.endswith('[]'): continue  # element entries are folded into the array's type
        ts = inv[p]
        leaf = p.split('.')[-1].replace('[]', '')
        dt = dtype(p, ts)
        if ts == {'null'} and leaf in NULL_ONLY: dt = NULL_ONLY[leaf]
        if dt is None:
            el = inv.get(p + '[]', set()) - {'null'}
            dt = 'array<object>' if 'object' in el else 'array<string>' if el <= {'string'} or not el else 'array<' + '|'.join(sorted(el)) + '>'
        elif dt == 'number' and leaf in INTEGER_LEAVES: dt = 'integer'
        elif dt == 'string' and leaf in DATE_LEAVES: dt = 'date'
        elif dt == 'string' and leaf in TS_LEAVES: dt = 'timestamptz'
        rel = re.sub(r'^(items\[\]\.|item\.)', '', p)
        found = lookup(rel, endpoint)
        if found is None:
            raise SystemExit(f'no description for {surface} {endpoint} {p} (rel {rel})')
        desc, allowed = found
        el_allowed = None
        if dt.startswith('array<') and (rel + '[]') in D: el_allowed = D[rel + '[]'][1]
        nullable = 'null' in ts or (not dt.startswith('array') and not ID_NOT_NULL.search(p))
        if dt.startswith('array') and 'null' not in ts: nullable = False
        r = {'api_surface': surface, 'endpoint': endpoint, 'field_path': p, 'data_type': dt, 'is_nullable': nullable, 'description': desc}
        av = allowed if allowed is not None else el_allowed
        if av is not None: r['allowed_values'] = av
        rows.append(r)
    for r in rows:
        if overrides and r['field_path'] in overrides: r.update(overrides[r['field_path']])
    return rows

ENVELOPE = {'api_version': {'string'}, 'request_id': {'string'}}
def with_env(inv):
    inv = dict(inv); inv.update(ENVELOPE); return inv

def sync_inv(entities_desc):
    return {'items': {'array'}, 'items[]': {'object'}, 'items[].entity': {'string'}, 'items[].id': {'string'}, 'items[].seq': {'number'},
            'items[].change': {'string'}, 'items[].item': {'object', 'null'}, 'has_more': {'boolean'}, 'next_cursor': {'string'}, 'mode': {'string'},
            'full_load_complete': {'boolean'}, 'checked_through': {'string', 'null'}, 'as_of': {'string'}}

D.update({
 'entity': ('The kind of record.', None), 'id': ('The record\'s identifier (store and match by it).', None), 'seq': ('Position in the change stream.', None),
 'change': ('upsert: store item by id; remove: delete or mark inactive the record with that id (no item).', ['upsert', 'remove']),
 'has_more': ('True while another page follows: call again with next_cursor.', None), 'next_cursor': ('Opaque cursor for the next call. Store it as it is, only after the page is written.', None),
 'mode': ('full for a full load, delta for changes since the cursor.', ['full', 'delta']), 'full_load_complete': ('True on the last page of a full load.', None),
 'as_of': ('Time of the reply.', None), 'checked_through': ('When the platform last finished checking every item for changes (null until the first check after a full load has finished).', None),
 'rows': ('Rows in this page of the file.', None), 'pages': ('Pages in the whole file.', None), 'total_rows': ('Rows in the whole file.', None),
 'complete': ('True once the platform has built every item of that entity.', None), 'sync_cursor': ('Where sync continues from: keep the one from the first page exported.', None),
 'csv': ('The CSV file of this page (with format json). Lists inside a cell are separated by "; ".', None),
 'flag_id': ('The report\'s identifier.', None), 'field': ('The field reported.', None), 'reason': ('The Platform Admin\'s reason, shown to the counsellor.', None),
 'reported_at': ('When the report was made.', None), 'closed_at': ('When the report was closed.', None),
})
WEB_SYNC_ITEM = 'The record: for course the search item, provider the provider detail, logo {provider_id, logo}, rankings {provider_id, rankings[]}, scholarship the scholarship detail, reference the reference lists. Absent for remove.'
ZOHO_SYNC_ITEM = 'The record: for provider the provider detail, campus a campuses item, contact a contacts item, course the course detail (v2 item shape). Absent for remove.'
EXPORT_COLS = {
 'provider': 'provider_id,cricos_provider_code,name,legal_name,institution_type,country_code,state,city,postcode,website,phone,email,course_count,campus_count,contact_count,qs_rank,the_rank,updated_at',
 'campus': 'campus_id,provider_id,cricos_provider_code,provider_name,name,address_line1,address_line2,city,state,postcode,country_code,latitude,longitude,metro_area,regional_category,course_count',
 'contact': 'contact_id,provider_id,cricos_provider_code,provider_name,type,name,title,team,email,phone,source,source_url,checked_at',
 'course': 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,study_level,study_area,country_code,states,campus_cities,delivery_modes,duration_months,intake_months,ielts_overall,ielts_band,pte_overall,tuition_annual,tuition_currency,tuition_year,official_url,scholarship_count'}
CSV_DESC = {'state': 'State or province code.', 'qs_rank': 'Latest QS rank as published.', 'the_rank': 'Latest THE rank as published.', 'states': 'States of the course\'s campuses, "; " separated.',
            'campus_cities': 'Campus cities, "; " separated.', 'delivery_modes': 'Delivery modes, "; " separated.', 'intake_months': 'Intake months, "; " separated.',
            'ielts_overall': 'Minimum IELTS overall.', 'ielts_band': 'Lowest IELTS band asked.', 'pte_overall': 'Minimum PTE overall.', 'tuition_annual': 'Annual tuition.',
            'tuition_currency': 'Tuition currency.', 'tuition_year': 'Tuition year.', 'study_level': 'Study level code.', 'study_area': 'Study area code.', 'institution_type': 'Institution type code.',
            'type': 'Contact type: head_of_institution, general, team or staff.'}

REQ = [(r'description_excerpt$|(^|\.)description$|official_url$', ['REQ-61']), (r'scholarships_top', ['REQ-31']), (r'english_requirements', ['REQ-34', 'REQ-55']),
       (r'delivery_modes', ['REQ-53']), (r'entry\.resolution', ['REQ-28']), (r'intakes\[\]\.start_date_status', ['REQ-48'])]

def tag(rows):
    for r in rows:
        ids = sorted({i for pat, v in REQ if re.search(pat, r['field_path']) for i in v})
        if ids: r['req_ids'] = ids
    return rows

PENDING = []
def strip_number_arrays(rows):
    keep = []
    for r in rows:
        if r['data_type'] not in ('string', 'integer', 'number', 'boolean', 'date', 'timestamptz', 'object', 'array<string>', 'array<object>'):
            PENDING.append({**r, 'pending_reason': 'array of numbers: ref.api_field_dictionary.data_type has no array<integer> yet (constraint change sent to the Platform Admin)'})
        else: keep.append(r)
    return keep

fields = []
W = lambda f: parse(f'website_{f}.txt')
Z = lambda f: parse(f'zoho_{f}.txt')
for ep in ['search', 'course', 'providers', 'provider', 'rankings', 'scholarships', 'scholarship', 'reference']:
    fields += build('website', ep, with_env(W(ep)))
fields += build('website', 'sync', with_env(sync_inv(None)), {'items[].item': {'description': WEB_SYNC_ITEM},
              'items[].entity': {'allowed_values': ['course', 'provider', 'logo', 'rankings', 'scholarship', 'reference']}})
for ep in ['search', 'course', 'courses', 'providers', 'provider', 'campuses', 'contacts', 'reference']:
    fields += build('zoho', ep, with_env(Z(ep)))
zr = {k.replace('website', ''): v for k, v in W('rankings').items()}
fields += build('zoho', 'rankings', with_env(W('rankings')))
fields += build('zoho', 'scholarships', with_env(W('scholarships')))
fields += build('zoho', 'scholarship', with_env(W('scholarship')))
stat = parse('zoho_statistics_qilt.txt') if os.path.exists(os.path.join(INV, 'zoho_statistics_qilt.txt')) else None
for k in ['qilt', 'prisms']:
    fields += build('zoho', f'statistics:{k}', with_env(parse(f'zoho_statistics_{k}.txt')))
fields += build('zoho', 'sync', with_env(sync_inv(None)), {'items[].item': {'description': ZOHO_SYNC_ITEM},
              'items[].entity': {'allowed_values': ['provider', 'campus', 'contact', 'course']}})
fields += build('zoho', 'report_status', with_env({'items': {'array'}, 'items[]': {'object'}, 'items[].flag_id': {'string'}, 'items[].entity': {'string'},
              'items[].id': {'string'}, 'items[].field': {'string'}, 'items[].status': {'string'}, 'items[].reason': {'string', 'null'},
              'items[].reported_at': {'string'}, 'items[].closed_at': {'string', 'null'}, 'not_found': {'array'}, 'not_found[]': {'string'}}),
              {'items[].status': {'description': 'Outcome of the report.', 'allowed_values': ['open', 'fixed', 'not_changed']},
               'items[].entity': {'allowed_values': ['course', 'provider', 'campus', 'contact']}})
fields += build('zoho', 'export', with_env({'entity': {'string'}, 'rows': {'number'}, 'page': {'number'}, 'pages': {'number'}, 'total_rows': {'number'},
              'has_more': {'boolean'}, 'complete': {'boolean'}, 'sync_cursor': {'string'}, 'csv': {'string'}}),
              {'entity': {'description': 'The file exported.', 'allowed_values': ['provider', 'campus', 'contact', 'course']},
               'csv': {'description': 'The CSV file of this page (only with format json; otherwise the reply body is the CSV and these fields are headers x-rows, x-page and so on). Lists inside a cell are separated by "; ".'}})
for ent, cols in EXPORT_COLS.items():
    for c in cols.split(','):
        found = lookup(c)
        desc = CSV_DESC.get(c) or (found[0] if found else None)
        if not desc: raise SystemExit(f'no description for export column {ent}.{c}')
        fields.append({'api_surface': 'zoho', 'endpoint': f'export:{ent}', 'field_path': c, 'data_type': 'string', 'is_nullable': c not in ('provider_id', 'course_id', 'campus_id', 'contact_id'),
                       'description': f'CSV column (text): {desc}'})
fields = tag(strip_number_arrays(fields))
doc = {'about': 'StudySearch API v3 field dictionary (REQ-76). Every field the Website API v3 and Zoho API v3 return, by action (endpoint). Loaded into ref.api_field_dictionary by migration; read by the field_dictionary action and the developer guide. Built from live v3 responses on 15 Nov 2026 and the developer guides.',
       'fields': fields, 'pending_fields': PENDING}
json.dump(doc, open(OUT, 'w'), indent=1, ensure_ascii=False)
open(OUT, 'a').write('\n')
from collections import Counter
print(len(fields), 'fields;', len(PENDING), 'pending;', dict(Counter(f['api_surface'] + ':' + f['endpoint'] for f in fields)))
