# Templates

A template defines a reusable structure of sections and fields, each with a
label and a type. Templates are used in two places:

- in a [request](requests.md), to define what respondents fill in,
- in the vault, to [create the same sections and records](vault.md#start-from-a-template)
  in one step.

## Custom templates

Templates are listed under **Settings → Developer → Templates**, and
through **Templates** on the Requests page.

The editor offers two views of the same template: **Visual** (adding and
reordering sections and fields) and **JSON (advanced)**. Changes carry
over between the two, so a template can be built visually, refined in
JSON, or pasted in from elsewhere.

Each field has a [type](vault.md#records) and can be marked **Required**:
a request using the template cannot be sent without it.

A field whose `format` is set to `hidden` in the JSON stores its answer as
a hidden record, which suits secrets.

### Who sees a template {#members}

A new template is seen by every member of the workspace, who can ask with
it, as templates always were. **Visibility** in a template's options, offered
to whoever made it, keeps it to its owner instead (**Private**), and sets
whether members who may manage templates can change and delete it. Templates
made before this setting existed have no owner and stay with the workspace.

## Built-in templates

Every server ships with ready-made templates: Wi-Fi access, API
credentials, personal information, employee onboarding and more. They
appear in every workspace, marked **Built-in**, and work wherever a
template does: when [creating a request](requests.md), or with
**New → From a template** in the [vault](vault.md#start-from-a-template).

Built-in templates cannot be changed or deleted, not even by a workspace
admin. A variation is created as a custom template with the required
fields. Server operators can also
[change the built-in list](../installation/operations.md#the-template-catalogue)
for every workspace on the server.
