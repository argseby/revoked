# Your AI assistant

An AI assistant can prepare Revoked actions from plain-language
instructions: sharing an address with a landlord, collecting a tax ID from
a colleague, or checking which links were opened. The assistant prepares
each action, and the action is confirmed in the Revoked app.

By default the assistant never sees values. It names what to share; values
are filled in and saved in the app. It can also
[keep notes](#let-it-keep-notes-for-you) in a section of its own and, if
permitted, [read the vault](#let-it-read-your-vault) to answer questions
about it.

## Requirements

- The Revoked app, signed in.
- An AI application that supports MCP, such as Claude Code or Claude
  Desktop.
- The Revoked assistant program, `revoked-mcp`, on the same computer as the
  AI application.

## Setup

### Building the program

`revoked-mcp` is built from the Revoked source code and requires
[Go](https://go.dev/dl/):

```bash
go build -o ~/.local/bin/revoked-mcp ./cmd/revoked-mcp
```

### Adding it to the AI application

The server address must be the one the Revoked app is signed in to. A
different server means a different account.

In **Claude Code**:

```bash
claude mcp add revoked -e REVOKED_SERVER=https://api.revoked.link -- ~/.local/bin/revoked-mcp
```

In **Claude Desktop**, under **Settings → Developer → Edit Config**:

```json
{
  "mcpServers": {
    "revoked": {
      "command": "/home/you/.local/bin/revoked-mcp",
      "env": { "REVOKED_SERVER": "https://api.revoked.link" }
    }
  }
}
```

The change takes effect in a new chat or after restarting the application.
For a server running on the same computer, the address is
`http://localhost:3000`.

### Connecting to the account

The AI application may list Revoked as connected as soon as the program
runs. The account still has to approve the connection:

1. Ask the assistant: *“Connect to Revoked.”*
2. The Revoked app opens with **Connect AI assistant**, and the assistant
   reports a short code, such as `83C-047`.
3. Confirm that the app shows the same code. If it does not, press
   **Decline**.
4. Select the permissions, then press **Connect**.
5. Ask the assistant: *“Check the Revoked connection.”*

This is a one-time step. The connection lasts 90 days, and connecting
again renews it.

## Example instructions

Instructions are given in plain language:

- *“Share my email and phone number with Sam for a week.”*
- *“Ask Alex for their tax ID with my bank details template.”*
- *“Which of my links have been opened?”*
- *“Has anyone answered my request yet?”*
- *“End the link I made for Sam.”*

Each prepared action opens the Revoked app with everything filled in.
Nothing happens until it is checked, completed and saved there.

The assistant tracks only what it prepared. Links and requests created
directly in the app are not visible to it.

## Notes section {#let-it-keep-notes-for-you}

The assistant can keep data such as a packing list or a draft in a section
of its own:

1. Ask the assistant: *“Connect to Revoked with a section of your own.”*
2. The Revoked app shows **Vault section** with the name of the new
   section. Leave it on and press **Connect**.
3. Items the assistant saves appear in the vault, marked **Added by** and
   the assistant's name.

It sees only that section and changes only what it added. To let it create
shares and requests without confirming each one, ask it to
*“connect with permission to create shares and requests”*. As with vault
access, this requires the Revoked app on the same computer.

## Vault access {#let-it-read-your-vault}

Questions such as *“What's my IBAN?”* or *“Fill in this form from my
vault”* require read access to the vault, which is granted explicitly:

1. Ask the assistant: *“Connect to Revoked with vault access.”*
2. The Revoked app shows **Read vault**, off by default.
3. Read **Vault read access**, and turn the switch on only if
   its terms are acceptable.
4. Press **Connect**. A browser tab opens to confirm the connection and can
   be closed.

Enabling it has these consequences:

- The assistant sees the value of any record it opens.
- What it sees leaves Revoked. Revoking or disconnecting later cannot take
  it back.
- For an AI assistant, the company that runs the AI also receives what it
  sees.
- It cannot change or delete records the owner added to the vault.
- Encrypted records stay hidden from it.

Vault access works only when the Revoked app runs on the same computer as
the assistant, so a connect link from someone else can never reach the
vault.

To withdraw access, open **Settings → Connected tools**, select the
assistant, and turn off **Read vault**. Reading stops immediately.
Enabling it again requires connecting with vault access.

## Limits

The assistant cannot:

- save, send or publish anything without confirmation,
- change or delete records the owner added to the vault,
- see the account, or links and requests created directly in the app,
- read the vault unless **Read vault** is on.

## Pausing and disconnecting

Under **Settings → Connected tools**, select the assistant:

- Turning off **Active** suspends it; turning it on restores it.
- **Disconnect** ends the connection permanently. What it prepared stays in
  the workspace.

After disconnecting, the assistant must connect again before it can be
used.

## Troubleshooting

| Symptom | Resolution |
|---|---|
| Nothing opens when it prepares something | The computer does not handle `revoked://` links. Ask the assistant for the link and open it in the Revoked app manually. |
| The codes don't match | Press **Decline**, then ask the assistant to connect again. |
| It says it isn't connected | Ask it to connect. A connection ends after 90 days, or when it is disconnected. |
| It can't read the vault | Ask it to connect with vault access, with the Revoked app running on the same computer. |
| It can't reach the server | Check the configured address. It must be the server the app is signed in to. |
