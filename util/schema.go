package util

// Ownership columns shared by every workspace-scoped collection; use the
// per-collection Fields.X.Y names when the collection is known.
const (
	FieldUser      = "user"
	FieldWorkspace = "workspace"
	FieldIdentity  = "identity"
)

// Columns a link and a request name identically, for code that handles a
// grant without caring which of the two it is.
const (
	FieldSlug   = "slug"
	FieldLabel  = "label"
	FieldStatus = "status"
)

type collectionSchema struct {
	Workspaces       string
	WorkspaceMembers string
	Users            string
	ApiKeys          string
	Records          string
	Sections         string
	AuditLogs        string
	Links            string
	Templates        string
	Identities       string
	Requests         string
	RequestResponses string
	Notifications    string
	Handshakes       string
	Invites          string
	// IdentityRevocations outlives the identity row itself, so a fingerprint
	// whose identity was hard-deleted still resolves to a definite answer.
	IdentityRevocations string
	Bookmarks           string
	BookmarkGroups      string
	// Connections are tools the owner connected: what they may do, and their
	// own small store. ConnectionTokens are the per-browser credentials.
	Connections      string
	ConnectionTokens string
	// Passkeys are how a person signs in: one row per authenticator they
	// registered. PasskeyTickets are the one-time links that let an account
	// register one without being signed in with another.
	Passkeys       string
	PasskeyTickets string
	// Reminders are a person's own: a vault entry to be reminded about, at a
	// date or when an entry changes.
	Reminders string
	// RemoteGrants are answers to this server's requests that live on another
	// server: an address and a token, never the values themselves.
	RemoteGrants string
	// GrantRecords index which request-born links resolve which vault entry,
	// so a change to an entry reaches every grant that reads it.
	GrantRecords string
	// GrantDeliveries are the outbox for grant events: to another server, or
	// to a request's callback URL. Retried with backoff until delivered.
	GrantDeliveries string
	// Attestations are statements this server signs about an identity, usually
	// one issued elsewhere: what is stated, about whom, and whether it still
	// stands. The signed credential itself is handed to its subject and not
	// kept here.
	Attestations string
	// AttestationStatus holds one bit per issued credential: revoked or not.
	// It outlives the attestation row, so deleting a workspace cannot turn a
	// revoked credential back into a valid one.
	AttestationStatus string
	// Groups name parts of a workspace (HR, Service, Techs) that an item's
	// audience can list. GroupMembers says who is in each. Superuser-only
	// until groups can be managed from the app (VISIBILITY.md §6).
	Groups       string
	GroupMembers string
	// Credentials are attestations a person holds about one of their own
	// identities, issued by this server or any other.
	Credentials string
	// AttestationChecks are one person asking another to show an attestation:
	// the request, and once answered, the verdict on what was shown.
	AttestationChecks string
	// AttestationShares are links a holder made to show an attestation to
	// whoever opens them: one presentation, signed for that link, and checked
	// again each time it is opened.
	AttestationShares string
	// SignIns are the services a person approved a sign-in at, so they can
	// find them again.
	SignIns string
	// Contacts are the counterparties a workspace sends to and asks from. A
	// contact names a route, never an identity relation: a peer's key material
	// is held as its own fingerprint and domain, proven by the peer check,
	// because the identity relation is ownership-checked for this workspace's
	// own identities.
	Contacts string
	// ContactDeliveries is the ledger of grants put in other people's trays:
	// one row per delivery, written by the server and read by nobody else. The
	// per-pair cap counts these rows rather than keeping a counter in memory,
	// so two instances cannot hand out the budget twice, and the recipient
	// deleting the bookmark cannot buy the sender a fresh one. The same rows
	// say a grant once came the other way, which is what tells a stranger from
	// somebody already in touch.
	ContactDeliveries string
	// ContactBlocks are the senders a person refuses: an account, an address,
	// or a whole domain. Personal, like bookmarks — being sent something
	// unwanted is not the workspace's business.
	ContactBlocks string
	// DeviceKeys is each person's signed, append-only list of the devices that
	// hold their keys. WorkspaceKeyEpochs and WorkspaceKeyWraps are a workspace's
	// encryption keys, wrapped per device. The server can read none of it.
	DeviceKeys         string
	WorkspaceKeyEpochs string
	WorkspaceKeyWraps  string
	// AccountKeyEpochs and AccountKeyWraps are a person's own key, wrapped
	// only to their own devices: what their identities' private keys travel
	// under, so a workspace key shared with other members never opens them.
	AccountKeyEpochs string
	AccountKeyWraps  string
	// WebhookEndpoints are where a workspace wants its events sent.
	// WebhookEvents record what happened, WebhookDeliveries carry one event
	// to one endpoint, and WebhookAttempts keep every try so a failing
	// receiver can be diagnosed. All four are reached through /api/webhooks
	// only: the endpoint's signing secret must never ride a list response.
	WebhookEndpoints  string
	WebhookEvents     string
	WebhookDeliveries string
	WebhookAttempts   string
}

