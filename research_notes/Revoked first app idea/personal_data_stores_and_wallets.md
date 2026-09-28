# Personal Data Stores, Consent-Managed Data Sharing and Digital Identity Wallets: Competitive Landscape and Lessons for "revoked" (as of September 2026)

Scope note: research done 2026-09-28. Where a fact is older than 2025 it is labelled with its date. "revoked" = the solo-developer, self-hosted Go/PocketBase + Flutter platform for revocable "living grants", templated data "requests", DNS-anchored identities and machine-readable outputs (JSON/ETag, CSV, vCard/CardDAV, iCal).

---

## 1. Solid / Inrupt: status, what shipped, lessons

### Takeaway
Solid is still alive, mostly as a government/enterprise B2B play (Flanders' Athumi is the flagship) and a W3C standard in draft ("Linked Web Storage"). It has not reached consumers at scale ten years after its 2016 release. Its visible wins are institutional pilots, not organic user adoption.

### Cited Findings
- Timeline: design notes 2009; Mastercard funding to MIT in 2015; official release on 10 Aug 2016; W3C standardization began and Inrupt was founded in 2018; Inrupt raised a $30M Series A in Dec 2021; the Open Data Institute took over stewardship of Solid in Oct 2024. [Wikipedia: Solid](https://en.wikipedia.org/wiki/Solid_(web_decentralization_project))
- W3C chartered a **Linked Web Storage (LWS) Working Group** (charter Sept 2024 to Sept 2026) to standardize Solid. A **First Public Working Draft of LWS Protocol 1.0 was published in March 2026**. The draft has authentication suites for OpenID Connect, SAML 2.0 and did:key, and a Use Cases note listing 39 core requirements. [W3C news, 2026](https://www.w3.org/news/2026/first-public-working-draft-linked-web-storage-protocol-1-0/); [W3C LWS WG](https://www.w3.org/groups/wg/lws/); [Inrupt blog](https://www.inrupt.com/blog/solid-achieves-major-milestone-in-web-standardization-process)
- **Flanders / Athumi**: Athumi, described as "Europe's first data utility company", was set up in spring 2023 as a neutral public company for government-to-business and business-to-business data exchange. [Athumi / search summary](https://athumi.eu/en/technologies/solid); [Inrupt case study](https://www.inrupt.com/case-study/flanders-strengthens-trusted-data-economy)
- The Flemish minister invested **EUR 14M in SolidLab**, a 4-year programme running 2022–2026. [SolidLab Flanders](https://solidlab.be/)
- Athumi's Solid platform launched in **May 2023**. Its first production use case shares diploma data with HR provider **Randstad** ("My career"). Interest was reported from employment, education, energy and healthcare, and 5 Dutch media companies were announced for personal data vaults. In **March 2024** Inrupt, Athumi and Cronos renewed their partnership as a multi-year commitment "to meet the demand for B2B adoption". No user, pod or company counts were published. [Inrupt blog, 20 Mar 2024](https://www.inrupt.com/blog/athumi-inrupt-cronos-groep-extend-partnership)
- Athumi and itsme (the Belgian bank-ID app) launched a solution to replace paper student certificates. [Athumi news](https://athumi.eu/en/blog/news/athumi-and-itsme-launch-innovative-solution-to-replace-student-certificates)
- **BBC**: "My PDS" (2021) pulled Spotify, Netflix and BBC viewing data into a Solid pod for recommendations and won best technical paper at IBC 2021. "BBC Together + Data Pod" paired social viewing with pod-held viewing data. Both were **experiments/R&D**, not a product rollout. [Inrupt BBC case study](https://www.inrupt.com/case-study/bbc-improves-viewing-experience-with-solid-pods); [Inrupt BBC consent case](https://www.inrupt.com/case-study/bbc-embraces-future-of-personal-data-access-and-consent)
- **NHS (2020)**: a pilot let patients store medical data in pods and share it with carers. It was announced in Nov 2020, and no published outcomes were found. [Fortune, 9 Nov 2020](https://www.fortune.com/2020/11/09/tim-berners-lee-solid-data-privacy-bbc-nhs)
- Other pilot: VITO (Belgium) built Solid-based personal health data sharing. [Inrupt VITO case](https://www.inrupt.com/case-study/vito-securely-shares-personal-health-data-using-solid)
- In 2025 Inrupt says AI adoption has "intensified" interest from CEOs. This is company messaging, not adoption data. [Web Summit Lisbon 2025 summary](https://websummit.com/summaries/lis25/hanging-in-the-balance/)

### Inferences
- Solid's traction came from **public money plus a public operator** (Athumi, EUR 14M SolidLab) and from big-brand R&D, not from bottom-up demand. Even with that backing, the published use cases after 3 years are a handful, and none have public usage numbers.
- Solid's model is "apps read data from your pod", which needs every relying app to integrate. That is the same two-sided problem that stalls every PDS. revoked's model has one advantage here: the reader only needs a URL, JSON, vCard, iCal or CardDAV, so the recipient does not need to adopt anything.
- A standards-heavy architecture (RDF/Linked Data, WebID, access-control specs) has been slow to converge: 10 years from release to a first public working draft. A small player should not wait for a standard. It should stay interoperable at the edges (vCard, iCal, JSON, OpenID) instead.

### Gaps
- No public figures for Athumi pod counts, active users or revenue; none for Inrupt's revenue or headcount in 2025–2026.
- Not verified whether SolidLab (ending 2026) has a successor programme.
- Could not access ING's Medium post on a Solid-based vault (403), so ING's Belgian Solid deployment is unconfirmed.

---

## 2. Personal data store companies: Mydex, digi.me, Meeco, HAT/Dataswift, Cozy Cloud, polypoly, Datacoup, CitizenMe

### Takeaway
Nearly every consumer-first PDS either died (Datacoup, polypoly), went into administration or was sold (digi.me, Cozy Cloud), or survived by **pivoting to B2B infrastructure or a narrow regulated vertical**. Examples: Meeco moved to verifiable-credential and wallet infrastructure; digi.me moved to health records in the Dutch PGO scheme; Mydex moved to public-sector and social-care projects. "Sell your data" marketplaces failed outright.

### Cited Findings
- **Market-level finding**: a 2023 academic review found that "no personal data store has seen significant mass-market penetration" and that few adoption figures exist. It names the two-sided mass-adoption problem and business reluctance to give up centralized data control as the main barriers. [Fallatah, Barhamgi, Perera, *Sensors* 2023, PDS: A Review](https://www.mdpi.com/1424-8220/23/3/1477) / [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9921726/)
- The same review notes a structural difference. DataSwift and Mydex are bound by foundations or CIC status, which protects them from privacy-hostile takeovers. Meeco, CitizenMe, digi.me and others are ordinary for-profits with no such safeguard. [Dataethics.eu summary](https://dataethics.eu/users-can-take-back-their-data-in-a-pds-without-sacrificing-their-privacy/)
- **digi.me** (UK, founded 2009, formerly Social Safe Ltd):
  - Administrators (Quantuma) were appointed to Digi.me Limited on **22 Sept 2021**. [Insolvency Intel](https://insolvencyintel.co.uk/digi-me-limited/)
  - Sydney-based **World Data Exchange completed its acquisition of digi.me in Oct 2022**. [iTWire](https://itwire.com/it-industry-news/deals/world-data-exchange-completes-acquisition-of-digi-me.html)
  - It is now positioned as "Your medical records in one place" and as a **Dutch Personal Health Record (PGO)**, with UK GP-record access claimed to cover over 50% of the country. [digi.me listings / search summary](https://digi.me/); [App Store](https://apps.apple.com/gb/app/digi-me/id6544805784)
- **Mydex CIC** (UK, Scotland-focused community interest company):
  - It has raised no external equity funding. It charges **organisations a small annual connection fee** plus a **4% fee on paid transactions**, and reinvests 65% of any surplus. [Tracxn](https://tracxn.com/d/companies/mydex/__IDkGusMp_-rYX2ZXiOVpYacYHaywdyQnNhrvHj-7NSo); [Mydex site](https://mydex.org/platform-services/); [Mydex Medium](https://medium.com/mydex/mydex-cic-is-different-heres-why-727cef01f57a)
  - Its current work is proof-point projects: chronic health conditions, debt advice, assisted living, identity assurance, and councils/government. Its May 2026 update still frames "securing funding for growth and expansion" as an open goal. [Mydex Medium, May 2026](https://medium.com/mydex/what-weve-been-up-to-6cad4d90e355) (403 on fetch; summary from search snippet)
- **Meeco** (Australia): now describes itself as "enterprise-grade infrastructure for the full lifecycle management of verifiable credentials and digital wallets" through a **B2B API**. It sits in the Japan–Australia cross-border VC interoperability group with DNP and MUFG, and was active at EIC 2025. [Meeco](https://www.meeco.me/); [Meeco VC](https://www.meeco.me/verifiable-credentials); [KuppingerCole](https://www.kuppingercole.com/vendors/meeco)
- **Hub of All Things / Dataswift (Dataswyft)**:
  - It spun out of a £1.2M UK research-funded HAT project across 6 universities, with the HAT Community Foundation acting as its regulator. It raised a US$2M seed round. [OpenCommons](https://opencommons.org/Dataswift); [Digital News Asia](https://www.digitalnewsasia.com/startups/personal-data-technology-platform-dataswift-raises-us2mil-seed-funding)
  - Companies House lists a **new "DATASWIFT LIMITED" incorporated 9 Dec 2023**, which suggests a corporate restructuring. [Companies House](https://find-and-update.company-information.service.gov.uk/company/15337989)
  - No evidence of consumer scale was found.
- **Cozy Cloud** (France, open-source personal cloud with "connectors" that pull bills and bank data):
  - It was in **judicial liquidation from 7 Feb 2025** and was acquired by **Linagora** (announced May 2025). It is being folded into **Twake Workplace**, and users' interface and branding started changing from 7 July 2025. [Linagora](https://linagora.com/en/cozy-cloud-joins-linagora-strengthen-twake-workplace-dynamic); [Next.ink, 30 May 2025](https://next.ink/brief-article/cozy-cloud-passe-chez-linagora/); [Goodtech](https://goodtech.info/cozy-cloud-linagora-twake-workplace/)
  - Reader comments on Next.ink blamed connectors that broke whenever third parties changed and pricing (€12/month for 1TB). These are anecdotal comments, not an official post-mortem. [Next.ink](https://next.ink/brief-article/cozy-cloud-passe-chez-linagora/)
- **polypoly** (Germany/Berlin, polyPod on-device PDS; "end the dominance of data monopolists", heise 2020): insolvency proceedings were opened over **polypoly Enterprise GmbH** by AG Charlottenburg with effect from **1 Jan 2023**. The polyPod code remains on GitHub. [Insolvenz-Radar](https://insolvenz-radar.de/firmeninsolvenz/hrb+207241/berlin/f1103/); [heise 2020](https://www.heise.de/news/Start-up-Polypoly-will-Vormachtstellung-der-Datenmonopolisten-beenden-4921628.html); [GitHub](https://github.com/polypoly-eu/polyPod)
- **Datacoup** (US, 2012–2014 era) offered users about **$8/month** for their social and card data. It is now defunct; its site showed "retooling our marketplace". [MIT Technology Review, Feb 2014](https://www.technologyreview.com/2014/02/12/174259/sell-your-personal-data-for-8-a-month/); [AdGuard](https://adguard.com/en/blog/they_must_pay.html)
- **CitizenMe** (UK, launched 2014): pays users cents for surveys and data. It pivoted to a platform for **market researchers**, where brands query consented, anonymised data held on users' phones. [Research Live](https://www.research-live.com/article/news/citizenme-opens-new-data-platform/id/5029792); [AdGuard](https://adguard.com/en/blog/they_must_pay.html)
- Why "sell your data" failed, in one commentator's words: big platforms already have the data first-hand, so "why would Google buy something from users". [AdGuard](https://adguard.com/en/blog/they_must_pay.html)
- **Plaxo** (2002–2017) is the closest historical precedent for "update once, propagate everywhere" contact data. Members edited their own card, and "the changes appeared in the address books of all those who listed the account changer". It reached about 20M users. Comcast bought it in 2008, and it shut down on **31 Dec 2017**. [Wikipedia: Plaxo](https://en.wikipedia.org/wiki/Plaxo)
  - Plaxo's growth engine was its viral "Hi, I'm updating my address book" e-mails, which drew a years-long "Plaxo spam" backlash. Plaxo said the e-mails were "a means to an end" and throttled them after passing 10M members. [Techdirt, 2006](https://techdirt.com/articles/20060322/0317223.shtml); [Loose Wire, 2006](https://www.loosewireblog.com/2006/03/plaxo_drops_the.html)

### Inferences
- Pattern: consumer PDSs have no one to charge. Consumers will not pay much (Cozy at €12/month was called expensive), and businesses will not pay to receive data they can already get from forms. Survivors charge **organisations**:
  - per-connection fees (Mydex),
  - infrastructure/API licences (Meeco),
  - government contracts (Athumi),
  - regulated-vertical funding (digi.me in Dutch health records).
- "Aggregate everything" PDSs (Cozy connectors, digi.me social import, HAT) take on a heavy maintenance burden scraping third parties. revoked avoids this because it stores **user-entered records**, not scraped data. That is a real advantage for a solo developer.
- Plaxo shows that demand for "living contact data" exists (20M users), but also that:
  - (a) the growth tactic of e-mailing contacts easily becomes spam, and
  - (b) once the address book lived in the phone OS and social networks (LinkedIn, Facebook), a standalone updater lost its reason to exist.
  - revoked's vCard/CardDAV output lets it plug into the OS address book instead of competing with it. This is the lesson Plaxo learned too late.
- Governance matters for trust. A self-hosted, open-source tool gets the takeover protection that Mydex and HAT sought through CIC/foundation structures, at no cost.

### Gaps
- No verified 2025–2026 user numbers for any of these PDSs.
- Current operational status of Dataswift/HAT is unclear (new company incorporated 2023; product activity not confirmed).
- No primary post-mortem found for digi.me's 2021 administration.
- CitizenMe's 2025–2026 status is not confirmed.

---

## 3. EU Digital Identity Wallet (eIDAS 2.0, Reg. 2024/1183), European Business Wallet, Germany's wallet: overlap with revoked

### Takeaway
The EUDI wallet is built for **one-time, verifiable presentation of issuer-signed attestations** (identity, licences, diplomas, and eventually verified IBAN or address). It is not built for **user-maintained, live-updating data that a relying party keeps reading**. The EU's answer to "take my data back" is a wallet **dashboard plus a standardised GDPR erasure request** to the relying party, not technical revocation of access.

Timeline:
- Member-state wallets are due by December 2026; readiness is patchy.
- Germany's public launch is 2 Jan 2027.
- Regulated private relying parties must accept wallets by about December 2027.
- The European Business Wallet (proposed 19 Nov 2025) is still in legislative negotiation.

### Cited Findings
**Deadlines and obligations**
- Every EU member state must offer at least one EUDI wallet by **December 2026**. AMLR key obligations apply from **10 July 2027**. [Corbado, EIC 2026 write-up](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026)
- Private relying parties that use strong customer authentication must accept the wallet within **36 months of the implementing acts, i.e. by about December 2027 (cited as 24 Dec 2027)**. Art. 5f(2) sectors: transport, energy, banking, financial services, social security, health, drinking water, postal, digital infrastructure, education, telecoms. **VLOPs (DSA) and gatekeepers (DMA)** must accept the wallet for login at the user's request. "A typical small SaaS company is not obliged to integrate the wallet." [Venvera](https://venvera.com/learn/who-must-comply-with-eidas-2-0); [Authologic](https://authologic.com/blog/how-eidas-20-affects-private-relying-parties-and-sca-analysis); [Truvity](https://www.truvity.com/blog/your-banks-first-3-steps-to-eidas-2-0-compliance) (secondary sources; consistent with each other)

**Readiness across member states**
- In Jan 2026, Signicat assessed only **12 of 27** member states as on track for end-2026.
- Namirial's assessment: "three countries near-certain, five very likely, eight likely". [Biometric Update, Aug 2026](https://www.biometricupdate.com/202608/germanys-eudi-wallet-push-highlights-europes-implementation-gap)
- Politecnico di Milano's observatory found "fewer than one third" of member states meet the readiness benchmark and counted 306 identity systems and wallets across member states. [Corbado](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026)
- Consumer awareness: **51%** of surveyed consumers in France and Germany had never heard of the EUDI wallet (IDnow survey, mid-2026). [Biometric Update, Aug 2026](https://www.biometricupdate.com/202608/germanys-eudi-wallet-push-highlights-europes-implementation-gap)

**Germany**
- SPRIND builds the German EUDI wallet for the Federal Ministry for Digital and State Modernisation (**BMDS**), working with BMI, BSI, Bundesdruckerei, Fraunhofer AISEC and PwC. [Biometric Update, Dec 2025](https://www.biometricupdate.com/202512/the-german-approach-to-eudi-wallet-sprind-launches-sandbox-for-relying-parties); [SPRIND](https://www.sprind.org/en/articles/eudi-wallet/); [eudi-wallet.gov.de](https://eudi-wallet.gov.de/en)
- A relying-party **sandbox launched in Jan 2026**. [Biometric Update, Jan 2026](https://www.biometricupdate.com/202601/germany-launches-eudi-wallet-sandbox-to-test-key-functions-apply-specific-use-cases)
- In its first six months the sandbox had about **115 organisations and 150 use cases**. SPRIND called relying-party onboarding "the real bottleneck". [Corbado](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026)
- Scheduled public launch: **2 Jan 2027**, with €79.3M funding through 2026. The first version supports **identification and credential presentation only**. QES, pseudonymous login and payments come in later phases. [Biometric Update, Aug 2026](https://www.biometricupdate.com/202608/germanys-eudi-wallet-push-highlights-europes-implementation-gap)

**Economics**
- Wallet-based onboarding is cited as cutting KYC cost from **€70–100 to €3–8 per customer**. [Corbado](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026)

**Attestation types and overlap with revoked**
- Banks and other attribute providers are expected to issue address, over-18, and, in future, **verified IBAN** and income-proof attestations. **IBAN attestations** let users prove bank-account ownership. The completed large-scale pilots (EWC, POTENTIAL, DC4EU, NOBID) covered travel, education, social security and payments. [Worldline, 2026](https://worldline.com/en/home/main-navigation/resources/blogs/2026/european-digital-identity-wallet-eudiw-from-pilots-to-real-world-impact); [Lissi](https://www.lissi.id/blog/introducing-eudi-wallet-based-strong-customer-authentication-for-financial-services-for-payment)

**Dashboard and erasure instead of live revocation**
- eIDAS 2.0 requires a **common dashboard** showing the relying parties the user connected to and the data exchanged. It must let the user **request erasure under GDPR Art. 17** and **report a relying party to the DPA** (Art. 5a). [EUDI ARF discussion #480](https://github.com/eu-digital-identity-wallet/eudi-doc-architecture-and-reference-framework/discussions/480); [AEPD blog, 24 Jan 2025](https://www.aepd.es/en/press-and-communication/blog/eidas2-the-eudi-wallet-and-the-gdpr-i)
- A technical spec for the deletion request, **EC TS07 v0.11 (Jan 2026), "common interface for data deletion requests to Relying Parties"**, is being standardised as ETSI EN 319 482-2. [EUDI standards issue #20](https://github.com/eu-digital-identity-wallet/eudi-doc-standards-and-technical-specifications/issues/20)
- The ARF also has a discussion topic on "export and data portability". [eudi.dev topic N](https://eudi.dev/3.0.0/discussion-topics/n-export-and-data-portability/)
- The Spanish DPA (AEPD) said in Jan 2025 that the ARF had "significant gaps" in ensuring GDPR compliance. [AEPD](https://www.aepd.es/en/press-and-communication/blog/eidas2-the-eudi-wallet-and-the-gdpr-i)

**European Business Wallet (EBW)**
- Proposed **19 Nov 2025**, COM(2025) 838, procedure 2025/0358(COD). Core functions: secure identification, electronic signing and sealing, and sending/receiving documents and data via a **qualified electronic registered delivery service**. [EP Legislative Train](https://www.europarl.europa.eu/legislative-train/theme-a-new-plan-for-europe-s-sustainable-prosperity-and-competitiveness/file-european-business-wallet); [EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex:52025PC0838)
- The Commission claims **at least €150bn per year** in savings. [cheqd summary](https://cheqd.io/blog/european-business-wallets-new-proposal-to-accelerate-eus-digital-future/); [VATupdate](https://www.vatupdate.com/2025/11/21/the-european-commission-proposes-regulation-on-european-business-wallets/)
- Status: the **Council adopted its negotiating position on 9 June 2026**, changing public-sector acceptance to "two years after the date of application of the last implementing acts". In Parliament the file sits with ITRE, rapporteur **Eero Heinäluoma** (S&D, FI), with hundreds of amendments tabled. It is not yet adopted as of Sept 2026. [EP Legislative Train](https://www.europarl.europa.eu/legislative-train/theme-a-new-plan-for-europe-s-sustainable-prosperity-and-competitiveness/file-european-business-wallet)
- Notaries of Europe (CNUE) published a position paper in March 2026. [CNUE PDF](https://www.notariesofeurope.eu/wp-content/uploads/2026/03/CNUE-Position-on-European-Business-Wallets-EN-final.pdf)

**Casualty in Germany: Verimi**
- The private German ID wallet **Verimi** (a 2018 JV of Allianz, Deutsche Bank, Telekom, VW, Lufthansa and others, which merged with the banks' **yes®** in 2023) announced on **15 July 2026** that it will **cease operations at the end of 2026**. It cited the EUDI wallet and AMLR, even though it had been **profitable since 2024** with 10× user growth in 2024. The combined Verimi/yes infrastructure processed more than 10M transactions in 2022. [heise, 15 Jul 2026](https://www.heise.de/en/news/Identity-service-provider-Verimi-ceases-business-operations-11366243.html); [BIIA](https://www.biia.com/the-competing-german-id-services-verimi-and-yes-merge/)

### Inferences
- **Overlap with revoked**: the EUDI wallet (and later the EBW) will own "prove who I am" and "prove this attribute is officially true" (PID, verified IBAN, address, VAT/registry data for businesses). It does **not** own:
  - "keep your copy of my billing address, IBAN or contact details current, and let me cut you off",
  - self-asserted business data (preferred invoice e-mail, delivery instructions, PO numbers, contact people),
  - machine-readable feeds (vCard/iCal/JSON).
  - revoked should position itself as **complementary**: a place where data is maintained and shared live, which could later **carry or reference wallet-verified attributes**. It should not compete as an identity provider.
- **Verimi is a warning**: even a profitable, corporate-backed German private identity wallet is being displaced by the state wallet. A small player should **not** compete on identity/KYC.
- The EU's own design treats "revoke" as a **legal request (GDPR Art. 17 erasure) routed through a dashboard**, not a technical cutoff. That is a mainstream precedent revoked can cite for honest framing (see section 8). revoked's "pause/revoke read access to the live value" is a real feature the wallet lacks. Deleting copies still needs the legal route.
- The EBW's "qualified electronic registered delivery" channel suggests the EU pictures B2B data exchange as **document delivery**, not living records. Business master-data sync (addresses, bank details, VAT IDs between suppliers and customers) remains an open niche. Watch whether EBW implementing acts add attribute-update notifications.
- Relying-party onboarding is the bottleneck even for a state-backed wallet (115 organisations in 6 months). That confirms the two-sided problem applies to everyone. revoked's advantage is that its "relying party" can be anyone who opens a link or subscribes to a vCard/iCal feed, with zero onboarding.

### Gaps
- Official Commission/OJ texts for the implementing-act dates were not fetched here. The "24 months after implementing acts → Dec 2026" and "36 months → Dec 2027" dates come from secondary sources. My understanding, unverified in this session, is that the first implementing regulations were adopted in late Nov 2024 and published in early Dec 2024.
- No confirmation found of whether the German wallet will carry an IBAN or address attestation at launch; the first version is ID and presentation only.
- The EBW's exact attestation list (VAT ID, EUID, powers of representation) was not confirmed from primary text in this session.
- Whether the ARF supports any "subscribe to updates" or re-presentation-on-change flow was not found; no evidence that it does.

---

## 4. Verifiable Credentials (W3C VC 2.0), SD-JWT VC, OpenID4VP: one-time presentation vs living data

### Takeaway
The VC/OpenID4VP stack is built around **issuer revocation of the credential** (status lists) and **one-time presentation to a verifier**. There is no standard way for a holder to revoke a verifier's continued access to data already presented, or for a verifier to "subscribe" to the current value. The nearest mechanism, **VC Refresh**, lets the *holder* get a fresh credential from the *issuer*, not the verifier.

### Cited Findings
- Token Status Lists: the issuer assigns each credential an index in a status list, published as a JWT/CWT. The verifier checks it and rejects revoked or suspended credentials. SD-JWT VC and W3C VC 2.0 both make status **optional**. What happens to data after verification "is at the discretion of the Relying Party". [verana-labs vs-agent issue #713](https://github.com/verana-labs/vs-agent/issues/713); [iya-sts issue #165](https://github.com/rcbj/iya-sts/issues/165); [W3C VC DM 2.0](https://www.w3.org/TR/vc-data-model-2.0/) (GitHub sources are practitioner implementations, not normative)
- **VC Refresh** (W3C CCG draft v0.5): a `refreshService` property lets a credential be refreshed "manually or, with the prior consent of the credential holder, automatically", with the issuer returning a new credential. It is aimed at expiry and updated values, and flows issuer → holder. [W3C CCG VC Refresh](https://w3c-ccg.github.io/vc-refresh/); 1EdTech has a profile of it for education. [1EdTech VCCR](https://www.imsglobal.org/spec/vccr/v1p0)

### Inferences
- In VC terms, revoked's "living grant" is closer to an **OAuth-protected resource** or **capability URL** than to a credential. The relying party holds a revocable handle, not a copy. This is a genuine model difference that can be explained crisply: "a credential proves a fact at a point in time; a grant gives access to the current value until you stop it."
- A pragmatic bridge: revoked could present wallet-verified facts (e.g. an IBAN attestation) *inside* a living grant. Revocation would then work at both levels: the grant is revoked by the owner, and the credential by its issuer.
- Revocation in the VC world protects **verifiers** from stale or withdrawn credentials. revoked's revocation protects the **data subject**. This difference is the product's clearest differentiator.

### Gaps
- Did not verify whether the OpenID Foundation has any draft for holder-initiated revocation or verifier "subscription" (e.g. linking CAEP/Shared Signals to wallets). No evidence was found either way.

---

## 5. Consent and data-access precedents: Open Banking (PSD2/PSD3), FIDA, UK Smart Data, Kantara/ISO 27560, MyData

### Takeaway
Open Banking is the strongest real-world precedent for **ongoing, revocable, dashboard-managed third-party access to live data**, and FIDA/UK Smart Data extend the same pattern to other sectors. The lessons:
- Mandatory **access dashboards** and revocation work.
- Periodic re-authentication friction was so damaging that the UK regulator changed it.
- The "permission ledger" behind a dashboard is the real engineering cost.

Consent-receipt standards exist (ISO/IEC TS 27560:2023, from Kantara) but have limited adoption.

### Cited Findings
- **UK Open Banking standards**: account information providers (AISPs) must let users "view and revoke on-going consents"; dashboards must be easy to find with "no barriers or obstructions". Account providers (ASPSPs) also offer access dashboards. [OBIE AIS Consent Dashboard](https://standards.openbanking.org.uk/customer-experience-guidelines/dashboards/ais-consent-dashboard-revocation-refresh/v3-1-9/); [OBIE Revocation](https://standards.openbanking.org.uk/customer-experience-guidelines/introduction/revocation/latest/)
- **The 90-day re-authentication rule**: PSD2 required strong customer authentication with the bank every 90 days. In **Nov 2021** the FCA changed this so users simply **re-confirm with the third party**, because the bank re-auth broke feeds. The EU moved to 180-day SCA. [PYMNTS, 2021](https://www.pymnts.com/news/banking/2021/fca-scraps-90-day-reauthentication-open-banking-rule/); [TrueLayer](https://truelayer.com/blog/compliance-and-regulation/explaining-changes-to-the-90-day-rule-for-open-banking-access/); [SaasAnt](https://www.saasant.com/blog/uk-eu-open-banking-consent-feed-break-fix/)
- Plaid argued that 90-day re-auth confuses authentication with authorisation. [Plaid blog](https://plaid.com/blog/misconceptions-of-authentication-and-authorisation-why-90-day/)
- **FIDA (Financial Data Access Regulation)**:
  - It nearly got withdrawn in the leaked 2025 Commission work programme, then returned to "pending" and is listed in the 2026 work programme (Annex III item 41). [finAPI](https://www.finapi.io/en/fida-regulation-status-pending/); [Freshfields](https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/risen-from-the-ashes-fida-trilogue-set-to-move-forward-102k3at); [KPMG, Feb 2026](https://kpmg.com/cy/en/home/insights/2026/02/introduction-to-fida-understanding-the-financial-data-access-regulation.html)
  - As of **July 2026 it was still in trilogue**. Scope covers mortgages, loans, savings, investments, crypto, pensions and non-life insurance. It requires data holders to provide a **"permission dashboard"**. Standards and liability are set through "Financial Data Sharing Schemes". One analyst notes the dashboard itself is "a week of front-end work", while the permission ledger ("which permission was granted, by whom, over what data, for how long") is the real cost. [Rousseau, 31 Jul 2026](https://sebastienrousseau.com/2026-07-31-fida-open-finance-data-sharing-schemes-banks-2026/)
  - Application is expected around 2028 per some commentators. [KPMG](https://kpmg.com/cy/en/home/insights/2026/02/introduction-to-fida-understanding-the-financial-data-access-regulation.html)
- **UK Smart Data**: the **Data (Use and Access) Act 2025** (Royal Assent **19 June 2025**) puts Open Banking on a statutory footing and lets the government create sectoral Smart Data schemes. The first sectoral statutory instrument (open banking) is expected **Q4 2026**. Schemes must define how permissions are captured, **how access can be revoked**, and what onward use is allowed. [CMS](https://cms.law/en/gbr/legal-updates/smart-data-schemes-enhanced-data-sharing-in-the-uk-under-the-new-data-use-and-access-act); [NatLawReview](https://natlawreview.com/article/uk-smart-data-and-data-use-and-access-act-2025-considerations-businesses); [legislation.gov.uk notes](https://www.legislation.gov.uk/ukpga/2025/18/notes/division/4/index.htm)
- **Consent receipts**: **ISO/IEC TS 27560:2023** defines a machine-readable consent record structure and "receipts" exchanged between entities. It is based on the **Kantara Consent Receipt v1.1**, with one change: Kantara saw the receipt as given by the data subject to the controller, while ISO says organisations generate records and give receipts to data subjects. An implementation guide using the W3C DPV vocabulary exists. [ISO](https://www.iso.org/standard/80392.html); [W3C DPV guide](https://w3c-cg.github.io/dpv/guides/consent-27560); [Pandit et al. 2024, arXiv](https://arxiv.org/pdf/2405.04528)
- **MyData Global**:
  - "MyData operators" are human-centric personal data intermediaries; **41** have self-described against MyData's operator framework, and 33 got the 2022 Operator Award. [MyData operators (old site)](https://oldwww.mydata.org/mydata-operators/); [MyData 2022 awards](https://oldwww.mydata.org/2022/03/16/mydata-operator-2022-awards/)
  - The 2024–25 MyData Awards received more than 400 nominations; OwnYourData (Austria) won the 2025 Technology award. [OwnYourData](https://www.ownyourdata.eu/en/mydata-award-2025/); [MyData awards](https://mydata.org/participate/awards/)
- **EU Data Governance Act**: "personal data spaces or data wallets" that share data on the data holder's consent are named as data-intermediation mechanisms. Providers of **data intermediation services must notify a national authority** and are entered in an EU register. [Commission DGA explainer](https://digital-strategy.ec.europa.eu/en/policies/data-governance-act-explained); [DLA Piper](https://www.dlapiper.com/en/insights/topics/data-governance-act); [INPLP](https://inplp.com/latest-news/article/data-governance-act-data-intermediation-services-provider-a-new-player-involved-in-personal-data-processing/)

### Inferences
- revoked's "grant list with pause/revoke" is the same user-facing primitive regulators mandated for Open Banking and plan for FIDA. That lends legitimacy ("like the Open Banking permissions dashboard, but for your address and bank details").
- Lesson from the 90-day saga: **forced re-consent kills ongoing grants**. revoked should default to open-ended grants with optional expiry or view caps, plus reminders, not hard expiry.
- revoked already has a permission ledger (grants, audit log, view caps). By the FIDA analyst's framing, that is the costly part, and it is already built.
- **Regulatory risk**: a *hosted* revoked service that brokers personal data between users and businesses could fall under the DGA's data-intermediation-service regime (notification, neutrality, structural separation). The **self-hosted, operator-runs-their-own-instance** model probably reduces this exposure, but it needs legal review. A hosted SaaS offering should be assessed before launch.
- Exporting ISO 27560-style consent receipts for each grant is cheap and gives business customers a compliance artefact. It could be a small differentiator for B2B buyers.

### Gaps
- Could not find the DGA register's current count of notified intermediaries or how many are personal-data (not B2B) intermediaries.
- PSD3/PSR text on permission dashboards was not verified (the provisional agreement date and dashboard article were not found in this session).
- No data found on consumer usage of Open Banking dashboards (how often people actually revoke).

---

## 6. "Update once, propagate everywhere": change-of-address services (DE, UK, EE)

### Takeaway
There is proven, paid-for demand around moving house. Germany's Deutsche Post runs a **free** address-change notification to **1,000+ partner companies** (monetised through the €31.90+ mail-forwarding product and B2B address data). Germany's online Ummeldung now reaches 55M citizens. The UK's Royal Mail charges £45–£95 for forwarding, while Tell Us Once covers only bereavement and only the public sector. Estonia's once-only principle plus its "Data Tracker" shows the state version of a living grant plus access log.

These services **push a one-time change notice** to a closed partner list. None gives the individual an ongoing, revocable grant or a view of who holds the address.

### Cited Findings
- **Deutsche Post Nachsendeauftrag (mail forwarding)**: €31.90 online / €34.90 in branch for **6 months** for private customers, €51.90/€54.90 for businesses. Since 1 Jan 2025 only a 6-month term is sold (12/24-month options dropped). Up to 11 household members at no extra cost. [umzugsfahrplan.de 2026](https://umzugsfahrplan.de/ratgeber/nachsendeauftrag); [Deutsche Post](https://www.deutschepost.de/de/n/nachsendeservice.html); [anyhelpnow 2026](https://anyhelpnow.com/blog/nachsendeauftrag-einrichten)
- **Deutsche Post Umzugsmitteilung / Adressänderungsservice**: free for consumers; you enter the new address once and "over 1,000" affiliated companies (banks, insurers, energy suppliers, mail-order) that already have the old address receive the new one. [Postbank](https://www.postbank.de/privatkunden/services/vorteilsangebote/rund-um-ihren-umzug/umzug-mitteilen.html); [Wikipedia DE: Umzugsmitteilung](https://de.wikipedia.org/wiki/Umzugsmitteilung)
  - Inference: the business model is B2B, with companies paying Deutsche Post Adress for address updates. This was not confirmed from a primary pricing page.
- **Germany digital re-registration (eWA, elektronische Wohnsitzanmeldung)**: about **2,000 registration offices** connected, available to **55M+ citizens** (BMDS, Nov 2025). It requires the eID card with online function, AusweisApp and BundID. [BMDS](https://bmds.bund.de/aktuelles/aktuelle-meldungen/detail/elektronische-wohnsitzanmeldung-55-millionen-bundesbuergerinnen-und-buerger-koennen-sich-nach-einem-umzug-digital-ummelden); [Behörden Spiegel, 14 Nov 2025](https://www.behoerden-spiegel.de/2025/11/14/digitale-wohnsitzmeldung-fuer-55-millionen-buerger/); [wohnsitzanmeldung.gov.de](https://wohnsitzanmeldung.gov.de/)
- **UK Royal Mail Redirection 2026**: **£45 (3 months), £66.50 (6), £95 (12)** for one adult; concessions from £22.50. It does not cover non-Royal-Mail couriers (DPD, Evri, Amazon, etc.), so each account must be updated manually. [Mailcoms 2026](https://www.mailcoms.co.uk/news/royal-mail-redirection-service-prices-2026/); [Royal Mail](https://www.royalmail.com/personal/receiving-mail/redirection); [moveinout 2026](https://www.moveinout.co.uk/blog/royal-mail-redirection)
- **UK Tell Us Once**: a free DWP service **for bereavement**. It notifies DWP, HMRC, council tax, passports, DVLA, Blue Badge, electoral register and public-sector pensions. It is available in England, Wales and Scotland but not Northern Ireland. It **does not notify commercial organisations** and cannot redirect post. [York Council](https://www.york.gov.uk/deaths-funerals-cremations/tell-us-bereavement-services); [Bereavement Advice Centre](https://www.bereavementadvice.org/topics/registering-a-death-and-informing-others/the-tell-us-once-service/)
- **Estonia**:
  - Once-only principle: once a citizen gives data to the state, other agencies must reuse it and may not ask again. X-Road (since 2001) handles more than 2.2bn transactions a year across 3,000+ services. [LOTI](https://loti.london/blog/estonia-insights/); [Future Shift Labs](https://futureshiftlabs.com/x-road-technology-a-digital-backbone-of-estonias-cyber-security-and-dpi/) (secondary)
  - Citizens can use the **Data Tracker** to see which agency or official viewed their data, when and why. Unjustified access is a criminal offence. [RIA Data Tracker](https://www.ria.ee/en/state-information-system/people-centred-data-exchange/data-tracker); [e-Estonia](https://e-estonia.com/i-spy-with-my-little-eyeprivacy/)

### Inferences
- **Demand signal**: people pay €32–£95 just to *forward mail* for a few months after moving, and Deutsche Post finds it worth running a free propagation service to 1,000+ companies. The pain of address changes is real and recurring.
- **Gap revoked can fill**:
  - Existing services are **one-shot pushes to a closed partner list** chosen by the operator.
  - Private-sector propagation in the UK is not covered at all (Tell Us Once is public-sector only).
  - None of them lets the person see who holds the data, pause it, or revoke it.
  - revoked's living grant is effectively "Estonia's Data Tracker plus once-only, for the private sector, controlled by the individual".
- **Hard truth**: incumbents already solved the *recipient side* for big companies (Deutsche Post's 1,000 partners, bank APIs). revoked's realistic first recipients are the **long tail** that incumbents skip: small businesses, freelancers, landlords, clubs, schools, B2B supplier relationships. These are the people currently sending e-mail forms and spreadsheets.
- Germany's eWA shows that digital change-of-address reaches millions only when the **state** anchors identity (eID). revoked's DNS-anchored identities are a lighter trust signal and should be framed as "verify the requester is really example-business.de", not as a legal identity.

### Gaps
- No uptake numbers were found for the Deutsche Post Umzugsmitteilung, and its B2B price list was not found.
- No uptake numbers for eWA (only coverage).
- umzug.de / umziehen.de business models were not investigated.
- Tell Us Once usage statistics were not retrieved.

---

## 7. The two-sided / cold-start problem and strategies that worked

### Takeaway
Every PDS hit the same wall: individuals get no value until organisations accept the data, and organisations will not integrate until individuals show up. The strategies that have worked elsewhere:
- **single-player utility first** ("come for the tool, stay for the network"),
- **zero-integration recipients** (links, standard formats),
- a **drop-in "button"/SDK** that gives the integrating party an immediate conversion win (Plaid Link),
- in Europe, **state or regulatory mandate** (Open Banking, EUDI, Athumi).

A solo developer only has the first two available at launch.

### Cited Findings
- PDSs face the classic two-sided adoption problem: "for individuals to fully reap the benefits... a sufficient number of businesses need to adopt and use the PDS; otherwise, PDS will be useless for individuals". Businesses also resist giving up centralised control. [Fallatah et al. 2023](https://www.mdpi.com/1424-8220/23/3/1477)
- **"Come for the tool, stay for the network"** (Chris Dixon; see also Andrew Chen, *The Cold Start Problem*): products such as Instagram's filters and Google Docs gave single-player utility first and layered network effects on later, "because solving the cold start problem head-on is so brutal". [Substack summary](https://usopm.substack.com/p/come-for-the-tool-stay-for-the-network); [Sachin Rekhi on Chen](https://www.sachinrekhi.com/p/andrew-chen-the-cold-start-problem)
- **Plaid Link**:
  - It has a network of **7,000+ companies** connected to **12,000+ financial institutions**. **1 in 2 US adults with a bank account** have used Link, with about **750,000 connections per day**. [Plaid, "A decade of Plaid Link"](https://plaid.com/blog/ten-years-plaid-link/); [Plaid Link](https://plaid.com/plaid-link/)
  - Returning users who opt to be "remembered" convert **11% better**, so the network effect accrues to the integrator's conversion rate, not to the consumer's goodwill. [Plaid blog](https://plaid.com/blog/more-conversion-with-plaid-link/)
- **Plaxo** grew to 10M and then 20M users through viral contact-update e-mails, i.e. by piggybacking on e-mail. It then had to throttle those e-mails after the spam backlash. [Techdirt 2006](https://techdirt.com/articles/20060322/0317223.shtml); [Wikipedia](https://en.wikipedia.org/wiki/Plaxo)
- Even the state-backed German EUDI wallet finds **relying-party onboarding** to be "the real bottleneck" (about 115 organisations in 6 months of sandbox). [Corbado](https://www.corbado.com/blog/eudi-wallet-2026-deadline-rollout-eic-2026)
- Solid/Athumi needed EUR 14M of public programme money plus a public operator to land a handful of B2B use cases. [SolidLab](https://solidlab.be/); [Inrupt](https://www.inrupt.com/blog/athumi-inrupt-cronos-groep-extend-partnership)

### Inferences (strategy for revoked)
- **Single-player first**: the vault must be worth using with zero counterparties. Candidates:
  - a secure personal/business "data sheet" (addresses, IBANs, VAT IDs, insurance numbers),
  - self-hosted with export,
  - vCard/iCal feeds for the user's *own* devices.
  - This is the "tool".
- **Recipient needs nothing**: the biggest structural advantage over Solid, Mydex, digi.me and EUDI is that a grant is just a URL, JSON, vCard or CardDAV feed. The recipient does not install, register or integrate. This mirrors how Plaxo propagated through existing address books, minus the spam, because the *owner* chooses whom to share with.
- **Requests as the growth loop**: the business-to-customer "request" (a business asks many customers for templated data) is the natural viral vector, like Plaxo's update e-mails. It must be **requester-initiated and opt-in** to avoid the Plaxo spam trap. One business sending 500 requests seeds 500 accounts. Note that revoked's invariant #12 requires responders to have an account, which adds friction to this loop. The onboarding cost for a responder has to be very low (the Plaid "returning user" idea: one account, answer many requesters).
- **A "Plaid Link for master data" button/SDK**: a drop-in "Fill from revoked / keep this updated" button for web forms (checkout, supplier onboarding, tenant applications). The integrator's win must be **measurable** (fewer bounced invoices, fewer failed deliveries, less manual data entry), not a privacy sermon.
- **Pick a wedge with a built-in multi-party pain**. Examples:
  - B2B supplier and customer master data: address, IBAN, VAT ID, invoice e-mail. Stale IBANs and addresses cause failed payments and invoice fraud (IBAN-change fraud), and "verify the requester via DNS" directly addresses phishing.
  - Landlord–tenant, club–member and school–parent contact data.
  - Freelancer ↔ client billing details.
- **Don't compete where a mandate is coming** (identity/KYC: see Verimi). **Ride** the mandates by accepting EUDI attestations later as an input.

### Gaps
- No quantitative study found comparing adoption of zero-integration link sharing with API integration for data-sharing products.
- No data found on invoice/IBAN-change fraud losses in DE/EU (would quantify the B2B wedge); not researched in this session.

---

## 8. Honest limits: revocation cannot unsee copies; how others frame it

### Takeaway
Nobody claims that technical revocation deletes a recipient's copy. The mainstream framing, from EUDI, Open Banking and GDPR, splits the job in two:
- **Technical**: stop *future* access (no new reads, no updates).
- **Legal/contractual**: obligations on the recipient covering purpose limitation, erasure on request, and supervisory complaints, backed by audit logs showing who accessed what and when.

revoked should adopt the same honest two-layer framing.

### Cited Findings
- The EUDI wallet does not attempt to claw back presented data. Instead it gives the user a dashboard of relying parties and data exchanged, a one-tap **GDPR Art. 17 erasure request**, and a **report-to-DPA** function. A dedicated deletion-request interface is being standardised (EC TS07 / ETSI EN 319 482-2). [AEPD, Jan 2025](https://www.aepd.es/en/press-and-communication/blog/eidas2-the-eudi-wallet-and-the-gdpr-i); [EUDI standards issue #20](https://github.com/eu-digital-identity-wallet/eudi-doc-standards-and-technical-specifications/issues/20); [ARF discussion #480](https://github.com/eu-digital-identity-wallet/eudi-doc-architecture-and-reference-framework/discussions/480)
- In the VC/OpenID4VP world, retention after verification "is at the discretion of the Relying Party". Revocation (status lists) concerns the credential's validity, not the verifier's copy. [verana-labs issue #713](https://github.com/verana-labs/vs-agent/issues/713)
- Open Banking revocation stops the third party's ongoing access. Schemes separately define "what onward uses are permitted" and allocate controller responsibilities. [OBIE Revocation](https://standards.openbanking.org.uk/customer-experience-guidelines/introduction/revocation/latest/); [NatLawReview on DUAA Smart Data](https://natlawreview.com/article/uk-smart-data-and-data-use-and-access-act-2025-considerations-businesses)
- Estonia backs its access log with criminal liability for unjustified access. The deterrent is legal accountability plus transparency, not technical prevention. [e-Estonia](https://e-estonia.com/i-spy-with-my-little-eyeprivacy/); [RIA](https://www.ria.ee/en/state-information-system/people-centred-data-exchange/data-tracker)
- Athumi/Solid pitches consumers as deciding "which data they share with which companies... and for how long". That is time-bounded access, not a guarantee of deletion. [Athumi](https://athumi.eu/en/technologies/solid)

### Inferences
- Recommended honest framing for revoked: "Revoking stops them seeing future values and makes their copy go stale. It cannot erase what they already saw. For that, revoked gives you an access log and sends a GDPR erasure request on your behalf."
- The access log is evidence of *what* was seen and *when*, which is what makes an erasure demand enforceable.
- A useful feature parallel to EUDI: revoking a grant can **auto-generate a GDPR Art. 17 erasure request** to the recipient, whose identity is known when the requester is DNS-verified. This matches the EU wallet's own model and costs little.
- The "living grant" gives a real, underrated security benefit even though copies persist. A **stale copy is less valuable**: a changed address or rotated IBAN makes the old one useless. Combining "rotate the underlying value" with "revoke the grant" is the strongest story. It is also where CLAUDE.md's "a grant the responder cannot manage is a frozen snapshot" design principle pays off.
- Business customers need contractual cover. Terms under which the requester agrees to purpose limitation and deletion on revocation, recorded as an ISO 27560-style consent record, would align with FIDA/Open Banking practice.

### Gaps
- Did not retrieve primary GDPR text (Art. 7(3) withdrawal not affecting prior lawfulness; Art. 17/19 duty to notify recipients). The report writer can cite these from gdpr-info.eu if needed; they were not verified in this session.
- No source found for any product that measured whether revocation or erasure requests are actually honoured by recipients.
