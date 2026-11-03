package services

import (
	"revoked/util"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// holdLink pauses a live link on behalf of the tool or service it belongs to.
func holdLink(app core.App, link *core.Record) error {
	f := util.Fields.Link
	if link.GetString(f.Status) != util.StatusActive {
		return nil
	}
	link.Set(f.Status, util.StatusPaused)
	link.Set(f.HeldPaused, true)
	return app.Save(link)
}

// releaseLink undoes holdLink, and nothing else: a link its owner paused
// themselves stays paused.
func releaseLink(app core.App, link *core.Record) error {
	f := util.Fields.Link
	if !link.GetBool(f.HeldPaused) {
		return nil
	}
	if link.GetString(f.Status) == util.StatusPaused {
		link.Set(f.Status, util.StatusActive)
	}
	link.Set(f.HeldPaused, false)
	return app.Save(link)
}

func revokeLink(app core.App, link *core.Record) error {
	f := util.Fields.Link
	if link.GetString(f.Status) == util.StatusRevoked && !link.GetBool(f.HeldPaused) {
		return nil
	}
	link.Set(f.Status, util.StatusRevoked)
	link.Set(f.HeldPaused, false)
	return app.Save(link)
}

func connectionLinks(app core.App, connectionID string) ([]*core.Record, error) {
	return app.FindAllRecords(util.Coll.Links,
		dbx.HashExp{util.Fields.Link.Connection: connectionID})
}

func connectionRequests(app core.App, connectionID string) ([]*core.Record, error) {
	return app.FindAllRecords(util.Coll.Requests,
		dbx.HashExp{util.Fields.Request.Connection: connectionID})
}

// holdRequest, releaseRequest and closeRequest are holdLink, releaseLink and
// revokeLink for the requests a tool proposed.
func holdRequest(app core.App, request *core.Record) error {
	f := util.Fields.Request
	if request.GetString(f.Status) != util.StatusActive {
		return nil
	}
	request.Set(f.Status, util.StatusPaused)
	request.Set(f.HeldPaused, true)
	return app.Save(request)
}

func releaseRequest(app core.App, request *core.Record) error {
	f := util.Fields.Request
	if !request.GetBool(f.HeldPaused) {
		return nil
	}
	if request.GetString(f.Status) == util.StatusPaused {
		request.Set(f.Status, util.StatusActive)
	}
	request.Set(f.HeldPaused, false)
	return app.Save(request)
}

func closeRequest(app core.App, request *core.Record, revoke bool) error {
	f := util.Fields.Request
	if revoke {
		if request.GetString(f.Status) == util.StatusRevoked && !request.GetBool(f.HeldPaused) {
			return nil
		}
		request.Set(f.Status, util.StatusRevoked)
	} else if !request.GetBool(f.HeldPaused) {
		return nil
	}
	request.Set(f.HeldPaused, false)
	return app.Save(request)
}

// eachConnectionRequest applies fn to every request the tool proposed.
func eachConnectionRequest(app core.App, connectionID string, fn func(core.App, *core.Record) error) error {
	requests, err := connectionRequests(app, connectionID)
	if err != nil {
		return err
	}
	for _, r := range requests {
		if err := fn(app, r); err != nil {
			return err
		}
	}
	return nil
}

// PauseConnection refuses the tool's tokens and holds the links and requests
// it proposed.
func PauseConnection(app core.App, conn *core.Record) error {
	return app.RunInTransaction(func(tx core.App) error {
		conn.Set(util.Fields.Connection.Paused, true)
		if err := tx.Save(conn); err != nil {
			return err
		}
		links, err := connectionLinks(tx, conn.Id)
		if err != nil {
			return err
		}
		for _, link := range links {
			if err := holdLink(tx, link); err != nil {
				return err
			}
		}
		return eachConnectionRequest(tx, conn.Id, holdRequest)
	})
}

// ResumeConnection undoes PauseConnection. The expiry is left alone: only
// connecting the tool again renews it.
func ResumeConnection(app core.App, conn *core.Record) error {
	return app.RunInTransaction(func(tx core.App) error {
		conn.Set(util.Fields.Connection.Paused, false)
		if err := tx.Save(conn); err != nil {
			return err
		}
		links, err := connectionLinks(tx, conn.Id)
		if err != nil {
			return err
		}
		for _, link := range links {
			if err := releaseLink(tx, link); err != nil {
				return err
			}
		}
		return eachConnectionRequest(tx, conn.Id, releaseRequest)
	})
}

// DisconnectConnection deletes the connection and its tokens. Its links and
// requests are revoked when revokeLinks is set. Otherwise they stay their owner's, and one
// held by a pause stays paused rather than waking up as the tool goes: it can
// no longer be released by the tool, so it becomes an ordinary paused link.
func DisconnectConnection(app core.App, conn *core.Record, revokeLinks bool) error {
	return app.RunInTransaction(func(tx core.App) error {
		links, err := connectionLinks(tx, conn.Id)
		if err != nil {
			return err
		}
		f := util.Fields.Link
		for _, link := range links {
			if revokeLinks {
				if err := revokeLink(tx, link); err != nil {
					return err
				}
			} else if link.GetBool(f.HeldPaused) {
				link.Set(f.HeldPaused, false)
				if err := tx.Save(link); err != nil {
					return err
				}
			}
		}
		if err := eachConnectionRequest(tx, conn.Id, func(app core.App, r *core.Record) error {
			return closeRequest(app, r, revokeLinks)
		}); err != nil {
			return err
		}
		return tx.Delete(conn)
	})
}

// SignInStatus reads a row's status; a row from before there were statuses is
// an active one.
func SignInStatus(row *core.Record) string {
	if s := row.GetString(util.Fields.SignIn.Status); s != "" {
		return s
	}
	return util.StatusActive
}

// signInLink is the link holding what a person shared with a service, in any
// of their workspaces.
func signInLink(app core.App, userID, clientID string) *core.Record {
	f := util.Fields.Link
	link, err := app.FindFirstRecordByFilter(util.Coll.Links,
		f.User+" = {:u} && "+f.SignInClient+" = {:c}", dbx.Params{"u": userID, "c": clientID})
	if err != nil {
		return nil
	}
	return link
}

// PauseSignIn refuses new sign-ins at the service and holds what it may read.
// A disconnected service has nothing left to pause.
func PauseSignIn(app core.App, row *core.Record) error {
	if SignInStatus(row) != util.StatusActive {
		return nil
	}
	return app.RunInTransaction(func(tx core.App) error {
		f := util.Fields.SignIn
		row.Set(f.Status, util.StatusPaused)
		if err := tx.Save(row); err != nil {
			return err
		}
		if link := signInLink(tx, row.GetString(f.User), row.GetString(f.ClientId)); link != nil {
			return holdLink(tx, link)
		}
		return nil
	})
}

// ResumeSignIn undoes PauseSignIn.
func ResumeSignIn(app core.App, row *core.Record) error {
	if SignInStatus(row) != util.StatusPaused {
		return nil
	}
	return app.RunInTransaction(func(tx core.App) error {
		f := util.Fields.SignIn
		row.Set(f.Status, util.StatusActive)
		if err := tx.Save(row); err != nil {
			return err
		}
		if link := signInLink(tx, row.GetString(f.User), row.GetString(f.ClientId)); link != nil {
			return releaseLink(tx, link)
		}
		return nil
	})
}

// DisconnectSignIn ends what a service can do: its grant is revoked, and the
// generation moves, so no code or access token issued before now works again
// even if the person later signs in.
//
// With newID the service gets a new subject at the next sign-in, and everything
// else that would tie that sign-in to this one goes too. The link is detached
// so the next share mints another: its id reaches the service. The name choice
// is forgotten so it is not offered again by default. The row keeps the scopes,
// because the service still holds what it learned.
//
// Disconnecting again can only add a new ID, never take one back.
func DisconnectSignIn(app core.App, row *core.Record, newID bool) error {
	f := util.Fields.SignIn
	already := SignInStatus(row) == util.StatusDisconnected
	if already && (!newID || row.GetBool(f.NewIdOnReturn)) {
		return nil
	}
	return app.RunInTransaction(func(tx core.App) error {
		if link := signInLink(tx, row.GetString(f.User), row.GetString(f.ClientId)); link != nil {
			if newID {
				link.Set(util.Fields.Link.SignInClient, "")
			}
			link.Set(util.Fields.Link.Status, util.StatusRevoked)
			link.Set(util.Fields.Link.HeldPaused, false)
			if err := tx.Save(link); err != nil {
				return err
			}
		}
		row.Set(f.Status, util.StatusDisconnected)
		row.Set(f.Generation, row.GetInt(f.Generation)+1)
		if !already {
			row.Set(f.DisconnectedAt, types.NowDateTime())
		}
		if newID {
			row.Set(f.SubjectVersion, row.GetInt(f.SubjectVersion)+1)
			row.Set(f.NewIdOnReturn, true)
			row.Set(f.Link, "")
			row.Set(f.NameRecord, "")
			row.Set(f.NameIdentity, "")
		}
		return tx.Save(row)
	})
}

// SignInAllows reports whether something issued under generation may still act
// for this person at this service.
func SignInAllows(app core.App, userID, clientID string, generation int) bool {
	row := findSignIn(app, userID, clientID)
	return row != nil && SignInStatus(row) == util.StatusActive &&
		row.GetInt(util.Fields.SignIn.Generation) == generation
}
