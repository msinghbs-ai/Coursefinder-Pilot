// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.363'
export const PACKAGE_VERSION='0.1.290'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Oct 2026',
  title:'Entry requirements workspace: filter, inspect, correct, add, withdraw, re-read and resolve',
  changes:[
    'Catalogue › Entry requirements, a new menu page beside Scholarships with four views: Provider entry matrix, Course entry requirements, Sources, reads and holds, and Resolution inspection. A summary above each view counts active, waiting in Layer 4, quarantined, withdrawn, held sources and courses with requirements.',
    'Filters on the server, combined, with chips and Clear filters; sorting headers; 50 rows a page; a Columns menu (show or hide, remembered in this browser); the shared catalogue table and drawer.',
    'Drawer: the full quote, the source and its stored copy, the reading run and model, the Layer 4 item, created and updated, and the history of every change by a person with before, after, who, when and why.',
    'Edit in list (Curator and above): qualification, level and mapped level, band, minimum, value and scale, edition, intake year, as-at; course score with its printed basis. A reason is asked once per editing session and kept with each change; a row changed by someone else since it was opened is refused; a band, minimum or value not printed in the quote is refused. Conditions are edited as parts (best of N, subject minimums, alternative routes).',
    'Add requirement from the provider\'s own source and its stored copy; Withdraw, Quarantine and Restore with a reason. No delete, no bulk action. Waiting AI rows are never edited or activated here: they link to Layer 4.',
    'Sources, reads and holds: each source\'s stored copy, latest read, tries, cost, rows not kept and why, Layer 4 item, last read and next refresh; Read again for one source (Platform Admin, with a reason; never past a held-as-unreadable source).',
    'Resolution inspection: for a course and a country, which of the five rules applied, the rows it returns with their quotes, why earlier rules did not apply, and what is not used (waiting or quarantined rows).',
    'The Provider drawer and Course detail sections stay read only and open the workspace.',
    'Consumer API unchanged (Decision 266): only active rows reach the course and provider payloads, as before.'
  ],
  bugFixes:[]
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
