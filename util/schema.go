package util

// Ownership columns shared by every workspace-scoped collection; use the
// per-collection Fields.X.Y names when the collection is known.
const (
	FieldUser      = "user"
	FieldWorkspace = "workspace"
	FieldIdentity  = "identity"
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
	// Credentials are attestations a person holds about one of their own
	// identities, issued by this server or any other.
	Credentials string
	// AttestationChecks are one person asking another to show an attestation:
	// the request, and once answered, the verdict on what was shown.
	AttestationChecks string
}

type inviteFields struct {
	Workspace, TokenHash, Permissions, Role, InvitedBy, Email,
	Label, Status, ExpiresAt, MaxUses, UseCount, Created, Updated string
}

type recordFields struct {
	Key, Value, User, Workspace, Label, Type, Format, RequestedBy, AliasOf,
	File, Filename, ContentHash, HashSalt, Mime, Size, Created, Updated string
}

type sectionFields struct {
	Key, Name, User, Workspace, Records, RequestedBy, Created, Updated string
}

type linkFields struct {
	Slug, Label, User, Workspace, Sections, Records, Status,
	Password, ExpiresAt, MaxViews, ViewCount, Identity, RequireHandshake,
	Request, Grants, Data, SenderName, Identifier, Watermark, WatermarkText,
	Purpose, Connection, Ref, HandedOver, ProposedBy,
	RemoteDomain, RemoteRequest, GrantTokenHash, SignInClient, Created, Updated string
}

type workspaceFields struct {
	Name, Slug, Type, Created, Updated string
}

type userFields struct {
	ActiveWorkspace, ActiveRole, Email, Verified, Avatar, Active string
}

type memberFields struct {
	User, Workspace, Role, Permissions, Created, Updated string
}

type apiKeyFields struct {
	Token, Label, User, Workspace, Scopes, LastUsedAt, ExpiresAt, Created, Updated string
}

type auditLogFields struct {
	User, Action, Collection, RecordId, OldData, NewData, Ip, UserAgent, Workspace, ApiKey string
}

type templateFields struct {
	Name, Description, Schema, Workspace, Created, Updated string
}

type identityFields struct {
	Name, Certificate, PublicKey, PrivateKey, Fingerprint,
	ParentSignature, DomainAtIssue, IsPrimary,
	Status, RevokedAt, RevokedReason,
	User, Workspace, Created, Updated string
}

type requestFields struct {
	Slug, Label, Status, Identity, Template, Password, ExpiresAt,
	MaxResponses, ResponseCount, Identifier, CallbackUrl,
	RequireHandshake, IdentityScope, AllowExtraFields, User, Workspace, Created, Updated string
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
	User, Origin, Slug, Label, Groups, Created, Updated string
}

type bookmarkGroupFields struct {
	User, Name, Created, Updated string
}

type connectionFields struct {
	User, Workspace, ClientId, ClientName, AllowRevoke, AllowHandOver, ExpiresAt, LastUsedAt, Created, Updated string
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

type attestationFields struct {
	User, Workspace, Type, Label, Claims, Status, ExpiresAt,
	OfferTokenHash, OfferExpiresAt,
	SubjectFingerprint, SubjectDomain, SubjectName,
	IssuedAt, RevokedAt, RevokedReason, Created, Updated string
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
	ExpiresAt, Result, AnsweredAt, Created, Updated string
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
}

// Fields holds the field (column) names for each collection.
var Fields = struct {
	Workspace          workspaceFields
	User               userFields
	WorkspaceMember    memberFields
	ApiKey             apiKeyFields
	Record             recordFields
	Section            sectionFields
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
}{
	Workspace: workspaceFields{
		Name:    "name",
		Slug:    "slug",
		Type:    "type",
		Created: "created",
		Updated: "updated",
	},
	User: userFields{
		ActiveWorkspace: "activeWorkspace",
		ActiveRole:      "activeRole",
		Email:           "email",
		Verified:        "verified",
		Avatar:          "avatar",
		Active:          "active",
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
		Token:      "token",
		Label:      "label",
		User:       "user",
		Workspace:  "workspace",
		Scopes:     "scopes",
		LastUsedAt: "lastUsedAt",
		ExpiresAt:  "expiresAt",
		Created:    "created",
		Updated:    "updated",
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
		Origin:  "origin",
		Slug:    "slug",
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
		User:          "user",
		Workspace:     "workspace",
		ClientId:      "clientId",
		ClientName:    "clientName",
		AllowRevoke:   "allowRevoke",
		AllowHandOver: "allowHandOver",
		ExpiresAt:     "expiresAt",
		LastUsedAt:    "lastUsedAt",
		Created:       "created",
		Updated:       "updated",
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
		Created:    "created",
		Updated:    "updated",
	},
}
