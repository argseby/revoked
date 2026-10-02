package hooks

import (
	"revoked/util"

	"github.com/pocketbase/pocketbase/core"
)

// BindMailSettings applies the mail server named in the environment over
// PocketBase's stored settings, at boot and whenever the settings reload. In
// memory only: the dashboard keeps whatever it saved, and the next boot wins.
func BindMailSettings(app core.App) {
	apply := func(app core.App) {
		cfg, ok := util.SMTPFromEnv()
		if !ok {
			return
		}
		s := app.Settings()
		s.SMTP.Enabled = true
		s.SMTP.Host = cfg.Host
		s.SMTP.Port = cfg.Port
		s.SMTP.Username = cfg.Username
		s.SMTP.Password = cfg.Password
		s.SMTP.TLS = cfg.TLS
		if cfg.AuthMethod != "" {
			s.SMTP.AuthMethod = cfg.AuthMethod
		}
		if cfg.SenderAddress != "" {
			s.Meta.SenderAddress = cfg.SenderAddress
		}
		s.Meta.SenderName = cfg.SenderName
	}
	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		apply(e.App)
		return nil
	})
	app.OnSettingsReload().BindFunc(func(e *core.SettingsReloadEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		apply(e.App)
		return nil
	})
}
