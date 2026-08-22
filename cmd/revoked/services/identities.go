package services

import (
	"fmt"
	"time"

	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// IdentityIsActive reports whether an identity may still be honoured.
//
// An empty status counts as active: rows predating migration 000049 are
// backfilled to "active" by it, so the blank only ever appears in the window
// before that migration has run, where refusing every identity would take the
// whole server down rather than fail safe.
func IdentityIsActive(identity *core.Record) bool {
	if identity == nil {
		return false
	}
	status := identity.GetString(util.Fields.Identity.Status)
	return status == "" || status == util.StatusActive
}

// IdentityStatusOf reports an identity's status as it appears on the wire.
func IdentityStatusOf(identity *core.Record) string {
	if IdentityIsActive(identity) {
		return util.StatusActive
	}
	return util.StatusRevoked
}

// RevokeWorkspaceIdentities revokes every identity a user holds in one
// workspace. This is what closes the gap behind a departing member: the
// certificate they already hold asserts membership of this workspace's domain,
// and nothing but a revocation stops it from going on asserting that.
//
// A single guarded UPDATE rather than a read-modify-write loop, so a concurrent
// re-add cannot interleave and leave half the set live.
func RevokeWorkspaceIdentities(app core.App, userId, workspaceId, reason string) error {
	if userId == "" || workspaceId == "" {
		return nil
	}
	_, err := app.DB().
		Update(
			util.Coll.Identities,
			dbx.Params{
				util.Fields.Identity.Status:        util.StatusRevoked,
				util.Fields.Identity.RevokedAt:     types.NowDateTime(),
				util.Fields.Identity.RevokedReason: reason,
				util.Fields.Identity.IsPrimary:     false,
			},
			dbx.And(
				dbx.HashExp{
					util.Fields.Identity.User:      userId,
					util.Fields.Identity.Workspace: workspaceId,
				},
				dbx.Not(dbx.HashExp{util.Fields.Identity.Status: util.StatusRevoked}),
			),
		).
		Execute()
	return err
}

// IdentityStatus is this server's current answer about one fingerprint,
// resolved from the identity row when it still exists and from the tombstone
// when it does not.
type IdentityStatus struct {
	Fingerprint string
	Status      string
	RevokedAt   time.Time
	Reason      string
	Domain      string

	// Known is false when the server has never heard of the fingerprint. It is
	// not the same as revoked, and a verifier must not treat it as such: a
	// restored backup or a reinstall answers this way about identities that
	// were perfectly valid.
	Known bool
}

// LookupIdentityStatus resolves a fingerprint to the server's current answer.
// The identity row wins when present, because it carries the live status; the
// tombstone answers for fingerprints whose row is gone.
func LookupIdentityStatus(app core.App, fingerprint string) (IdentityStatus, error) {
	if fingerprint == "" {
		return IdentityStatus{}, nil
	}

	identity, err := app.FindFirstRecordByFilter(
		util.Coll.Identities,
		fmt.Sprintf("%s = {:fingerprint}", util.Fields.Identity.Fingerprint),
		map[string]any{"fingerprint": fingerprint},
	)
	if err == nil && identity != nil {
		status := IdentityStatus{
			Fingerprint: fingerprint,
			Status:      util.StatusActive,
			Domain:      identity.GetString(util.Fields.Identity.DomainAtIssue),
			Known:       true,
		}
		if !IdentityIsActive(identity) {
			status.Status = util.StatusRevoked
			status.RevokedAt = identity.GetDateTime(util.Fields.Identity.RevokedAt).Time()
			status.Reason = identity.GetString(util.Fields.Identity.RevokedReason)
		}
		return status, nil
	}

	tombstone, err := app.FindFirstRecordByFilter(
		util.Coll.IdentityRevocations,
		fmt.Sprintf("%s = {:fingerprint}", util.Fields.IdentityRevocation.Fingerprint),
		map[string]any{"fingerprint": fingerprint},
	)
	if err == nil && tombstone != nil {
		return IdentityStatus{
			Fingerprint: fingerprint,
			Status:      util.StatusRevoked,
			RevokedAt:   tombstone.GetDateTime(util.Fields.IdentityRevocation.RevokedAt).Time(),
			Reason:      tombstone.GetString(util.Fields.IdentityRevocation.Reason),
			Domain:      tombstone.GetString(util.Fields.IdentityRevocation.Domain),
			Known:       true,
		}, nil
	}

	return IdentityStatus{Fingerprint: fingerprint}, nil
}

// WriteIdentityTombstone records that a fingerprint's identity row is gone, so
// a later status query answers "revoked" rather than the silence that a missing
// row would otherwise produce.
//
// The first tombstone wins: a fingerprint that already has one keeps its
// original timestamp and reason.
func WriteIdentityTombstone(app core.App, fingerprint, domain, reason string) error {
	if fingerprint == "" {
		return nil
	}

	existing, err := app.FindFirstRecordByFilter(
		util.Coll.IdentityRevocations,
		fmt.Sprintf("%s = {:fingerprint}", util.Fields.IdentityRevocation.Fingerprint),
		map[string]any{"fingerprint": fingerprint},
	)
	if err == nil && existing != nil {
		return nil
	}

	col, err := app.FindCollectionByNameOrId(util.Coll.IdentityRevocations)
	if err != nil {
		return err
	}
	if reason == "" {
		reason = util.RevocationDeleted
	}

	tombstone := core.NewRecord(col)
	tombstone.Set(util.Fields.IdentityRevocation.Fingerprint, fingerprint)
	tombstone.Set(util.Fields.IdentityRevocation.RevokedAt, types.NowDateTime())
	tombstone.Set(util.Fields.IdentityRevocation.Reason, reason)
	tombstone.Set(util.Fields.IdentityRevocation.Domain, domain)
	return app.Save(tombstone)
}