type inviteFields struct {
	Workspace, TokenHash, Permissions, Features, Role, InvitedBy, Email,
	Label, Status, ExpiresAt, MaxUses, UseCount, Created, Updated string
}

type recordFields struct {
	Key, Value, User, Workspace, Label, Type, Format, RequestedBy, AliasOf,
	File, Filename, ContentHash, HashSalt, Mime, Size, Created, Updated,
	Sealed, SealedValue, SealedVersion, KeyEpoch, KeyWrap, WrittenBy, WrittenByName string
	// Readers and Editors are the members who may see and change the record,
	// worked out by services.Access from the sections holding it. The server
	// alone writes them; the collection rules match them.
	Readers, Editors string
}

type deviceKeyFields struct {
	User, Seq, Action, Kind, Label, CredentialId, HpkePublicKey, SigningPublicKey, TargetSeq,
	PreviousHash, SignerSeq, AnchorSignature, Signature, Created string
}

type workspaceKeyEpochFields struct {
	Workspace, Epoch, PriorWrap, RotationDue, CreatedBy, Created string
}

type workspaceKeyWrapFields struct {
	Workspace, Epoch, User, DeviceSeq, Wrap, SignerSeq, ChainSeq, Signature, Created string
	// Granter is who handed the key over, empty when it was the recipient's own
	// device. On such a copy ChainSeq is the granter's list and
	// RecipientChainSeq the recipient's.
	Granter, RecipientChainSeq string
}

type accountKeyEpochFields struct {
	User, Epoch, PriorWrap, RotationDue, Created string
}

type accountKeyWrapFields struct {
	User, Epoch, DeviceSeq, Wrap, SignerSeq, ChainSeq, Signature, Created string
}

type sectionFields struct {
	Key, Name, User, Workspace, Records, RequestedBy, Created, Updated string
	// Shared is the section's audience as it was before audiences existed:
	// true for "workspace". Kept in step with AudienceKind for one release.
	Shared string
	// AudienceKind and AudienceGroups say who sees the section (private,
	// workspace or groups); Editing says whether that audience may change it.
	// Only the owner changes them. Readers and Editors are worked out from
	// them by services.Access and written by the server alone.
	AudienceKind, AudienceGroups, Editing, Readers, Editors string
}

type groupFields struct {
	Workspace, Key, Name, Created, Updated string
}

type groupMemberFields struct {
	Group, User, Created string
}

type linkFields struct {
	Slug, Label, User, Workspace, Sections, Records, Status,
	Password, ExpiresAt, MaxViews, ViewCount, Identity, RequireHandshake,
	Request, Grants, Data, SenderName, Identifier, Watermark, WatermarkText,
	Purpose, Connection, Ref, HandedOver, ProposedBy, HeldPaused,
	RemoteDomain, RemoteRequest, GrantTokenHash, SignInClient, Created, Updated string
}

type workspaceFields struct {
	Name, Slug, Type, Created, Updated string
	// DefaultAudience is who sees a new item of each area that names no
	// audience: {"links": "private", "templates": "workspace", …}
	// (VISIBILITY.md §4.4). An area left out keeps its built-in default.
	DefaultAudience string
}

type userFields struct {
	ActiveWorkspace, ActiveRole, Email, Verified, Avatar, Active, Features string
	// TotpSecret is the confirmed authenticator secret, TotpPending one being
	// set up and not yet confirmed. Both hidden: no rule or API returns them.
	// TotpEnabledAt is when the confirmed one was turned on.
	// TotpLastStep is the time step of the last code accepted, so no code
	// works twice.
	TotpSecret, TotpPending, TotpEnabledAt, TotpLastStep string
}

type memberFields struct {
	User, Workspace, Role, Permissions, Created, Updated string
}

type apiKeyFields struct {
	Token, Label, User, Workspace, Scopes, VaultAccess, Sections, LastUsedAt, ExpiresAt, Created, Updated string
}

type auditLogFields struct {
	User, Action, Collection, RecordId, OldData, NewData, Ip, UserAgent, Workspace, ApiKey string
}

