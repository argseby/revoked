package util

import "slices"

// How much of its reach a key or a connected tool may use. Reach itself — which
// sections, or for a tool on the owner's own machine the whole vault — is
// stored beside it, never as record scopes: a record scope on a key would be
// honoured by the collection rules, which see the whole workspace.
const (
	VaultAccessRead  = "read"
	VaultAccessWrite = "write"
)

// VaultAccessValues lists the stored values of vaultAccess.
var VaultAccessValues = []string{VaultAccessRead, VaultAccessWrite}

// ConnectionStorageEnv caps, in megabytes, what one key or tool may keep in
// the vault: its files and values together. 0 means no cap.
const ConnectionStorageEnv = "CONNECTION_STORAGE_MB"

// DefaultConnectionStorageMB applies when ConnectionStorageEnv is unset.
const DefaultConnectionStorageMB = 100

// ConnectionStorageLimit is the cap in bytes; -1 means none.
func ConnectionStorageLimit() int64 {
	mb := LimitFromEnv(ConnectionStorageEnv, DefaultConnectionStorageMB)
	if mb == 0 {
		return -1
	}
	return int64(mb) << 20
}

// ConnectionPermissions are the catalogue entries a connected tool may hold:
// the ones a tool's routes act on. Members, templates, contacts and settings
// stay with people and keys, whose routes are the collection API.
var ConnectionPermissions = []string{
	PermSharesRead, PermSharesManage, PermRequestsManage, PermAttestationsIssue,
	PermVaultRead, PermVaultWrite,
}

// ConnectionEndScopes let a tool end what it proposed or created, and nothing
// more: what "End what it proposed" grants.
var ConnectionEndScopes = []string{ScopeLinkUpdate, ScopeRequestUpdate, ScopeAttestationUpdate}

// ConnectionHandOverScope lets a tool receive the links handed to it.
const ConnectionHandOverScope = ScopeLinkRead

// SplitVaultPermissions takes the vault keys out of a grant and returns the
// rest with the access they ask for. Write implies read.
func SplitVaultPermissions(keys []string) (rest []string, access string) {
	for _, k := range keys {
		switch k {
		case PermVaultWrite:
			access = VaultAccessWrite
		case PermVaultRead:
			if access == "" {
				access = VaultAccessRead
			}
		default:
			rest = append(rest, k)
		}
	}
	return rest, access
}

// HeldPermissions lists the catalogue keys a grant holds in full, with the
// vault keys its access stands for.
func HeldPermissions(scopes []string, vaultAccess string) []string {
	out := []string{}
	for _, p := range Permissions {
		switch p.Key {
		case PermVaultRead:
			if vaultAccess != "" {
				out = append(out, p.Key)
			}
			continue
		case PermVaultWrite:
			if vaultAccess == VaultAccessWrite {
				out = append(out, p.Key)
			}
			continue
		}
		if len(p.Scopes) > 0 && !slices.ContainsFunc(p.Scopes, func(s string) bool { return !slices.Contains(scopes, s) }) {
			out = append(out, p.Key)
		}
	}
	return out
}

// HasAllScopes reports whether have holds every scope in want.
func HasAllScopes(have, want []string) bool {
	for _, s := range want {
		if !slices.Contains(have, s) {
			return false
		}
	}
	return true
}
