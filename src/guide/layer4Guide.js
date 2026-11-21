// CF-247 s931 (Decision 279 §7.2): Help › Platform guide › Layer 4 guide, for counsellors and reviewers. Plain words; no figures that go stale.
export const LAYER4_GUIDE = [
  { key: 'tell', title: 'How to tell a record is under review', body: [
    'A value a person still decides shows the pill In Layer 4 review (N waiting) on the record.',
    'Counsellors and Viewers cannot open Layer 4; the pill tells them a reviewer is checking the value. Curators and above open the item from the pill.'] },
  { key: 'card', title: 'The card, zone by zone', body: [
    'Entity: the module, the university, the course and its CRICOS or course code, when the item was made and how many days it has waited; the Field line names the value in plain words.',
    'Values: the proposed value beside the value live now (or the pill that says why there is none).',
    'Source: the official address, the date the copy was saved and the quote the value was read from.',
    'Why it is held: the plain reason, with (i) Hint: what it means, an example, and when to choose Yes or No.',
    'Decide: Yes (Approve), No (Reject), Resubmit to Review with AI, and More options for the queue\'s other choices.',
    'Folds, closed: Progress and history, Evidence and course links, and Technical detail (the reference, the rule code and the raw reason).'] },
  { key: 'decide', title: 'Yes, No and Resubmit: what each does next', body: [
    'Yes (Approve) admits the value as read; where the queue allows it, Lock this value keeps automation from changing it.',
    'No (Reject) refuses it with a reason; Wrong course, Outdated year, Bad parse and Not offered fill the reason in one click.',
    'Resubmit to Review with AI asks the queue\'s own re-read: entry requirements read the stored copy again with no AI ($0); descriptions are read again within today\'s AI budget, shown before you confirm. The new read comes back here for Yes or No; nothing it returns is admitted on its own.',
    'After any decision the queue count, All in this queue and Card X of Y are read again together, so they always agree.'] },
  { key: 'who', title: 'Who may decide what', body: [
    'Entry requirements and provider departures: the Platform Admin.',
    'Archiving a provider or a course: the PIM Admin or the Platform Admin.',
    'Most other queues, descriptions included: a Pipeline Operator or above. Approve all verified for provider shows the provider\'s own verified count and admits only those.',
    'Curators read the queues and correct records; they add an official address from the No official website / course URL on file pill.'] },
  { key: 'report', title: 'Reporting a wrong value as a counsellor', body: [
    'In Zoho, use Counsellor report on the course. It reaches Layer 4 as a counsellor report; a reviewer marks it Fixed or Not changed.'] },
]
