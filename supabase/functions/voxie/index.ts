// Supabase Edge Function for the watchOS Voxie app.
// Deploy with `supabase functions deploy voxie --no-verify-jwt`.
// All privileged access stays here; never embed Supabase secret keys in watchOS.
import { createClient } from "npm:@supabase/supabase-js@2";

const projectURL = Deno.env.get("SUPABASE_URL")!;
const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => {
  try {
    const values = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return Object.values(values)[0] as string | undefined;
  } catch { return undefined; }
})();
if (!secret) throw new Error("Configure Supabase secret key for Edge Functions");

const db = createClient(projectURL, secret, { auth: { persistSession: false } });
const encoder = new TextEncoder();
const cors = { "content-type": "application/json", "cache-control": "no-store" };
const json = (status: number, value: unknown) => new Response(JSON.stringify(value), { status, headers: cors });
const fail = (status: number, message: string) => json(status, { error: message });

const randomHex = (bytes: number) => Array.from(crypto.getRandomValues(new Uint8Array(bytes)))
  .map((x) => x.toString(16).padStart(2, "0")).join("");

async function sha256(value: string) {
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(hash)).map(x => x.toString(16).padStart(2, "0")).join("");
}

async function userFrom(req: Request) {
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (token.length < 32 || token.length > 256) return null;
  const { data, error } = await db.from("voxie_users").select("*")
    .eq("token_hash", await sha256(token)).maybeSingle();
  return error ? null : data;
}

function decodeAudio(bytes: Uint8Array) {
  let result = "";
  for (let i = 0; i < bytes.length; i += 8192) {
    result += String.fromCharCode(...bytes.subarray(i, i + 8192));
  }
  return btoa(result);
}

async function bodyJSON(req: Request) {
  if (Number(req.headers.get("content-length") || 0) > 1024) return null;
  try { return await req.json(); } catch { return null; }
}

