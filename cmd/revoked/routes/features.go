package routes

import (
	"net/http"
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// FeaturesRoute serves the feature catalogue and the invite presets, beside
// the permission catalogue, so a client renders the list the server knows
// instead of a copy that drifts. Unauthenticated: it is API contract.
func FeaturesRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/features", func(re *core.RequestEvent) error {
			presets := make([]map[string]any, 0, len(util.FeaturePresets))
			for _, p := range util.FeaturePresets {
				presets = append(presets, map[string]any{
					"key":         p.Key,
					"label":       p.Label,
					"description": p.Description,
					"permissions": p.Permissions,
					"features":    p.Features,
				})
			}
			return re.JSON(http.StatusOK, map[string]any{
				"features": featureDetails(util.AllFeatureKeys()),
				"presets":  presets,
			})
		})
		return e.Next()
	})
}

// AccountFeaturesRoute lets a person choose which parts of the app they see.
// The only way the field is written: the collection API refuses it, so every
// stored set has been checked against the catalogue.
func AccountFeaturesRoute(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.PUT("/api/account/features", func(re *core.RequestEvent) error {
			// Users only: a feature set is a person's view, which an API key has none of.
			if re.Auth == nil || re.Auth.Collection().Name != util.Coll.Users {
				return appErrorResponse(re, http.StatusUnauthorized, &util.Errors.NotAuthenticated)
			}
			var body struct {
				Features []string `json:"features"`
			}
			if err := re.BindBody(&body); err != nil || body.Features == nil {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.ValidationFieldRequired)
			}
			features, unknown := util.NormalizeFeatures(body.Features)
			if len(unknown) > 0 {
				return appErrorResponse(re, http.StatusBadRequest, &util.Errors.UnknownFeature)
			}
			re.Auth.Set(util.Fields.User.Features, features)
			if err := app.Save(re.Auth); err != nil {
				return re.InternalServerError("Failed to save the feature set", nil)
			}
			return re.JSON(http.StatusOK, map[string]any{"features": features})
		})
		return e.Next()
	})
}

// featureDetails labels feature keys so screens never show raw ones.
func featureDetails(keys []string) []map[string]any {
	out := []map[string]any{}
	for _, key := range keys {
		f, ok := util.FeatureByKey(key)
		if !ok {
			continue
		}
		out = append(out, map[string]any{
			"key":         f.Key,
			"label":       f.Label,
			"description": f.Description,
			"permission":  f.Permission,
			"defaultOn":   f.DefaultOn,
		})
	}
	return out
}

// accountFeatureKeys is what an account sees: what it chose, or the defaults.
func accountFeatureKeys(user *core.Record) []string {
	if user == nil {
		return util.DefaultFeatureKeys()
	}
	if chosen, set := util.StoredFeatures(user, util.Fields.User.Features); set {
		return chosen
	}
	return util.DefaultFeatureKeys()
}
