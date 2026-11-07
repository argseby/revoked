package services

import (
	"html"
	"net/mail"
	"strconv"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/mailer"
)

// signupMail is the confirmation email in one language. Lines are joined for
// the text part and wrapped in paragraphs for the HTML part; the code goes
// between intro and the rest.
type signupMail struct {
	subject func(code string) string
	intro   string
	where   func(origin string) string
	expiry  string
	ignore  string
}

var signupMails = map[string]signupMail{
	"en": {
		subject: func(code string) string { return code + " is your Revoked confirmation code" },
		intro:   "Your confirmation code is:",
		where: func(origin string) string {
			return "Enter it on the sign-in page at " + origin + " to create your account."
		},
		expiry: "It works for 10 minutes.",
		ignore: "If you did not ask for this, ignore this email: without the code, no account is created.",
	},
	"de": {
		subject: func(code string) string { return code + " ist dein Revoked-Bestätigungscode" },
		intro:   "Dein Bestätigungscode lautet:",
		where: func(origin string) string {
			return "Gib ihn auf der Anmeldeseite unter " + origin + " ein, um dein Konto zu erstellen."
		},
		expiry: "Er gilt 10 Minuten.",
		ignore: "Wenn du das nicht angefordert hast, ignoriere diese E-Mail: Ohne den Code wird kein Konto erstellt.",
	},
}

// accountExistsMail answers a confirmation request for an address that
// already has an account, in one language.
type accountExistsMail struct {
	subject string
	intro   func(origin string) string
	signIn  string
	ignore  string
}

var accountExistsMails = map[string]accountExistsMail{
	"en": {
		subject: "You already have a Revoked account",
		intro: func(origin string) string {
			return "Someone asked to create an account at " + origin + " with this address, which already has one."
		},
		signIn: "To get in, choose Sign in with passkey on the sign-in page. No new account is needed.",
		ignore: "If you did not ask for this, ignore this email: nothing has changed.",
	},
	"de": {
		subject: "Du hast bereits ein Revoked-Konto",
		intro: func(origin string) string {
			return "Für diese Adresse wurde unter " + origin + " ein Konto angefordert. Sie hat bereits eines."
		},
		signIn: "Zum Anmelden auf der Anmeldeseite „Mit Passkey anmelden“ wählen. Ein neues Konto ist nicht nötig.",
		ignore: "Wenn du das nicht angefordert hast, ignoriere diese E-Mail: Es hat sich nichts geändert.",
	},
}

// SendAccountExists tells the owner of an address that already has an
// account that someone asked to create another with it. It goes out in place
// of a confirmation code, so the sign-up page answers the same either way.
func SendAccountExists(app core.App, to, origin, locale string) error {
	m, ok := accountExistsMails[locale]
	if !ok {
		m = accountExistsMails["en"]
	}
	meta := app.Settings().Meta
	text := strings.Join([]string{m.intro(origin), "", m.signIn, "", m.ignore}, "\n")
	body := "<p>" + html.EscapeString(m.intro(origin)) + "</p>" +
		"<p>" + html.EscapeString(m.signIn) + "</p>" +
		"<p>" + html.EscapeString(m.ignore) + "</p>"
	return app.NewMailClient().Send(&mailer.Message{
		From:    mail.Address{Name: meta.SenderName, Address: meta.SenderAddress},
		To:      []mail.Address{{Address: to}},
		Subject: m.subject,
		HTML:    body,
		Text:    text,
	})
}

// SendSignupCode mails the code that confirms a new account's address, in the
// language the sign-in page was shown in (English unless it names one this
// knows). The message says what the code is for and where it was asked for,
// so someone who did not ask can tell and ignore it.
func SendSignupCode(app core.App, to, code, origin, locale string) error {
	m, ok := signupMails[locale]
	if !ok {
		m = signupMails["en"]
	}
	meta := app.Settings().Meta
	text := strings.Join([]string{
		m.intro,
		"",
		"    " + code,
		"",
		m.where(origin),
		m.expiry,
		"",
		m.ignore,
	}, "\n")
	body := "<p>" + html.EscapeString(m.intro) + "</p>" +
		`<p style="font-size:28px;font-weight:700;letter-spacing:6px;font-family:monospace">` + html.EscapeString(code) + "</p>" +
		"<p>" + html.EscapeString(m.where(origin)+" "+m.expiry) + "</p>" +
		"<p>" + html.EscapeString(m.ignore) + "</p>"
	return app.NewMailClient().Send(&mailer.Message{
		From:    mail.Address{Name: meta.SenderName, Address: meta.SenderAddress},
		To:      []mail.Address{{Address: to}},
		Subject: m.subject(code),
		HTML:    body,
		Text:    text,
	})
}

