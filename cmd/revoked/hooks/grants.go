package hooks

import (
	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindGrantHooks keeps the entry → grant index current, announces every
// change to a request-born link or to an entry one reads, and runs the
// delivery worker that carries those announcements out.
//
// Events are queued from inside the save that caused them, with the app it ran
// in, so a rolled-back change announces nothing. The worker is woken once the
// queued row has committed.
func BindGrantHooks(app core.App, root *server.RootKey) {
	// Where a link points on another server, which service it was given to
	// at sign-in, and how either reads it are set by the server — never by a
	// client.
	app.OnRecordCreateRequest(util.Coll.Links).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := util.RestrictFields(e, serverSetLinkFields...); err != nil {
			return err
		}
		return e.Next()
	})
	app.OnRecordUpdateRequest(util.Coll.Links).BindFunc(func(e *core.RecordRequestEvent) error {
		if err := util.RestrictFields(e, serverSetLinkFields...); err != nil {
			return err
		}
		return e.Next()
	})

	app.OnRecordCreate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		return services.SyncGrantIndex(e.App, e.Record)
	})

	app.OnRecordUpdate(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		original := e.Record.Original()
		statusBefore := original.GetString(util.Fields.Link.Status)
		grantsBefore := original.GetString(util.Fields.Link.Grants)
		if err := e.Next(); err != nil {
			return err
		}
		if err := services.SyncGrantIndex(e.App, e.Record); err != nil {
			return err
		}
		status := e.Record.GetString(util.Fields.Link.Status)
		switch {
		case status != statusBefore:
			services.DispatchGrantEvents(e.App, []*core.Record{e.Record},
				services.EventTypeForStatus(status), "")
		case e.Record.GetString(util.Fields.Link.Grants) != grantsBefore &&
			(status == util.StatusActive || status == util.StatusPaused):
			services.DispatchGrantEvents(e.App, []*core.Record{e.Record}, util.GrantEventChanged, "")
		}
		return nil
	})

	// A deleted grant is a revoked one to whoever held it.
	app.OnRecordDelete(util.Coll.Links).BindFunc(func(e *core.RecordEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		if s := e.Record.GetString(util.Fields.Link.Status); s == util.StatusActive || s == util.StatusPaused {
			services.DispatchGrantEvents(e.App, []*core.Record{e.Record},
				util.GrantEventRevoked, util.StatusRevoked)
		}
		return nil
	})

	app.OnRecordUpdate(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		changed := recordContentChanged(e.Record)
		if err := e.Next(); err != nil {
			return err
		}
		if changed {
			services.DispatchRecordChanged(e.App, e.Record.Id)
		}
		return nil
	})

	// The grants are collected first: once the entry is gone, so are the
	// aliases that led to it.
	app.OnRecordDelete(util.Coll.Records).BindFunc(func(e *core.RecordEvent) error {
		links := services.GrantLinksForRecord(e.App, e.Record.Id)
		if err := e.Next(); err != nil {
			return err
		}
		services.DispatchRecordDeleted(e.App, e.Record.Id, links)
		return nil
	})

	app.OnRecordAfterCreateSuccess(util.Coll.GrantDeliveries).BindFunc(func(e *core.RecordEvent) error {
		services.KickGrantDeliveries()
		return e.Next()
	})

	stop := make(chan struct{})
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go services.RunGrantDeliveries(app, root, stop)
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		select {
		case <-stop:
		default:
			close(stop)
		}
		return e.Next()
	})
}

var serverSetLinkFields = []string{
	util.Fields.Link.RemoteDomain,
	util.Fields.Link.RemoteRequest,
	util.Fields.Link.GrantTokenHash,
	util.Fields.Link.SignInClient,
}
