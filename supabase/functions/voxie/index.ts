// Supabase Edge Function for the watchOS Voxie app.
// Deploy with `supabase functions deploy voxie --no-verify-jwt`.
// All privileged access stays here; never embed Supabase secret keys in watchOS.
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5";

const projectURL = Deno.env.get("SUPABASE_URL")!;
const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => {
  try {
    const values = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return Object.values(values)[0] as string | undefined;
  } catch { return undefined; }
})();
if (!secret) throw new Error("Configure Supabase secret key for Edge Functions");

const db = createClient(projectURL, secret, { auth: { persistSession: false } });
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const appleAudiences = ["nl.lrvdlinden.Voxie", "nl.lrvdlinden.Voxie.watchkitapp"];
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
  const hash = await sha256(token);
  const { data: session } = await db.from("voxie_sessions").select("user_id")
    .eq("token_hash", hash).gt("expires_at", new Date().toISOString()).maybeSingle();
  if (!session) return null;
  const { data } = await db.from("voxie_users").select("*")
    .eq("id", session.user_id).maybeSingle();
  return data;
}

function decodeAudio(bytes: Uint8Array) {
  let result = "";
  for (let i = 0; i < bytes.length; i += 8192) {
    result += String.fromCharCode(...bytes.subarray(i, i + 8192));
  }
  return btoa(result);
}

