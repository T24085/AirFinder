import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import os from "node:os";

const port = Number(process.env.PORT || 4173);
const root = resolve(fileURLToPath(new URL(".", import.meta.url)));

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".ico": "image/x-icon"
};

function resolvePath(requestPath) {
  const decoded = decodeURIComponent(requestPath.split("?")[0]);
  const relative = decoded === "/" ? "/index.html" : decoded;
  const safePath = normalize(relative).replace(/^(\.\.(\/|\\|$))+/, "");
  return join(root, safePath);
}

function getLocalAddresses() {
  const networks = os.networkInterfaces();
  const addresses = [];

  for (const entries of Object.values(networks)) {
    for (const entry of entries || []) {
      if (entry.family !== "IPv4" || entry.internal) continue;
      addresses.push(entry.address);
    }
  }

  return [...new Set(addresses)];
}

const server = createServer(async (req, res) => {
  try {
    const filePath = resolvePath(req.url || "/");
    const ext = extname(filePath);
    const contentType = mimeTypes[ext] || "application/octet-stream";
    const data = await readFile(filePath);
    res.writeHead(200, { "Content-Type": contentType, "Cache-Control": "no-cache" });
    res.end(data);
  } catch {
    const fallback = join(root, "index.html");
    const data = await readFile(fallback);
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
    res.end(data);
  }
});

server.listen(port, "0.0.0.0", () => {
  console.log(`AirFinder web prototype running on http://localhost:${port}`);
  for (const address of getLocalAddresses()) {
    console.log(`LAN URL: http://${address}:${port}`);
  }
  console.log("If Tailscale is installed, run: tailscale serve --bg " + port);
});
