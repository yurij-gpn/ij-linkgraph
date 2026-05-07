# Building a Single-File App with GitHub Pages + Supabase

A practical guide based on a real project. Covers the full stack: static HTML app hosted on GitHub Pages, Supabase for auth and database, Supabase Edge Functions for secret API proxying.

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

## 1. GitHub repo setup

1. Create a **public** repo on GitHub (GitHub Pages requires public for free plans)
2. Push your `index.html` to `master`
3. Go to **Settings → Pages → Source** → select branch `master`, folder `/`
4. Your app is live at `https://<username>.github.io/<repo>/`

Every push to `master` triggers an automatic redeploy (usually under 60 seconds).

---

## 2. Supabase project setup

1. Create a project at [supabase.com](https://supabase.com)
2. From **Project Settings → API**, copy:
   - `Project URL` → your `SB_URL`
   - `anon / public` key → your `SB_KEY` (safe to commit, used client-side)
   - Never commit the `service_role` secret key

Load the Supabase JS client via CDN — no npm needed:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
<script>
const SB_URL = 'https://your-project-ref.supabase.co';
const SB_KEY = 'your-anon-public-key';
const sb = window.supabase.createClient(SB_URL, SB_KEY);
</script>
```

---

## 3. Authentication

### Login screen pattern

Gate the entire app behind a login screen. Show the app only after a valid session is confirmed.

```html
<!-- Login screen (shown by default) -->
<div id="login-screen">
  <input id="login-email" type="email" placeholder="Email">
  <input id="login-password" type="password" placeholder="Password">
  <button id="login-btn">Sign in</button>
  <div id="login-error"></div>
</div>

<!-- App (hidden until authenticated) -->
<div id="app" style="display:none">
  <!-- your app here -->
  <button id="btn-logout">Sign out</button>
</div>
```

```js
// On page load: check for existing session
sb.auth.onAuthStateChange((event, session) => {
  if (session) {
    showApp(session.user);
  } else {
    showLogin();
  }
});

function showApp(user) {
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('app').style.display = '';
  loadFromSupabase(); // load data now that we're authenticated
}

function showLogin() {
  document.getElementById('login-screen').style.display = '';
  document.getElementById('app').style.display = 'none';
}

// Sign in
document.getElementById('login-btn').addEventListener('click', async () => {
  const email = document.getElementById('login-email').value.trim();
  const pass  = document.getElementById('login-password').value;
  const { error } = await sb.auth.signInWithPassword({ email, password: pass });
  if (error) {
    document.getElementById('login-error').textContent = error.message;
  }
  // onAuthStateChange fires automatically on success
});

// Sign out
document.getElementById('btn-logout').addEventListener('click', async () => {
  await sb.auth.signOut();
  // onAuthStateChange fires automatically
});
```

### Creating users

Users are created in **Supabase Dashboard → Authentication → Users → Add user**. For a private internal tool, disable public signups: **Auth → Settings → Disable "Enable email signup"**.

---

## 4. Database schema and RLS

Run SQL in **Supabase Dashboard → SQL Editor**. Store migrations as numbered files in `migrations/` so you can track schema history.

```sql
-- migrations/001_initial_schema.sql

create table if not exists items (
  id          text primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  name        text not null,
  data        jsonb,
  created_at  timestamptz default now()
);

-- Row Level Security: only authenticated users can access their own rows
alter table items enable row level security;

create policy "auth_all" on items
  for all
  using (auth.uid() is not null)
  with check (auth.uid() is not null);
```

For a single-user or small team tool, `auth.uid() is not null` (any logged-in user) is sufficient. For multi-tenant, use `auth.uid() = user_id`.

---

## 5. Reading and writing data

```js
// Load all items
async function loadData() {
  const { data, error } = await sb.from('items').select('*').order('created_at');
  if (error) { console.error(error); return; }
  renderItems(data);
}

// Insert a new item
async function createItem(item) {
  const { error } = await sb.from('items').insert(item);
  if (error) console.error(error);
}

// Update an item
async function updateItem(id, changes) {
  const { error } = await sb.from('items').update(changes).eq('id', id);
  if (error) console.error(error);
}

// Delete an item
async function deleteItem(id) {
  const { error } = await sb.from('items').delete().eq('id', id);
  if (error) console.error(error);
}
```

### camelCase ↔ snake_case mapping

Supabase columns are snake_case; JS objects are camelCase. Map explicitly on load:

```js
const { data } = await sb.from('items').select('*');
const items = (data || []).map(row => ({
  id:        row.id,
  createdAt: row.created_at,
  userName:  row.user_name,
  // ...
}));
```

And reverse when writing:

```js
await sb.from('items').insert({
  id:         item.id,
  created_at: item.createdAt,
  user_name:  item.userName,
});
```

---

## 6. Real-time subscriptions

Receive live updates from other sessions without polling.

**Step 1** — enable replication for your tables (run once in SQL editor):
```sql
alter publication supabase_realtime add table items;
```

**Step 2** — subscribe in your app:
```js
let rtChannel = null;

function startRealtime() {
  rtChannel = sb.channel('db-changes')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'items' }, handleRemoteChange)
    .subscribe(status => {
      console.log('Realtime:', status); // SUBSCRIBED | CHANNEL_ERROR
    });
}

