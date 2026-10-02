package routes

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"revoked/cmd/revoked/server"
	"revoked/cmd/revoked/services"
	"revoked/util"

	validation "github.com/go-ozzo/ozzo-validation/v4"
	"github.com/go-ozzo/ozzo-validation/v4/is"
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

// passkeyLimiter bounds the unauthenticated passkey surface per IP: every
// ceremony costs a lookup and a signature check, and a begin costs memory.
var passkeyLimiter = util.NewRateLimiter(limitFromEnv("RATELIMIT_PASSKEY_REQUESTS", 60), time.Minute)

// PasskeysRoute is how a person signs in: with a passkey, and nothing else.
//
// A passkey is bound to the address it was made at, and an installed app has
// no address of its own that a self-hosted server could vouch for. So the
// ceremony runs on this server's own page (GET /passkey) in the system
// browser, and the app gets the result the way a connected tool does — a
// one-time code bound to a PKCE challenge only the app that asked can redeem:
//
//	POST /api/passkeys/login/begin      {challenge}
//	POST /api/passkeys/login/finish     {session, credential}      -> {code}
//	POST /api/passkeys/register/begin   {email | ticket, name?, challenge?}
//	POST /api/passkeys/register/finish  {session, credential}      -> {code?}
//	POST /api/passkeys/token            {code, verifier}           -> session
//
// Registering is either a new account (an email address, where the operator
// allows signups, confirmed with a code first where the operator asks for
// that — see SignupEmailRoute) or a ticket: a one-time link that lets the
// account it names add a passkey. The operator issues one for a new or locked-out account; a
// signed-in person issues one for another device:
//
//	POST   /api/passkeys/tickets        (the owner, signed in)     -> {url}
//	DELETE /api/passkeys/{id}           (the owner, signed in)
//
// The last passkey cannot be removed: there would be no way back in.
func PasskeysRoute(app core.App, root *server.RootKey) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		// util.PasskeyPagePath, spelled out so the route list reads as one.
		e.Router.GET("/passkey", func(re *core.RequestEvent) error {
			return servePasskeyPage(app, re, root)
		})

		e.Router.POST("/api/passkeys/login/begin", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Challenge string `json:"challenge"`
			}
			if err := re.BindBody(&body); err != nil || !util.ValidPKCE(body.Challenge) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}
			// No account is named: the authenticator offers the passkeys it
			// holds for this address, and the answer says whose it is.
			options, session, err := w.BeginDiscoverableLogin(
				webauthn.WithUserVerification(protocol.VerificationRequired))
			if err != nil {
				return re.InternalServerError("Failed to start the sign-in", err)
			}
			id := passkeyCeremonies.put(&passkeyCeremony{session: *session, pkce: body.Challenge}, util.PasskeyCeremonyTTL)
			return re.JSON(http.StatusOK, map[string]any{"session": id, "options": options})
		})

		e.Router.POST("/api/passkeys/login/finish", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Session    string          `json:"session"`
				Credential json.RawMessage `json:"credential"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			// Spent whatever happens next: a challenge is answered once.
			ceremony, ok := passkeyCeremonies.take(body.Session)
			if !ok || ceremony.register {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyCeremonyInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}
			failed := func(err error) error {
				app.Logger().Warn("Passkey sign-in refused", "error", err, "ip", re.RealIP())
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.PasskeyVerificationFailed)
			}
			parsed, err := protocol.ParseCredentialRequestResponseBytes(body.Credential)
			if err != nil {
				return failed(err)
			}
			var account *core.Record
			handler := func(rawID, userHandle []byte) (webauthn.User, error) {
				user, err := app.FindRecordById(util.Coll.Users, string(userHandle))
				if err != nil {
					return nil, err
				}
				account = user
				return services.LoadPasskeyUser(app, user)
			}
			_, credential, err := w.ValidatePasskeyLogin(handler, ceremony.session, parsed)
			if err != nil || account == nil {
				return failed(err)
			}
			// A counter that went backwards means the key exists twice.
			if credential.Authenticator.CloneWarning {
				return failed(errors.New("signature counter went backwards"))
			}
			if err := services.TouchPasskey(app, credential); err != nil {
				app.Logger().Error("Failed to record a passkey sign-in", "error", err)
			}
			return re.JSON(http.StatusOK, map[string]any{
				"code": passkeyCodes.put(&passkeyGrant{user: account.Id, pkce: ceremony.pkce}, util.PasskeyCodeTTL),
			})
		})

		e.Router.POST("/api/passkeys/register/begin", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Email     string `json:"email"`
				Ticket    string `json:"ticket"`
				Name      string `json:"name"`
				Challenge string `json:"challenge"`
				// The confirmed address, where the operator asks for one.
				Proof string `json:"proof"`
			}
			if err := re.BindBody(&body); err != nil ||
				(body.Challenge != "" && !util.ValidPKCE(body.Challenge)) {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}

			ceremony := &passkeyCeremony{register: true, pkce: body.Challenge, name: passkeyName(body.Name)}
			user := &services.PasskeyUser{}
			if body.Ticket != "" {
				_, account, err := services.FindPasskeyTicket(app, body.Ticket)
				if err != nil {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyTicketInvalid)
				}
				if user, err = services.LoadPasskeyUser(app, account); err != nil {
					return re.InternalServerError("Failed to start the registration", err)
				}
				ceremony.user, ceremony.ticket = account.Id, body.Ticket
			} else {
				if !util.SignupsAllowed() {
					return appErrorResponse(re, http.StatusForbidden, &util.Errors.SignupsDisabled)
				}
				email := strings.ToLower(strings.TrimSpace(body.Email))
				if validation.Validate(email, validation.Required, validation.Length(3, 255), is.EmailFormat) != nil {
					return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyEmailInvalid)
				}
				users, err := app.FindCollectionByNameOrId(util.Coll.Users)
				if err != nil {
					return re.InternalServerError("Failed to start the registration", err)
				}
				if taken, _ := app.FindAuthRecordByEmail(users, email); taken != nil {
					return appErrorResponse(re, http.StatusConflict, &util.Errors.PasskeyEmailTaken)
				}
				// Checked, not spent: the account is written, and the proof
				// spent, only once the passkey verified.
				if util.SignupEmailVerification() {
					proof, ok := emailProofs.peek(body.Proof)
					if !ok || proof.email != email {
						return appErrorResponse(re, http.StatusForbidden, &util.Errors.EmailVerificationRequired)
					}
					ceremony.proof = body.Proof
				}
				// The account is only written once its passkey verified, under
				// the id the authenticator is about to be told.
				ceremony.user, ceremony.email = security.RandomStringWithAlphabet(core.DefaultIdLength, core.DefaultIdAlphabet), email
				user = &services.PasskeyUser{ID: ceremony.user, Email: email}
			}

			exclude := make([]protocol.CredentialDescriptor, 0, len(user.Credentials))
			for _, c := range user.Credentials {
				exclude = append(exclude, c.Descriptor())
			}
			options, session, err := w.BeginRegistration(user,
				// A passkey has to be found without naming the account, and is
				// the only factor: the authenticator must keep it and must
				// check who is holding it.
				webauthn.WithAuthenticatorSelection(protocol.AuthenticatorSelection{
					ResidentKey:        protocol.ResidentKeyRequirementRequired,
					RequireResidentKey: protocol.ResidentKeyRequired(),
					UserVerification:   protocol.VerificationRequired,
				}),
				webauthn.WithExclusions(exclude),
			)
			if err != nil {
				return re.InternalServerError("Failed to start the registration", err)
			}
			ceremony.session = *session
			id := passkeyCeremonies.put(ceremony, util.PasskeyCeremonyTTL)
			return re.JSON(http.StatusOK, map[string]any{"session": id, "options": options})
		})

		e.Router.POST("/api/passkeys/register/finish", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Session    string          `json:"session"`
				Credential json.RawMessage `json:"credential"`
			}
			if err := re.BindBody(&body); err != nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyRequestInvalid)
			}
			ceremony, ok := passkeyCeremonies.take(body.Session)
			if !ok || !ceremony.register {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyCeremonyInvalid)
			}
			w, ok := passkeyAuthority(re, root)
			if !ok {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyOriginInvalid)
			}
			parsed, err := protocol.ParseCredentialCreationResponseBytes(body.Credential)
			if err != nil {
				app.Logger().Warn("Passkey registration refused", "error", err, "ip", re.RealIP())
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyVerificationFailed)
			}
			user := &services.PasskeyUser{ID: ceremony.user, Email: ceremony.email}
			credential, err := w.CreateCredential(user, ceremony.session, parsed)
			if err != nil {
				app.Logger().Warn("Passkey registration refused", "error", err, "ip", re.RealIP())
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyVerificationFailed)
			}

			// A new account's confirmed address is spent with the account it
			// pays for; one confirmation makes one account.
			verified := false
			if ceremony.ticket == "" && (ceremony.proof != "" || util.SignupEmailVerification()) {
				proof, ok := emailProofs.take(ceremony.proof)
				if !ok || proof.email != ceremony.email {
					return appErrorResponse(re, http.StatusForbidden, &util.Errors.EmailVerificationRequired)
				}
				verified = true
			}

			var refused *util.AppError
			err = app.RunInTransaction(func(tx core.App) error {
				if ceremony.ticket != "" {
					// The ticket is spent here, with the passkey it paid for:
					// it may have been used while this ceremony was open.
					row, _, err := services.FindPasskeyTicket(tx, ceremony.ticket)
					if err != nil {
						refused = &util.Errors.PasskeyTicketInvalid
						return err
					}
					if err := tx.Delete(row); err != nil {
						return err
					}
				} else {
					users, err := tx.FindCollectionByNameOrId(util.Coll.Users)
					if err != nil {
						return err
					}
					account := core.NewRecord(users)
					account.Id = ceremony.user
					account.SetEmail(ceremony.email)
					account.SetVerified(verified)
					account.SetRandomPassword()
					if err := tx.Save(account); err != nil {
						// Someone took the address while this ceremony was open.
						refused = &util.Errors.PasskeyEmailTaken
						return err
					}
				}
				_, err := services.SavePasskey(tx, ceremony.user, ceremony.name, credential)
				return err
			})
			if refused != nil {
				status := http.StatusBadRequest
				if refused == &util.Errors.PasskeyEmailTaken {
					status = http.StatusConflict
				}
				return appErrorResponse(re, status, refused)
			}
			if err != nil {
				return re.InternalServerError("Failed to save the passkey", err)
			}
			app.Logger().Info("Passkey registered", "user", ceremony.user, "newAccount", ceremony.ticket == "")

			out := map[string]any{}
			// Asked for by the app: it is signed in with what was just made.
			if ceremony.pkce != "" {
				out["code"] = passkeyCodes.put(&passkeyGrant{user: ceremony.user, pkce: ceremony.pkce}, util.PasskeyCodeTTL)
			}
			return re.JSON(http.StatusOK, out)
		})

		e.Router.POST("/api/passkeys/token", func(re *core.RequestEvent) error {
			if !allowRequest(re, passkeyLimiter, "") {
				return rateLimitedResponse(re)
			}
			var body struct {
				Code     string `json:"code"`
				Verifier string `json:"verifier"`
			}
			invalid := func() error {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.PasskeyGrantInvalid)
			}
			if err := re.BindBody(&body); err != nil || body.Code == "" || !util.ValidPKCE(body.Verifier) {
				return invalid()
			}
			// A code is spent the moment anyone presents it, right or wrong: a
			// stolen code cannot be retried against the verifier.
			grant, ok := passkeyCodes.take(body.Code)
			if !ok || subtle.ConstantTimeCompare([]byte(util.PKCEChallenge(body.Verifier)), []byte(grant.pkce)) != 1 {
				return invalid()
			}
			account, err := app.FindRecordById(util.Coll.Users, grant.user)
			if err != nil || account == nil {
				return invalid()
			}
			return apis.RecordAuthResponse(re, account, "passkey", nil)
		})

		e.Router.POST("/api/passkeys/tickets", func(re *core.RequestEvent) error {
			// Users only: an API key must not be able to let itself in as the
			// person behind it.
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			ticket, expires, err := services.IssuePasskeyTicket(app, re.Auth.Id, util.PasskeyTicketTTL)
			if err != nil {
				return re.InternalServerError("Failed to issue a ticket", err)
			}
			app.Logger().Info("Passkey ticket issued", "user", re.Auth.Id, "ip", re.RealIP())
			return re.JSON(http.StatusOK, map[string]any{
				"url":       services.PasskeyTicketURL(pageOrigin(re, root), ticket),
				"expiresAt": expires.UTC().Format(time.RFC3339),
			})
		})

		e.Router.DELETE("/api/passkeys/{id}", func(re *core.RequestEvent) error {
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			var last bool
			err := app.RunInTransaction(func(tx core.App) error {
				row, err := tx.FindRecordById(util.Coll.Passkeys, re.Request.PathValue("id"))
				if err != nil || row == nil || row.GetString(util.Fields.Passkey.User) != re.Auth.Id {
					return errPasskeyMissing
				}
				count, err := tx.CountRecords(util.Coll.Passkeys,
					dbx.HashExp{util.Fields.Passkey.User: re.Auth.Id})
				if err != nil {
					return err
				}
				if count <= 1 {
					last = true
					return nil
				}
				return tx.Delete(row)
			})
			if errors.Is(err, errPasskeyMissing) {
				return re.NotFoundError("Passkey not found", nil)
			}
			if err != nil {
				return re.InternalServerError("Failed to remove the passkey", err)
			}
			if last {
				return appErrorResponse(re, http.StatusConflict, &util.Errors.PasskeyLast)
			}
			app.Logger().Info("Passkey removed", "user", re.Auth.Id, "ip", re.RealIP())
			return re.NoContent(http.StatusNoContent)
		})

		return e.Next()
	})
}

var errPasskeyMissing = errors.New("passkey not found")

// passkeyAuthority is the relying party a request's ceremony belongs to: the
// address the person actually reached, when that is this server's own. It
// reports !ok for an address no passkey can be bound to.
func passkeyAuthority(re *core.RequestEvent, root *server.RootKey) (*webauthn.WebAuthn, bool) {
	rpID, origin, ok := util.PasskeyRelyingParty(pageOrigin(re, root))
	if !ok {
		return nil, false
	}
	w, err := webauthn.New(&webauthn.Config{
		RPID:          rpID,
		RPDisplayName: "revoked",
		RPOrigins:     []string{origin},
	})
	return w, err == nil
}

// passkeyName tidies the label a device gives its passkey.
func passkeyName(raw string) string {
	name := strings.Join(strings.Fields(raw), " ")
	if r := []rune(name); len(r) > 60 {
		name = string(r[:60])
	}
	return name
}

// passkeyCeremony is what the server remembers between a challenge and its
// answer.
type passkeyCeremony struct {
	session  webauthn.SessionData
	register bool
	// The account being registered for: an existing one (ticket set) or the
	// id and email a new one will get.
	user, email, ticket string
	// What the new passkey is called.
	name string
	// The app's PKCE challenge, when the result goes back to an app.
	pkce string
	// The proof that a new account's address was confirmed, when one was asked
	// for.
	proof string
}

// passkeyGrant is a finished ceremony waiting for the app to collect it.
type passkeyGrant struct {
	user, pkce string
}

// passkeyVault keeps short-lived values under a random one-time key. In
// memory: a restart costs an attempt in progress and nothing else, and the
// server is one process.
type passkeyVault[T any] struct {
	mu    sync.Mutex
	items map[string]passkeyEntry[T]
}

type passkeyEntry[T any] struct {
	value   *T
	expires time.Time
}

// passkeyVaultCap bounds what unauthenticated callers can make the server
// hold; past it the oldest attempts give way.
const passkeyVaultCap = 10000

func (v *passkeyVault[T]) put(value *T, ttl time.Duration) string {
	key := security.RandomString(48)
	now := time.Now()
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.items == nil {
		v.items = map[string]passkeyEntry[T]{}
	}
	for k, e := range v.items {
		if !e.expires.After(now) {
			delete(v.items, k)
		}
	}
	for len(v.items) >= passkeyVaultCap {
		oldest, at := "", time.Time{}
		for k, e := range v.items {
			if oldest == "" || e.expires.Before(at) {
				oldest, at = k, e.expires
			}
		}
		delete(v.items, oldest)
	}
	v.items[util.HashToken(key)] = passkeyEntry[T]{value: value, expires: now.Add(ttl)}
	return key
}

// peek returns the value under key, if it is still good, and leaves it there.
func (v *passkeyVault[T]) peek(key string) (*T, bool) {
	if key == "" {
		return nil, false
	}
	v.mu.Lock()
	defer v.mu.Unlock()
	e, ok := v.items[util.HashToken(key)]
	if !ok || !e.expires.After(time.Now()) {
		return nil, false
	}
	return e.value, true
}

// take removes and returns the value under key, if it is still good.
func (v *passkeyVault[T]) take(key string) (*T, bool) {
	if key == "" {
		return nil, false
	}
	v.mu.Lock()
	defer v.mu.Unlock()
	hash := util.HashToken(key)
	e, ok := v.items[hash]
	delete(v.items, hash)
	if !ok || !e.expires.After(time.Now()) {
		return nil, false
	}
	return e.value, true
}

var (
	passkeyCeremonies passkeyVault[passkeyCeremony]
	passkeyCodes      passkeyVault[passkeyGrant]
)