type templateFields struct {
	Name, Description, Schema, Workspace, Created, Updated string
	// User is who made the template, set since templates carry an audience
	// (VISIBILITY.md, phase 3). Empty on older ones and on built-ins.
	User string
}

type identityFields struct {
	Name, Certificate, PublicKey, PrivateKey, Fingerprint,
	ParentSignature, DomainAtIssue, IsPrimary,
	Status, RevokedAt, RevokedReason,
	SealedKey, SealedKeyEpoch, SealedKeyScope,
	User, Workspace, Created, Updated string
}

type requestFields struct {
	Slug, Label, Status, Identity, Template, Password, ExpiresAt,
	MaxResponses, ResponseCount, Identifier, CallbackUrl,
	RequireHandshake, IdentityScope, AllowExtraFields, User, Workspace,
	Connection, Ref, ProposedBy, HeldPaused, Created, Updated string
}

// requestResponseFields describes the legacy `requestResponses` collection.
//
// Deprecated: the grant primitive was unified into `links`. The collection is
// intentionally not dropped and is still referenced by historical migrations
// (000020/000031/000032), so this struct must stay.
type requestResponseFields struct {
	Request, Identity, Identifier, Data, SenderName, Workspace,
	Records, Responder, Status, Grants, Created string
}

type notificationFields struct {
	User, Workspace, Type, Title, Message, RefCollection, RefId, Read, Created string
}

type handshakeFields struct {
	Request, Link, Identity, TokenHash, Workspace, Created string
}

type identityRevocationFields struct {
	Fingerprint, RevokedAt, Reason, Domain, Created string
}

type bookmarkFields struct {
	User, Sender, Origin, Slug, Kind, Label, Groups, Created, Updated string
}

type bookmarkGroupFields struct {
	User, Name, Created, Updated string
}

type connectionFields struct {
	User, Workspace, ClientId, ClientName, AllowVaultRead,
	Scopes, VaultAccess, Section, SectionOff, Sections, Paused, ExpiresAt, LastUsedAt, Created, Updated string
}

type connectionTokenFields struct {
	Connection, CodeHash, CodeChallenge, CodeExpiresAt, RedirectUri,
	Poll, TokenHash, LastUsedAt, Created string
}

type passkeyFields struct {
	User, CredentialId, Credential, Name, LastUsedAt, Created string
}

type passkeyTicketFields struct {
	User, TokenHash, ExpiresAt, Created string
}

type remoteGrantFields struct {
	Request, Domain, Grant, Token, Status, StatusAt, Keys, SenderName, Identifier,
	IdentityName, IdentityFingerprint, IdentityDomain, Created, Updated string
}

type grantRecordFields struct {
	Link, Record string
}

type grantDeliveryFields struct {
	Kind, Target, Request, Payload, Attempts, NextAttemptAt, DeliveredAt,
	FailedAt, LastError, Created string
}

type reminderFields struct {
	User, Workspace, Record, Kind, DueAt, Watch, Note, FiredAt, Created, Updated string
}

type contactFields struct {
	Workspace, Name, User, Email, PeerDomain, PeerFingerprint,
	TrustState, VerifiedAt, LastUsedAt, Created, Updated string
	// CreatedBy is the member who added the contact, its owner for who sees
	// it (VISIBILITY.md). User is someone else: the account the contact
	// points to. Empty on contacts older than audiences.
	CreatedBy string
}

type contactDeliveryFields struct {
	Sender, Recipient, Workspace, Kind, Created string
}

type contactBlockFields struct {
	User, BlockedUser, Email, Domain, Created string
}

type attestationFields struct {
	User, Workspace, Type, Label, Claims, Status, ExpiresAt,
	OfferTokenHash, OfferExpiresAt,
	SubjectFingerprint, SubjectDomain, SubjectName,
	IssuedAt, RevokedAt, RevokedReason, Connection, Ref, ProposedBy, Created, Updated string
}

type attestationStatusFields struct {
	Idx, Attestation, Revoked, RevokedAt, Created string
}

type credentialFields struct {
	User, Workspace, Identity, Issuer, Type, Credential, Claims,
	IssuedAt, ExpiresAt, Created, Updated string
}

type attestationCheckFields struct {
	User, Identity, Type, Issuers, Claims, Nonce, Audience, Status,
	ExpiresAt, Result, AnsweredAt, Connection, Ref, ProposedBy, Created, Updated string
}

