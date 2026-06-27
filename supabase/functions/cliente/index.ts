const allowedOrigins = new Set(
  (Deno.env.get('ALLOWED_ORIGINS') ||
    'https://whereismc.netlify.app,https://hoczdolplvaiupcqlmgv.functions.supabase.co')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
);

function corsHeaders(req: Request) {
  const origin = req.headers.get('origin');
  const allowedOrigin =
    origin && allowedOrigins.has(origin)
      ? origin
      : 'https://hoczdolplvaiupcqlmgv.functions.supabase.co';

  return {
    'access-control-allow-origin': allowedOrigin,
    'access-control-allow-methods': 'GET, OPTIONS',
    'access-control-allow-headers':
      'authorization, x-client-info, apikey, content-type',
    vary: 'Origin',
  };
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req);

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers });
  }

  const html = await Deno.readTextFile(new URL('./cliente.html', import.meta.url));
  const config = {
    SUPABASE_URL: Deno.env.get('WMD_SUPABASE_URL') || '',
    SUPABASE_ANON_KEY: Deno.env.get('WMD_SUPABASE_ANON_KEY') || '',
  };

  const body = html.replace(
    '</head>',
    `<script>window.WMD_CONFIG=${JSON.stringify(config)};</script>\n</head>`,
  );

  return new Response(body, {
    headers: {
      ...headers,
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
});