// GrantMailData is everything one grant email states.
//
// Nothing here is secret: Label names the grant, never its contents, and URL
// is the share page, which applies every gate the link carries.
type GrantMailData struct {
	// SenderName is shown only when it passed util.SafeDisplayName. Empty
	// means the mail says the grant is unsigned instead of showing a name it
	// cannot vouch for.
	SenderName string

	// Domain is this server's own, and the one value in the mail the sender
	// could not choose.
	Domain string

	Label string
	URL   string

	// IsAsk switches to the wording for a request, which the recipient needs
	// an account to answer.
	IsAsk bool

	Locale string
}

// grantMail is the grant email in one language.
type grantMail struct {
	subjectNamed    func(name, label string) string
	subjectPlain    string
	subjectAsk      func(name string) string
	subjectAskPlain string

	// panelLead heads the block that names who this came from.
	panelLead    string
	panelLeadAsk string

	// headline stands in for the grant's own name when it has none worth
	// showing.
	headline    string
	headlineAsk string

	lead    string
	leadAsk func(domain string) string

	// check tells the reader to look at the domain and says what the mail
	// cannot prove about the name above it; unsigned replaces it when no name
	// could be shown.
	check    func(domain string) string
	unsigned func(domain string) string

	button    func(domain string) string
	buttonAsk func(domain string) string

	closer    string
	closerAsk string
}

var grantMails = map[string]grantMail{
	"en": {
		subjectNamed: func(name, label string) string {
			return name + " shared " + quoted(label) + " with you"
		},
		subjectPlain:    "Something was shared with you",
		subjectAsk:      func(name string) string { return name + " needs something from you" },
		subjectAskPlain: "Someone needs something from you",

		panelLead:    "Sent to you by",
		panelLeadAsk: "Asked by",

		headline:    "Something was shared with you",
		headlineAsk: "Someone needs something from you",

		lead: "Shared with you. It always shows the current version, and the " +
			"sender can revoke it at any time.",
		leadAsk: func(domain string) string {
			return "Answering needs an account on " + domain +
				", so your answer stays yours — you can change it or take it back later."
		},

		check: func(domain string) string {
			return "Check that " + domain + " is a server you expect to hear from. " +
				"The name above it is what that server reports, not something this email can prove."
		},
		unsigned: func(domain string) string {
			return "This isn't signed by a named person, so anyone with access to " +
				domain + " could have sent it."
		},

		button:    func(domain string) string { return "Open it on " + domain },
		buttonAsk: func(domain string) string { return "Answer on " + domain },

		closer:    "Nothing that was shared is in this email.",
		closerAsk: "Nothing is asked for in this email. You answer in the app, on your own account.",
	},
	"de": {
		subjectNamed: func(name, label string) string {
			return name + " hat " + quoted(label) + " mit dir geteilt"
		},
		subjectPlain:    "Es wurde etwas mit dir geteilt",
		subjectAsk:      func(name string) string { return name + " braucht etwas von dir" },
		subjectAskPlain: "Jemand braucht etwas von dir",

		panelLead:    "Gesendet von",
		panelLeadAsk: "Angefragt von",

		headline:    "Es wurde etwas mit dir geteilt",
		headlineAsk: "Jemand braucht etwas von dir",

		lead: "Mit dir geteilt. Du siehst immer den aktuellen Stand, und der " +
			"Absender kann den Link jederzeit widerrufen.",
		leadAsk: func(domain string) string {
			return "Zum Antworten brauchst du ein Konto auf " + domain +
				". So bleibt deine Antwort deine — du kannst sie ändern oder zurückziehen."
		},

		check: func(domain string) string {
			return "Prüfe, ob " + domain + " ein Server ist, von dem du etwas erwartest. " +
				"Der Name darüber ist die Angabe dieses Servers und lässt sich in dieser E-Mail nicht belegen."
		},
		unsigned: func(domain string) string {
			return "Dies ist nicht von einer benannten Person signiert. Jede Person mit Zugang zu " +
				domain + " könnte es gesendet haben."
		},

		button:    func(domain string) string { return "Auf " + domain + " öffnen" },
		buttonAsk: func(domain string) string { return "Auf " + domain + " antworten" },

		closer:    "Diese E-Mail enthält nichts von dem, was geteilt wurde.",
		closerAsk: "Diese E-Mail fragt nichts ab. Du antwortest in der App, mit deinem eigenen Konto.",
	},
}