type attestationShareFields struct {
	User, Credential, Status, Nonce, Audience, TokenHash, Presentation,
	Disclosed, ExpiresAt, ViewCount, LastViewedAt, Created, Updated string
}

type webhookEndpointFields struct {
	Workspace, User, Url, Description, Events, Secret, PreviousSecret,
	PreviousSecretExpiresAt, Enabled, DisabledReason, FailingSince, Created, Updated string
}

type webhookEventFields struct {
	Workspace, Type, Data, Test, Created string
}

type webhookDeliveryFields struct {
	Workspace, Endpoint, Event, Status, Attempts, NextAttemptAt, LastStatus,
	LastError, DeliveredAt, Created, Updated string
}

type webhookAttemptFields struct {
	Delivery, Endpoint, Workspace, ResponseStatus, ResponseBody, Error,
	DurationMs, Manual, Created string
}

type signInFields struct {
	User, Workspace, ClientId, Scopes, Link, NameRecord, NameIdentity, LastSignInAt,
	Status, Generation, SubjectVersion, DisconnectedAt, NewIdOnReturn, Created, Updated string
}

// Coll holds the collection (table) names used across the backend.
var Coll = collectionSchema{
	Workspaces:       "workspaces",
	WorkspaceMembers: "workspaceMembers",
	Users:            "users",
	ApiKeys:          "apiKeys",
	Records:          "records",
	Sections:         "sections",
	AuditLogs:        "auditLogs",
	Links:            "links",
	Templates:        "templates",
	Identities:       "identities",
	Requests:         "requests",
	// Deprecated: unified into Links; retained for historical data and migrations.
	RequestResponses: "requestResponses",
	Notifications:    "notifications",
	Handshakes:       "handshakes",
	Invites:          "invites",

	IdentityRevocations: "identityRevocations",
	Bookmarks:           "bookmarks",
	BookmarkGroups:      "bookmarkGroups",
	Connections:         "connections",
	ConnectionTokens:    "connectionTokens",
	Passkeys:            "passkeys",
	PasskeyTickets:      "passkeyTickets",
	Reminders:           "reminders",
	RemoteGrants:        "remoteGrants",
	GrantRecords:        "grantRecords",
	GrantDeliveries:     "grantDeliveries",
	Attestations:        "attestations",
	AttestationStatus:   "attestationStatus",
	Credentials:         "credentials",
	AttestationChecks:   "attestationChecks",
	AttestationShares:   "attestationShares",
	SignIns:             "signIns",
	Contacts:            "contacts",
	ContactDeliveries:   "contactDeliveries",
	ContactBlocks:       "contactBlocks",
	DeviceKeys:          "deviceKeys",
	WorkspaceKeyEpochs:  "workspaceKeyEpochs",
	WorkspaceKeyWraps:   "workspaceKeyWraps",
	AccountKeyEpochs:    "accountKeyEpochs",
	AccountKeyWraps:     "accountKeyWraps",
	WebhookEndpoints:    "webhookEndpoints",
	WebhookEvents:       "webhookEvents",
	WebhookDeliveries:   "webhookDeliveries",
	WebhookAttempts:     "webhookAttempts",
	Groups:              "groups",
	GroupMembers:        "groupMembers",
}

