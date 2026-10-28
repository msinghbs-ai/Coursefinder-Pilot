// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.364'
export const PACKAGE_VERSION='0.1.291'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Oct 2026',
  title:'Entry requirements: course-level reading in batches, the rendered no-table note, and Read again fetching a page again as HTML',
  changes:[
    'Catalogue › Entry requirements › Course entry requirements: a new Course-level reading panel. For each provider in the plan it shows the courses that can be read (stored official page and strong identity), read, reading, waiting in Layer 4, admitted, with no row kept, and remaining, with the estimated cost left.',
    'The cost a course (measured once 20 reads are measured, an estimate until then), the OpenRouter balance against its floor and the batch size are shown above the table.',
    'Platform Admin: Preview next batch shows how many courses the next batch would read (next by priority, or one provider) and its estimated cost; Read next batch asks for it with a reason. A batch is at most the set number of courses, never a course already read, and is refused while an earlier course read waits, when AI is stopped, or when it would take the balance below its floor. Every course read goes to Layer 4.',
    'Sources, reads and holds: a page read rendered that shows no requirements table now waits in Layer 4 as a note (Rendered, no table: in Layer 4); once approved it shows as No matrix published (confirmed). Approving the note admits and replaces nothing.',
    'Read again on a web page stored as markdown fetches the page again as HTML (the markdown copy stays as evidence); its waiting rows and Layer 4 item are superseded first, with the reason.',
    'Entry matrices: slices of a long page are read six at a time, 8,000 characters a slice (Settings › Pipeline settings, Entry requirements).',
    'Consumer API unchanged (Decision 266).'
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
