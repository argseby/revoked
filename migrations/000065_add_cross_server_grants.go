package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds what a grant needs to cross from one server to another.
//
// On the responder's server, a link that answers another server's request
// names that server (remoteDomain) and the request's slug there
// (remoteRequest), and keeps the hash of the token that server reads it with.
// The link is otherwise an ordinary request-born link: its owner sees,
// updates and revokes it as any other.
//
// On the requester's server, remoteGrants holds the other side: where the
// answer lives and the token to read it with, never the values. The token is
// kept in the clear because this server presents it; the field is hidden and
// the collection is superuser-only, read through the requests routes alone.
//
// grantRecords indexes which request-born links resolve which vault entry, so
// a changed entry reaches every grant that reads it without scanning links.
// grantDeliveries is the outbox for grant events, retried with backoff.
// Both are internal and superuser-only.
func init() {
	migrations.Register(func(app core.App) error {
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return err
		}
		requests, err := app.FindCollectionByNameOrId(util.Coll.Requests)
		if err != nil {
			return err
		}

		if links.Fields.GetByName(util.Fields.Link.RemoteDomain) == nil {
			links.Fields.Add(
				&core.TextField{Name: util.Fields.Link.RemoteDomain, Max: 255},
				&core.TextField{Name: util.Fields.Link.RemoteRequest, Max: 255},
				&core.TextField{Name: util.Fields.Link.GrantTokenHash, Max: 64, Hidden: true},
			)
			links.AddIndex("idxLinksRemote", false,
				util.Fields.Link.RemoteDomain+", "+util.Fields.Link.RemoteRequest+", "+util.Fields.Link.User, "")
			if err := app.Save(links); err != nil {
				return err
			}
		}

		f := util.Fields.RemoteGrant
		remote := core.NewBaseCollection(util.Coll.RemoteGrants)
		remote.Fields.Add(
			&core.RelationField{
				Name:          f.Request,
				CollectionId:  requests.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.TextField{Name: f.Domain, Required: true, Max: 255},
			&core.TextField{Name: f.Grant, Required: true, Max: 64},
			&core.TextField{Name: f.Token, Required: true, Max: 128, Hidden: true},
			&core.SelectField{
				Name:      f.Status,
				Required:  true,
				Values:    util.LinkStatuses,
				MaxSelect: 1,
			},
			// Milliseconds of the event that set the status, so an event that
			// arrives late cannot undo a newer one.
			&core.NumberField{Name: f.StatusAt, OnlyInt: true},
			&core.JSONField{Name: f.Keys},
			&core.TextField{Name: f.SenderName, Max: 255},
			&core.TextField{Name: f.Identifier, Max: 255},
			&core.TextField{Name: f.IdentityName, Max: 255},
			&core.TextField{Name: f.IdentityFingerprint, Max: 64},
			&core.TextField{Name: f.IdentityDomain, Max: 255},
			&core.AutodateField{Name: f.Created, OnCreate: true},
			&core.AutodateField{Name: f.Updated, OnCreate: true, OnUpdate: true},
		)
		remote.AddIndex("idxRemoteGrantsGrant", true, f.Domain+", "+f.Grant, "")
		remote.AddIndex("idxRemoteGrantsRequest", false, f.Request, "")
		if err := app.Save(remote); err != nil {
			return err
		}

		g := util.Fields.GrantRecord
		index := core.NewBaseCollection(util.Coll.GrantRecords)
		index.Fields.Add(
			&core.RelationField{
				Name:          g.Link,
				CollectionId:  links.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// Text, not a relation: a deleted entry must still be found here,
			// to tell the grants that read it.
			&core.TextField{Name: g.Record, Required: true, Max: 64},
		)
		index.AddIndex("idxGrantRecordsRecord", false, g.Record, "")
		index.AddIndex("idxGrantRecordsLink", false, g.Link, "")
		if err := app.Save(index); err != nil {
			return err
		}
		if err := backfillGrantRecords(app, index); err != nil {
			return err
		}

		d := util.Fields.GrantDelivery
		deliveries := core.NewBaseCollection(util.Coll.GrantDeliveries)
		deliveries.Fields.Add(
			&core.SelectField{
				Name:      d.Kind,
				Required:  true,
				Values:    util.DeliveryKinds,
				MaxSelect: 1,
			},
			// A peer domain for kind peer, a callback URL for kind callback.
			&core.TextField{Name: d.Target, Required: true, Max: 2048},
			// The request whose owner hears about a callback that never landed.
			&core.TextField{Name: d.Request, Max: 64},
			&core.JSONField{Name: d.Payload},
			&core.NumberField{Name: d.Attempts, OnlyInt: true},
			&core.DateField{Name: d.NextAttemptAt},
			&core.DateField{Name: d.DeliveredAt},
			&core.DateField{Name: d.FailedAt},
			&core.TextField{Name: d.LastError, Max: 500},
			&core.AutodateField{Name: d.Created, OnCreate: true},
		)
		deliveries.AddIndex("idxGrantDeliveriesDue", false,
			d.DeliveredAt+", "+d.FailedAt+", "+d.NextAttemptAt, "")
		return app.Save(deliveries)
	}, func(app core.App) error {
		for _, name := range []string{util.Coll.GrantDeliveries, util.Coll.GrantRecords, util.Coll.RemoteGrants} {
			if col, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		links, err := app.FindCollectionByNameOrId(util.Coll.Links)
		if err != nil {
			return nil
		}
		links.RemoveIndex("idxLinksRemote")
		links.Fields.RemoveByName(util.Fields.Link.RemoteDomain)
		links.Fields.RemoveByName(util.Fields.Link.RemoteRequest)
		links.Fields.RemoveByName(util.Fields.Link.GrantTokenHash)
		return app.Save(links)
	})
}

// backfillGrantRecords indexes the request answers that exist already, so a
// change to an entry behind one of them is announced from the first start on.
func backfillGrantRecords(app core.App, index *core.Collection) error {
	links, err := app.FindRecordsByFilter(util.Coll.Links,
		"request != '' && (status = 'active' || status = 'paused')", "", 0, 0)
	if err != nil {
		return err
	}
	for _, link := range links {
		grants := map[string]string{}
		if err := link.UnmarshalJSONField(util.Fields.Link.Grants, &grants); err != nil {
			continue
		}
		seen := map[string]bool{}
		for _, recordID := range grants {
			if recordID == "" || seen[recordID] {
				continue
			}
			seen[recordID] = true
			row := core.NewRecord(index)
			row.Set(util.Fields.GrantRecord.Link, link.Id)
			row.Set(util.Fields.GrantRecord.Record, recordID)
			if err := app.Save(row); err != nil {
				return err
			}
		}
	}
	return nil
}
