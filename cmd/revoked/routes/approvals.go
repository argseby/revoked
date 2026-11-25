package routes

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

// What an approval can be for. The purpose is part of the signed challenge,
// so an approval of one kind never stands in for the other.
const (
	ApprovalPurposeSignIn  = "signin"
	ApprovalPurposeConnect = "connect"
)

// approvalPrefix separates an approval's challenge from every other one this
// server asks a passkey to sign, the sign-in ceremony's included: the same
// reason invariant 11 types the status payload.
const approvalPrefix = "revoked-approval-v1"

// approvalTTL is how long a finished approval waits to be presented.
const approvalTTL = 2 * time.Minute

type approvalCeremony struct {
	session               webauthn.SessionData
	user, purpose, ticket string
}

type approvalProof struct {
	user, purpose, ticket string
}

// In process, like the other short-lived registries (CLAUDE.md, Gotchas).
var (
	approvalCeremonies passkeyVault[approvalCeremony]
	approvalProofs     passkeyVault[approvalProof]
)

// approvalChallenge is SHA-256(prefix ‖ purpose ‖ ticket ‖ nonce), each part
// ended by a zero byte so no two inputs run together into the same bytes.
func approvalChallenge(purpose, ticket string, nonce []byte) []byte {
	h := sha256.New()
	for _, part := range [][]byte{[]byte(approvalPrefix), []byte(purpose), []byte(ticket), nonce} {
		h.Write(part)
		h.Write([]byte{0})
	}
	return h.Sum(nil)
}

// ApprovalsRoute lets a browser approve a sign-in with the passkey of the
// person signed in, where the app signs with an identity key (BROWSER.md §4.5):
//
//	POST /api/approvals/begin   {purpose, ticket}       -> {session, options}
//	POST /api/approvals/finish  {session, credential}   -> {approval}
//
// The assertion must come from a passkey of the signed-in account, with user
// verification. The approval it earns is good once, for that ticket and
// purpose only, for two minutes. Only the endpoint the purpose names accepts it.
func ApprovalsRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.POST("/api/approvals/begin", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !allowRequest(re, passkeyLimiter, "approval|"+re.Auth.Id) {
				return rateLimitedResponse(re)
			}
			var body struct {
				Purpose string `json:"purpose"`
				Ticket  string `json:"ticket"`
			}
			if err := re.BindBody(&body); err != nil || body.Ticket == "" || len(body.Ticket) > 256 ||
				(body.Purpose != ApprovalPurposeSignIn && body.Purpose != ApprovalPurposeConnect) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}
			user, err := services.LoadPasskeyUser(app, re.Auth)
			if err != nil {
				return re.InternalServerError("Failed to start the approval", err)
			}
			nonce := []byte(security.RandomString(32))
			options, session, err := w.BeginLogin(user,
				webauthn.WithChallenge(approvalChallenge(body.Purpose, body.Ticket, nonce)),
				webauthn.WithUserVerification(protocol.VerificationRequired))
			if err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			id := approvalCeremonies.put(&approvalCeremony{
				session: *session, user: re.Auth.Id, purpose: body.Purpose, ticket: body.Ticket,
			}, util.PasskeyCeremonyTTL)
			return re.JSON(http.StatusOK, map[string]any{"session": id, "options": options})
		})

		e.Router.POST("/api/approvals/finish", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			if !allowRequest(re, passkeyLimiter, "approval|"+re.Auth.Id) {
				return rateLimitedResponse(re)
			}
			var body struct {
				Session    string          `json:"session"`
				Credential json.RawMessage `json:"credential"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			ceremony, ok := approvalCeremonies.take(body.Session)
			if !ok || ceremony.user != re.Auth.Id {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyCeremonyInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}
			failed := func(err error) error {
				app.Logger().Warn("Passkey approval refused", "user", re.Auth.Id, "error", err, "ip", re.RealIP())
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.PasskeyVerificationFailed)
			}
			parsed, err := protocol.ParseCredentialRequestResponseBytes(body.Credential)
			if err != nil {
				return failed(err)
			}
			user, err := services.LoadPasskeyUser(app, re.Auth)
			if err != nil {
				return failed(err)
			}
			// Checks the challenge, the origin, that the credential is one of
			// this account's, and the UV flag the session requires.
			credential, err := w.ValidateLogin(user, ceremony.session, parsed)
			if err != nil {
				return failed(err)
			}
			if !parsed.Response.AuthenticatorData.Flags.HasUserVerified() {
				return failed(errors.New("user not verified"))
			}
			if credential.Authenticator.CloneWarning {
				return failed(errors.New("signature counter went backwards"))
			}
			if err := services.TouchPasskey(app, credential); err != nil {
				app.Logger().Error("Failed to record a passkey approval", "error", err)
			}
			approval := approvalProofs.put(&approvalProof{
				user: ceremony.user, purpose: ceremony.purpose, ticket: ceremony.ticket,
			}, approvalTTL)
			return re.JSON(http.StatusOK, map[string]any{"approval": approval})
		})
		return e.Next()
	})
}

// takeApproval spends approval and reports whether it was given by user, for
// purpose and ticket. Spent whatever the answer: a presented approval is used.
func takeApproval(approval, user, purpose, ticket string) bool {
	proof, ok := approvalProofs.take(approval)
	return ok && proof.user == user && proof.purpose == purpose && proof.ticket == ticket
}
