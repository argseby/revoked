# Templates

A template saves you building the same thing twice. It lists sections and
fields, each with a label and a type. You can use it two ways:

- in a [request](requests.md), to say what people should fill in,
- in your vault, to [create the same sections and records](vault.md#start-from-a-template)
  in one go.

## Build your own

Find your templates under **Settings → Developer → Templates**, or press
**Templates** on the Requests page.

The editor shows the same template two ways: **Visual** (add sections and
fields, reorder them) and **JSON (advanced)**. Changes carry over between
the two. Build it visually, fine-tune the JSON, or paste in a template
someone sent you.

For each field, pick its [type](vault.md#records) and whether it's
**Required**: a request using this template can't be sent without it.

Collecting secrets? Set a field's `format` to `hidden` in the JSON, and its
answer is saved as a hidden record.

## Built-in templates

Every server comes with ready-made templates: Wi-Fi access, API
credentials, personal information, employee onboarding and more. So you
have something to start from on day one. They show up in every workspace,
marked **Built-in**, and work wherever a template does: when you
[create a request](requests.md), or with **New → From a template** in your
[vault](vault.md#start-from-a-template).

Nobody can change or delete a built-in, not even a workspace admin. Want a
variation? Create your own template with the fields you need. If you run
the server, you can also
[change the built-in list](../installation/operations.md#the-template-catalogue)
for everyone on it.
