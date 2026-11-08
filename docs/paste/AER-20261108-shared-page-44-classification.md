# AER shared-page held reads: classification of the 44 (read only, live project fxcwkweaxjtknorudmwp, 8 Nov 2026)

Nothing in this file has been applied. It is the list for the Platform Admin behind migration `20261108030000` (one general rule) and the items that stay with a person.
The 45 of 7 Nov is 44 today (one has moved). "Shared page" here means the waiting course read (`course_entry_first_read`, pending, readiness `technical_blocked`) whose stored page is also
recorded against a differently named course and which has no cut rows (rows cut sit in the row-limit class).

## Counts

| Class | Meaning | Items | What happens |
|---|---|---|---|
| (a) page covers the course | Own binding accepted on a strong basis (cricos_code 16, nzqa_code 3), no hand lock, every differently named course on the page holds a REFUSED (mismatch) binding | 19 | Released by the migration's rule. 14 have no other reason and become reviewable (a person still decides: Approve all / Approve except / Reject). 5 also carry dropped requirements and move to that class (stored-read recovery) |
| (b) generic or multi-course | Another BOUND or AMBIGUOUS course holds the same page (multi-major / multi-award pages) | 11 | Stay held, reason recorded by the gate |
| (b) locked | Hand lock on the course page address | 14 | Stay held unless individually authorised. 9 of the 14 also have a binding the identity check refused (the page is not their page) |
| (c) wrong binding, better stored page | none found | 0 | See "Rebind check" |
| (d) near-duplicate records | report only, no merges | see below | Report |

Total 19 + 11 + 14 = 44.

## Per provider

| Provider | (a) released | (b) multi | locked | Total |
|---|---|---|---|---|
| RMIT University | 15 | 10 | 2 | 27 |
| University of Auckland | 1 | 0 | 2 | 3 |
| Auckland University of Technology | 1 | 0 | 0 | 1 |
| Alphacrucis College | 1 | 0 | 0 | 1 |
| Nelson Marlborough Institute of Technology | 1 | 0 | 0 | 1 |
| Academy of Music and Performing Arts | 0 | 1 | 0 | 1 |
| Eastern Institute of Technology | 0 | 0 | 2 | 2 |
| Manukau Institute of Technology | 0 | 0 | 3 | 3 |
| Monash University | 0 | 0 | 2 | 2 |
| Toi Ohomai Institute of Technology | 0 | 0 | 1 | 1 |
| University of Southern Queensland | 0 | 0 | 1 | 1 |
| Victoria University of Wellington | 0 | 0 | 1 | 1 |
| Total | 19 | 11 | 14 | 44 |