// The app's own palette, so the mail looks like the product the recipient
// will open rather than like the browser page it links to.
const (
	mailPaper   = "#FAF9F6"
	mailCard    = "#FFFFFF"
	mailTint    = "#E9E6FB"
	mailOnTint  = "#2A2390"
	mailBrand   = "#3D35B5"
	mailDivider = "#E1DEE8"
	mailInk     = "#16151F"
	mailMuted   = "#575569"

	// The same stacks the share page sets, so the mail and the page it links
	// to are set in one typeface. The app ships no font of its own either —
	// it uses the platform's — so this *is* the product's type.
	mailSans = "system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
	mailMono = "ui-monospace,'SF Mono',Menlo,Consolas,monospace"
)

// mailMark draws the Revoked mark — four redaction bars — out of table cells.
//
// Not an image: the brand route inlines the real SVG as a data: URI, and Gmail
// and Outlook both refuse those, while a hosted one would be a request from
// somebody's inbox to this server and would vanish behind every client's
// block-images default. The mark is four rectangles, so it can simply be
// built, and then it renders everywhere with nothing to load.
//
// Proportions come straight from brand/revoced-mark-redacted-*.svg: bars at
// x=100,140,100,180 of width 300,220,300,140 on a 500 canvas.
func mailMark(colour string, bar, gap int, widths, offsets [4]int) string {
	var b strings.Builder
	b.WriteString(`<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;">`)
	for i := 0; i < 4; i++ {
		pad := ""
		if i < 3 {
			pad = `padding-bottom:` + strconv.Itoa(gap) + `px;`
		}
		b.WriteString(`<tr><td style="` + pad + `font-size:0;line-height:0;">` +
			`<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;"><tr>` +
			`<td width="` + strconv.Itoa(offsets[i]) + `" style="width:` + strconv.Itoa(offsets[i]) + `px;font-size:0;line-height:0;">&nbsp;</td>` +
			`<td width="` + strconv.Itoa(widths[i]) + `" height="` + strconv.Itoa(bar) + `" bgcolor="` + colour +
			`" style="width:` + strconv.Itoa(widths[i]) + `px;height:` + strconv.Itoa(bar) +
			`px;background-color:` + colour + `;font-size:0;line-height:0;">&nbsp;</td>` +
			`</tr></table></td></tr>`)
	}
	b.WriteString(`</table>`)
	return b.String()
}

// The mark at the two sizes the mail uses it.
func markLarge(colour string) string {
	return mailMark(colour, 3, 2, [4]int{17, 12, 17, 8}, [4]int{6, 8, 6, 10})
}

func markSmall(colour string) string {
	return mailMark(colour, 2, 2, [4]int{12, 9, 12, 6}, [4]int{4, 6, 4, 7})
}