// Fields holds the field (column) names for each collection.
var Fields = struct {
	Workspace          workspaceFields
	User               userFields
	WorkspaceMember    memberFields
	ApiKey             apiKeyFields
	Record             recordFields
	DeviceKey          deviceKeyFields
	WorkspaceKeyEpoch  workspaceKeyEpochFields
	WorkspaceKeyWrap   workspaceKeyWrapFields
	AccountKeyEpoch    accountKeyEpochFields
	AccountKeyWrap     accountKeyWrapFields
	Section            sectionFields
	Group              groupFields
	GroupMember        groupMemberFields
	Link               linkFields
	AuditLog           auditLogFields
	Template           templateFields
	Identity           identityFields
	IdentityRevocation identityRevocationFields
	Request            requestFields
	RequestResponse    requestResponseFields
	Notification       notificationFields
	Handshake          handshakeFields
	Invite             inviteFields
	Bookmark           bookmarkFields
	BookmarkGroup      bookmarkGroupFields
	Connection         connectionFields
	ConnectionToken    connectionTokenFields
	Passkey            passkeyFields
	PasskeyTicket      passkeyTicketFields
	Reminder           reminderFields
	RemoteGrant        remoteGrantFields
	GrantRecord        grantRecordFields
	GrantDelivery      grantDeliveryFields
	Attestation        attestationFields
	AttestationStatus  attestationStatusFields
	Credential         credentialFields
	AttestationCheck   attestationCheckFields
	AttestationShare   attestationShareFields
	SignIn             signInFields
	Contact            contactFields
	ContactDelivery    contactDeliveryFields
	ContactBlock       contactBlockFields
	WebhookEndpoint    webhookEndpointFields
	WebhookEvent       webhookEventFields
	WebhookDelivery    webhookDeliveryFields
	WebhookAttempt     webhookAttemptFields
}{
	Workspace: workspaceFields{
		Name:    "name",
		Slug:    "slug",
		Type:    "type",
		Created: "created",
		Updated: "updated",

		DefaultAudience: "defaultAudience",
	},
	User: userFields{
		ActiveWorkspace: "activeWorkspace",
		ActiveRole:      "activeRole",
		Email:           "email",
		Verified:        "verified",
		Avatar:          "avatar",
		Active:          "active",
		Features:        "features",
		TotpSecret:      "totpSecret",
		TotpPending:     "totpPending",
		TotpEnabledAt:   "totpEnabledAt",
		TotpLastStep:    "totpLastStep",
	},
	WorkspaceMember: memberFields{
		User:        "user",
		Workspace:   "workspace",
		Role:        "role",
		Permissions: "permissions",
		Created:     "created",
		Updated:     "updated",
	},
	ApiKey: apiKeyFields{
		Token:       "token",
		Label:       "label",
		User:        "user",
		Workspace:   "workspace",
		Scopes:      "scopes",
		VaultAccess: "vaultAccess",
		Sections:    "sections",
		LastUsedAt:  "lastUsedAt",
		ExpiresAt:   "expiresAt",
		Created:     "created",
		Updated:     "updated",
	},
	Record: recordFields{
		Key:         "key",
		Value:       "value",
		Type:        "type",
		Format:      "format",
		Label:       "label",
		Workspace:   "workspace",
		User:        "user",
		RequestedBy: "requestedBy",
		AliasOf:     "aliasOf",
		File:        "file",
		Filename:    "filename",
		ContentHash: "contentHash",
		HashSalt:    "hashSalt",
		Mime:        "mime",
		Size:        "size",
		Created:     "created",
		Updated:     "updated",

		Sealed:        "sealed",
		SealedValue:   "sealedValue",
		SealedVersion: "sealedVersion",
		KeyEpoch:      "keyEpoch",
		KeyWrap:       "keyWrap",
		WrittenBy:     "writtenBy",
		WrittenByName: "writtenByName",
		Readers:       "readers",
		Editors:       "editors",
	},
	DeviceKey: deviceKeyFields{
		User:             "user",
		Seq:              "seq",
		Action:           "action",
		Kind:             "kind",
		Label:            "label",
		CredentialId:     "credentialId",
		HpkePublicKey:    "hpkePublicKey",
		SigningPublicKey: "signingPublicKey",
		TargetSeq:        "targetSeq",
		PreviousHash:     "previousHash",
		SignerSeq:        "signerSeq",
		AnchorSignature:  "anchorSignature",
		Signature:        "signature",
		Created:          "created",
	},
	WorkspaceKeyEpoch: workspaceKeyEpochFields{
		Workspace:   "workspace",
		Epoch:       "epoch",
		PriorWrap:   "priorWrap",
		RotationDue: "rotationDue",
		CreatedBy:   "createdBy",
		Created:     "created",
	},
	WorkspaceKeyWrap: workspaceKeyWrapFields{
		Workspace: "workspace",
		Epoch:     "epoch",
		User:      "user",
		DeviceSeq: "deviceSeq",
		Wrap:      "wrap",
		SignerSeq: "signerSeq",
		ChainSeq:  "chainSeq",
		Signature: "signature",
		Created:   "created",

		Granter:           "granter",
		RecipientChainSeq: "recipientChainSeq",
	},
	AccountKeyEpoch: accountKeyEpochFields{
		User:        "user",
		Epoch:       "epoch",
		PriorWrap:   "priorWrap",
		RotationDue: "rotationDue",
		Created:     "created",
	},
	AccountKeyWrap: accountKeyWrapFields{
		User:      "user",
		Epoch:     "epoch",
		DeviceSeq: "deviceSeq",
		Wrap:      "wrap",
		SignerSeq: "signerSeq",
		ChainSeq:  "chainSeq",
		Signature: "signature",
		Created:   "created",
	},
	Section: sectionFields{
		Key:         "key",
		Name:        "name",
		Workspace:   "workspace",
		User:        "user",
		Records:     "records",
		RequestedBy: "requestedBy",
		Created:     "created",
		Updated:     "updated",
		Shared:      "shared",

		AudienceKind:   "audienceKind",
		AudienceGroups: "audienceGroups",
		Editing:        "editing",
		Readers:        "readers",
		Editors:        "editors",
	},
	Group: groupFields{
		Workspace: "workspace",
		Key:       "key",
		Name:      "name",
		Created:   "created",
		Updated:   "updated",
	},
	GroupMember: groupMemberFields{
		Group:   "group",
		User:    "user",
		Created: "created",
	},
	Link: linkFields{
		Slug:             "slug",
		Label:            "label",
		User:             "user",
		Workspace:        "workspace",
		Sections:         "sections",
		Records:          "records",
		Status:           "status",
		Password:         "password",
		ExpiresAt:        "expiresAt",
		MaxViews:         "maxViews",
		ViewCount:        "viewCount",
		Identity:         "identity",
		RequireHandshake: "requireHandshake",
		Request:          "request",
		Grants:           "grants",
		Data:             "data",
		SenderName:       "senderName",
		Identifier:       "identifier",
		Watermark:        "watermark",
		WatermarkText:    "watermarkText",
		Purpose:          "purpose",
		Connection:       "connection",
		Ref:              "ref",
		HandedOver:       "handedOver",
		ProposedBy:       "proposedBy",
		RemoteDomain:     "remoteDomain",
		RemoteRequest:    "remoteRequest",
		GrantTokenHash:   "grantTokenHash",
		SignInClient:     "signInClient",
		HeldPaused:       "heldPaused",
		Created:          "created",
		Updated:          "updated",
	},
	AuditLog: auditLogFields{
		User:       "user",
		Action:     "action",
		Collection: "collection",
		RecordId:   "recordId",
		OldData:    "oldData",
		NewData:    "newData",
		Ip:         "ip",
		UserAgent:  "userAgent",
		Workspace:  "workspace",
		ApiKey:     "apiKey",
	},
	Template: templateFields{
		Name:        "name",
		Description: "description",
		Schema:      "schema",
		Workspace:   "workspace",
		Created:     "created",
		Updated:     "updated",
		User:        "user",
	},
	Identity: identityFields{
		Name:            "name",
		Certificate:     "certificate",
		PublicKey:       "publicKey",
		PrivateKey:      "privateKey",
		Fingerprint:     "fingerprint",
		ParentSignature: "parentSignature",
		DomainAtIssue:   "domainAtIssue",
		IsPrimary:       "isPrimary",
		Status:          "status",
		RevokedAt:       "revokedAt",
		RevokedReason:   "revokedReason",
		SealedKey:       "sealedKey",
		SealedKeyEpoch:  "sealedKeyEpoch",
		SealedKeyScope:  "sealedKeyScope",
		User:            "user",
		Workspace:       "workspace",
		Created:         "created",
		Updated:         "updated",
	},
	IdentityRevocation: identityRevocationFields{
		Fingerprint: "fingerprint",
		RevokedAt:   "revokedAt",
		Reason:      "reason",
		Domain:      "domain",
		Created:     "created",
	},
	Request: requestFields{
		Slug:             "slug",
		Label:            "label",
		Status:           "status",
		Identity:         "identity",
		Template:         "template",
		Password:         "password",
		ExpiresAt:        "expiresAt",
		MaxResponses:     "maxResponses",
		ResponseCount:    "responseCount",
		Identifier:       "identifier",
		CallbackUrl:      "callbackUrl",
		RequireHandshake: "requireHandshake",
		IdentityScope:    "identityScope",
		AllowExtraFields: "allowExtraFields",
		User:             "user",
		Workspace:        "workspace",
		Connection:       "connection",
		Ref:              "ref",
		ProposedBy:       "proposedBy",
		HeldPaused:       "heldPaused",
		Created:          "created",
		Updated:          "updated",
	},
	RequestResponse: requestResponseFields{
		Request:    "request",
		Identity:   "identity",
		Identifier: "identifier",
		Data:       "data",
		SenderName: "senderName",
		Workspace:  "workspace",
		Records:    "records",
		Responder:  "responder",
		Status:     "status",
		Grants:     "grants",
		Created:    "created",
	},
	Notification: notificationFields{
		User:          "user",
		Workspace:     "workspace",
		Type:          "type",
		Title:         "title",
		Message:       "message",
		RefCollection: "refCollection",
		RefId:         "refId",
		Read:          "read",
		Created:       "created",
	},
	Handshake: handshakeFields{
		Request:   "request",
		Link:      "link",
		Identity:  "identity",
		TokenHash: "tokenHash",
		Workspace: "workspace",
		Created:   "created",
	},
	Invite: inviteFields{
		Workspace:   "workspace",
		TokenHash:   "tokenHash",
		Permissions: "permissions",
		Features:    "features",
		Role:        "role",
		InvitedBy:   "invitedBy",
		Email:       "email",
		Label:       "label",
		Status:      "status",
		ExpiresAt:   "expiresAt",
		MaxUses:     "maxUses",
		UseCount:    "useCount",
		Created:     "created",
		Updated:     "updated",
	},
	Bookmark: bookmarkFields{
		User:    "user",
		Sender:  "sender",
		Origin:  "origin",
		Slug:    "slug",
		Kind:    "kind",
		Label:   "label",
		Groups:  "groups",
		Created: "created",
		Updated: "updated",
	},
	BookmarkGroup: bookmarkGroupFields{
		User:    "user",
		Name:    "name",
		Created: "created",
		Updated: "updated",
	},
	Connection: connectionFields{
		User:           "user",
		Workspace:      "workspace",
		ClientId:       "clientId",
		ClientName:     "clientName",
		AllowVaultRead: "allowVaultRead",
		Scopes:         "scopes",
		VaultAccess:    "vaultAccess",
		Section:        "section",
		SectionOff:     "sectionOff",
		Sections:       "sections",
		Paused:         "paused",
		ExpiresAt:      "expiresAt",
		LastUsedAt:     "lastUsedAt",
		Created:        "created",
		Updated:        "updated",
	},
	ConnectionToken: connectionTokenFields{
		Connection:    "connection",
		CodeHash:      "codeHash",
		CodeChallenge: "codeChallenge",
		CodeExpiresAt: "codeExpiresAt",
		RedirectUri:   "redirectUri",
		Poll:          "poll",
		TokenHash:     "tokenHash",
		LastUsedAt:    "lastUsedAt",
		Created:       "created",
	},
	Passkey: passkeyFields{
		User:         "user",
		CredentialId: "credentialId",
		Credential:   "credential",
		Name:         "name",
		LastUsedAt:   "lastUsedAt",
		Created:      "created",
	},
	PasskeyTicket: passkeyTicketFields{
		User:      "user",
		TokenHash: "tokenHash",
		ExpiresAt: "expiresAt",
		Created:   "created",
	},
	Reminder: reminderFields{
		User:      "user",
		Workspace: "workspace",
		Record:    "record",
		Kind:      "kind",
		DueAt:     "dueAt",
		Watch:     "watch",
		Note:      "note",
		FiredAt:   "firedAt",
		Created:   "created",
		Updated:   "updated",
	},
	RemoteGrant: remoteGrantFields{
		Request:             "request",
		Domain:              "domain",
		Grant:               "grant",
		Token:               "token",
		Status:              "status",
		StatusAt:            "statusAt",
		Keys:                "keys",
		SenderName:          "senderName",
		Identifier:          "identifier",
		IdentityName:        "identityName",
		IdentityFingerprint: "identityFingerprint",
		IdentityDomain:      "identityDomain",
		Created:             "created",
		Updated:             "updated",
	},
	GrantRecord: grantRecordFields{
		Link:   "link",
		Record: "record",
	},
	GrantDelivery: grantDeliveryFields{
		Kind:          "kind",
		Target:        "target",
		Request:       "request",
		Payload:       "payload",
		Attempts:      "attempts",
		NextAttemptAt: "nextAttemptAt",
		DeliveredAt:   "deliveredAt",
		FailedAt:      "failedAt",
		LastError:     "lastError",
		Created:       "created",
	},
	Attestation: attestationFields{
		User:               "user",
		Workspace:          "workspace",
		Type:               "type",
		Label:              "label",
		Claims:             "claims",
		Status:             "status",
		ExpiresAt:          "expiresAt",
		OfferTokenHash:     "offerTokenHash",
		OfferExpiresAt:     "offerExpiresAt",
		SubjectFingerprint: "subjectFingerprint",
		SubjectDomain:      "subjectDomain",
		SubjectName:        "subjectName",
		IssuedAt:           "issuedAt",
		RevokedAt:          "revokedAt",
		RevokedReason:      "revokedReason",
		Connection:         "connection",
		Ref:                "ref",
		ProposedBy:         "proposedBy",
		Created:            "created",
		Updated:            "updated",
	},
	AttestationStatus: attestationStatusFields{
		Idx:         "idx",
		Attestation: "attestation",
		Revoked:     "revoked",
		RevokedAt:   "revokedAt",
		Created:     "created",
	},
	Credential: credentialFields{
		User:       "user",
		Workspace:  "workspace",
		Identity:   "identity",
		Issuer:     "issuer",
		Type:       "type",
		Credential: "credential",
		Claims:     "claims",
		IssuedAt:   "issuedAt",
		ExpiresAt:  "expiresAt",
		Created:    "created",
		Updated:    "updated",
	},
	AttestationCheck: attestationCheckFields{
		User:       "user",
		Identity:   "identity",
		Type:       "type",
		Issuers:    "issuers",
		Claims:     "claims",
		Nonce:      "nonce",
		Audience:   "audience",
		Status:     "status",
		ExpiresAt:  "expiresAt",
		Result:     "result",
		AnsweredAt: "answeredAt",
		Connection: "connection",
		Ref:        "ref",
		ProposedBy: "proposedBy",
		Created:    "created",
		Updated:    "updated",
	},
	AttestationShare: attestationShareFields{
		User:         "user",
		Credential:   "credential",
		Status:       "status",
		Nonce:        "nonce",
		Audience:     "audience",
		TokenHash:    "tokenHash",
		Presentation: "presentation",
		Disclosed:    "disclosed",
		ExpiresAt:    "expiresAt",
		ViewCount:    "viewCount",
		LastViewedAt: "lastViewedAt",
		Created:      "created",
		Updated:      "updated",
	},
	SignIn: signInFields{
		User:         "user",
		Workspace:    "workspace",
		ClientId:     "clientId",
		Scopes:       "scopes",
		Link:         "link",
		NameRecord:   "nameRecord",
		NameIdentity: "nameIdentity",
		LastSignInAt: "lastSignInAt",

		Status:         "status",
		Generation:     "generation",
		SubjectVersion: "subjectVersion",
		DisconnectedAt: "disconnectedAt",
		NewIdOnReturn:  "newIdOnReturn",

		Created: "created",
		Updated: "updated",
	},
	Contact: contactFields{
		Workspace:       "workspace",
		Name:            "name",
		User:            "user",
		Email:           "email",
		PeerDomain:      "peerDomain",
		PeerFingerprint: "peerFingerprint",
		TrustState:      "trustState",
		VerifiedAt:      "verifiedAt",
		LastUsedAt:      "lastUsedAt",
		Created:         "created",
		Updated:         "updated",
		CreatedBy:       "createdBy",
	},
	ContactDelivery: contactDeliveryFields{
		Sender:    "sender",
		Recipient: "recipient",
		Workspace: "workspace",
		Kind:      "kind",
		Created:   "created",
	},
	ContactBlock: contactBlockFields{
		User:        "user",
		BlockedUser: "blockedUser",
		Email:       "email",
		Domain:      "domain",
		Created:     "created",
	},
	WebhookEndpoint: webhookEndpointFields{
		Workspace:               "workspace",
		User:                    "user",
		Url:                     "url",
		Description:             "description",
		Events:                  "events",
		Secret:                  "secret",
		PreviousSecret:          "previousSecret",
		PreviousSecretExpiresAt: "previousSecretExpiresAt",
		Enabled:                 "enabled",
		DisabledReason:          "disabledReason",
		FailingSince:            "failingSince",
		Created:                 "created",
		Updated:                 "updated",
	},
	WebhookEvent: webhookEventFields{
		Workspace: "workspace",
		Type:      "type",
		Data:      "data",
		Test:      "test",
		Created:   "created",
	},
	WebhookDelivery: webhookDeliveryFields{
		Workspace:     "workspace",
		Endpoint:      "endpoint",
		Event:         "event",
		Status:        "status",
		Attempts:      "attempts",
		NextAttemptAt: "nextAttemptAt",
		LastStatus:    "lastStatus",
		LastError:     "lastError",
		DeliveredAt:   "deliveredAt",
		Created:       "created",
		Updated:       "updated",
	},
	WebhookAttempt: webhookAttemptFields{
		Delivery:       "delivery",
		Endpoint:       "endpoint",
		Workspace:      "workspace",
		ResponseStatus: "responseStatus",
		ResponseBody:   "responseBody",
		Error:          "error",
		DurationMs:     "durationMs",
		Manual:         "manual",
		Created:        "created",
	},
}
