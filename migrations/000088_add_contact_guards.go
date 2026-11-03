package migrations

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Adds what bounds unsolicited deliveries: a ledger of what was put in whose
// tray, and the senders a person refuses.
//
// Handing a grant to a contact is the one path that writes into somebody
// else's account, and the address it is aimed at can be guessed. The ledger is
// what makes the per-pair cap exact: like the per-address email cap it counts
// rows rather than keeping a counter in memory, so two instances behind a load
// balancer cannot give out the budget twice, and the recipient deleting the
// bookmark — the obvious thing to do with something unwanted — cannot buy the
// sender a fresh allowance. Its rows are also the record that a grant once
// came the other way, which is what tells a stranger from somebody already in
// touch.
//
// Blocks are personal rather than workspace data, like bookmarks: being sent
// something unwanted is not the workspace's business. A block is added or
// removed and never edited, so no update rule is installed.
//
// `bookmarks.sender` is what makes a block possible to act on: without it the
// recipient sees a label and a workspace name, and has nothing to point at.
// The relation does not cascade — a bookmark outlives the account that sent
// it, as a contact outlives the account it named.
func init() {
	migrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(util.Coll.Users)
		if err != nil {
			return err
		}
		workspaces, err := app.FindCollectionByNameOrId(util.Coll.Workspaces)
		if err != nil {
			return err
		}

		d := util.Fields.ContactDelivery
		deliveries := core.NewBaseCollection(util.Coll.ContactDeliveries)
		deliveries.Fields.Add(
			&core.RelationField{
				Name:          d.Sender,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          d.Recipient,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			// Deliberately not cascading: a workspace deleted by its own
			// admin must not clear the ledger that caps them.
			&core.RelationField{
				Name:         d.Workspace,
				CollectionId: workspaces.Id,
				MaxSelect:    1,
			},
			&core.SelectField{Name: d.Kind, Required: true, Values: util.BookmarkKinds, MaxSelect: 1},
			&core.AutodateField{Name: d.Created, OnCreate: true},
		)
		// The index the per-pair count runs on, in the order it filters:
		// recipient, then sender, then the window.
		deliveries.AddIndex("idxContactDeliveriesPair", false,
			d.Recipient+", "+d.Sender+", "+d.Created, "")
		// No rules at all: the server writes these and nobody reads them.
		if err := app.Save(deliveries); err != nil {
			return err
		}

		b := util.Fields.ContactBlock
		blocks := core.NewBaseCollection(util.Coll.ContactBlocks)
		blocks.Fields.Add(
			&core.RelationField{
				Name:          b.User,
				CollectionId:  users.Id,
				Required:      true,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.RelationField{
				Name:          b.BlockedUser,
				CollectionId:  users.Id,
				MaxSelect:     1,
				CascadeDelete: true,
			},
			&core.EmailField{Name: b.Email},
			&core.TextField{Name: b.Domain, Max: 255, Pattern: `^[A-Za-z0-9.\-]*$`},
			&core.AutodateField{Name: b.Created, OnCreate: true},
		)
		blocks.AddIndex("idxContactBlocksUser", false, b.User, "")
		blocks.AddIndex("idxContactBlocksUnique", true,
			b.User+", "+b.BlockedUser+", "+b.Email+", "+b.Domain, "")

		owner := util.AccessSpec{Kind: util.AccessUserSelf}
		blocks.ListRule = types.Pointer(owner.Rule())
		blocks.ViewRule = types.Pointer(owner.Rule())
		blocks.CreateRule = types.Pointer(owner.Rule())
		blocks.DeleteRule = types.Pointer(owner.Rule())
		if err := app.Save(blocks); err != nil {
			return err
		}

		bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks)
		if err != nil {
			return err
		}
		bookmarks.Fields.Add(&core.RelationField{
			Name:         util.Fields.Bookmark.Sender,
			CollectionId: users.Id,
			MaxSelect:    1,
		})
		return app.Save(bookmarks)
	}, func(app core.App) error {
		if bookmarks, err := app.FindCollectionByNameOrId(util.Coll.Bookmarks); err == nil {
			bookmarks.Fields.RemoveByName(util.Fields.Bookmark.Sender)
			if err := app.Save(bookmarks); err != nil {
				return err
			}
		}
		for _, name := range []string{util.Coll.ContactBlocks, util.Coll.ContactDeliveries} {
			col, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(col); err != nil {
				return err
			}
		}
		return nil
	})
}
