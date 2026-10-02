package services

import (
	"html"
	"net/mail"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/mailer"
)

// SendSignupCode mails the code that confirms a new account's address. The
// message says what the code is for and where it was asked for, so someone
// who did not ask can tell and ignore it.
func SendSignupCode(app core.App, to, code, origin string) error {
	meta := app.Settings().Meta
	text := strings.Join([]string{
		"Your confirmation code is:",
		"",
		"    " + code,
		"",
		"Enter it on the sign-in page at " + origin + " to create your account.",
		"It works for 10 minutes.",
		"",
		"If you did not ask for this, ignore this email: without the code, no account is created.",
	}, "\n")
	body := "<p>Your confirmation code is:</p>" +
		`<p style="font-size:28px;font-weight:700;letter-spacing:6px;font-family:monospace">` + html.EscapeString(code) + "</p>" +
		"<p>Enter it on the sign-in page at " + html.EscapeString(origin) + " to create your account. It works for 10 minutes.</p>" +
		"<p>If you did not ask for this, ignore this email: without the code, no account is created.</p>"
	return app.NewMailClient().Send(&mailer.Message{
		From:    mail.Address{Name: meta.SenderName, Address: meta.SenderAddress},
		To:      []mail.Address{{Address: to}},
		Subject: code + " is your Revoked confirmation code",
		HTML:    body,
		Text:    text,
	})
}
