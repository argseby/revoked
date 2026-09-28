# Client onboarding and credential/access handoff between service providers and clients (as of Sept 2026)

Scope note: research done 2026-09-28 with a limited budget of about 16 search/fetch calls. Most figures come from vendor pages, trade press and review aggregators surfaced by search snippets. Only a few primary pages were fetched in full (the DATEV Community thread returned HTTP 403). Items not verified are listed under Gaps rather than stated as fact.

## 1. How agencies and freelancers collect client data and access today: tools, prices, gaps

### Takeaway
The market is split into three tool families, and none of them does the whole job. (a) OAuth/partner-API "access request" tools (Leadsie, AgencyAccess, ClientInvite) are priced at about $59–129/mo and cover only ad/analytics/e-commerce platforms that have partner-access APIs. (b) Form and content collectors (Content Snare, Dubsado, HoneyBook, Moxie, Typeform/Jotform/Tally) cost about $12–258/mo and turn secrets into static form answers stored by the requester. (c) Password managers and one-time-secret tools (1Password, Bitwarden Send, etc.) cost about $4–8/user/mo. These move a secret but give no structured request, no template, no verification of who is asking and no tie back to an engagement. Nothing in the evidence found combines a templated request, a responder-owned revocable answer and a verified requester for arbitrary logins/keys/DNS/CMS credentials.

