package migrations

import (
	"slices"

	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// Adds workspace webhooks: endpoints, the events they hear about, one delivery
// per event and endpoint, and every attempt at it.
//
// All four collections keep nil rules. They are served by /api/webhooks only,
// which checks the webhook:manage scope itself; a collection rule would put an
// endpoint's signing secret into every list response.
//
// Members who may manage the workspace get the new scope, since nobody else
// could grant it to them: a grant may never exceed the granter's own access.
func init() {
	migrations.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId(util.Coll.WebhookEndpoints); err == nil {
			return nil
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}

		ep := util.Fields.WebhookEndpoint
		endpoints := core.NewBaseCollection(util.Coll.WebhookEndpoints)
		endpoints.Fields.Add(
			&core.RelationField{Name: ep.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: ep.User, CollectionId: users.Id, MaxSelect: 1},
			&core.TextField{Name: ep.Url, Required: true, Max: 2048},
			&core.TextField{Name: ep.Description, Max: 200},
			&core.JSONField{Name: ep.Events, MaxSize: 4000},
			&core.TextField{Name: ep.Secret, Required: true, Max: 200, Hidden: true},
			&core.TextField{Name: ep.PreviousSecret, Max: 200, Hidden: true},
			&core.DateField{Name: ep.PreviousSecretExpiresAt},
			&core.BoolField{Name: ep.Enabled},
			&core.TextField{Name: ep.DisabledReason, Max: 200},
			&core.DateField{Name: ep.FailingSince},
			&core.AutodateField{Name: ep.Created, OnCreate: true},
			&core.AutodateField{Name: ep.Updated, OnCreate: true, OnUpdate: true},
		)
		endpoints.AddIndex("idxWebhookEndpointsWorkspace", false, ep.Workspace, "")
		if err := app.Save(endpoints); err != nil {
			return err
		}

		ev := util.Fields.WebhookEvent
		events := core.NewBaseCollection(util.Coll.WebhookEvents)
		events.Fields.Add(
			&core.RelationField{Name: ev.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.TextField{Name: ev.Type, Required: true, Max: 64},
			&core.JSONField{Name: ev.Data, MaxSize: 8000},
			&core.BoolField{Name: ev.Test},
			&core.AutodateField{Name: ev.Created, OnCreate: true},
		)
		events.AddIndex("idxWebhookEventsWorkspace", false, ev.Workspace+", "+ev.Created, "")
		if err := app.Save(events); err != nil {
			return err
		}

		d := util.Fields.WebhookDelivery
		deliveries := core.NewBaseCollection(util.Coll.WebhookDeliveries)
		deliveries.Fields.Add(
			&core.RelationField{Name: d.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: d.Endpoint, CollectionId: endpoints.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: d.Event, CollectionId: events.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.SelectField{Name: d.Status, Required: true, Values: util.WebhookDeliveryStatuses, MaxSelect: 1},
			&core.NumberField{Name: d.Attempts, OnlyInt: true},
			&core.DateField{Name: d.NextAttemptAt},
			&core.NumberField{Name: d.LastStatus, OnlyInt: true},
			&core.TextField{Name: d.LastError, Max: 500},
			&core.DateField{Name: d.DeliveredAt},
			&core.AutodateField{Name: d.Created, OnCreate: true},
			&core.AutodateField{Name: d.Updated, OnCreate: true, OnUpdate: true},
		)
		deliveries.AddIndex("idxWebhookDeliveriesDue", false, d.Status+", "+d.NextAttemptAt, "")
		deliveries.AddIndex("idxWebhookDeliveriesEndpoint", false, d.Endpoint+", "+d.Created, "")
		deliveries.AddIndex("idxWebhookDeliveriesWorkspace", false, d.Workspace+", "+d.Created, "")
		if err := app.Save(deliveries); err != nil {
			return err
		}

		a := util.Fields.WebhookAttempt
		attempts := core.NewBaseCollection(util.Coll.WebhookAttempts)
		attempts.Fields.Add(
			&core.RelationField{Name: a.Delivery, CollectionId: deliveries.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: a.Endpoint, CollectionId: endpoints.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.RelationField{Name: a.Workspace, CollectionId: workspaces.Id, Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.NumberField{Name: a.ResponseStatus, OnlyInt: true},
			&core.TextField{Name: a.ResponseBody, Max: 2048},
			&core.TextField{Name: a.Error, Max: 500},
			&core.NumberField{Name: a.DurationMs, OnlyInt: true},
			&core.BoolField{Name: a.Manual},
			&core.AutodateField{Name: a.Created, OnCreate: true},
		)
		attempts.AddIndex("idxWebhookAttemptsDelivery", false, a.Delivery+", "+a.Created, "")
		attempts.AddIndex("idxWebhookAttemptsEndpoint", false, a.Endpoint+", "+a.Created, "")
		if err := app.Save(attempts); err != nil {
			return err
		}

		notifications, err := app.FindCollectionByNameOrId(util.Coll.Notifications)
		if err != nil {
			return err
		}
		if typeField, ok := notifications.Fields.GetByName(util.Fields.Notification.Type).(*core.SelectField); ok {
			typeField.Values = util.NotificationTypes
		}
		if err := app.Save(notifications); err != nil {
			return err
		}

		return grantWebhookScopeToWorkspaceManagers(app)
	}, func(app core.App) error {
		for _, name := range []string{
			util.Coll.WebhookAttempts, util.Coll.WebhookDeliveries,
			util.Coll.WebhookEvents, util.Coll.WebhookEndpoints,
		} {
			if col, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(col); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

func grantWebhookScopeToWorkspaceManagers(app core.App) error {
	members, err := app.FindAllRecords(util.Coll.WorkspaceMembers)
	if err != nil {
		return err
	}
	perms := util.Fields.WorkspaceMember.Permissions
	for _, m := range members {
		scopes := m.GetStringSlice(perms)
		if !slices.Contains(scopes, util.ScopeWorkspacesUpdate) || slices.Contains(scopes, util.ScopeWebhookManage) {
			continue
		}
		scopes = append(scopes, util.ScopeWebhookManage)
		slices.Sort(scopes)
		m.Set(perms, scopes)
		if err := app.Save(m); err != nil {
			return err
		}
	}
	return nil
}
