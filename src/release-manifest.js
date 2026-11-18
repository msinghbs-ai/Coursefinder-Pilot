// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.35'
export const PACKAGE_VERSION='0.1.457'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Dashboard for your role, Role guides, guided Create user and a formatted email editor',
  changes:[
    'Dashboard: drawn for your role. Viewers and Counsellors start with Search the catalogue and see no pipeline or Inbox counts; Curators see Waiting for you without the operator rows; a Platform Admin also sees Waiting for your approval (an edition ready to publish, Layer 1 drafts, how email is sent).',
    'Continue where you left off: your last searches, review queues and pages, on this browser only. Resume puts a search back exactly as you left it; Clear empties the list.',
    'Guides › Role guides: a guide for each role (what you can and cannot do, the pages you can open, where to start), your own first, with Your role guide on the Dashboard. The same guides are kept as documents.',
    'Users & roles › Create user is four short steps (Person, Role, Sign-in, Review): the email is checked as you type, the chosen role shows what it can and cannot do, the invitation or password is explained, and a confirmation says what the person receives.',
    'Links & Email Templates: the email body is edited as formatted text (bold, headings, lists, Insert link, a Sign in button, plain-English variables); Edit HTML still shows the code. The top of the tab says how mail is sent now (Supabase Built-in or Resend API), the sender, the key and the last test.',
    'Buttons say what they do: Save Provider Settings and Send Test Email on the delivery card; Save Template and Send This Template as a Test on the templates.'
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
