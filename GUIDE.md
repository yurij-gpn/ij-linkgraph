# Building a Single-File App with GitHub Pages + Supabase

A practical guide based on a real project. Covers the full stack: static HTML app hosted on GitHub Pages, Supabase for auth and database, Supabase Edge Functions for secret API proxying.

**Claude Code does all setup steps via CLI.** You provide credentials; Claude applies migrations, creates users, deploys edge functions, configures GitHub Pages, and pushes code — no dashboard copy-pasting required.

---

## Stack overview

| Concern | Solution |
|---------|----------|
| App code | Single `index.html` (HTML + CSS + JS, no build step) |
| Hosting | GitHub Pages (free, auto-deploys on push) |
| Auth | Supabase Auth (email/password) |
| Database | Supabase Postgres with RLS |
| Real-time | Supabase Realtime (postgres_changes) |
| Secret API proxy | Supabase Edge Function (Deno) |
| Local dev | `python3 -m http.server 8080` |

---

## Quick start: what to give Claude

You do **three one-time manual steps**, then hand off to Claude.

### Step 1 — Create a Supabase project (2 minutes)
1. Go to [supabase.com](https://supabase.com) → New project
2. Note down your **project ref** (the ID in the URL: `https://supabase.com/dashboard/project/<ref>`)
3. Go to **Account → Access Tokens** → create a token → note it down

### Step 2 — Authenticate the GitHub CLI (if not already done)
```bash
gh auth login
```

### Step 3 — Tell Claude

Paste this into Claude Code, filling in your values:

```
Set up a new app on this stack:
- Supabase project ref: <your-project-ref>
- Supabase access token: <your-access-token>
- GitHub repo to create (or existing): <username/repo-name>
- App user email: <email>  password: <password>
- Tables needed: <describe your data model in plain English>
- Third-party API keys to proxy (if any): <NAME=value, one per line>
```

Claude will run all steps below automatically.

---

## What Claude does (automated steps)

When given the credentials above, Claude will:

1. **Install Supabase CLI** if not present
2. **Fetch project credentials** (project URL + anon key) from the Supabase Management API
3. **Write `index.html`** with the auth pattern and Supabase client wired up
4. **Write migration SQL** into `migrations/001_initial_schema.sql`
5. **Apply the migration** to the live database
6. **Enable realtime** on all tables
7. **Disable public signups** (private tool mode)
8. **Create the app user** with the provided email/password
9. **Create and push the GitHub repo** (public, so GitHub Pages works)
10. **Enable GitHub Pages** on the `master` branch
11. **Deploy edge functions** and set secrets (if any API proxy is needed)

---

## CLI reference: how Claude runs each step

This section documents the exact CLI commands used, so Claude can reproduce them in any project.

### Install Supabase CLI
```bash
brew install supabase/tap/supabase-beta
export SUPABASE_ACCESS_TOKEN=<token>   # set for the session
```

### Fetch project URL and anon key
```bash
curl -s "https://api.supabase.com/v1/projects/<ref>/api-keys" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}"
# returns array; pick the object where name == "anon"
```

### Apply a SQL migration
```bash
# Write the SQL to migrations/001_initial_schema.sql first, then:
SQL=$(cat migrations/001_initial_schema.sql)
curl -s -X POST "https://api.supabase.com/v1/projects/<ref>/database/query" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-raw "{\"query\": $(echo "$SQL" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}"
```

### Enable realtime on tables
```bash
SQL="alter publication supabase_realtime add table items;"
curl -s -X POST "https://api.supabase.com/v1/projects/<ref>/database/query" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-raw "{\"query\": $(echo "$SQL" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}"
```

### Disable public signups
```bash
curl -s -X PATCH "https://api.supabase.com/v1/projects/<ref>/config/auth" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"disable_signup": true}'
```

### Create an app user
```bash
curl -s -X POST "https://api.supabase.com/v1/projects/<ref>/auth/users" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "secret", "email_confirm": true}'
```

### Create GitHub repo and enable Pages
```bash
gh repo create username/repo-name --public --source=. --remote=origin --push
gh api repos/username/repo-name/pages -X POST \
  -f source='{"branch":"master","path":"/"}' 2>/dev/null || true
# Pages URL: https://username.github.io/repo-name/
```

### Deploy an edge function
```bash
# Write supabase/functions/my-proxy/index.ts first, then:
supabase functions deploy my-proxy --project-ref <ref>
supabase secrets set MY_API_TOKEN=the_secret --project-ref <ref>
```

---

## Code patterns for `index.html`

### Supabase client setup
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
<script>
const SB_URL = 'https://<ref>.supabase.co';
const SB_KEY = '<anon-key>';   // safe to commit — anon key is public by design
const sb = window.supabase.createClient(SB_URL, SB_KEY);
</script>
```

### Auth gate pattern
```html
<div id="login-screen">
  <input id="login-email" type="email" placeholder="Email">
  <input id="login-password" type="password" placeholder="Password">
  <button id="login-btn">Sign in</button>
  <div id="login-error"></div>
</div>
<div id="app" style="display:none">
  <!-- app content -->
  <button id="btn-logout">Sign out</button>
</div>
```

```js
sb.auth.onAuthStateChange((event, session) => {
  if (session) {
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('app').style.display = '';
    loadData();
  } else {
    document.getElementById('login-screen').style.display = '';
    document.getElementById('app').style.display = 'none';
  }
});

document.getElementById('login-btn').addEventListener('click', async () => {
  const { error } = await sb.auth.signInWithPassword({
    email:    document.getElementById('login-email').value.trim(),
    password: document.getElementById('login-password').value,
  });
  if (error) document.getElementById('login-error').textContent = error.message;
});

document.getElementById('btn-logout').addEventListener('click', () => sb.auth.signOut());
```

### Database schema template
```sql
-- migrations/001_initial_schema.sql
create table if not exists items (
  id          text primary key,
  name        text not null,
  data        jsonb,
  created_at  timestamptz default now()
);

alter table items enable row level security;
create policy "auth_all" on items
  for all using (auth.uid() is not null)
  with check (auth.uid() is not null);

alter publication supabase_realtime add table items;
```

### CRUD helpers
```js
async function loadData() {
  const { data } = await sb.from('items').select('*').order('created_at');
  return data || [];
}
async function createItem(item) {
  const { error } = await sb.from('items').insert(item);
  if (error) console.error(error);
}
async function updateItem(id, changes) {
  const { error } = await sb.from('items').update(changes).eq('id', id);
  if (error) console.error(error);
}
async function deleteItem(id) {
  const { error } = await sb.from('items').delete().eq('id', id);
  if (error) console.error(error);
}
```

### Realtime subscription with self-loop guard
```js
let _lastWriteAt = 0;

function startRealtime() {
  sb.channel('db-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'items' }, (payload) => {
      if (Date.now() - _lastWriteAt < 3000) return; // skip own changes
      if (payload.eventType === 'INSERT') { /* add to local state */ }
      if (payload.eventType === 'UPDATE') { /* update local state */ }
      if (payload.eventType === 'DELETE') { /* remove from local state */ }
    })
    .subscribe();
}

