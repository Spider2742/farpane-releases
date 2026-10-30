// Serves the repo metadata from public/ and sends package and app downloads to their GitHub release.
const RELEASES = "https://github.com/Spider2742/farpane-releases/releases/download";
const PACKAGE = /^farpane[-_](\d+\.\d+\.\d+)(?:-[\w.]+)?\.(?:rpm|deb|apk|flatpak)$/;

export default {
  async fetch(request, env) {
    const file = new URL(request.url).pathname.split("/").pop();
    const match = file.match(PACKAGE);
    if (match) return Response.redirect(`${RELEASES}/v${match[1]}/${file}`, 302);
    return env.ASSETS.fetch(request);
  },
};
