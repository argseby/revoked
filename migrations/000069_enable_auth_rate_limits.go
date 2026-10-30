package migrations

import (
	"slices"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/migrations"
)

// authRateLimitRules throttles PocketBase's own sign-in endpoints, which the
// custom limiters never see. The superuser login guards the root key, so it
// gets a budget a person typing never reaches and a guesser always does.
//
// No catch-all "/api/" or "*:create" rule: PocketBase keys by RealIP, so
// behind a proxy without trusted-proxy headers every visitor would share one
// bucket. PocketBase ships both among its defaults, inert while the limiter is
// off, so a limiter that was off has its rules replaced rather than extended.
var authRateLimitRules = []core.RateLimitRule{
	{Label: core.CollectionNameSuperusers + ":auth", MaxRequests: 5, Duration: 300},
	{Label: "*:auth", MaxRequests: 2, Duration: 3},
	{Label: "*:requestPasswordReset", MaxRequests: 2, Duration: 600},
	{Label: "*:requestOTP", MaxRequests: 2, Duration: 600},
}

func init() {
	migrations.Register(func(app core.App) error {
		settings := app.Settings()
		if !settings.RateLimits.Enabled {
			settings.RateLimits.Rules = nil
		}
		for _, rule := range authRateLimitRules {
			if !slices.ContainsFunc(settings.RateLimits.Rules, func(r core.RateLimitRule) bool {
				return r.Label == rule.Label && r.Audience == rule.Audience
			}) {
				settings.RateLimits.Rules = append(settings.RateLimits.Rules, rule)
			}
		}
		settings.RateLimits.Enabled = true
		return app.Save(settings)
	}, func(app core.App) error {
		settings := app.Settings()
		settings.RateLimits.Rules = slices.DeleteFunc(settings.RateLimits.Rules, func(r core.RateLimitRule) bool {
			return slices.Contains(authRateLimitRules, r)
		})
		if len(settings.RateLimits.Rules) == 0 {
			settings.RateLimits.Enabled = false
		}
		return app.Save(settings)
	})
}
