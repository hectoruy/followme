import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type TokenRole = 'driver' | 'viewer';

const defaultOrigins = [
  'https://project-jcd2n.vercel.app',
  'https://whereismydriver-hfreire111s-projects.vercel.app',
];

const allowedOrigins = new Set(
  (Deno.env.get('WMD_ALLOWED_ORIGINS') || defaultOrigins.join(','))
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
);

function corsHeaders(req: Request) {
  const origin = req.headers.get('origin');
  const fallback = defaultOrigins[0];
  return {
    'access-control-allow-origin':
      origin && allowedOrigins.has(origin) ? origin : fallback,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers':
      'authorization, x-client-info, apikey, content-type',
    vary: 'Origin',
  };
}

function json(req: Request, body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function base64Url(input: string | Uint8Array) {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

async function signJwt(payload: Record<string, unknown>, secret: string) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const encodedHeader = base64Url(JSON.stringify(header));
  const encodedPayload = base64Url(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(data),
  );
  return `${data}.${base64Url(new Uint8Array(signature))}`;
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

function roomNameFor(sessionId: string) {
  return `wmd-${sessionId.replaceAll('-', '')}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  if (req.method !== 'POST') {
    return json(req, { error: 'Method not allowed' }, 405);
  }

  const livekitUrl = Deno.env.get('LIVEKIT_URL') || '';
  const livekitApiKey = Deno.env.get('LIVEKIT_API_KEY') || '';
  const livekitApiSecret = Deno.env.get('LIVEKIT_API_SECRET') || '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

  if (!livekitUrl || !livekitApiKey || !livekitApiSecret) {
    return json(req, { error: 'LiveKit is not configured' }, 503);
  }
  if (!supabaseUrl || !serviceRoleKey) {
    return json(req, { error: 'Supabase service is not configured' }, 503);
  }

  let body: { sessionId?: unknown; role?: unknown; driverSecret?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(req, { error: 'Invalid JSON body' }, 400);
  }

  const sessionId = body.sessionId;
  const role = body.role as TokenRole;
  const driverSecret =
    typeof body.driverSecret === 'string' ? body.driverSecret : '';

  if (!isUuid(sessionId)) {
    return json(req, { error: 'Invalid session id' }, 400);
  }
  if (role !== 'driver' && role !== 'viewer') {
    return json(req, { error: 'Invalid role' }, 400);
  }
  if (role === 'driver' && driverSecret.length < 24) {
    return json(req, { error: 'Driver secret is required' }, 401);
  }

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: session, error: sessionError } = await db
    .from('location_sessions')
    .select('id, active, video_enabled')
    .eq('id', sessionId)
    .maybeSingle();

  if (sessionError) return json(req, { error: 'Session lookup failed' }, 500);
  if (!session || session.active !== true) {
    return json(req, { error: 'Session is not active' }, 404);
  }
  if (session.video_enabled !== true) {
    return json(req, { error: 'Live camera is not enabled' }, 403);
  }

  const roomName = roomNameFor(sessionId);

  if (role === 'driver') {
    const driverSecretHash = await sha256Hex(driverSecret);
    const { data: existing, error: existingError } = await db
      .from('live_stream_sessions')
      .select('session_id, room_name, driver_secret_hash')
      .eq('session_id', sessionId)
      .maybeSingle();

    if (existingError) return json(req, { error: 'Stream lookup failed' }, 500);
    if (existing && existing.driver_secret_hash !== driverSecretHash) {
      return json(req, { error: 'Invalid driver secret' }, 403);
    }
    if (!existing) {
      const { error: insertError } = await db
        .from('live_stream_sessions')
        .insert({
          session_id: sessionId,
          room_name: roomName,
          driver_secret_hash: driverSecretHash,
        });
      if (insertError) return json(req, { error: 'Stream setup failed' }, 500);
    }
  } else {
    const { data: stream, error: streamError } = await db
      .from('live_stream_sessions')
      .select('room_name')
      .eq('session_id', sessionId)
      .maybeSingle();

    if (streamError) return json(req, { error: 'Stream lookup failed' }, 500);
    if (!stream) return json(req, { error: 'Stream is not ready' }, 404);
  }

  const now = Math.floor(Date.now() / 1000);
  const identity = `${role}-${crypto.randomUUID()}`;
  const token = await signJwt(
    {
      iss: livekitApiKey,
      sub: identity,
      name: role === 'driver' ? 'Driver' : 'Viewer',
      nbf: now - 10,
      exp: now + 60 * 60,
      video: {
        room: roomName,
        roomJoin: true,
        canPublish: role === 'driver',
        canPublishData: false,
        canPublishSources: role === 'driver' ? ['camera'] : [],
        canSubscribe: role === 'viewer',
      },
    },
    livekitApiSecret,
  );

  return json(req, { url: livekitUrl, token, room: roomName });
});