(Auckland's generic catalogue page is shared by 15 records; the Commerce/Laws conjoint read on it is one of the locked items. Other Auckland conjoint reads with cut rows sit in the row-limit class, not here.)

## (a) released by the rule (19), item id then title

Dropped requirements also present (second reason) marked `*`.
- Alphacrucis `4fc7bb27-6a46-481c-9426-63a8a3ce5228` Associate Degree in Ministry *
- Auckland UT `00289c97-f1f1-4d43-90d4-255f035e49df` Doctor of Health Science (Level 10)
- NMIT `befb307a-a34b-4b3f-8a99-b5a01d5030bd` New Zealand Certificate in Mechanical Engineering (Level 3)
- Auckland `2827dfa0-2cb3-4fe9-a373-a747de8a2782` Postgraduate Diploma in Property Practice (Level 8)
- RMIT (15): `7de227ca-89a6-483d-94bf-a10ae1becc78` Associate Degree in Engineering Technology *; `101e42c8-8cd5-489b-b582-914be20386f2` Associate Degree in Fashion;
  `83d89c91-939b-4978-908d-9b2ddc5b0d00` Bachelor of Applied Science (Aviation); `b0960eda-7899-44ec-a515-5fdbbe716b5e` Bachelor of Aviation (Pilot Training);
  `cfb0f3e2-7b0a-4af7-b494-b40030c700a7` Bachelor of Engineering (Aerospace Engineering) (Honours)/Bachelor of Business; `40e34856-2972-4ab4-815b-30b896849cc8` Bachelor of Social Science *;
  `8cf8ef55-0ac3-4366-a40c-e40bf3415959` Diploma of Interior Design *; `4db6e044-5025-41da-b2d3-a5205b99c6de` Graduate Certificate in Commerce;
  `99fa8983-b798-4244-b969-4f28acb0e34c` Graduate Certificate in Professional Accounting; `9d560a52-8524-4b39-8066-a006486e0ac5` Graduate Diploma in Media;
  `aeb10643-a237-450e-b305-34249c46bf70` Graduate Diploma in Project Management; `bb56de1a-ab6b-48ea-a0e0-e9f441cd80e2` Graduate Diploma of Communication;
  `1da31c5c-03e4-4238-8bb5-78dcac852ac1` Master of Applied Science (Health & Medical Physics); `8fc4ce98-7343-4b90-8113-76505455da87` Master of Arts (Arts Management) *;
  `2f38e67e-4ad3-4eeb-aaa3-ab1bdbc62847` Master of Food Science and Technology

Evidence for (a): `coverage_course_pages.status = 'bound'` on cricos_code or nzqa_code for the course; every other differently named course on the same url has status `mismatch`.
The rule does not look at the page text and does not approve anything.

## (b) generic or multi-course, stay held (11), unlocked

The page is also the bound or ambiguous page of another programme (a multi-major / multi-award page, so its requirements cannot be told apart by programme):
- RMIT BH012 Science (Honours) page, 7 reads: Biology `3746fb3d-b18c-4118-8413-ae7c928f5dc8`, Biotechnology `6f612c44-4d6c-46da-8654-c4d18fbc1add`, Environmental Science `a7986759-3f28-4114-869e-57e96c064dc5`,
  Food Technology and Nutrition `bebd42b5-0d3f-41fb-ad2a-9ebb62786d6c`, Geospatial Science `b207d79b-cd01-40e6-b050-3850e0bd19f9`, Mathematics and Statistics `825d0c2e-5690-4a74-a2d1-00094e2d4f2a`,
  Space Science `846d58a4-0a09-4bbb-aeaf-e35eecaad1ec` (8 bound courses share the page plus one refused binding).
- RMIT Advanced Diploma of Engineering Technology - Electrical `9a579a7d-827d-4d16-b4de-0d85b39428c4` (shares with 2 ambiguous).
- RMIT Bachelor of Arts (Photography) (Honours) `4c324aad-2ed6-4392-95fa-d356b012d147` * (shares with 1 bound).
- RMIT Bachelor of Software Engineering (Professional) `8e77c79e-277d-4d16-b6ef-02391abc2a37` (shares with the two Bachelor of Software Engineering records).
- AMPA Associate Degree of Music (Performance) `40664303-cff6-4c76-be7c-84284b1a3765` (shares with 1 bound).
Way forward for a person: either confirm the page is the course's own page (then the existing rebind path), or reject the read. No rule can settle these.

## Locked (14): held unless individually authorised

Own binding refused (9): EIT Postgraduate Certificate in Digital Business, EIT Postgraduate Diploma in Digital Business; MIT Foundation Skills, MIT Refrigeration and Air Conditioning, MIT Diploma in Early Childhood Education;
RMIT Bachelor of Engineering (Aerospace Engineering) (Honours) (single degree), RMIT Graduate Certificate of Commerce; Auckland Conjoint Bachelor of Commerce/Bachelor of Laws (Honours), Auckland Conjoint Bachelor of Global Studies.
Own binding bound (5): Monash Bachelor of Pharmacy (Honours) and Master of Pharmacy, Monash Master of Interpreting and Translation Studies, Toi Ohomai Bachelor of Social Work, USQ Master of Data Science, VUW Master of Global Business.

## Rebind check (class c), from the stored candidate for each of the 9 refused bindings

No stored first-party page was found that the existing identity path could accept without a person confirming it:
- Wrong page for the programme: EIT Postgraduate Certificate (page is a general Master's pathway post), EIT Postgraduate Diploma (page is Graduate Diploma in Business, Level 7), MIT Early Childhood Diploma (generic
  Education area page), Auckland Conjoint Commerce/Laws (generic catalogue "Details" plan page), Auckland Conjoint Global Studies (the single degree page BGlobalSt), RMIT Aerospace single degree (page is the BH082 double degree).
- Possible own page, identity not settled: MIT Refrigeration and Air Conditioning (page "Certificate in Refrigeration and Air Conditioning", Trades Assistant Level 3, title near; level and variant need a person), MIT Foundation Skills
  (page is the Level 2 Industry Cadetship variant).
- (d) Near-duplicate record: RMIT Graduate Certificate of Commerce (locked, refused) and Graduate Certificate in Commerce (bound, released) are one programme recorded twice ("of" and "in"); the page's h1 is "Graduate Certificate in Commerce".
Because all nine are locked, none is touched. A person decides, one by one, whether to authorise a rebind (`security.course_page_rebind_v1`).

## (d) near-duplicates seen (report only, no merges)

- RMIT Graduate Certificate of Commerce / Graduate Certificate in Commerce (above).
- RMIT Bachelor of Software Engineering, two records with the same title and a third "(Professional)" on the same page.
- RMIT Bachelor of Education (Primary), (Primary and Secondary), (Primary and Early Childhood): three bound records on related pages (these carry cut rows; row-limit class).

## QUT (separate route, migration `20261108030100`)

38 held reads: 37 cut at the row limit (30 to 111 rows) and 1 ordinary row-limit read (8 rows). 14 of the 37 are locked and are not mapped. 23 unlocked course pages, each with a stored HTML copy,
are mapped (under a count and md5 guard, held) as course-level matrix sources. Nothing is read until a Platform Admin runs `security.aer_matrix_route_activate_v1` (capped by `aer.matrix_route_activate_max`, default 5).
