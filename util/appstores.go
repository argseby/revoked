package util

import (
	"net/url"
	"os"
	"strings"
)

// Where the app is downloaded, shown on the /app page a phone reaches from the
// QR code a computer shows. Unset, the page only offers to open the app.
const (
	AppStoreURLEnv  = "APP_STORE_URL"
	PlayStoreURLEnv = "PLAY_STORE_URL"
)

// AppStoreURL is the iOS download link, or "" when unset or not https.
func AppStoreURL() string { return httpsURL(os.Getenv(AppStoreURLEnv)) }

// PlayStoreURL is the Android download link, or "" when unset or not https.
func PlayStoreURL() string { return httpsURL(os.Getenv(PlayStoreURLEnv)) }

func httpsURL(raw string) string {
	raw = strings.TrimSpace(raw)
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return ""
	}
	return u.String()
}
