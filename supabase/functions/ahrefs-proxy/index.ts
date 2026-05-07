import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AHREFS_TOKEN = Deno.env.get("AHREFS_TOKEN") ?? "";
const AHREFS_BASE = "https://api.ahrefs.com/v3";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors, status: 200 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error } = await sb.auth.getUser();
  if (error || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const match = url.pathname.match(/\/ahrefs-proxy\/(.*)/);
  const path = match ? match[1] : "";
  const targetUrl = `${AHREFS_BASE}/${path}${url.search}`;

  const body = req.method !== "GET" ? await req.arrayBuffer() : undefined;
  const resp = await fetch(targetUrl, {
    method: req.method,
    headers: {
      Authorization: `Bearer ${AHREFS_TOKEN}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body,
  });

  const data = await resp.arrayBuffer();
  return new Response(data, {
    status: resp.status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
