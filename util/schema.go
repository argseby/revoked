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
	Request, Grants, Data, SenderName, Identifier, Created, Updated string
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
	Name, Schema, Workspace, Created, Updated string
}

type identityFields struct {
	Name, Certificate, PublicKey, PrivateKey, Fingerprint,
	ParentSignature, DomainAtIssue, IsPrimary,
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
}

// Fields holds the field (column) names for each collection.
var Fields = struct {
	Workspace       workspaceFields
	User            userFields
	WorkspaceMember memberFields
	ApiKey          apiKeyFields
	Record          recordFields
	Section         sectionFields
	Link            linkFields
	AuditLog        auditLogFields
	Template        templateFields
	Identity        identityFields
	Request         requestFields
	RequestResponse requestResponseFields
	Notification    notificationFields
	Handshake       handshakeFields
	Invite          inviteFields
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
		Name:      "name",
		Schema:    "schema",
		Workspace: "workspace",
		Created:   "created",
		Updated:   "updated",
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
		User:            "user",
		Workspace:       "workspace",
		Created:         "created",
		Updated:         "updated",
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
}
