# Labs

Each lab takes one part of Revoked and has you use it. You follow the steps,
and every step tells you what you should see. If it doesn't match, the lab says
what to do.

New here? [Try it in 5 minutes](../try/index.md) first.

| Lab | You'll learn to | Time | You need |
|---|---|---|---|
| [Share](share.md) | Decide who gets in, watermark a file, and end a link | 10 min | The app |
| [Collect](collect.md) | Ask people for information and get it into your own system | 15 min | The app, Python |
| [Prove](prove.md) | Confirm a fact and show only part of it | 15 min | The app, Python |
| [Connect](connect.md) | Let a tool see what became of its links | 15 min | The app, Python |
| [Sign in](sign-in.md) | Sign people in to a service with no passwords | 15 min | The app, Node 22 |

!!! warning "These labs use the official test server"
    `api.revoked.link` is experimental and for testing, with no guarantees for
    your data. Keep nothing there you can't lose. Every lab also works on
    [your own server](../installation/index.md): use its address instead.

## Get the lab files

Three labs use small files from the repository:

```bash
git clone https://github.com/argseby/revoked && cd revoked
```

| File | What it does |
|---|---|
| `examples/labs/listen.py` | Prints every request it receives, so you can see what the server and the app send. |
| `examples/labs/guestbook/` | A tiny tool, one HTML file, for the Connect lab. |
| `examples/sign-in-demo/` | Corner Shop, a complete service for the Sign in lab. |

## Open a link in the app

Labs use `revoked://` links. Click one if the app is registered on your
computer. Otherwise, choose **New → Open or scan a link** in the app and paste
it. You can also press **Ctrl+V** in the app with the link on your clipboard.
