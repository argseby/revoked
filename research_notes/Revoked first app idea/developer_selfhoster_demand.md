# Developer and self-hoster demand and distribution channels for a revocable, live data-sharing platform (as of Sept 2026)

Method note: GitHub star counts, Home Assistant analytics and npm package counts below were pulled live on 2026-09-28 from the public GitHub REST API, analytics.home-assistant.io JSON and the npm registry search API. Vendor prices come from vendor pages or 2026 third-party pricing write-ups (flagged where secondary). npm per-package download counts could not be retrieved (npm API rate-limited, HTTP 429), and the GitHub API rate-limited after about 60 repos.

## 1. Secret/config delivery patterns and their gaps (Doppler, Infisical, Vault, 1Password, Bitwarden SM, SOPS, dotenv, GH Actions); is there demand for "someone else owns the secret, I read the current value, they can revoke"?

### Takeaway
The secrets-manager market is crowded and mature: Vault, Infisical and SOPS each have 23k–36k GitHub stars, and every major vendor already ships CI integrations. Pricing favours per-seat or per-identity growth inside a single organisation. What these tools model poorly is a secret owned by a different party (a client) that a contractor or agency reads live and the owner can revoke. Today that gap is filled with advice ("paste it in Slack, rotate later", "make a second key") rather than a product. That is revoked's natural wedge, but it is a niche, and competing head-on as a general secrets manager is not realistic for a solo developer.

