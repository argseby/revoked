// Reading the entries a person shared at sign-in.
//
// The service never receives a copy. It holds a grant — an id and a token —
// and reads the current value from the person's server when it needs it,
// keeping a value no longer than the server's maxAge allows. When the person
// edits the entry, the next read shows the new value; when they revoke the
// grant, the next read says so and returns nothing.

export class GrantError extends Error {}

// Reads every grant of a sign-in. `cache` is the session's own and holds the
// last answer per grant: reused while fresh, revalidated with its ETag after.
export async function readGrants(signIn, cache) {
  const links = signIn.grants;
  if (!links?.grants?.length) return [];

  // The tokens go to the person's own server and nowhere else, whatever the
  // userinfo answer names as its endpoint.
  const endpoint = new URL(links.endpoint);
  if (endpoint.origin !== new URL(signIn.issuer).origin) {
    throw new GrantError('The grant endpoint is not on the server the person signed in with.');
  }

  const now = Date.now();
  const stale = links.grants.filter((g) => !(cache.get(g.id)?.expires > now));
  if (stale.length) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(8000),
      body: JSON.stringify({
        grants: stale.map((g) => ({ id: g.id, token: g.token, etag: cache.get(g.id)?.etag })),
      }),
    });
    if (!response.ok) {
      throw new GrantError(`The person's server answered ${response.status} when the entries were read.`);
    }
    const { items } = await response.json();
    for (const item of items) {
      const previous = cache.get(item.id);
      cache.set(item.id, {
        status: item.status,
        values: item.notModified ? previous?.values ?? {} : item.values ?? {},
        etag: item.etag,
        maxAge: item.maxAge,
        readAt: now,
        expires: now + Math.max(0, item.maxAge) * 1000,
      });
    }
  }

  return links.grants.map((g) => {
    const entry = cache.get(g.id);
    return {
      keys: g.keys,
      status: entry?.status ?? 'not_found',
      values: entry?.status === 'active' ? entry.values : {},
      readAt: entry ? new Date(entry.readAt) : null,
      maxAge: entry?.maxAge ?? 0,
    };
  });
}