// SendGrantEmail mails a contact the link to a grant.
//
// Who sent it leads: the tinted panel at the top carries the sender's name and
// this server's own domain before the reader has decided anything, because
// "someone shared something with you, click here" is the shape of a phishing
// mail and this is the first thing the product puts in an inbox. The name is
// quoted as the claim it is; the domain is the one value in the message the
// sender could not choose.
//
// Table layout with inline styles throughout: Outlook renders mail with Word,
// which ignores a style block, every float and every border radius. Both
// background-color and color are stated wherever either is, so a client that
// inverts one inverts both — and the panel's name and domain also stand on
// their own in reading order, so losing its tint costs emphasis rather than
// meaning.
func SendGrantEmail(app core.App, to string, g GrantMailData) error {
	m, ok := grantMails[g.Locale]
	if !ok {
		m = grantMails["en"]
	}
	meta := app.Settings().Meta
	named := g.SenderName != ""

	subject := m.subjectPlain
	switch {
	case g.IsAsk && named:
		subject = m.subjectAsk(g.SenderName)
	case g.IsAsk:
		subject = m.subjectAskPlain
	case named:
		subject = m.subjectNamed(g.SenderName, g.Label)
	}

	panelLead, heading, lead := m.panelLead, m.headline, m.lead
	button, closer := m.button(g.Domain), m.closer
	if g.IsAsk {
		panelLead, heading = m.panelLeadAsk, m.headlineAsk
		lead, button, closer = m.leadAsk(g.Domain), m.buttonAsk(g.Domain), m.closerAsk
	}
	// The grant's own name is the heading where it has one; the neutral
	// headline stands in where it does not.
	if g.Label != "" {
		heading = g.Label
	}
	caveat := m.unsigned(g.Domain)
	if named {
		caveat = m.check(g.Domain)
	}

	esc := html.EscapeString
	var b strings.Builder
	b.WriteString(`<!doctype html><html><head><meta charset="utf-8">` +
		`<meta name="viewport" content="width=device-width,initial-scale=1">` +
		`<meta name="color-scheme" content="light dark">` +
		`<meta name="supported-color-schemes" content="light dark">` +
		`<title>` + esc(subject) + `</title></head>`)
	b.WriteString(`<body style="margin:0;padding:0;background-color:` + mailPaper + `;color:` + mailInk + `;">`)
	b.WriteString(`<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:` + mailPaper + `;border-collapse:collapse;">`)
	b.WriteString(`<tr><td align="center" style="padding:32px 16px;">`)
	b.WriteString(`<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="520" style="width:520px;max-width:520px;border-collapse:collapse;">`)

	b.WriteString(`<tr><td style="padding:0 2px 20px;">` +
		`<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;"><tr>` +
		`<td valign="middle">` + markLarge(mailInk) + `</td>` +
		`<td valign="middle" style="padding-left:10px;font:600 17px ` + mailSans + `;color:` + mailInk + `;letter-spacing:-0.2px;">Revoked</td>` +
		`</tr></table></td></tr>`)

	b.WriteString(`<tr><td style="background-color:` + mailCard + `;color:` + mailInk +
		`;border:1px solid ` + mailDivider + `;border-radius:14px;">`)
	b.WriteString(`<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">`)

	// Who it came from, before anything else.
	b.WriteString(`<tr><td bgcolor="` + mailTint + `" style="background-color:` + mailTint +
		`;padding:22px 30px;border-radius:14px 14px 0 0;">`)
	b.WriteString(`<div style="font:400 13px ` + mailSans + `;color:` + mailOnTint + `;padding-bottom:10px;">` + esc(panelLead) + `</div>`)
	if named {
		b.WriteString(`<div style="font:400 19px/1.3 ` + mailSans + `;color:` + mailInk + `;padding-bottom:6px;">` + esc(quoted(g.SenderName)) + `</div>`)
	}
	b.WriteString(`<div style="font:400 14px/1.4 ` + mailMono + `;color:` + mailOnTint + `;">` + esc(g.Domain) + `</div>`)
	b.WriteString(`</td></tr>`)

	b.WriteString(`<tr><td style="padding:28px 30px;">`)
	b.WriteString(`<div style="font:400 22px/1.3 ` + mailSans + `;color:` + mailInk + `;padding-bottom:6px;">` + esc(heading) + `</div>`)
	b.WriteString(`<div style="font:400 15px/1.6 ` + mailSans + `;color:` + mailMuted + `;padding-bottom:24px;">` + esc(lead) + `</div>`)
	// The share page's own primary button — full width, 54px tall, radius 15,
	// weight 650, the mark beside the label — so arriving on that page after
	// tapping this feels like the same thing continuing. A cell background
	// under an inline-block link, so a client that strips the cell still
	// leaves something usable.
	b.WriteString(`<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;border-collapse:collapse;"><tr>` +
		`<td align="center" height="54" bgcolor="` + mailBrand + `" style="height:54px;background-color:` + mailBrand + `;border-radius:15px;">` +
		`<a href="` + esc(g.URL) + `" style="display:block;padding:14px 16px;text-decoration:none;color:#ffffff;">` +
		`<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="border-collapse:collapse;"><tr>` +
		`<td valign="middle">` + markSmall("#ffffff") + `</td>` +
		`<td valign="middle" style="padding-left:10px;font:650 16px ` + mailSans + `;color:#ffffff;">` + esc(button) + `</td>` +
		`</tr></table></a></td></tr></table>`)
	b.WriteString(`<div style="border-top:1px solid ` + mailDivider + `;margin-top:24px;padding-top:18px;font:400 13px/1.65 ` + mailSans + `;color:` + mailMuted + `;">` +
		esc(caveat) + ` ` + esc(closer) + `</div>`)
	b.WriteString(`</td></tr></table></td></tr>`)
	b.WriteString(`</table></td></tr></table></body></html>`)

	// The same order in text, so a client that shows only this loses the
	// emphasis and nothing else.
	lines := []string{panelLead + ":"}
	if named {
		lines = append(lines, "  "+quoted(g.SenderName))
	}
	lines = append(lines, "  "+g.Domain, "", heading, "", lead, "", button+":", g.URL, "", caveat, closer)

	return app.NewMailClient().Send(&mailer.Message{
		From:    mail.Address{Name: meta.SenderName, Address: meta.SenderAddress},
		To:      []mail.Address{{Address: to}},
		Subject: subject,
		HTML:    b.String(),
		Text:    strings.Join(lines, "\n"),
	})
}
