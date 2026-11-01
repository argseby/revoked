package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"sync"

	"revoked/tests/testutils"
	"revoked/util"

	"github.com/google/uuid"
)

// SeedUser is one account the generator drives, with everything a scenario
// needs to act as it: the JWT, the workspace its records live in, an identity
// to sign shares with, and the device holding its passkey.
type SeedUser struct {
	ID          string `json:"id"`
	WorkspaceID string `json:"workspace"`
	IdentityID  string `json:"identity"`
	Token       string `json:"-"`
	RecordIDs   []string
	Device      *testutils.PasskeyDevice `json:"-"`
}

// SeedSlug is a capability slug plus the index of the account that owns it,
// so a scenario can answer somebody else's request rather than its own.
type SeedSlug struct {
	Slug  string
	Owner int
}

// Fixtures is the data the run reads and writes against.
type Fixtures struct {
	Users    []SeedUser
	Links    []SeedSlug
	Requests []SeedSlug
}

type seedConfig struct {
	users           int
	recordsPerUser  int
	linksPerUser    int
	requestsPerUser int
}

// Seed builds the fixtures over the public API, the way a client does, so a
// run exercises the same hooks and rules a real workload would. Accounts are
// registered in parallel: each one is a passkey ceremony, and serially they
// dominate the setup time.
func Seed(ctx context.Context, c *Caller, cfg seedConfig) (*Fixtures, error) {
	fx := &Fixtures{}

	users := make([]*SeedUser, cfg.users)
	errs := make([]error, cfg.users)
	var wg sync.WaitGroup
	for i := range users {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			u, err := seedUser(ctx, c, cfg)
			if err != nil {
				errs[i] = err
				return
			}
			users[i] = u
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			return nil, fmt.Errorf("seeding account %d: %w", i, err)
		}
		fx.Users = append(fx.Users, *users[i])
	}

	for owner, u := range fx.Users {
		for i := 0; i < cfg.linksPerUser; i++ {
			slug, err := seedLink(ctx, c, u)
			if err != nil {
				return nil, fmt.Errorf("seeding link: %w", err)
			}
			fx.Links = append(fx.Links, SeedSlug{Slug: slug, Owner: owner})
		}
		for i := 0; i < cfg.requestsPerUser; i++ {
			slug, err := seedRequest(ctx, c, u)
			if err != nil {
				return nil, fmt.Errorf("seeding request: %w", err)
			}
			fx.Requests = append(fx.Requests, SeedSlug{Slug: slug, Owner: owner})
		}
	}

	log.Printf("seeded %d accounts, %d links, %d requests",
		len(fx.Users), len(fx.Links), len(fx.Requests))
	return fx, nil
}

func seedUser(ctx context.Context, c *Caller, cfg seedConfig) (*SeedUser, error) {
	// The suite's helper is the one implementation of the registration
	// ceremony; a second copy here would drift from the server it drives.
	id, token, device, err := testutils.CreateRandomUserWithDevice(c.base)
	if err != nil {
		return nil, err
	}
	u := &SeedUser{ID: id, Token: token, Device: device}

	var account struct {
		ActiveWorkspace string `json:"activeWorkspace"`
	}
	if err := c.JSON(ctx, "GET", "/api/collections/"+util.Coll.Users+"/records/"+id, token, nil, &account); err != nil {
		return nil, err
	}
	u.WorkspaceID = account.ActiveWorkspace

	publicKey, err := newPublicKeyPem()
	if err != nil {
		return nil, err
	}
	var identity struct{ Id string }
	if err := c.JSON(ctx, "POST", "/api/collections/"+util.Coll.Identities+"/records", token, map[string]any{
		util.Fields.Identity.Name:      "loadtest",
		util.Fields.Identity.PublicKey: publicKey,
		util.Fields.Identity.User:      id,
		util.Fields.Identity.Workspace: u.WorkspaceID,
	}, &identity); err != nil {
		return nil, err
	}
	u.IdentityID = identity.Id

	for i := 0; i < cfg.recordsPerUser; i++ {
		var record struct{ Id string }
		if err := c.JSON(ctx, "POST", "/api/collections/"+util.Coll.Records+"/records", token, map[string]any{
			util.Fields.Record.Key:       fmt.Sprintf("loadtest_%d", i),
			util.Fields.Record.Value:     fmt.Sprintf("value-%s", uuid.NewString()),
			util.Fields.Record.Label:     fmt.Sprintf("Load test record %d", i),
			util.Fields.Record.Type:      util.TypeText,
			util.Fields.Record.Format:    util.FormatDefault,
			util.Fields.Record.User:      id,
			util.Fields.Record.Workspace: u.WorkspaceID,
		}, &record); err != nil {
			return nil, err
		}
		u.RecordIDs = append(u.RecordIDs, record.Id)
	}
	return u, nil
}

func seedLink(ctx context.Context, c *Caller, u SeedUser) (string, error) {
	slug := "lt-" + uuid.NewString()
	return slug, c.JSON(ctx, "POST", "/api/collections/"+util.Coll.Links+"/records", u.Token, map[string]any{
		util.Fields.Link.Slug:      slug,
		util.Fields.Link.Label:     "Load test share",
		util.Fields.Link.Status:    util.StatusActive,
		util.Fields.Link.User:      u.ID,
		util.Fields.Link.Workspace: u.WorkspaceID,
		util.Fields.Link.Identity:  u.IdentityID,
		util.Fields.Link.Records:   u.RecordIDs,
	}, nil)
}

func seedRequest(ctx context.Context, c *Caller, u SeedUser) (string, error) {
	slug := "lr-" + uuid.NewString()
	return slug, c.JSON(ctx, "POST", "/api/collections/"+util.Coll.Requests+"/records", u.Token, map[string]any{
		util.Fields.Request.Slug:      slug,
		util.Fields.Request.Label:     "Load test request",
		util.Fields.Request.Status:    util.StatusActive,
		util.Fields.Request.User:      u.ID,
		util.Fields.Request.Workspace: u.WorkspaceID,
		util.Fields.Request.Identity:  u.IdentityID,
	}, nil)
}

// newPublicKeyPem returns a fresh RSA public key. Only the public half is ever
// sent, matching what a client does: the private key stays on the device.
func newPublicKeyPem() (string, error) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", err
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		return "", err
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})), nil
}
