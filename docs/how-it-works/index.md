# How it works

Revoked is client and server infrastructure for exchanging data. Whoever holds
data shares it, and whoever needs data requests it. Either way, the data stays
with its owner, and everyone else gets access they can lose.

<video controls preload="none" playsinline poster="https://revoked.link/video/revoked-short-wide.jpg" style="width:100%" aria-label="A short film showing how to share a link, change a value, revoke access, ask for data and sign people in with Revoked. It has no sound.">
  <source media="(max-width: 599px)" src="https://revoked.link/video/revoked-short-tall.mp4" type="video/mp4">
  <source src="https://revoked.link/video/revoked-short-wide.mp4" type="video/mp4">
</video>

## The big picture

Every person uses the app, and every app talks to a server of their choosing.
Services and tools talk to that same server. Servers talk to each other, so people
on different servers can answer each other.

```mermaid
flowchart LR
    subgraph P[On your device]
        A[Revoked app<br/>keeps your private keys]
    end
    subgraph H[Your server, on your domain]
        S[API]
        V[(Vault, shares,<br/>requests, identities)]
        S --- V
    end
    subgraph O[Everyone else]
        L[Whoever has a link]
        Y[Your service or tool]
        R[Other Revoked servers]
    end
    D[DNS record<br/>_revoked.your-domain]
    A <--> S
    L --> S
    Y <--> S
    R <--> S
    D -. names the server's key .-> S
```

| Part | What it does |
|---|---|
| **App** | Your window on all of it. Your identity's private key is made here and never leaves the device. |
| **Server** | Keeps your vault, and checks the rules every time someone opens a link. One Go binary with a built-in database. |
| **DNS record** | Names your server's key, which is what ties it to your domain. |
| **API** | Everything the app does, this API does. There are no private endpoints. |

## Why it's access, not copies

A copy leaves your hands the moment you send it. A link goes back to the vault
every time, so each change and each revocation takes effect on the next read.

```mermaid
flowchart LR
    subgraph C[With a copy]
        direction TB
        O1[Your data] -- sent --> X1[Their copy]
        O1 -- sent --> X2[Another copy]
        X1 -. can't be changed or taken back .-> Z1[Out of your hands]
    end
    subgraph K[With a link]
        direction TB
        O2[(Your vault)]
        L1[Their link] -- reads today's value --> O2
        L2[Another link] -- reads today's value --> O2
    end
```

## Five ways to use it

Each one is the same idea with a different starting point.

| | Who starts it | What the other side ends up with | Try it |
|---|---|---|---|
| **Share** | Whoever has the data | A link to records | [Lab](../labs/share.md) |
| **Collect** | Whoever needs the data | A link to their answer, or the typed answer | [Lab](../labs/collect.md) |
| **Sign in** | A service | An ID made for it, and any entries you agreed to share | [Lab](../labs/sign-in.md) |
| **Prove** | A service, or whoever asks | Only the details you ticked, and proof they're real | [Lab](../labs/prove.md) |
| **Connect** | A tool | The status and views of links it proposed | [Lab](../labs/connect.md) |

## Share

```mermaid
sequenceDiagram
    participant R as Whoever has the link
    participant S as Your server
    R->>S: Open the link
    S->>S: Active? Password? Views left? Verified viewer?
    alt A rule says no
        S-->>R: Refused, with the reason
    else All rules pass
        S-->>R: Today's values from your vault
    end
```

## Collect

```mermaid
sequenceDiagram
    participant A as You
    participant S as Server
    participant R as The person answering
    A->>S: Create a request
    A->>R: Send the link
    R->>S: Check who is asking
    R->>S: Answer from their vault
    S-->>A: Callback, if you set one
    A->>S: Read the answers
    S-->>A: Today's values
```

An answer is kept in the workspace of whoever gave it, so they can change it or
take it back. When people are on different servers, the answer stays at home, and
the other server fetches it each time it's needed.

## Sign in

```mermaid
sequenceDiagram
    participant Y as Your server
    participant P as Your page
    participant A as Revoked app
    participant S as Revoked server
    P->>Y: 1. Start
    Y-->>P: Link and check code
    P->>A: 2. QR code or link
    A->>S: 3. Approve, signed
    A->>Y: 4. Code to your callback
    Y->>S: 5. Redeem the code
    S-->>Y: ID token
    Y-->>P: 6. The session starts
```

Revoked keeps no session of its own. Every sign-in is approved in the app, and the
service keeps its own session after that.

## Prove

Every check starts from DNS. That's what stops anyone from claiming to be someone
they aren't.

```mermaid
flowchart TB
    D[DNS names the server's key] --> S[The server shows that same key]
    S --> I[That key signed the sender's identity]
    I --> T[The server hasn't revoked the identity]
    T --> OK[DNS verified]
    D -- no record --> NV[Not verified: you decide]
    S -- doesn't match --> SP[Spoofed: blocked]
    I -- doesn't match --> SP
    T -- revoked --> RV[Revoked: blocked]
```

```mermaid
sequenceDiagram
    participant C as Who confirms it
    participant Y as Your app
    participant S as The service
    participant V as A Revoked server
    C->>Y: Offer
    Y->>C: Accept, signed with your key
    C-->>Y: The attestation
    S->>Y: Ask, with a fresh nonce
    Y-->>S: Proof with only the ticked details
    S->>V: Check the proof
    V-->>S: verified, and the ticked details
```

## Connect

```mermaid
sequenceDiagram
    participant T as The tool
    participant A as Your app
    participant S as Your server
    T->>A: Propose a link, and ask to connect
    A->>S: Create the share and the connection
    A-->>T: One-time code
    T->>S: Code and verifier
    S-->>T: Connection token
    T->>S: What became of my links?
    S-->>T: Status and views, never the values
```

## What the server can and can't see

| | Server sees it? | Why |
|---|---|---|
| Your vault records | Yes | It reads them to answer a link. Run your own server, so it's yours. |
| An end-to-end encrypted record | **No** | Encrypted on your device. Its value on the server is always empty. |
| Your identity's private key | **No** | Made on your device, and it never leaves. |
| Your passkey | **No** | Your device keeps it. The server only sees the public half. |
| Who opened a link | How often | It counts views. The owner sees the count. |

## Go deeper

- [Trust chain](../api/trust-chain.md) explains each check, for developers.
- [Authentication](../api/authentication.md) covers the three credentials.
- [Roadmap](../roadmap.md) has what's planned and how it's designed.