### Cited Findings
**Leadsie (partner-access requests)**
- Starter plan is $59/mo for up to 3 new client onboardings/month plus 10 prospect audits. Agency plan is $129/mo. Overage is $50 per 3 onboarding credits on Starter and $50 per 5 credits on Agency. There is a 30-day money-back guarantee. — [Leadsie pricing](https://www.leadsie.com/pricing); [Leadsie KB pricing](https://help.leadsie.com/article/96-leadsie-pricing)
- Leadsie requests manage or view-only access to 31 account/asset types across Meta, Google and 14 more platforms (Shopify, LinkedIn, X, TikTok). The agency is added as a partner business or authorised user, so no passwords are shared. Access "won't expire unless you remove it or your client revokes it". — [Leadsie](https://www.leadsie.com/) (via search summary)
- Flow: the agency builds a request link, the client opens it, follows the guided steps and grants permissions. Links are reusable and unlimited. — [Leadsie agencies](https://www.leadsie.com/agencies)
- Competitors in the same niche include AgencyAccess, which offers "a single branded link for clients to connect advertising, analytics, and ecommerce accounts … using official platform APIs without storing usernames or passwords", and ClientInvite. — [AgencyAccess on Capterra](https://www.capterra.com/p/10014213/AgencyAcess/); [AgencyAccess vs Leadsie](https://www.agencyaccess.co/blog/agencyaccess-vs-leadsie-which-client-onboarding-tool-is-right-for-your-agency); [ClientInvite blog](https://clientinvite.com/blog/leadsie-vs-clientinvite-the-better-choice-for-agencies)

**Content/data collectors**
- Content Snare costs $35/mo (Basic, annual billing: 20 active requests, 2 users, 20 GB) up to $215+/mo (Custom, 200+ active requests). Monthly billing is $42–$258+. Pricing is based on the number of *active requests* in flight, with unlimited clients, about a 20% annual discount and a free trial. — [Portico: Content Snare pricing explained (2026)](https://www.portico.run/blog/post/content-snare-pricing); [Capterra pricing](https://www.capterra.com/p/167019/Content-Snare/pricing/)
- HoneyBook costs $36–$129/mo (Starter/Essentials/Premium), or $29–$109/mo billed yearly. Starter includes 2 lead forms, 1 contact form and 1 scheduler form. — [taskip: HoneyBook pricing 2026](https://taskip.net/honeybook-pricing/)
- Dubsado has two tiers: Starter at $20/mo (limited to 3 projects) and Premier at $40/mo (unlimited). Its portal ties contracts, invoices, forms and files to a project. — [Assembly: Dubsado vs HoneyBook 2026](https://assembly.com/blog/dubsado-vs-honeybook)
- Moxie costs $12–40/mo flat across three tiers. — [Plutio: Moxie vs Dubsado 2026](https://www.plutio.com/compare/moxie-vs-dubsado) (a competitor's comparison page, so treat it with some caution)

**Password managers and secret sharing**
- Bitwarden Teams costs $4/user/mo. Bitwarden Send shares text or files through an expiring, self-deleting link. Sending files needs Premium ($19.80/yr) or a paid organisation seat. — [costbench: Bitwarden pricing 2026](https://costbench.com/software/password-management/bitwarden/); [tech-insider: Bitwarden Send setup 2026](https://tech-insider.org/ca/bitwarden-send-setup-2026/)
- 1Password Business lets members share items with anyone outside the account by link ("anyone with the link can view the item"), and admins control the sharing settings. — [1Password Support: manage item sharing](https://support.1password.com/manage-item-sharing/)
- 1Password Teams: one source gives $24.95/mo flat (Teams Starter Pack) and also a per-user figure. The two numbers could not be reconciled from the snippet. — [usecarly: 1Password pricing 2026](https://www.usecarly.com/blog/1password-pricing/)
- TeamPassword markets itself to digital-marketing agencies for sharing client logins. It claims to save "120 minutes on average" per staff/client onboarding (vendor claim). — [AlternativeTo: TeamPassword](https://alternativeto.net/software/teampassword/about)

**Pain descriptions**
- Informal credential handoff is described as "sticky notes, spreadsheets titled 'passwords', … Slack or email". This comes from a 2026 dev.to vendor-style guide, not a survey. — [dev.to: Agency access management 2026](https://dev.to/instarenewal/the-ultimate-guide-to-agency-access-management-moving-beyond-password-sharing-in-2026-hk8)
- The same article cites a claim that 82% of intrusions detected in 2025 involved no malware and that attackers "simply logged in" with valid credentials. This is a secondary citation, and the primary source (likely the CrowdStrike Threat Hunting/Global Threat Report) was not verified. — [dev.to](https://dev.to/instarenewal/the-ultimate-guide-to-agency-access-management-moving-beyond-password-sharing-in-2026-hk8)

### Inferences
- The partner-API tools prove that agencies will pay $59–129/mo just to avoid chasing access. The pricing unit is also useful as a benchmark: Leadsie charges per *onboarding*, Content Snare per *active request*. A requests-based product can copy that metering directly.
- Leadsie's model depends on platforms offering delegated access (Meta Business Manager, Google partner links). The long tail has no such API: WordPress/CMS admin logins, hosting/cPanel, domain registrar and DNS access, SaaS API keys, FTP/SSH, Wi‑Fi and alarm codes (MSPs). That is exactly where credentials still travel by email or form, and where "revoked" (a responder-held, revocable, current-value grant) fits.
- Form tools (Content Snare, Typeform, etc.) store answers as copies on the requester's side. The client cannot revoke them at the end of the engagement, and a rotated password is not reflected. This is the concrete gap that "living grants" address.
- Leadsie's own wording that access "won't expire unless you remove it or your client revokes it" admits the offboarding problem: nothing in the partner-access model expires by default.

### Gaps
- No Reddit (r/agency, r/freelance, r/msp) threads or G2/Capterra review texts were fetched, so no direct user complaint quotes are available. Search did not surface them within budget.
- AgencyAccess, ClientInvite, Keeper, LastPass, Passbolt, Typeform/Jotform/Tally and Yopass/PrivateBin/OneTimeSecret pricing was not verified in this session.
- 1Password's exact 2026 Business/Teams per-user price and whether its item-share links expire or are view-limited were not confirmed.

## 2. The offboarding problem: access not revoked when engagements end

### Takeaway
There is strong, recent evidence that third-party and ex-insider access is a leading breach vector. Verizon's 2025 DBIR says third-party involvement in breaches doubled from 15% to 30%. A 2025 Ponemon/Imprivata study found 47% of organisations had a breach involving third-party network access in the past 12 months. Ex-employee access surveys consistently put lingering access at about 25–50%.

### Cited Findings
- Verizon DBIR 2025: third-party involvement in breaches doubled from 15% to 30% year over year. The dataset was 22,052 incidents and 12,195 confirmed breaches across 139 countries, covering Nov 1 2023 to Oct 31 2024. — [Verizon news release](https://www.verizon.com/about/news/2025-data-breach-investigations-report); [ASIS summary](https://www.asisonline.org/security-management-magazine/latest-news/today-in-security/2025/april/verizon-dbir-2025/); [DBIR 2025 PDF](https://www.verizon.com/business/resources/T16f/reports/2025-dbir-data-breach-investigations-report.pdf)
- DBIR 2025 also reports ransomware in 44% of breaches and a 34% rise in vulnerability exploitation as an initial vector. Credential abuse remains the top vector per commentary. — [Verizon news release](https://www.verizon.com/about/news/2025-data-breach-investigations-report); [Descope DBIR 2025 analysis](https://www.descope.com/blog/post/dbir-2025)
- Ponemon/Imprivata (2025) surveyed 1,942 IT/security practitioners in the US, UK, **Germany** and Australia. 47% had a breach or cyberattack in the past 12 months involving a third party accessing their network. 34% said the cause was a third party having too much privileged access. — [Ponemon-Sullivan report, Mar 2025](https://ponemonsullivanreport.com/2025/03/creating-a-cybersecurity-infrastructure-to-reduce-third-party-and-privileged-internal-access-risks-a-global-study/); [Imprivata 2025 Ponemon report](https://www.imprivata.com/2025-ponemon-report); [Imprivata press](https://www.imprivata.com/company/press/imprivata-study-finds-nearly-half-organizations-suffered-third-party-security)
- Same study: organisations share sensitive data with an average of 583 third parties, but only 34% keep a comprehensive inventory of those relationships. 69% blame the lack of centralised control. — [Ponemon-Sullivan report](https://ponemonsullivanreport.com/2025/03/creating-a-cybersecurity-infrastructure-to-reduce-third-party-and-privileged-internal-access-risks-a-global-study/)
- Older data (2021): 51% of organisations had experienced a breach caused by a third party (SecureLink/Ponemon). — [GlobeNewswire, May 2021](https://www.globenewswire.com/en/news-release/2021/05/04/2222054/0/en/51-of-Organizations-Have-Experienced-a-Data-Breach-Caused-by-a-Third-party-New-Report-Finds.html)
- Ex-employee access. PasswordManager.com surveyed 1,000 US workers: 47% said they still used a former employer's passwords after leaving. Of those, 58% said the passwords were never changed, 44% said a current employee shared them and 6.2% guessed them. — [PasswordManager.com](https://www.passwordmanager.com/47-of-workers-admit-to-hacking-accounts-with-former-employers-passwords/); [MSSP Alert](https://www.msspalert.com/news/nearly-half-of-workers-pilfer-former-employers-passwords-to-access-accounts-study-says) (undated in snippet; likely 2022, treat as older)
- Beyond Identity found about 1 in 4 ex-employees still have access to former workplace accounts. — [LeadingIT summary](https://goleadingit.com/1-in-4-ex-employees-still-has-access-to-company-data/); [LinkedIn](https://www.linkedin.com/pulse/1-4-ex-employees-still-has-access-company-data-stephen-taylor) (secondary; Beyond Identity original ~2022)
- OneLogin research (older, around 2018): 48% of respondents knew of ex-employees who still had access to corporate apps, and 50% of IT decision-makers said ex-employee accounts stayed active more than a day after departure. — [OneLogin press release](https://www.onelogin.com/press-center/press-releases/new-research-from-onelogin-finds-over-50-of-ex-employees-still-have-access-to-corporate-applications)
- A Beyond Identity figure that 56% of ex-employees with continued access used it to harm a former employer, and 24% intentionally kept a password, is reported by secondary sources. — [HRD America](https://www.hcamag.com/us/specialization/employment-law/many-ex-employees-still-accessing-employer-accounts/443129)

### Inferences
- The shared-secret handoff (a client gives an agency its CMS/DNS login) is the external version of the "password never changed after departure" failure. 58% of lingering ex-employee access came from passwords that were never rotated. A grant that the owner revokes centrally, or that auto-expires, removes the "remember to change it" step.
- Ponemon's "only 34% keep an inventory of third parties" statistic supports a "who has what" dashboard on the data owner's side as a selling point, separate from the request flow.
- Caveat: DBIR's "third-party" category includes software supply chain and service-provider compromise (Change Healthcare, CDK, Blue Yonder), not just contractor credentials. Do not claim that 30% of breaches come from un-revoked freelancer logins.

### Gaps
- No 2025/2026 SecureLink or Ponemon study specifically quantified "orphaned contractor access after engagement end" in SMBs.
- No German-specific survey on un-revoked access of Steuerberater, agencies or IT-Dienstleister was found.

## 3. German Steuerberater / Mandanten onboarding

### Takeaway
DATEV dominates the market and already offers a digital intake flow: DATEV Mandatsanbahnung (onboarding module), DATEV Meine Steuern (€3 per client per assessment year) and Unternehmen online. Practitioners report the pieces are siloed, too complex for many clients, collect only master data and still need print-sign-scan for mandate documents. This is a real but DATEV-locked niche. A standalone tool competes with DATEV's ecosystem integration, and Kanzleien choose tools by DATEV compatibility.

### Cited Findings
- With DATEV Mandatsanbahnung (DATEV Onboarding), a firm defines which master data, documents and custom questionnaires it needs from a prospect and requests them digitally. The prospect registers with a DATEV account, enters the data, can edit it several times and submits it. The firm gets email notifications. The new client can then be created in DATEV Basisdaten online, which syncs to the DATEV workplace. — [DATEV Mandatsanbahnung](https://www.datev.de/web/de/loesungen/steuerberater/kanzleimanagement/marketing/datev-mandatsanbahnung/); [DATEV: Mandate digital anbahnen](https://www.datev.de/web/de/steuerberatung/loesungen/kanzleimanagement/kanzleiprozesse-optimieren-und-steuern/mandanten-digital-anbahnen); [DATEV: Mandat anlegen](https://www.datev.de/web/de/steuerberatung/loesungen/kanzleimanagement/kanzleiprozesse-optimieren-und-steuern/mandanten-digital-anbahnen/ein-mandat-anlegen)
- Limitations reported in DATEV Community discussions, as summarised by the search engine (the thread itself returned 403): DATEV Onboarding collects only master data, all documents (such as the mandate/Vollmacht) still have to be printed, signed and scanned, and there is no automatic sync between client management and master data. — [DATEV-Community: Stammdaten digitaler Prozess](https://www.datev-community.de/t5/Office-Management/Stammdaten-von-Mandanten-digitaler-und-effizienter-Prozess/td-p/349634); [DATEV-Community: Onboarding](https://www.datev-community.de/t5/Office-Management/Onboarding/td-p/484808?nobounce)
- DATEV Meine Steuern costs €3.00 per client (Ordnungsbegriff) per assessment year. Clients upload receipts via web or the DATEV Upload mobil app. — [DATEV Meine Steuern](https://www.datev.de/web/de/steuerberatung/loesungen/steuern/dokumente-und-daten-digital-erhalten/datev-meine-steuern); [DATEV FAQ 1008324](https://wissensplattform.apps.datev.de/help/document/1008324)
- Practitioner criticism: Meine Steuern is powerful but "too complex for many clients". Some firms would rather receive receipts by email if they must be downloaded and re-uploaded anyway. Silo software and its costs are a major complaint. — [DATEV-Community: Kosteneinsparung über Meine Steuern](https://www.datev-community.de/t5/Unternehmen-online/Kosteneinsparung-kleine-Buchhaltungen-%C3%BCber-Meine-Steuern/td-p/385521); [milia.io: DATEV Unternehmen online zu teuer?](https://milia.io/blog/datev-unternehmen-online-zu-teuer-wann-belege-online-plus-plattform-die-bessere-wahl-ist) (milia is a competing vendor)
- Third-party Mandantenportale and onboarding checklists exist and a 2026 comparison market is visible (e.g. Taxaro's "Mandantenportale im Vergleich 2026" and "Digitales Mandanten-Onboarding" guides). — [Taxaro: Mandantenportal-Vergleich 2026](https://taxaro.de/wissen/mandantenportal-vergleich); [Taxaro: Digitales Mandanten-Onboarding](https://taxaro.de/wissen/digitales-mandanten-onboarding-kanzlei)
- The "Fragebogen zur steuerlichen Erfassung" (tax registration questionnaire for new businesses) is commonly submitted by the Steuerberater via DATEV/ELSTER. It is a typical onboarding artefact needing tax IDs, bank details and business data from the client. — [onlinebilanz.de](https://onlinebilanz.de/fragebogen-steuerliche-erfassung-datev-steuerberater/)

### Inferences
- The Steuerberater segment is DATEV-gravity-bound. Any tool that does not push Stammdaten into DATEV (Basisdaten online) creates re-typing, which is the exact complaint above. A solo developer would need a DATEV Marketplace/API integration to be credible, which is a significant barrier.
- The requester in this context must retain data (tax retention duties under AO §147 / HGB §257, typically 6–10 years, plus GoBD immutability). A "living, revocable" grant of Stammdaten therefore conflicts with the Kanzlei's need for a frozen, auditable copy. The Kanzlei will snapshot anyway. Revocable sharing is more valuable for *access credentials* (ELSTER certificates? no, those are personal; better bank-portal or online-shop logins for bookkeeping) and for *the client's view of what their advisor holds* than for tax master data. (The retention-law detail is from general knowledge and was not sourced in this session. Verify before use.)
- The anti-phishing angle is strong here, because the fake requests that circulate impersonate ELSTER/Finanzamt and ask exactly for Steuer-ID and IBAN (see section 4).

### Gaps
- No Steuerberaterkammer/BStBK publication on onboarding pain or secure data exchange was retrieved.
- No GoBD text was fetched. The claim that GoBD/AO retention cuts against revocable sharing is an unsourced inference.
- DATEV Mandatsanbahnung and Unternehmen online prices were not found.

## 4. Phishing around data requests: the value of a verified requester

### Takeaway
Fake data requests that impersonate authorities and service providers are a live, large-scale problem in 2026. Verbraucherzentrale reports recurring ELSTER phishing waves in 2026 that ask for Steuer-ID, date of birth and IBAN, including one starting 11 Sept 2026. The FBI IC3 2025 report puts business email compromise (often vendor or payment-detail impersonation) at about $3.05B in losses. The BSI 2025 Lagebericht lists phishing and account misuse as the most common consumer incidents.

### Cited Findings
- Verbraucherzentrale warns of 2026 ELSTER phishing waves with subjects such as "Ihre elektronische Steuererklärung für 2026 ist abrufbereit" and tax-refund lures. Fake sites ask for name, address, tax number, date of birth and ultimately IBAN/bank details. ELSTER never asks for an IBAN by email. — [Verbraucherzentrale Finanzen: ELSTER-Phishing 2026](https://www.verbraucherzentrale-finanzen.org/elster-phishing-warnung/); [infranken.de](https://www.infranken.de/ratgeber/karriere-geld/elster-phishing-2026-steuerbescheid-ki-zugangsdaten-betrug-art-6376541)
- From 11 Sept 2026, a new wave titled "Elster Registerdatenabgleich – Steuerdaten prüfen" asks for Steuer-ID, bank details and contact data. — [Verbraucherschutzforum Berlin, 13 Sep 2026](https://verbraucherschutzforum.berlin/2026-09-13/erneute-elster-phishing-welle-betrueger-verlangen-steuer-id-bankverbindung-und-kontaktdaten-434695/); [borncity: Steuer-Phishing 2026](https://borncity.com/news/steuer-phishing-betrueger-kapern-die-steuersaison-2026/)
- Similar tax-authority phishing warnings came from the Austrian BMF (Aug 2025) and KPMG Austria (Sep 2025). — [BMF Austria](https://www.bmf.gv.at/presse/pressemeldungen/2025/august/phishing-warnung.html); [KPMG AT](https://kpmg.com/at/de/home/insights/2025/09/tn-warnung-vor-phishingmails.html)
- BSI Lagebericht 2025: of about 10,500 consumer enquiries to the BSI service centre, nearly half concerned concrete incidents, most often phishing and account misuse/identity theft. BKA recorded 950 ransomware attacks, about 80% against SMEs. — [security-insider: BSI-Lagebericht 2025](https://www.security-insider.de/bsi-lagebericht-itsicherheit-2025-deutschland-a-d2a510480d46ec84f9be259c38435110/); [BSI Lagebericht 2025 summary PDF](https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/Publikationen/Lageberichte/Lagebericht2025_Achtseiter.pdf?__blob=publicationFile&v=7); [computer-spezial](https://www.computer-spezial.de/news/bsi-lagebericht-2025-besorgt-um-kmu-wie-sieht-es-mit-ihrer-it-sicherheit-aus-4321186.html)
- A secondary source's figure that "60% of recipients can no longer detect AI-generated phishing" and that deepfake attacks rose 1,100% in Q1 2025 appears in regional MSP marketing. It is not confirmed as a BSI statement, so do not attribute it to BSI. — [bios-tec](https://www.bios-tec.de/2025/11/12/bsi-lagebericht-2025-warum-bayerische-kmu-jetzt-handeln-muessen-950-ransomware-angriffe-und-steigende-bedrohung/)
- FBI IC3 2025: total reported losses were about $20.9B (+26% vs 2024). BEC losses were $3.046B across 24,768 complaints (about $123k average). More than $30M of BEC losses had a confirmed AI nexus, with AI used to impersonate leadership and vendors. — [IC3 2025 Annual Report PDF](https://www.ic3.gov/AnnualReport/Reports/2025_IC3Report.pdf); [Red Sift](https://redsift.com/blog/fbi-ic3-2025-report-email-fraud); [dmarcian](https://dmarcian.com/fbi-internet-crime-report-2025/)

### Inferences
- The recurring pattern is "a trusted party asks you to (re)submit Steuer-ID/IBAN/logins via a link". A request that is signed by a DNS-anchored identity for the claimed domain, and verified in-app before any field is shown, directly neutralises this pattern. It works for Kanzlei → Mandant, vendor → customer (bank-detail change) and agency → client alike.
- Vendor bank-detail-change fraud (BEC) runs in the *opposite* direction too: a supplier's IBAN is "updated". A living grant where the payee's IBAN is read from the payee's own verified workspace is a clean answer to that. This is a possible adjacent pitch (accounts payable), though not researched further here.

### Gaps
- No Verbraucherzentrale or BSI warning was found that specifically covers fake *Steuerberater* or *agency* requests (as opposed to ELSTER/Finanzamt/bank impersonation).
- BEC share attributable to vendor-impersonation specifically (vs CEO fraud) was not broken out in the retrieved snippets.

## 5. Event/trip/volunteer/Verein data collection with retention limits

### Takeaway
German Vereine collecting trip data (passport numbers, emergency contacts, health info) are bound by purpose limitation and storage limitation. Data protection authorities (LfDI BW, LfD Niedersachsen, Stiftung Datenschutz) tell them to maintain a Löschkonzept. In practice they rely on paper, Excel, Google Forms or Vereinssoftware. A "grant that expires after the trip" matches the legal default neatly, but willingness to pay is low, since it is volunteer-run.

### Cited Findings
- Vereine must define deletion rules in advance, document them in a Löschkonzept and communicate them. The retention period follows from the purpose: once the purpose is fulfilled, the data may no longer be processed. — [vereinswelt.de: Löschkonzept](https://www.vereinswelt.de/gruendung/datenschutz-und-privatsphaere/loeschkonzept-nach-dsgvo-regeln-pflichten-tipps-fuer-vereine/); [Stiftung Datenschutz: Löschfristen und Löschkonzepte (Ehrenamt)](https://stiftungdatenschutz.org/ehrenamt/praxisratgeber/praxisratgeber-detailseite/loeschfristen-und-loeschkonzepte-277)
- Authority guidance for Vereine exists from LfDI Baden-Württemberg ("Orientierungshilfe Datenschutz im Verein") and LfD Niedersachsen (FAQ). — [LfDI BW](https://www.baden-wuerttemberg.datenschutz.de/orientierungshilfe-datenschutz-verein/); [LfDI BW PDF](https://www.baden-wuerttemberg.datenschutz.de/wp-content/uploads/2020/06/OH-Datenschutz-im-Verein-nach-der-DSGVO.pdf); [LfD Niedersachsen FAQ](https://www.lfd.niedersachsen.de/startseite/infothek/faqs_zur_ds_gvo/vereine/vereine-166239.html)
- A reference point for trip data: Austria's foreign ministry deletes travel registration data (companions, emergency contacts) at the latest 30 days after the trip ends if no consular help was provided. — [BMEIA Datenschutz](https://www.bmeia.gv.at/reise-services/auslandsservice/datenschutz)
- Vereinsplaner and similar Vereinssoftware market GDPR templates for clubs. — [vereinsplaner.de](https://vereinsplaner.de/c/datenschutz-im-verein-deutschland)

### Inferences
- "Revocable grant with automatic expiry after the event" is a natural technical implementation of Art. 5(1)(e). The organiser never holds the passport number past the trip, and the family can revoke it. This is a compelling compliance story for volunteer organisers, who are personally anxious about DSGVO liability.
- However, this segment has very low willingness to pay and requires *every responder to create an account*, as revoked mandates. For one-off volunteers, parents or trip participants, that is heavy friction (a known conversion killer compared with a Google Form). It is a better adoption/viral channel than a revenue segment.

### Gaps
- No quantitative data was found on how Vereine currently collect trip/passport data, and no pricing was retrieved for Vereinssoftware (e.g. Vereinsplaner, easyVerein, ComMusic) or for event registration tools.
- No authority guidance specific to retaining passport copies for group trips was retrieved.

## 6. Which segment has the highest willingness to pay and the shortest path to first users?

### Takeaway
On the evidence gathered, **digital/web agencies and freelancers (plus small MSPs/IT-Dienstleister) handling long-tail credentials** show the clearest proven willingness to pay (Leadsie $59–129/mo, Content Snare $35–258/mo, per-onboarding or per-request pricing). They have an uncovered gap (non-OAuth logins, DNS, hosting, API keys) and a natural offboarding story. Steuerberater have a strong phishing/verification story but are DATEV-locked. Vereine/events have the best compliance fit but little money. A solo developer's shortest path is probably web agencies/freelancers and MSPs in the DACH developer/open-source community, where self-hosting is a feature rather than a burden.

### Cited Findings
- Agencies already pay for access-request tooling: Leadsie at $59/mo for only 3 onboardings/month, with $50 overages. — [Leadsie pricing](https://www.leadsie.com/pricing)
- Agencies pay for structured data collection separately: Content Snare at $35–258/mo, priced by active requests. — [Portico](https://www.portico.run/blog/post/content-snare-pricing)
- Freelancer CRMs are cheap ($12–40/mo Moxie, $20–40 Dubsado), which sets a low price anchor for solo freelancers. — [Plutio](https://www.plutio.com/compare/moxie-vs-dubsado); [Assembly](https://assembly.com/blog/dubsado-vs-honeybook)
- Steuerberater face per-client DATEV fees (€3/client/year for Meine Steuern) and complain about silo tools. — [DATEV Meine Steuern](https://www.datev.de/web/de/steuerberatung/loesungen/steuern/dokumente-und-daten-digital-erhalten/datev-meine-steuern); [DATEV-Community](https://www.datev-community.de/t5/Unternehmen-online/Kosteneinsparung-kleine-Buchhaltungen-%C3%BCber-Meine-Steuern/td-p/385521)
- Third-party access risk is recognised at the organisational level (47% of organisations had a third-party-access breach in 12 months; the sample included Germany). This supports an MSP/IT-provider pitch to their SMB customers. — [Ponemon-Sullivan 2025](https://ponemonsullivanreport.com/2025/03/creating-a-cybersecurity-infrastructure-to-reduce-third-party-and-privileged-internal-access-risks-a-global-study/)

### Inferences
- **Ranking by willingness to pay:** (1) agencies and MSPs, B2B with $50–250/mo tool budgets already proven; (2) Steuerberater, who have high revenue per firm but buy through DATEV and are conservative; (3) HR onboarding, where large HRIS suites (Personio etc.) already collect this data, so the gap is narrow; (4) landlords/property managers, who are plausible but unresearched here; (5) Vereine/events, with the lowest willingness to pay.
- **Ranking by shortest path for a solo developer:** agencies/freelancers/MSPs first. They are reachable via Reddit, dev communities and open-source channels, can self-host, and accept a responder-account requirement because the client relationship is ongoing. Steuerberater need DATEV integration and trust signals (German hosting, AVV/DPA). Vereine need zero-friction guest flows, which revoked has deliberately removed.
- **Positioning wedge:** "Leadsie for everything Leadsie can't do". That means CMS/hosting/DNS/registrar/API-key handoff, plus one-click offboarding ("revoke all grants to Agency X") and a signed-request badge. It complements Leadsie/AgencyAccess rather than fighting them head-on on Meta/Google access.
- **Main risk:** the account-required responder model adds friction on the *client* side, and the agency is the payer. Agencies will judge the tool by how easily their clients complete it. Leadsie's whole value proposition is making the client step trivial.

### Gaps
- No direct interview, survey or review data was found on agencies' willingness to pay specifically for credential (not OAuth) handoff or for offboarding/revocation features.
- MSP-specific tooling (e.g. IT Glue, Hudu, Passportal) and its pricing was not researched in this session. It is an important competitor set for the MSP segment.
- Landlord/property-manager and HR onboarding segments were not researched within budget.
