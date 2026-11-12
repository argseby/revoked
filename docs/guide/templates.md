# Templates

A template defines a reusable structure of sections and fields, each with a
label and a type. Templates are used in two places:

- in a [request](requests.md), to define what respondents fill in,
- in the vault, to [create the same sections and records](vault.md#start-from-a-template)
  in one step.

## Example: one structure, two uses

A delivery-details template can define these fields:

| Key | Label | Type | Required |
|---|---|---|---|
| `shipping_address` | Delivery address | Text | Yes |
| `phone` | Phone number | Text | No |

Used in a **request**, it produces a form asking a respondent for an address
and an optional phone number. Used with **New → From a template** in the vault,
it creates records with those keys, ready for values to be entered.

The template defines structure; it does not hold a customer's address and does
not grant access to records. Two customers can answer the same template with
different records and values. Consistent keys let the receiving service locate
the address without depending on a display label or field order.

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

### JSON example

The delivery-details example above has this schema in **JSON (advanced)**.
The template name is entered separately; this object is the field schema,
not the complete API record:

```json
{
  "records": [
    {
      "key": "shipping_address",
      "label": "Delivery address",
      "type": "text",
      "required": true
    },
    {
      "key": "phone",
      "label": "Phone number",
      "type": "text"
    }
  ]
}
```

Switching to **Visual** shows the same two fields. `required` is omitted for
the optional phone number. Keys match the fields requested by an integration;
labels supply their readable names.

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