async function bodyJSON(req: Request, maxBytes = 1024) {
  if (Number(req.headers.get("content-length") || 0) > maxBytes) return null;
  try {
    const body = await req.text();
    if (encoder.encode(body).length > maxBytes) return null;
    return JSON.parse(body);
  } catch { return null; }
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
  // Supabase forwards paths as /voxie/v3/... (or /functions/v1/voxie/v3/...).
  // Normalize both API versions to the routes used below.
  const match = url.pathname.match(/\/(v[23]\/[^?#]*)$/);
  const path = match ? `/${match[1]}`
    : url.pathname.endsWith("/health") ? "/health" : url.pathname;
  if (path === "/health") return json(200, { ok: true });

  // Client nonce is never trusted on its own: it must match a server-issued,
  // single-use challenge and the signed nonce claim in Apple's identity token.
  if (req.method === "POST" && path === "/v3/nonce") {
    const nonce = randomHex(32);
    const { error } = await db.from("voxie_login_challenges")
      .insert({ nonce_hash: await sha256(nonce) });
    return error ? fail(503, "login unavailable") : json(200, { nonce });
  }

  if (req.method === "POST" && path === "/v3/apple") {
    const input = await bodyJSON(req, 12000);
    if (typeof input?.identityToken !== "string" || input.identityToken.length > 8000 ||
        typeof input?.nonce !== "string" || !/^[a-f0-9]{64}$/.test(input.nonce)) {
      return fail(400, "invalid login request");
    }
    try {
      const { payload } = await jwtVerify(input.identityToken, appleKeys, {
        issuer: "https://appleid.apple.com", audience: appleAudiences,
        algorithms: ["RS256"], clockTolerance: "5s"
      });
      if (typeof payload.sub !== "string" || payload.nonce !== await sha256(input.nonce))
        return fail(401, "Apple identity mismatch");
      // Atomic one-time consumption prevents replay of an intercepted login.
      const { data: consumed, error: challengeError } = await db
        .from("voxie_login_challenges").delete()
        .eq("nonce_hash", await sha256(input.nonce))
        .gt("expires_at", new Date().toISOString()).select("nonce_hash");
      if (challengeError || !consumed?.length) return fail(401, "login expired");

      let { data: user } = await db.from("voxie_users").select("*")
        .eq("apple_subject", payload.sub).maybeSingle();
      if (!user) {
        for (let i = 0; i < 5; i++) {
          const code = randomHex(4).toUpperCase();
          const legacyHash = await sha256(randomHex(32));
          const { data, error } = await db.from("voxie_users")
            .insert({ apple_subject: payload.sub, display_name: "Voxie-gebruiker",
              invite_code: code, token_hash: legacyHash })
            .select("*").single();
          if (!error && data) { user = data; break; }
          if (error?.code !== "23505") return fail(500, "account creation failed");
          const { data: existing } = await db.from("voxie_users")
            .select("*").eq("apple_subject", payload.sub).maybeSingle();
          if (existing) { user = existing; break; }
        }
      }
      if (!user) return fail(503, "account unavailable");
      const token = randomHex(32);
      const { error: sessionError } = await db.from("voxie_sessions")
        .insert({ token_hash: await sha256(token), user_id: user.id });
      return sessionError ? fail(500, "session failed") :
        json(200, { id: user.id, token, code: user.invite_code,
          username: user.username, avatar: user.avatar_base64,
          deliveryTarget: user.delivery_target ?? "both" });
    } catch { return fail(401, "Apple sign-in failed"); }
  }

  // Retire unauthenticated legacy registration. Only verified Apple sign-in may
  // mint sessions. Old builds must upgrade.
  if (req.method === "POST" && path === "/v2/register") {
    return fail(410, "upgrade required");
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

  // The authenticated iPhone grants its paired Watch a separate revocable session.
  // The Watch never invokes Sign in with Apple itself.
  if (req.method === "POST" && path === "/v3/watch-session") {
    if (!me.username) return fail(409, "complete setup on iPhone first");
    const token = randomHex(32);
    const { error } = await db.from("voxie_sessions")
      .insert({ token_hash: await sha256(token), user_id: me.id });
    return error ? fail(503, "watch pairing unavailable") : json(200, { token });
  }

  // Explicit account deletion only. iOS does not notify servers on uninstall.
  // Foreign keys cascade invitations, friendships, sessions and audio frames.
  if (req.method === "DELETE" && path === "/v3/account") {
    const { data, error } = await db.from("voxie_users").delete()
      .eq("id", me.id).select("id");
    if (error || data?.length !== 1) return fail(500, "account deletion failed");
    return json(200, { ok: true });
  }

  if (req.method === "POST" && path === "/v3/profile") {
    const input = await bodyJSON(req, 150000);
    if (!input || typeof input !== "object") return fail(400, "invalid profile");
    const change: Record<string, string | null> = {};
    if ("username" in input) {
      const username = typeof input.username === "string" ? input.username.trim().toLowerCase() : "";
      if (!/^[a-z0-9_]{3,20}$/.test(username)) return fail(400, "username must be 3-20 letters, numbers or underscores");
      change.username = username;
      change.display_name = username;
    }
    if ("avatar" in input) {
      const avatar = input.avatar;
      if (avatar !== null && (typeof avatar !== "string" || avatar.length > 110000 ||
          !/^[a-zA-Z0-9+/]*={0,2}$/.test(avatar))) return fail(400, "invalid avatar");
      change.avatar_base64 = avatar;
    }
    if ("deliveryTarget" in input) {
      if (!["watch", "phone", "both"].includes(input.deliveryTarget))
        return fail(400, "invalid delivery target");
      change.delivery_target = input.deliveryTarget;
    }
    if (!Object.keys(change).length) return fail(400, "empty profile");
    const { data, error } = await db.from("voxie_users").update(change).eq("id", me.id)
      .select("username,avatar_base64,delivery_target").single();
    if (error?.code === "23505") return fail(409, "username taken");
    if (error || !data) return fail(500, "profile update failed");
    return json(200, { ok: true, username: data.username, avatar: data.avatar_base64,
      deliveryTarget: data.delivery_target });
  }

  if (req.method === "POST" && path === "/v3/invite") {
    const input = await bodyJSON(req);
    const username = typeof input?.username === "string" ? input.username.trim().toLowerCase().replace(/^@/, "") : "";
    if (!/^[a-z0-9_]{3,20}$/.test(username)) return fail(400, "invalid username");
    const { data: recipient } = await db.from("voxie_users").select("id")
      .eq("username", username).maybeSingle();
    if (!recipient || recipient.id === me.id) return fail(404, "user not found");
    if (await friendship(me.id, recipient.id)) return fail(409, "already friends");
    const { error } = await db.from("voxie_invitations").upsert(
      { sender: me.id, recipient: recipient.id, status: "pending" },
      { onConflict: "sender,recipient" });
    return error ? fail(500, "invite failed") : json(201, { ok: true });
  }

  const removeFriend = path.match(/^\/v3\/friends\/([a-f0-9-]{36})\/remove$/);
  if (req.method === "POST" && removeFriend) {
    const other = removeFriend[1];
    const [user_a, user_b] = [me.id, other].sort();
    const { error } = await db.from("voxie_friends").delete()
      .eq("user_a", user_a).eq("user_b", user_b);
    if (error) return fail(500, "remove failed");
    await db.from("voxie_invitations").delete()
      .or(`and(sender.eq.${me.id},recipient.eq.${other}),and(sender.eq.${other},recipient.eq.${me.id})`);
    return json(200, { ok: true });
  }

  if (req.method === "GET" && path === "/v2/state") {
    const { data: links, error: linkError } = await db.from("voxie_friends").select("user_a,user_b")
      .or(`user_a.eq.${me.id},user_b.eq.${me.id}`);
    if (linkError) return fail(500, "friends unavailable");
    const friendIDs = (links ?? []).map(x => x.user_a === me.id ? x.user_b : x.user_a);
    let friends: Array<{ id: string; name: string; available: boolean }> = [];
    if (friendIDs.length) {
      const { data, error } = await db.from("voxie_users")
        .select("id,display_name,username,avatar_base64,available").in("id", friendIDs);
      if (error) return fail(500, "friends unavailable");
      friends = (data ?? []).map(x => ({ id: x.id, name: x.username ?? x.display_name,
        username: x.username, avatar: x.avatar_base64, available: x.available }));
    }
    const { data: invites, error } = await db.from("voxie_invitations")
      .select("id,sender").eq("recipient", me.id).eq("status", "pending");
    if (error) return fail(500, "invitations unavailable");
    const senders = (invites ?? []).map(x => x.sender);
    let names = new Map<string, string>();
    if (senders.length) {
      const { data } = await db.from("voxie_users").select("id,display_name,username").in("id", senders);
      names = new Map((data ?? []).map(x => [x.id, x.username ?? x.display_name]));
    }
    const { data: outgoingInvites } = await db.from("voxie_invitations")
      .select("recipient").eq("sender", me.id).eq("status", "pending");
    const pendingIDs = (outgoingInvites ?? []).map(x => x.recipient);
    let pending: Array<{ id: string; name: string }> = [];
    if (pendingIDs.length) {
      const { data } = await db.from("voxie_users")
        .select("id,display_name,username").in("id", pendingIDs);
      pending = (data ?? []).map(x => ({ id: x.id, name: x.username ?? x.display_name }));
    }
    return json(200, { id: me.id, code: me.invite_code, username: me.username,
      avatar: me.avatar_base64, deliveryTarget: me.delivery_target ?? "both", friends, pending,
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
    const device = url.searchParams.get("device");
    if (device && device !== "watch" && device !== "phone") return fail(400, "invalid device");
    if (device && me.delivery_target && me.delivery_target !== "both" && me.delivery_target !== device)
      return json(200, { frames: [] });
    const after = Math.max(0, Number(url.searchParams.get("after") ?? "0"));
    if (!Number.isSafeInteger(after)) return fail(400, "invalid cursor");
    await db.from("voxie_users").update({ last_poll: new Date().toISOString() }).eq("id", me.id);
    const cutoff = new Date(Date.now() - 15_000).toISOString();
    // Opportunistically purge stale frames (including previous app versions).
    await db.from("voxie_audio_frames").delete().lt("created_at", cutoff);
    const { data, error } = await db.from("voxie_audio_frames")
      .select("id,sender,pcm_base64").eq("recipient", me.id)
      .gt("id", after).gt("created_at", cutoff).order("id").limit(20);
    if (error) return fail(500, "audio fetch failed");
    return json(200, { frames: (data ?? []).map(x => ({ id: x.id, sender: x.sender, pcm: x.pcm_base64 })) });
  }

  if (req.method === "POST" && path === "/v2/frames/ack") {
    const input = await bodyJSON(req, 2048);
    const ids: unknown = input?.ids;
    const device = input?.device;
    if (!Array.isArray(ids) || ids.length < 1 || ids.length > 50 ||
        !ids.every((id: unknown) => Number.isSafeInteger(id) && Number(id) > 0) ||
        (device !== "phone" && device !== "watch"))
      return fail(400, "invalid playback acknowledgement");
    const key = device === "watch" ? "played_watch" : "played_phone";
    const { error } = await db.from("voxie_audio_frames")
      .update({ [key]: true }).eq("recipient", me.id).in("id", ids);
    if (error) return fail(500, "acknowledgement failed");
    let removal = db.from("voxie_audio_frames").delete()
      .eq("recipient", me.id).in("id", ids);
    if (me.delivery_target === "both") {
      removal = removal.eq("played_watch", true).eq("played_phone", true);
    } else {
      removal = removal.eq(key, true);
    }
    const { error: deleteError } = await removal;
    if (deleteError) return fail(500, "frame deletion failed");
    return json(200, { ok: true });
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
