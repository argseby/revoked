package routes

import (
	"net/http"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// CertificateRoute registers the unauthenticated GET /api/certificate[/{id}]
// endpoints. They expose public key material only: the CA private key is filtered
// out by [util.ServerCertificate.PublicView] — never serialize the certificate
// struct directly.
func CertificateRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/certificate", func(e *core.RequestEvent) error {
			cert, err := util.GetServerCertificate()
			if err != nil {
				return e.BadRequestError("Certificate not loaded", err)
			}
			return e.JSON(http.StatusOK, cert.PublicView())
		})

		e.Router.GET("/api/certificate/{id}", func(e *core.RequestEvent) error {
			identity, err := app.FindRecordById(util.Coll.Identities, e.Request.PathValue("id"))
			if err != nil || identity == nil {
				return e.NotFoundError("Identity not found", err)
			}
			return e.JSON(http.StatusOK, map[string]any{
				"id":              identity.Id,
				"name":            identity.GetString(util.Fields.Identity.Name),
				"certificate":     identity.GetString(util.Fields.Identity.Certificate),
				"fingerprint":     identity.GetString(util.Fields.Identity.Fingerprint),
				"parentSignature": identity.GetString(util.Fields.Identity.ParentSignature),
				"domainAtIssue":   identity.GetString(util.Fields.Identity.DomainAtIssue),
			})
		})

		return e.Next()
	})
}
