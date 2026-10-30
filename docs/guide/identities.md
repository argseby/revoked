# Identities & trust

An identity lets people check that a share or request really came from
you. It's tied to your server's domain, so a fake sent in your name shows
up as a fake.

Your identity's private key is made on your device and never leaves it. It
stays in your system's keychain. Your server only ever sees the public
half, and signs it. Your domain's DNS names your server's key. That closes
the loop: your domain vouches for your server, your server vouches for
your identity, and your identity signs what you send. The
[trust chain](../api/trust-chain.md) has the details.

## Manage your identities

You choose your name when you set up, and that's the name recipients see.
Under **Settings → Identities** you can create more, **Set as primary**
(the one offered first when you sign a share or request), and **Revoke**
the ones you no longer stand behind.

Revoking can't be undone. An identity's certificate stays valid for years,
so revoking is what tells everyone to stop trusting it. Anyone who checks
it, on your server or another, is told within the hour. Links and requests
it signed keep working, but no longer show as verified. Revoking also
erases the private key from this device. Revoked identities are kept on
record, never erased, so nobody is left guessing.

Lose your device, and you lose its private key too. There's no export, on
purpose.

## Check who sent something

Whenever a share, request or invite arrives, the app checks who sent it.
You always see the result together with the reason, never just a badge:

| Result | What it means | What the app does |
|---|---|---|
| **DNS verified** | The domain, the keys, the signature and the identity's status all agree. | Lets you continue. |
| **Not verified** | The domain hasn't published its DNS record, or the identity is older than this check. Not proven, but not forged either. | Asks you to confirm before you continue. |
| **Spoofed** | The claim contradicts what the domain publishes. | Blocks it. This is not a setup mistake. |
| **Revoked** | Everything checks out, but the sender's server has withdrawn the identity. | Blocks it. |

The app asks public DNS services over an encrypted connection, so it
doesn't rely on whatever network you're on. If the check can't finish, the
result is **Not verified**. A failed check never counts as a pass.

## Let others confirm facts about you

An identity shows where something came from. It says nothing else about
you. Facts like your age, a membership or your job are confirmed by
others, as [attestations](attestations.md). Each one belongs to one
identity. Revoke the identity, and its attestations stop working too.

## When you leave a workspace

If you're removed from a workspace, the identities you used there are
revoked at the same moment. That's the point of the whole chain: a
certificate keeps proving what it proved on day one. Only revoking can end
it.

## Check your own domain

Running your own server? **Settings → Developer → Domain verification**
checks the whole chain against it and tells you exactly which step fails.
Until your [DNS record](../installation/dns.md) is published, everything
you send shows as **Not verified**. Publish it, and your earlier shares and
requests show as verified too.
