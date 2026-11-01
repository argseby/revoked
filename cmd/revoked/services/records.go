package services

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// LinkRecords loads the records a link grants, in grant order, leaving out ids
// that no longer resolve.
//
// One query rather than one per record: resolving a share of twenty entries
// was twenty trips through the record layer, which is most of what the resolve
// spent its time on. The ids become bound parameters of a single IN clause,
// which is safe here because the relation caps a link at 100 records.
func LinkRecords(app core.App, link *core.Record) []*core.Record {
	return recordsByIds(app, link.GetStringSlice(util.Fields.Link.Records))
}

// recordsByIds loads records in the order ids gives them, repeats included,
// leaving out any that no longer resolve.
func recordsByIds(app core.App, ids []string) []*core.Record {
	if len(ids) == 0 {
		return nil
	}

	found, err := app.FindRecordsByIds(util.Coll.Records, uniqueIds(ids))
	if err != nil {
		app.Logger().Error("Failed to load a link's records", "error", err, "ids", len(ids))
		return nil
	}

	byId := make(map[string]*core.Record, len(found))
	for _, rec := range found {
		byId[rec.Id] = rec
	}

	out := make([]*core.Record, 0, len(ids))
	for _, id := range ids {
		if rec, ok := byId[id]; ok {
			out = append(out, rec)
		}
	}
	return out
}

// uniqueIds keeps the first occurrence of each id, in order.
func uniqueIds(ids []string) []string {
	seen := make(map[string]bool, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}
