package util

// MaxOpenConnectionsEnv caps how many TCP connections the server holds at once.
// 0 removes the cap.
const MaxOpenConnectionsEnv = "MAX_CONNECTIONS"

// DefaultMaxOpenConnections is well above what any single-tenant instance sees
// — a few hundred keep-alive browsers and clients — and well below what a
// modest container can hold in memory at once.
const DefaultMaxOpenConnections = 2048
