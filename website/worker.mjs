const CACHE = "public, max-age=0, must-revalidate";
const DOWNLOAD = "https://github.com/nomdelasociete/skilli/releases/latest/download/skil.li.dmg";
const APPCAST = "https://github.com/nomdelasociete/skilli/releases/latest/download/appcast.xml";

export default {
  fetch(request, env) {
    return route(request) ?? env.ASSETS.fetch(request);
  },
};

// Routes Caddy used to own. Null means the static site answers.
export function route(request) {
  const url = new URL(request.url);
  const { pathname } = url;
  if (pathname === "/health") {
    return new Response("ok", {
      status: 200,
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": CACHE,
      },
    });
  }
  if (pathname === "/download") return redirect(DOWNLOAD);
  if (pathname === "/appcast.xml") return redirect(APPCAST);
  if (pathname === "/website" || pathname.startsWith("/website/")) {
    const stripped = pathname.slice("/website".length);
    const next = stripped === "" || stripped === "/" ? "/" : stripped;
    // Join onto the origin. new URL("//host", base) would leave this host.
    const path = next.startsWith("/") ? next : `/${next}`;
    return redirect(url.origin + path + url.search, 301);
  }
  return null;
}

function redirect(location, status = 302) {
  return new Response(null, {
    status,
    headers: { location, "cache-control": CACHE },
  });
}
