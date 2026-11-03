package util

import "time"

// What a hand-over to a contact may be told to its sender.
//
// The sender learns which channel was used only where something already
// connects them to the recipient. Otherwise the answer is
// [ContactChannelHandedOver] whatever happened: a precise outcome would
// answer "does this address have an account on this server?" for any address
// typed in, which is the first step of addressing a stranger's tray.
const (
	// ContactChannelAccount — it is in their tray on this server.
	ContactChannelAccount = "account"
	// ContactChannelEmail — it was queued for their address.
	ContactChannelEmail = "email"
	// ContactChannelManual — nothing went out; the slug is the sender's to
	// pass on.
	ContactChannelManual = "manual"
	// ContactChannelHandedOver — the grant exists and the slug is in the
	// answer, and the sender is told no more than that.
	ContactChannelHandedOver = "handed_over"
)

const (
	// ContactPairPerDayEnv caps how many grants one account may put in one
	// other account's tray while nothing connects the two.
	ContactPairPerDayEnv = "RATELIMIT_CONTACT_PAIR"

	// DefaultContactPairPerDay is that cap's default. Enough for a first
	// hand-over and a correction or two, far short of a flood.
	DefaultContactPairPerDay = 3
)

// ContactPairWindow is the period [DefaultContactPairPerDay] is measured over.
const ContactPairWindow = 24 * time.Hour

// Why a delivery into somebody else's tray did not happen. Recorded in the
// audit row, never returned to the sender: either answer would say whether
// the address names an account here.
const (
	ContactRefusedBlocked = "blocked"
	ContactRefusedPairCap = "pair-cap"
)
