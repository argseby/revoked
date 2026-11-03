package util

import (
	"encoding/json"
	"slices"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// Feature is a part of the app a person chooses to see. It is a display
// choice stored on the account, never a boundary: what a member may do is the
// permission catalogue, and a screen shows a feature only where both agree.
type Feature struct {
	Key         string
	Label       string
	Description string
	// Permission names the permission the feature is pointless without. A
	// client hides the feature from a member who lacks it; the server enforces
	// the permission regardless.
	Permission string
	// DefaultOn is what a fresh account sees before it chooses.
	DefaultOn bool
}

// Feature keys.
const (
	FeatureSharing      = "sharing"
	FeatureRequests     = "requests"
	FeatureAttestations = "attestations"
	FeatureContacts     = "contacts"
	FeatureTools        = "tools"
	FeatureDeveloper    = "developer"
)

// Features is the catalogue a person picks from, in display order. The vault
// is not in it: every account has one, and nothing else makes sense without it.
var Features = []Feature{
	{
		Key: FeatureSharing, Label: "Sharing",
		Description: "Share links to your records, and see who can read what.",
		Permission:  PermSharesRead,
		DefaultOn:   true,
	},
	{
		Key: FeatureRequests, Label: "Requests",
		Description: "Ask people for information and read their answers.",
		Permission:  PermRequestsRead,
		DefaultOn:   true,
	},
	{
		Key: FeatureAttestations, Label: "Identities and attestations",
		Description: "Prove it’s really you, and keep what others confirm about you.",
		Permission:  PermAttestationsRead,
		DefaultOn:   true,
	},
	{
		Key: FeatureContacts, Label: "Contacts",
		Description: "Keep the people you send to and ask from.",
		Permission:  PermContactsRead,
		DefaultOn:   true,
	},
	{
		Key: FeatureTools, Label: "Connected tools",
		Description: "Let other apps and services use your records, and sign in with Revoked.",
		DefaultOn:   true,
	},
	{
		Key: FeatureDeveloper, Label: "Developer",
		Description: "API keys, and the request behind every form.",
		DefaultOn:   true,
	},
}

// FeaturePreset bundles the permissions and features an invite hands out, so
// an admin picks a kind of member rather than sixteen boxes. The server stores
// the expanded lists; the preset's name is never kept.
type FeaturePreset struct {
	Key         string
	Label       string
	Description string
	Permissions []string
	Features    []string
}

// FeaturePresets are offered first when inviting, in display order.
var FeaturePresets = []FeaturePreset{
	{
		Key: "vault", Label: "Vault only",
		Description: "Keep and edit records. Nothing is shared or asked.",
		Permissions: []string{PermVaultRead, PermVaultWrite},
		Features:    []string{},
	},
	{
		Key: "vault-sharing", Label: "Vault and sharing",
		Description: "Keep records and share them with links.",
		Permissions: []string{PermVaultRead, PermVaultWrite, PermSharesRead, PermSharesManage},
		Features:    []string{FeatureSharing},
	},
	{
		Key: "everything", Label: "Everything",
		Description: "Every part of the workspace, without the sensitive permissions.",
		Permissions: []string{
			PermVaultRead, PermVaultWrite,
			PermResponsesRead, PermResponsesManage,
			PermSharesRead, PermSharesManage,
			PermRequestsRead, PermRequestsManage,
			PermTemplatesRead, PermTemplatesManage,
			PermIdentitiesRead,
			PermAttestationsRead,
			PermContactsRead, PermContactsManage,
			PermMembersRead,
		},
		Features: []string{FeatureSharing, FeatureRequests, FeatureAttestations, FeatureContacts, FeatureTools, FeatureDeveloper},
	},
}

// FeatureByKey returns the catalogue entry for a feature key.
func FeatureByKey(key string) (Feature, bool) {
	for _, f := range Features {
		if f.Key == key {
			return f, true
		}
	}
	return Feature{}, false
}

// AllFeatureKeys lists every feature key in catalogue order.
func AllFeatureKeys() []string {
	keys := make([]string, 0, len(Features))
	for _, f := range Features {
		keys = append(keys, f.Key)
	}
	return keys
}

// DefaultFeatureKeys is what an account sees until it chooses.
func DefaultFeatureKeys() []string {
	keys := []string{}
	for _, f := range Features {
		if f.DefaultOn {
			keys = append(keys, f.Key)
		}
	}
	return keys
}

// NormalizeFeatures dedupes keys into catalogue order; unknown keys are
// reported, not dropped, so a typo cannot quietly hide a part of the app.
func NormalizeFeatures(keys []string) (features []string, unknown []string) {
	features = []string{}
	for _, f := range Features {
		if slices.Contains(keys, f.Key) {
			features = append(features, f.Key)
		}
	}
	for _, k := range keys {
		if _, ok := FeatureByKey(k); !ok && !slices.Contains(unknown, k) {
			unknown = append(unknown, k)
		}
	}
	return features, unknown
}

// StoredFeatures reads a features JSON field. The second result tells an
// empty list ("show me nothing") from a field never written, which is what
// lets an invite's starting set land only on an account that never chose.
func StoredFeatures(record *core.Record, field string) ([]string, bool) {
	raw := strings.TrimSpace(record.GetString(field))
	if raw == "" || raw == "null" {
		return nil, false
	}
	var keys []string
	if err := json.Unmarshal([]byte(raw), &keys); err != nil {
		return nil, false
	}
	features, _ := NormalizeFeatures(keys)
	return features, true
}