async function saveItem(item) {
  _lastWriteAt = Date.now();
  await sb.from('items').upsert(item);
}
```

### Edge Function: secret API proxy
```typescript
// supabase/functions/my-proxy/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SECRET_TOKEN = Deno.env.get("MY_API_TOKEN") ?? "";
const API_BASE     = "https://api.example.com/v1";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return new Response("Unauthorized", { status: 401, headers: cors });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401, headers: cors });

  const url   = new URL(req.url);
  const match = url.pathname.match(/\/my-proxy\/(.*)/);
  const path  = match ? match[1] : "";
  const body  = req.method !== "GET" ? await req.arrayBuffer() : undefined;

  const resp = await fetch(`${API_BASE}/${path}${url.search}`, {
    method: req.method,
    headers: { Authorization: `Bearer ${SECRET_TOKEN}`, "Content-Type": "application/json" },
    body,
  });
  return new Response(await resp.arrayBuffer(), {
    status: resp.status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
```

Calling the edge function from the browser:
```js
const PROXY = 'https://<ref>.supabase.co/functions/v1/my-proxy';

async function proxyGet(endpoint, params = {}) {
  const qs = new URLSearchParams(params).toString();
  const { data: { session } } = await sb.auth.getSession();
  const r = await fetch(`${PROXY}/${endpoint}${qs ? '?' + qs : ''}`, {
    headers: session ? { Authorization: `Bearer ${session.access_token}` } : {},
  });
  if (!r.ok) throw new Error(`${endpoint}: ${r.status}`);
  return r.json();
}
```

---

## Security rules

- `anon` key in source code is fine — it's public by design, protected by RLS
- `service_role` key must never be in source code or git history
- Third-party API keys go in Edge Function secrets only
- RLS must be enabled on every table
- Disable public signups for internal tools

### If a secret is accidentally committed
```bash
# 1. Revoke the key immediately in the provider's dashboard
# 2. Scrub history
pip3 install git-filter-repo
git filter-repo --replace-text <(echo "exposed_secret==>REDACTED") --force
# 3. Re-add remote and force-push
git remote add origin https://github.com/user/repo.git
git push --force --all
# 4. Set the new key as an edge function secret
supabase secrets set MY_API_TOKEN=new_key --project-ref <ref>
```

---

## Dev workflow

```bash
# Run locally
python3 -m http.server 8080

# Apply a new schema change
# 1. Write migrations/00N_description.sql
# 2. Claude runs the curl command above to apply it
# 3. Push code to master — GitHub Pages redeploys automatically
```

Local and GitHub Pages share the same Supabase database. Apply schema changes before pushing code that depends on them.
