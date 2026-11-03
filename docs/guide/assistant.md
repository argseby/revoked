# Your AI assistant

Let your AI assistant do the busywork. Ask it in plain words to share your
address with your landlord, collect a tax ID from a colleague, or check which
of your links were opened. It prepares everything, and you confirm in the
Revoked app.

By default your assistant never sees your values. It names what to share,
and you fill in and save. If you want it to answer questions about your
vault too, you can [let it read your vault](#let-it-read-your-vault).

## What you need

- The Revoked app, signed in to your account.
- An AI app that supports MCP, such as Claude Code or Claude Desktop.
- The Revoked assistant program, `revoked-mcp`, on the same computer as the
  AI app.

## Set it up once

### Get the program

Build it from the Revoked source code. You need [Go](https://go.dev/dl/):

```bash
go build -o ~/.local/bin/revoked-mcp ./cmd/revoked-mcp
```

### Add it to your AI app

Use the address of the server your Revoked app is signed in to. If it's a
different server, your assistant works for a different account.

In **Claude Code**, run:

```bash
claude mcp add revoked -e REVOKED_SERVER=https://api.revoked.link -- ~/.local/bin/revoked-mcp
```

In **Claude Desktop**, open **Settings → Developer → Edit Config** and add:

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

Then start a new chat, or restart the app. Running your own server on this
computer? Use `http://localhost:3000` as the address.

### Connect it to your account

Your AI app may already list Revoked as connected. That only means the
program is running. Your account still has to say yes:

1. Ask your assistant: *“Connect to Revoked.”*
2. The Revoked app opens with **AI assistant wants to connect**, and your
   assistant tells you a short code, such as `83C-047`.
3. Check that the app shows the same code. If it doesn't, press **Decline**.
4. Choose what it may do, then press **Connect**.
5. Ask your assistant: *“Check the Revoked connection.”*

You only do this once. The connection lasts 90 days, and connecting again
renews it.

## Ask it things

Talk to it as you would to a person:

- *“Share my email and phone number with Sam for a week.”*
- *“Ask Alex for their tax ID with my bank details template.”*
- *“Which of my links have been opened?”*
- *“Has anyone answered my request yet?”*
- *“End the link I made for Sam.”*

Each time it prepares something, the Revoked app opens with everything
filled in. Check it, fill in anything missing, and save. Nothing happens
until you do.

Your assistant only keeps track of what it prepared. Links and requests you
made yourself stay out of its sight.

## Let it read your vault

Want to ask *“What's my IBAN?”* or *“Fill in this form from my vault”*? Your
assistant has to read your vault for that. You decide:

1. Ask your assistant: *“Connect to Revoked with vault access.”*
2. The Revoked app shows **Read your vault**. It's off.
3. Read **What reading your vault means**. Turn it on only if you agree.
4. Press **Connect**. A browser tab opens and says your assistant is
   connected. You can close it.

Before you turn it on, know what it means:

- Your assistant sees the value of any record it opens.
- What it sees leaves Revoked. Revoking or disconnecting later can’t take
  it back.
- If it's an AI assistant, the company that runs the AI gets what it sees,
  too.
- It can't change or delete anything in your vault.
- Encrypted records stay hidden from it.

This only works when the Revoked app runs on the same computer as your
assistant. That way, a connect link from someone else can never get into
your vault.

**Changed your mind?** Open **Settings → Connected tools**, pick your
assistant, and untick **Read your vault**. It stops reading at once. To turn
it on again, ask your assistant to connect with vault access.

## What it can never do

- Save, send or publish anything without you.
- Change or delete records in your vault.
- See your account, or the links and requests you made yourself.
- Read your vault, unless you turned on **Read your vault**.

## Take a break or stop

Open **Settings → Connected tools** and pick your assistant:

- **Pause** stops it for now. **Activate** brings it back.
- **Disconnect** cuts it off for good. What it prepared stays yours.

To use it again after disconnecting, ask it to connect.

## Something isn't working

| What you see | What to do |
|---|---|
| Nothing opens when it prepares something | Your computer doesn't open `revoked://` links. Ask your assistant for the link, and open it in the Revoked app yourself. |
| The codes don't match | Press **Decline**. Then ask your assistant to connect again. |
| It says it isn't connected | Ask it to connect. A connection ends after 90 days, or when you disconnect it. |
| It can't read your vault | Ask it to connect with vault access, with the Revoked app on the same computer. |
| It can't reach your server | Check the address you gave it. It must be the server your app is signed in to. |