async function friendship(a: string, b: string) {
  const [user_a, user_b] = [a, b].sort();
  const { data } = await db.from("voxie_friends").select("user_a")
    .eq("user_a", user_a).eq("user_b", user_b).maybeSingle();
  return Boolean(data);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  const url = new URL(req.url);
  const start = url.pathname.indexOf("/v2/");
  const path = start >= 0 ? url.pathname.slice(start)
    : url.pathname.endsWith("/health") ? "/health" : url.pathname;
  if (path === "/health") return json(200, { ok: true });

  // A random private credential is minted on registration. It is never logged.
  if (req.method === "POST" && path === "/v2/register") {
    const input = await bodyJSON(req);
    const name = typeof input?.name === "string" ? input.name.trim() : "";
    if (name.length < 1 || name.length > 36) return fail(400, "invalid name");
    for (let attempt = 0; attempt < 5; attempt++) {
      const token = randomHex(32);
      const code = randomHex(4).toUpperCase();
      const { data, error } = await db.from("voxie_users")
        .insert({ token_hash: await sha256(token), invite_code: code, display_name: name })
        .select("id").single();
      if (!error && data) return json(201, { id: data.id, token, code });
      if (error?.code !== "23505") return fail(500, "registration failed");
    }
    return fail(503, "try again");
  }

  const me = await userFrom(req);
  if (!me) return fail(401, "unauthorized");

  if (req.method === "GET" && path === "/v2/state") {
    const { data: links, error: linkError } = await db.from("voxie_friends").select("user_a,user_b")
      .or(`user_a.eq.${me.id},user_b.eq.${me.id}`);
    if (linkError) return fail(500, "friends unavailable");
    const friendIDs = (links ?? []).map(x => x.user_a === me.id ? x.user_b : x.user_a);
    let friends: Array<{ id: string; name: string; available: boolean }> = [];
    if (friendIDs.length) {
      const { data, error } = await db.from("voxie_users")
        .select("id,display_name,available").in("id", friendIDs);
      if (error) return fail(500, "friends unavailable");
      friends = (data ?? []).map(x => ({ id: x.id, name: x.display_name, available: x.available }));
    }
    const { data: invites, error } = await db.from("voxie_invitations")
      .select("id,sender").eq("recipient", me.id).eq("status", "pending");
    if (error) return fail(500, "invitations unavailable");
    const senders = (invites ?? []).map(x => x.sender);
    let names = new Map<string, string>();
    if (senders.length) {
      const { data } = await db.from("voxie_users").select("id,display_name").in("id", senders);
      names = new Map((data ?? []).map(x => [x.id, x.display_name]));
    }
    return json(200, { id: me.id, code: me.invite_code, friends,
      invitations: (invites ?? []).map(x => ({ id: x.id, name: names.get(x.sender) || "Vriend" })) });
  }

  if (req.method === "POST" && path === "/v2/invite") {
    const input = await bodyJSON(req);
    const code = typeof input?.code === "string" ? input.code.trim().toUpperCase() : "";
    if (!/^[A-F0-9]{8}$/.test(code)) return fail(400, "invalid friend code");
    const { data: recipient } = await db.from("voxie_users")
      .select("id").eq("invite_code", code).maybeSingle();
    if (!recipient || recipient.id === me.id) return fail(404, "friend not found");
    if (await friendship(me.id, recipient.id)) return fail(409, "already friends");
    const { error } = await db.from("voxie_invitations").upsert(
      { sender: me.id, recipient: recipient.id, status: "pending" },
      { onConflict: "sender,recipient" });
    return error ? fail(500, "invite failed") : json(201, { ok: true });
  }

  const invitation = path.match(/^\/v2\/invitations\/(\d+)\/(accept|decline)$/);
  if (req.method === "POST" && invitation) {
    const { data: invite } = await db.from("voxie_invitations").select("*")
      .eq("id", Number(invitation[1])).eq("recipient", me.id).eq("status", "pending").maybeSingle();
    if (!invite) return fail(404, "invitation missing");
    const accepted = invitation[2] === "accept";
    const { error } = await db.from("voxie_invitations").update({ status: accepted ? "accepted" : "declined" })
      .eq("id", invite.id).eq("recipient", me.id).eq("status", "pending");
    if (error) return fail(500, "update failed");
    if (accepted) {
      const [user_a, user_b] = [invite.sender, invite.recipient].sort();
      const { error: friendError } = await db.from("voxie_friends").upsert({ user_a, user_b },
        { onConflict: "user_a,user_b" });
      if (friendError) return fail(500, "friendship failed");
    }
    return json(200, { ok: true });
  }

  if (req.method === "POST" && path === "/v2/presence") {
    const input = await bodyJSON(req);
    if (typeof input?.available !== "boolean") return fail(400, "invalid status");
    const { error } = await db.from("voxie_users").update({ available: input.available }).eq("id", me.id);
    return error ? fail(500, "update failed") : json(200, { ok: true });
  }

  if (req.method === "POST" && path === "/v2/device") {
    const input = await bodyJSON(req);
    if (!/^[0-9a-fA-F]{32,512}$/.test(input?.token ?? "")) return fail(400, "invalid APNs token");
    const { error } = await db.from("voxie_users").update({ apns_token: input.token }).eq("id", me.id);
    return error ? fail(500, "update failed") : json(200, { ok: true });
  }

  if (req.method === "GET" && path === "/v2/frames") {
    const after = Math.max(0, Number(url.searchParams.get("after") ?? "0"));
    if (!Number.isSafeInteger(after)) return fail(400, "invalid cursor");
    await db.from("voxie_users").update({ last_poll: new Date().toISOString() }).eq("id", me.id);
    const cutoff = new Date(Date.now() - 15_000).toISOString();
    const { data, error } = await db.from("voxie_audio_frames")
      .select("id,sender,pcm_base64").eq("recipient", me.id)
      .gt("id", after).gt("created_at", cutoff).order("id").limit(20);
    if (error) return fail(500, "audio fetch failed");
    return json(200, { frames: (data ?? []).map(x => ({ id: x.id, sender: x.sender, pcm: x.pcm_base64 })) });
  }

  const frame = path.match(/^\/v2\/frames\/([a-f0-9-]{36})$/);
  if (req.method === "POST" && frame) {
    if (req.headers.get("content-type") !== "application/octet-stream") return fail(415, "expected PCM16");
    const targetID = frame[1];
    if (!await friendship(me.id, targetID) || !me.available) return fail(403, "not available");
    const { data: target } = await db.from("voxie_users").select("available")
      .eq("id", targetID).maybeSingle();
    if (!target?.available) return fail(403, "friend unavailable");
    const pcm = new Uint8Array(await req.arrayBuffer());
    if (pcm.length < 2 || pcm.length > 32768 || pcm.length % 2) return fail(413, "invalid audio frame");
    const { error } = await db.from("voxie_audio_frames")
      .insert({ sender: me.id, recipient: targetID, pcm_base64: decodeAudio(pcm) });
    return error ? fail(500, "audio upload failed") : json(201, { ok: true });
  }
  return fail(404, "unknown path");
});