### Cited Findings
**Pricing (2026):**
- Infisical Pro is $18/month per identity, and humans and machines both count: service accounts, CI pipelines and Kubernetes workloads are each billed. Example: 10 developers plus 20 machine identities cost $540/month. The free tier covers 5 identities, 3 projects, all integrations and self-hosting — [EnvManager (secondary)](https://envmanager.com/blog/infisical-pricing); [Infisical pricing](https://infisical.com/pricing)
- Doppler Team is $21/user/month (as of June 2026). Add-ons (custom roles, user groups, extra integration syncs) are $9/seat/month each, so a fully loaded seat can reach about $39. The Developer plan is free for 3 users, then $8/user, capped at 25 users. Audit logs are paywalled off the free tier — [Doppler pricing](https://www.doppler.com/pricing); [EnvManager (secondary)](https://envmanager.com/blog/doppler-pricing-alternatives)
- Bitwarden Secrets Manager: free for 2 users, 3 projects and 3 machine accounts. Teams is $6/user/month (20 machine accounts) and Enterprise $12/user/month (50 machine accounts), with extra machine accounts at $1 each — [Bitwarden help: SM plans](https://bitwarden.com/help/secrets-manager-plans/); [Capterra](https://www.capterra.com/p/10012844/Secrets-Manager/pricing/)
- 1Password Business is $8.99/user/month, annual billing only — [CloudEagle (secondary)](https://www.cloudeagle.ai/blogs/1password-pricing-guide)
- 1Password service accounts have hourly per-token limits and an account-wide daily limit (example given: 1,000 requests/day). A community thread complains of blocks of 15+ minutes with no backoff duration shown. 1Password Connect (a self-hosted cache) is the workaround for "unlimited requests" — [1Password dev docs: rate limits](https://www.1password.dev/service-accounts/rate-limits); [1Password Community thread](https://www.1password.community/developers-69/service-account-rate-limits-15-minutes-block-no-backoff-duration-shown-23967); [1Password secrets management](https://1password.com/features/secrets-management)
- Low-cost challengers are marketing directly against per-seat pricing, e.g. EnvManager at $9/month for a whole team with audit logs included — [EnvManager](https://envmanager.com/blog/doppler-pricing-alternatives). (Note: EnvManager is a competitor writing about competitors, so treat its framing as biased.)

**Adoption / popularity (GitHub stars, 2026-09-28):**
- hashicorp/vault 36,315; Infisical/infisical 29,477 (created Aug 2022, so fast growth); getsops/sops 23,234; dotenvx/dotenvx 5,815 (created Nov 2023); dotenv-org/dotenv-vault 1,246 (last push June 2025, apparently superseded by dotenvx); phasehq/console 925; bitwarden/sdk-sm 480 — GitHub API: [vault](https://github.com/hashicorp/vault), [infisical](https://github.com/Infisical/infisical), [sops](https://github.com/getsops/sops), [dotenvx](https://github.com/dotenvx/dotenvx), [dotenv-vault](https://github.com/dotenv-org/dotenv-vault), [phase](https://github.com/phasehq/console), [sdk-sm](https://github.com/bitwarden/sdk-sm)
- GitHub Actions secret-loader actions: hashicorp/vault-action 513, 1Password/load-secrets-action 346, bitwarden/sm-action 93, Infisical/secrets-action 82 stars. Even big vendors' CI actions have only modest star counts, so a revoked GH Action would not stand out by stars alone — GitHub API: [vault-action](https://github.com/hashicorp/vault-action), [load-secrets-action](https://github.com/1Password/load-secrets-action), [sm-action](https://github.com/bitwarden/sm-action), [secrets-action](https://github.com/Infisical/secrets-action)

**The "client owns the secret" pain (agency/contractor):**
- Upwork's guidance: the app owner should create and keep the key, and an agency that won't share production credentials should create a separate dev key for developers. This is a manual workaround — [Upwork Help](https://support.upwork.com/hc/en-us/articles/115015855747-How-API-key-ownership-and-sharing-works-on-Upwork)
- A 2024 dev.to post on sharing secrets with contractors and AI agents ranks current practice from fastest to safest: paste into Slack or a password manager and rotate on departure; `.env.example` plus values one at a time; scoped short-lived tokens; runtime injection. A commenter notes injection only helps if agent-controlled code can't read the value — [dev.to, Sept 2024](https://dev.to/ivannovazzi/how-do-you-share-secrets-with-contractors-and-ai-agents-5dh)
- Agency offboarding guides stress that removing the agency's user account can leave API tokens and shared links active, and that the only proof of revocation is failing to get in. They cite the figure that 64% of secrets leaked in 2022 were still valid years later — [DEV: agency access management 2026](https://dev.to/instarenewal/the-ultimate-guide-to-agency-access-management-moving-beyond-password-sharing-in-2026-hk8); [Chaser offboarding checklist](https://www.trychaser.com/checklist-articles/client-offboarding-checklist-for-agencies); [flatkey.ai](https://flatkey.ai/blog/ai-api-access-review)
- Common recommended practice for a short contractor engagement: create a scoped, expiring key, send it over a one-time link, and revoke at the end — [CYPH3RDROP](https://www.cyph3rdrop.com/learn/share-api-keys-safely); [API7](https://api7.ai/blog/share-api-keys-securely)
- 1Password Business includes 20 guest accounts for sharing vault items with contractors and auditors, and access can be revoked. This is the incumbent answer to cross-organisation sharing, but it requires the client to be on 1Password — [LastPass comparison blog (competitor source)](https://blog.lastpass.com/posts/lastpass-vs-1password-vs-bitwarden-small-businesses)
- AI agents are a fresh driver: the Ask HN "Do you trust AI agents with API keys / private keys?" (2026) and WorkOS guidance on agent secrets show the "hand a secret to a third party you may want to cut off" problem expanding — [HN](https://news.ycombinator.com/item?id=47736831); [WorkOS](https://workos.com/blog/ai-agent-secrets-management)

### Inferences
- Every incumbent assumes one organisation owns both the secret and the consumer. revoked's "the owner keeps it in their vault, the consumer reads the live value, the owner revokes" maps onto the agency/client and AI-agent cases, which today are solved by rotation plus manual discipline.
- Per-identity pricing (Infisical) and rate limits (1Password service accounts) are real complaints for small teams with many machine consumers. A self-hosted endpoint with ETag polling that bills nothing per consumer is a legitimate differentiator.
- As a first app, a CLI or GitHub Action (e.g. `revoked run -- cmd` / `uses: revoked/load-secret`) is cheap to build. But the category is saturated, stars for such actions are low even for big vendors, and trust barriers for a new secrets tool are high.
- It would have to be positioned narrowly: "let your client give your deploy pipeline their API key; they can see every read and cut you off."

### Gaps
- No quantitative survey found on how many agencies or freelancers need client-owned secrets. Evidence is qualitative (guides, advice posts).
- No original r/devops threads retrieved (Reddit is not directly searchable here). The complaints about Doppler/Infisical pricing come mainly from competitor blogs.
- GitHub Actions secrets limits and pricing were not researched in detail.

## 2. One-time secret sharing tools: popularity and what users ask for beyond one-time links

### Takeaway
One-time secret tools are a stable, moderately popular self-hosted niche (3k–9k stars each). The leader, Password Pusher, has already moved beyond one-time links into audit logs, teams, and "Requests" (collecting passwords from clients without an account), and it sells hosted plans at $25–$49/month. That validates revoked's "requests" concept commercially, but it also means revoked would be a late entrant to that exact feature. The "living" part (the value updates, the owner can revoke later) is what none of them offer: 1Password item links are explicitly snapshots.

### Cited Findings
- GitHub stars (2026-09-28): PrivateBin 8,633; pingvin-share 4,667 (last push May 2026); PasswordPusher 3,203; Yopass 3,155 (since 2014); OneTimeSecret 2,947 (since 2013) — GitHub API: [PrivateBin](https://github.com/PrivateBin/PrivateBin), [pingvin-share](https://github.com/stonith404/pingvin-share), [PasswordPusher](https://github.com/pglombardo/PasswordPusher), [yopass](https://github.com/jhaals/yopass), [onetimesecret](https://github.com/onetimesecret/onetimesecret)
- Yopass is used by organisations including Spotify, Doddle and Gumtree Australia; OneTimeSecret is positioned as enterprise-focused (API, compliance) — [dele.to comparison / Yopass repo](https://github.com/jhaals/yopass); [dele.to alternatives](https://dele.to/alternatives)
- Password Pusher offers time- or view-limited links with manual revoke and permanent audit logs showing who accessed what and when. Pricing: Free (no account), Premium $25/month (files, branding, custom domain, file requests), Pro $49/month (teams with 2 seats, white-label, SSO, policies), Self-Hosted Pro from $59/month for 5 users. It hosts both US and EU instances — [pwpush features](https://us.pwpush.com/features); [pwpush EU pricing](https://eu.pwpush.com/pricing)
- Password Pusher "Requests": send a link to collect passwords and credentials from clients through an encrypted form, with no account needed on their end; data is deleted after expiry — [pwpush requests](https://eu.pwpush.com/requests)
- 1Password item sharing produces a copy: "To change an item's details after you've already shared a copy, update the item then share a new link." Links can be restricted by email and deleted (revoked) — [1Password support](https://support.1password.com/share-items/)
- Bitwarden Send is a time-limited link for text or files, with expiry and access-count limits and no account required for the recipient — [Businesswire 2021 launch (older)](https://www.businesswire.com/news/home/20210315005067/en/Bitwarden-Delivers-New-Trusted-Way-to-Share-Sensitive-Data); [LastPass blog comparison](https://blog.lastpass.com/posts/lastpass-vs-1password-vs-bitwarden-small-businesses)
- The awesome-selfhosted "Pastebins" category already lists 21 entries, including Password Pusher, PrivateBin, Yopass, Hemmelig and 1time — [awesome-selfhosted README](https://github.com/awesome-selfhosted/awesome-selfhosted)

### Inferences
- The asks beyond one-time links that vendors have monetised are audit trails, team seats, branding/custom domains, file support, and collecting from others (requests). revoked has all of these plus live updates and cryptographic identity.
- Password Pusher's paid "Requests" and 1Password's snapshot limitation are the two cleanest comparison points for revoked's messaging: "a link that stays current and that you can still revoke after they've used it."
- pwpush's no-account request flow is a direct UX competitor. revoked deliberately requires an account to respond (CLAUDE.md invariant 12), which is more friction for one-off collection. The pitch must lean on "the responder keeps control", not on convenience.

### Gaps
- No usage figures (Docker pulls, MAU) found for Yopass, OneTimeSecret or pwpush. Docker Hub pulls were not retrieved.
- No aggregated "feature request" analysis from these projects' GitHub issues.

## 3. Self-hosted community signals and what makes a new project take off

### Takeaway
The self-hosted audience is large (r/selfhosted about 830k members; awesome-selfhosted 322k stars; 4,081 respondents to the 2025 selfh.st survey, most citing privacy as their main motivation), and leaders grow to tens of thousands of stars within 2–4 years (Immich 115k, Vaultwarden 68k, PocketBase 61k, Paperless-ngx 46k). A Show HN produces a sharp, roughly 24-hour star spike (median about 121 stars in 24h, 289 in a week, among projects that got HN exposure), and awesome-selfhosted won't list a project until its first release is 4+ months old. Launches that stack HN, Reddit and newsletters (selfh.st) in the same 48 hours are the documented pattern.

### Cited Findings
**Size of the audience and of the winners (stars, 2026-09-28, GitHub API):**
- awesome-selfhosted 322,396; open-webui 153,429; immich 115,207 (created Feb 2022); uptime-kuma 91,907; home-assistant/core 91,194; vaultwarden 68,259; memos 63,399; coolify 62,340; pocketbase 61,185 (the backend revoked uses); paperless-ngx 46,118 (Feb 2022); headscale 44,195; nextcloud/server 36,946; changedetection.io 34,629; homepage 32,896; karakeep 29,328 (created Feb 2024); dockge 24,463 (Oct 2023); firefly-iii 24,767; bitwarden/server 20,215; linkwarden 19,857; linkding 11,251; invoiceninja 10,126; pocket-id 9,308 (created Aug 2024); passbolt_api 6,142; Radicale 5,057; Baikal 3,326; davis 753 — [GitHub](https://github.com/awesome-selfhosted/awesome-selfhosted), [immich](https://github.com/immich-app/immich), [vaultwarden](https://github.com/dani-garcia/vaultwarden), [pocketbase](https://github.com/pocketbase/pocketbase), [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx), [karakeep](https://github.com/karakeep-app/karakeep), [pocket-id](https://github.com/pocket-id/pocket-id), [Radicale](https://github.com/Kozea/Radicale)
- r/selfhosted has about 823k members (Aug 2026, GummySearch) or about 839k (Sept 2026, Hive Index) — [GummySearch](https://gummysearch.com/r/selfhosted/); [Hive Index](https://thehiveindex.com/communities/r-selfhosted/)
- selfh.st 2025 Self-Host User Survey: 4,081 completed responses; Linux used by 81%; privacy cited as the main reason for self-hosting. Raw JSON is published on GitHub — [selfh.st results](https://selfh.st/survey/2025-results/); [Linuxiac](https://linuxiac.com/self-hosters-confirm-it-again-linux-dominates-the-homelab-os-space/)
- awesome-selfhosted categories relevant to revoked: Password Managers (AliasVault, Bitwarden, Passbolt, PassIt, Psono, Teampass, Vaultwarden), Pastebins (21 entries incl. Password Pusher, Yopass, PrivateBin), Calendar & Contacts (Baïkal, DAViCal, Davis, Keeper.sh, Manage My Damn Life, Radicale, SabreDAV, Xandikos), and File Transfer subcategories — [awesome-selfhosted README](https://raw.githubusercontent.com/awesome-selfhosted/awesome-selfhosted/master/README.md)
- awesome-selfhosted inclusion rule: "first release more than four months old", actively maintained, working install instructions. Projects inactive for 6–12 months may be removed — [awesome-selfhosted-data CONTRIBUTING](https://github.com/awesome-selfhosted/awesome-selfhosted-data/blob/master/CONTRIBUTING.md)
- Self-hosted family/file sharing tools pitched in the community: Pingvin Share (share confidential files with family; visitor limit and password), Share, SelfDrop — [dev.to Pingvin Share](https://dev.to/stonith404/pingvin-share-a-selfhosted-file-sharing-platform-2mb0); [Docker Hub ggtrd/share](https://hub.docker.com/r/ggtrd/share)

**Launch mechanics:**
- Show HN by the Numbers (188k posts, April 2026): a score of 50+ puts a post in the top 6%; the median Show HN scores 2. Each upvote brings about 1.4 GitHub stars within 48h. Score explains only about 8% of star variance (r=0.29). Category matters little. The best slot is Monday 00:00 UTC (10.8% reach 50+), the worst Thursday 06:00 UTC (2.6%). 92% of star gain happens within 48h — [Daniel King, 2026](https://danfking.github.io/blog/2026/04/23/show-hn-by-the-numbers/)
- arXiv study of 138 repo launches (2024–25): average +121 stars in 24h, +189 in 48h, +289 in a week after HN exposure — [arXiv 2511.04453](https://arxiv.org/abs/2511.04453)
- Stacking Show HN, Reddit and newsletter mentions within 24–48h can push a repo onto GitHub Trending, which compounds — [gingiris growth guide (secondary, marketing)](https://gingiris.github.io/growth-tools/blog/2026/04/14/github-stars-growth-guide/)
- ToolJet credits r/selfhosted with boosting its 2.0 launch (older, about 2022) — [dev.to ToolJet](https://dev.to/tooljet/how-tooljet-gained-20000-github-stars-and-400-contributors-4ee0)
- selfh.st publishes a weekly newsletter ("Self-Host Weekly") that covers new project launches, making it a distribution channel alongside Reddit — [selfh.st weekly](https://selfh.st/weekly/2026-01-02/)

### Inferences
- Winning self-hosted projects replace a specific, well-known SaaS (Google Photos becomes Immich, Bitwarden becomes Vaultwarden, Evernote/Pocket becomes memos/karakeep). revoked's abstract "living grants" pitch has no obvious SaaS to replace. A first app should frame it as "self-hosted X", e.g. "self-hosted HiHello/Popl" or "self-hosted Password Pusher that stays live".
- PocketBase's 61k stars and its community (PocketBase-based apps) are an adjacent audience worth mentioning in launch posts.
- A realistic 2–3 month plan: Docker one-liner, then a Show HN timed for Sunday evening US time, the same day an r/selfhosted post, and a selfh.st newsletter submission. Expect hundreds of stars, not thousands, unless the project hits the front page. The awesome-selfhosted listing arrives only after 4 months, so it is not a 2–3 month lever.

### Gaps
- r/selfhosted's current self-promotion and new-project posting rules (there are reported restrictions on new or AI-built project posts) could not be verified from here; check the subreddit sidebar before launching.
- Could not extract the per-app numbers from the selfh.st 2025 survey (charts are rendered client-side). The raw JSON is on GitHub but the API was rate-limited.

## 4. Integration ecosystems as distribution: which has the lowest barrier and largest reach for a solo developer?

### Takeaway
Home Assistant and n8n are the two ecosystems with both large self-hosted reach and low publishing barriers. Home Assistant is especially notable for a German developer: Germany is its #1 country (about 19% of 690k active installs). But custom integrations follow a long-tail distribution: the median HACS custom integration reports only about 20 installs, and only 268 of 4,282 exceed 1,000. n8n has 13k+ community packages on npm and a verification path to n8n Cloud, now requiring GitHub-Actions provenance. Zapier's public directory is closed to integrations you don't own (fine for revoked, since the developer owns it) but carries a review and 90-day beta. The WordPress.org review queue was about 4,700 plugins deep in Aug 2026, and Chrome Web Store reviews for broad-permission (autofill) extensions can take weeks.

### Cited Findings
**Home Assistant / HACS:**
- Home Assistant analytics (opt-in; used by about 77% of installs): 690,463 active installations reporting. Countries: DE 132,534 (19.2%), US 117,846, GB 38,381, NL 37,885, FR 36,849 — [analytics.home-assistant.io data.json](https://analytics.home-assistant.io/); [HA analytics integration docs](https://www.home-assistant.io/integrations/analytics/)
- Custom-integration analytics: 4,282 custom integrations reported. HACS itself is on 391,686 installs. Top custom integrations: sonoff 44,881, localtuya 33,010, alexa_media 29,681, frigate 28,035, waste_collection_schedule 25,067. Median custom integration 20 installs; 1,153 have ≥100 and 268 have ≥1,000. Among calendar-feed custom integrations, ics_calendar has 1,782 and ical 661 — [analytics.home-assistant.io/custom_integrations.json](https://analytics.home-assistant.io/custom_integrations.json)
- There are no Bitwarden, Vaultwarden, 1Password, Infisical or Doppler custom integrations among reported custom integrations. A community "immich" integration has 143 installs and "paperless_ngx" has 6 — [custom_integrations.json](https://analytics.home-assistant.io/custom_integrations.json)
- HACS publishing requires a public GitHub repo with a description, one integration per repo under `custom_components/<name>/`, a manifest.json, brand assets (icon.png) and a full GitHub release; then a PR adds it to hacs/default. Users can also add any repo as a "custom repository" immediately, with no review — [HACS: integration requirements](https://www.hacs.xyz/docs/publish/integration/); [HACS: include default](https://www.hacs.xyz/docs/publish/include/); [HACS: custom repositories](https://www.hacs.xyz/docs/faq/custom_repositories/)
- There are "over 1,500 custom integrations available through HACS" (secondary, 2026) — [HomeShift guide](https://joinhomeshift.com/home-assistant-hacs)

**n8n:**
- n8n: 206,190 GitHub stars — [GitHub](https://github.com/n8n-io/n8n)
- npm packages tagged `n8n-community-node-package`: 13,171 (live npm registry search, 2026-09-28). This contradicts a secondary 2026 blog claiming "500+" packages and a July 2025 figure of about 2,000 packages / 8M downloads. The live npm count is the authoritative one, and it shows the count has grown very fast — [npm registry search](https://www.npmjs.com/search?q=keywords:n8n-community-node-package); [openhosst (secondary)](https://openhosst.com/blog/n8n-community-nodes)
- Unverified community nodes install from npm on self-hosted n8n only. Verified nodes are discoverable in the node panel on both self-hosted and n8n Cloud (Cloud launched with about 25 verified nodes) — [n8n docs: install verified](https://docs.n8n.io/integrations/community-nodes/installation/verified-install/); [n8n blog](https://blog.n8n.io/community-nodes-available-on-n8n-cloud/)
- Verification requirements: no runtime dependencies, README docs, technical guidelines. From 1 May 2026, nodes must be published via GitHub Actions with an npm provenance statement (`@n8n/node-cli` ≥ 0.23.0) — [n8n docs: submit community nodes](https://docs.n8n.io/integrations/creating-nodes/deploy/submit-community-nodes/); [verification guidelines](https://docs.n8n.io/integrations/creating-nodes/build/reference/verification-guidelines/); [n8n-nodes-starter](https://github.com/n8n-io/n8n-nodes-starter)

**Zapier:**
- A public App Directory listing requires HTTPS on every endpoint, English only, OAuth or API-key auth, tested triggers and actions, and platform agreement compliance. Review responses come within about a week, and new integrations launch with a Beta tag lasting 90 days. Non-owners of the underlying app can only publish private/invite-only integrations — [Zapier publishing requirements](https://docs.zapier.com/integrations/publish/integration-publishing-requirements); [GolmTech (secondary)](https://golmtech.solutions/blog/how-to-publish-your-app-on-zapier/)

**WordPress.org:**
- The plugin review queue peaked at about 1,050 in mid-April 2026, was cleared to near zero, then rose to 5,127 (24 Aug) and 4,715 (31 Aug 2026), with about 3,850+ plugins older than 7 days. From 18 Sept 2026 every plugin release waits 6 hours for an automated security review — [Make WordPress Plugins, June 2026](https://make.wordpress.org/plugins/2026/06/13/update-on-the-status-of-the-team-june-2026/); [Plugins Team 31 Aug 2026](https://make.wordpress.org/updates/2026/08/31/plugins-team-31-aug-2026/); [Plugins Team 24 Aug 2026](https://make.wordpress.org/updates/2026/08/24/plugins-team-24-aug-2026/); [wpnews](https://www.wpnews.io/wordpress-org-plugin-release-cooldown-and-security-review/)

**Browser extensions:**
- Chrome Web Store: a first submission typically takes 2–5 business days. Broad host permissions (which a form-autofill extension needs) trigger manual review of up to several weeks. Manifest V2 is rejected entirely in 2026, and 2026 brought extended review times from record submission volume — [Chrome for Developers: CWS review updates 2026](https://developer.chrome.com/blog/cws-review-updates-2026); [CWS review process](https://developer.chrome.com/docs/webstore/review-process); [MetaDesign (secondary)](https://metadesignsolutions.com/blog/chrome-extension-web-store-submission-guide)

**Other ecosystems (stars only):**
- Invoice Ninja 10,126; Paperless-ngx 46,118; Nextcloud server 36,946 — [invoiceninja](https://github.com/invoiceninja/invoiceninja); [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx); [nextcloud](https://github.com/nextcloud/server)

### Inferences
- Lowest barrier: n8n (npm publish means instant availability on every self-hosted n8n) and HACS (installable as a custom repository immediately). Both are review-free for the unverified path.
- Largest reach: n8n (206k stars, very high community-node activity) and Home Assistant (690k+ installs, Germany-heavy).
- Slowest: WordPress (queue of several weeks), the Chrome Web Store (autofill permissions mean manual review) and Zapier (review plus 90-day beta).
- n8n fits revoked's primitives unusually well:
  - a "revoked trigger" can fire on a request response or grant change (revoked already has webhook callbacks);
  - a "get live value" node can read a grant with ETag;
  - a "create request" action can collect data from a customer inside a workflow.
  - This turns revoked into a credential/data source for automations that the data owner can revoke.
- For Home Assistant the natural fit is a sensor or calendar fed by a revoked grant (iCal/JSON), e.g. a family member shares a live value (location note, Wi-Fi guest password, shift calendar). But the long-tail install data (median 20) suggests a HA integration will not by itself create traction unless it solves a very common household need.

### Gaps
- No install/usage stats per n8n community node (npm downloads API rate-limited). Could not rank which node categories get the most adoption.
- Nextcloud app store, Paperless-ngx and Invoice Ninja integration or plugin marketplaces were not researched in detail (time budget).
- Make.com custom app publishing requirements were not researched.

## 5. "Sign in with X"-style buttons for data (Plaid Link, Autofill with Google, Shop Pay, Stripe Link, Apple contact sharing): how they drive two-sided adoption; open-source equivalents?

### Takeaway
Consented data-sharing buttons succeed when one side of the network is already huge before the button reaches the other side: Stripe Link reaches 200M+ consumers and ships default-on inside Stripe Checkout. No open-source, self-hostable equivalent of Plaid Link or Link for general personal data turned up. In the EU, the state-backed EUDI Wallet (Germany's "d-you" launching 2 Jan 2027) is about to become the standardised "share verified attributes with a website" button. That is both a threat and an interoperability opportunity for a "Fill with Revoked" button.

### Cited Findings
- Stripe Link: reaches 200M+ consumers (network reach 300M+). It autofills payment details, lifting conversion by over 7% for logged-in users and returning-user conversion by an average of 14%, with checkout 3x faster. Once saved, a user can pay at any Stripe-powered checkout with one click plus a phone code — [Stripe Link](https://stripe.com/payments/link); [Stripe docs: Link](https://docs.stripe.com/payments/link)
- Plaid's alternatives are other commercial aggregators (Akoya, Basiq, Flinks, Codat). None are open-source consent buttons — [Open Banking Tracker](https://www.openbankingtracker.com/embedded-finance/plaid/alternatives); [Plaid blog on permissioned access](https://plaid.com/blog/open-finance-trust-security/)
- EUDI Wallet in Germany: named "d-you", announced 9 Sept 2026, with a planned free-app launch on 2 Jan 2027 and about 40 partners at launch. The SPRIND sandbox (opened Jan 2026) had about 115 organisations and about 150 use cases after six months. Relying parties may request only attributes they have registered with a declared purpose, and the wallet warns users about over-asking. The cabinet draft of the German Digital Identity Act (20 May 2026) prohibits numerical caps on independently developed recognised wallets — [Corbado](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026); [walt.id](https://walt.id/eidas2/eudi-wallet); [Freshfields](https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/the-eudi-wallet-is-coming-what-businesses-need-to-know-102mvuy); [Wikipedia](https://en.wikipedia.org/wiki/EU_Digital_Identity_Wallet)

### Inferences
- Two-sided buttons bootstrap by bundling the button into a platform that merchants already use (Stripe Checkout, Shopify). A solo developer cannot replicate that. The realistic bootstrap for "Fill with Revoked" is to target a context where one party already controls both sides: an agency onboarding its own clients, a club collecting member data, a landlord collecting tenant data. There the requester deploys revoked and invites responders.
- The EUDI Wallet will own "verified identity attributes" in the EU from 2027. revoked should position "Fill with Revoked" for unverified, self-asserted, changeable data (addresses, contact details, preferences, API keys) that stays live and revocable, which EUDI does not cover, rather than compete with it.

### Gaps
- No usage data found for Google "Autofill with Google", Shop Pay or Apple contact sharing as data-sharing primitives. No open-source "data consent button" project found (absence of evidence from limited searching, not proof).
- The EUDI Wallet's support for ongoing (living) data access versus one-time presentation was not verified.

## 6. Contact sharing: demand for self-updating contact cards; does a revocable, live vCard/CardDAV feed have an audience?

### Takeaway
Digital business cards are a proven paid market: Popl claims 2M+ users, and prices run about $5–10/user/month. Their core selling point is exactly "details update instantly". But these vendors now compete on team lead-capture and CRM sync, and their "live update" works only while the recipient opens the web card, not in the recipient's address book. Self-hosted CardDAV servers (Radicale, Baikal, Davis, Nextcloud) cover same-server shared address books. None found offers a cross-person, revocable "subscribe to my contact card" feed. That gap is revoked's clearest unique capability, but consumer demand evidence is thin and anecdotal.

### Cited Findings
- Popl: "2M+ happy users worldwide across 150+ countries"; also claims 2.5M professionals across 90% of the Fortune 500 (vendor claims). It now positions itself as an "AI GTM platform for event lead capture" with badge scanning and CRM integrations. Individual Pro about $7.99/month; teams billed per member plus per badge scan — [Popl](https://popl.co/); [Popl digital business card](https://popl.co/pages/digital-business-card); [Blinq comparison (competitor source)](https://blinq.me/blog/comparing-costs-of-digital-business-card-platforms)
- HiHello: free for individuals; Professional/Business about $5–6/month. Blinq: Premium from $9.99/month, Business from $4.99–6.99 per user/month with a 5-card minimum (figures from Blinq's own comparison, so potentially biased) — [Blinq: HiHello alternatives](https://blinq.me/blog/best-hihello-digital-business-card-alternatives); [KadiConnect comparison 2026](https://kadiconnect.com/blog/kadiconnect-vs-popl-blinq-hihello-2026)
- Claim: 37% of small businesses and 23% of individuals use digital business cards (vendor-sourced statistic; origin unverified) — [Blinq](https://blinq.me/blog/comparing-costs-of-digital-business-card-platforms)
- Digital business cards "update instantly, so everyone who opens it from that moment on saves your latest details", unlike a static vCard file. This confirms the update reaches only people who reopen the card — [businesscards.io](https://businesscards.io/features/vcard)
- Project vCard markets automatic address-book updates when you change your own details, and a published patent describes subscribing to a business card for update notifications. Prior attempts exist but none surfaced as mainstream — [vcard.com](https://vcard.com/); [EPO patent EP2222056](https://data.epo.org/publication-server/rest/v1.2/patents/EP2222056NWA1/document.html)
- An Apple Community thread asks whether a shared contact card updates automatically (it doesn't; Apple contact sharing is a snapshot) — [Apple Community](https://discussions.apple.com/thread/254418537)
- Self-hosted CardDAV: Nextcloud ships a CardDAV backend with shareable address books; Radicale supports shared address books via ACLs; Baikal/Nextcloud have admin UIs for sharing between users; DAVx5 syncs to Android contacts. All of these share within one server's user base — [Nextcloud admin manual](https://docs.nextcloud.com/server/stable/admin_manual/groupware/contacts.html); [selfhosting.sh](https://selfhosting.sh/replace/google-contacts/); [GrapheneOS forum](https://discuss.grapheneos.org/d/24286-self-hosted-carddav-server-for-synchronising-contacts-via-davx5)
- CardDAV server projects are modest in stars: Radicale 5,057; Baikal 3,326; Davis 753 — GitHub API: [Radicale](https://github.com/Kozea/Radicale), [Baikal](https://github.com/sabre-io/Baikal), [Davis](https://github.com/tchapi/davis)
- Home Assistant's calendar-feed integrations show a modest but real live-feed appetite: ics_calendar 1,782 and ical 661 installs. The German-origin waste_collection_schedule integration, which pulls municipal feeds, has 25,067 — [HA custom_integrations.json](https://analytics.home-assistant.io/custom_integrations.json)

### Inferences
- A "self-hosted HiHello/Popl, but the contact actually updates in their phone (CardDAV) and you can revoke it" is a concrete, easy-to-explain first app. It uses revoked primitives that already exist (vCard, CardDAV live contacts, revocable links) and maps to a known SaaS category with visible pricing to undercut. That matches the "self-hosted X" pattern that wins on r/selfhosted.
- Main risk: the recipient must add a CardDAV account (DAVx5 on Android; iOS Settings → Contacts → Accounts), which is heavy friction for non-technical recipients. Business-card vendors deliberately avoided this in favour of web cards. The audience is therefore self-hosters, freelancers and privacy-conscious professionals, not mass market.
- The German/EU angle is favourable: GDPR-minded professionals and the Germany-heavy self-hosted/Home Assistant population. Revocability matters when someone leaves a job or ends a client relationship.

### Gaps
- No quantitative evidence of demand for subscribable or revocable contact feeds specifically (no survey or issue counts found).
- No data on HiHello or Blinq user counts beyond vendor claims; no independent market-size data.
- iOS's current support for adding arbitrary CardDAV accounts from a link or profile (to reduce friction) was not verified.

## 7. Which would give the quickest measurable traction (stars, installs, paying users) in about 2–3 months?

### Takeaway
On the evidence, the fastest measurable path is:
1. **An n8n community node**, published to npm (instant availability on self-hosted n8n), then submitted for verification. It has the biggest active integration ecosystem and zero review for the unverified path, and it matches revoked's webhook/request/live-read primitives.
2. **A "self-hosted live business card / contact feed" framing**, launched via Show HN plus r/selfhosted plus the selfh.st newsletter in one 48-hour window. It is the most differentiated story for star traction.
3. A Home Assistant (HACS) integration as a cheap secondary channel aimed at the Germany-heavy HA base, with low expected installs.

WordPress plugins, Chrome autofill extensions and Zapier are slower because of review queues, and a general secrets-manager CLI or GitHub Action enters a saturated, low-star category.

### Cited Findings
- Show HN launch outcomes: about +121 stars/24h, +289/week on average among HN-exposed repos; a 50+ score is the top 6% — [arXiv 2511.04453](https://arxiv.org/abs/2511.04453); [Show HN by the Numbers](https://danfking.github.io/blog/2026/04/23/show-hn-by-the-numbers/)
- n8n: npm community packages 13,171; publish is instant via npm; verified nodes need GitHub Actions provenance (since May 2026) — [npm search](https://www.npmjs.com/search?q=keywords:n8n-community-node-package); [n8n docs](https://docs.n8n.io/integrations/creating-nodes/deploy/submit-community-nodes/)
- HACS: median custom integration 20 installs; 268 of 4,282 exceed 1,000; Germany is 19% of HA installs — [HA analytics](https://analytics.home-assistant.io/custom_integrations.json)
- WordPress queue about 4,700 (Aug 2026); Chrome broad-permission review up to several weeks; Zapier 90-day beta — [Make WordPress](https://make.wordpress.org/updates/2026/08/31/plugins-team-31-aug-2026/); [Chrome docs](https://developer.chrome.com/docs/webstore/review-process); [Zapier docs](https://docs.zapier.com/integrations/publish/integration-publishing-requirements)
- Paying-user benchmark: Password Pusher monetises exactly the "share and collect secrets with audit logs" niche at $25–$59/month — [pwpush pricing](https://eu.pwpush.com/pricing)
- awesome-selfhosted listing requires the first release to be 4+ months old, so it cannot help inside a 2–3 month window unless a release is already tagged and aging — [awesome-selfhosted-data CONTRIBUTING](https://github.com/awesome-selfhosted/awesome-selfhosted-data/blob/master/CONTRIBUTING.md)

### Inferences
- Measurable 2–3 month targets that seem realistic from the benchmarks: a few hundred GitHub stars from a well-timed Show HN and Reddit launch, tens of npm installs for an n8n node, and tens (not hundreds) of HACS installs. Paying users are most plausible from the agency/freelancer "collect client credentials that stay live and revocable" use case, benchmarked against Password Pusher's $25–49/month tiers.
- Tag a release now so the awesome-selfhosted 4-month clock starts running.

### Gaps
- No direct evidence comparing time-to-first-users across these channels for a comparable project. The ranking above is inferred from barrier and reach data, not measured outcomes.
