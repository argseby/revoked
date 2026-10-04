package services

import (
	"html"
	"net/mail"
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