function handleRemoteChange(payload) {
  // payload.eventType = 'INSERT' | 'UPDATE' | 'DELETE'
  // payload.new = the new row, payload.old = {id} for deletes
  if (payload.eventType === 'INSERT') { /* add to local state */ }
  if (payload.eventType === 'UPDATE') { /* update local state */ }
  if (payload.eventType === 'DELETE') { /* remove from local state */ }
}
```

**Avoid self-loops** — ignore changes you triggered yourself:
```js
let _lastSyncAt = 0;

async function saveToDatabase(data) {
  _lastSyncAt = Date.now();
  await sb.from('items').upsert(data);
}

function handleRemoteChange(payload) {
  if (Date.now() - _lastSyncAt < 3000) return; // ignore own changes
  // ... apply remote change
}
```

---

## 7. Edge Functions (secret API proxy)

Use Edge Functions when you need to call a third-party API with a secret key from a static site. The function runs server-side on Supabase's infrastructure; the key never reaches the browser.

### File structure
```
supabase/
  functions/
    my-proxy/
      index.ts
```

### Example: proxy to an external API

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

  // Verify caller is a logged-in Supabase user
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return new Response("Unauthorized", { status: 401, headers: cors });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401, headers: cors });

  // Strip function path prefix, forward to real API
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

### Deploy

```bash
# Install Supabase CLI (macOS)
brew install supabase/tap/supabase-beta

# Authenticate (get token from supabase.com → Account → Access Tokens)
export SUPABASE_ACCESS_TOKEN=your_token

# Deploy
supabase functions deploy my-proxy --project-ref your-project-ref

# Set the secret (never commit this)
supabase secrets set MY_API_TOKEN=the_actual_secret --project-ref your-project-ref
```

### Call the function from the browser

```js
const PROXY_URL = 'https://your-project-ref.supabase.co/functions/v1/my-proxy';

async function proxyGet(endpoint, params = {}) {
  const qs  = new URLSearchParams(params).toString();
  const url = `${PROXY_URL}/${endpoint}${qs ? '?' + qs : ''}`;

  const { data: { session } } = await sb.auth.getSession();
  const headers = session ? { Authorization: `Bearer ${session.access_token}` } : {};

  const r = await fetch(url, { headers });
  if (!r.ok) throw new Error(`${endpoint}: ${r.status}`);
  return r.json();
}
```

---

## 8. Local dev workflow

```bash
# Serve index.html locally (no build step needed)
python3 -m http.server 8080
# Open http://localhost:8080

# Or with a custom proxy for local API calls
python3 server.py 8080
```

Both local and GitHub Pages share the **same Supabase database**. Schema changes need to be applied before pushing code that depends on them:

1. Write migration SQL → `migrations/00N_description.sql`
2. Run it in Supabase SQL Editor
3. Push code changes to `master`

---

## 9. Security checklist

- [ ] `anon` key is in source code — that's fine, it's public by design
- [ ] `service_role` key is never in source code or git history
- [ ] Third-party API keys are stored as Edge Function secrets, not in code
- [ ] RLS is enabled on every table
- [ ] Public signups are disabled if this is a private tool
- [ ] Repo is public only if you're OK with anyone seeing the code (data is protected by RLS + auth)

### If you accidentally commit a secret

```bash
# 1. Rotate/revoke the key immediately in the provider's dashboard

# 2. Scrub from git history
pip3 install git-filter-repo
git filter-repo --replace-text <(echo "exposed_secret==>REDACTED") --force

# 3. Re-add remote and force-push
git remote add origin https://github.com/user/repo.git
git push --force --all

# 4. Set the new secret in Supabase
supabase secrets set MY_API_TOKEN=new_secret --project-ref your-project-ref
```

---

## 10. Deployment checklist

- [ ] `SB_URL` and `SB_KEY` (anon) are set in `index.html`
- [ ] All tables have RLS enabled with appropriate policies
- [ ] `supabase_realtime` publication includes all real-time tables
- [ ] Edge Functions deployed and secrets set
- [ ] GitHub Pages enabled on the correct branch
- [ ] Tested login flow from the GitHub Pages URL (not just localhost)
