// Local unauthenticated proxy shim: accepts Chrome requests on 127.0.0.1
// and re-issues them to the egress proxy from the env, adding its credentials.
// Credentials are read from the environment at runtime only.
import http from 'node:http';
import net from 'node:net';
import { URL } from 'node:url';

const raw = process.env.https_proxy || process.env.HTTPS_PROXY || process.env.http_proxy;
if (!raw) { console.error('no proxy env'); process.exit(1); }
const upstream = new URL(raw);
const auth = 'Basic ' + Buffer.from(
  `${decodeURIComponent(upstream.username)}:${decodeURIComponent(upstream.password)}`
).toString('base64');
const upHost = upstream.hostname;
const upPort = Number(upstream.port || 3128);
const PORT = 18080;

const server = http.createServer((req, res) => {
  let targetHost = req.headers.host;
  try { targetHost = new URL(req.url).host; } catch {}
  const headers = { ...req.headers, 'proxy-authorization': auth, host: targetHost };
  delete headers['proxy-connection'];
  const up = http.request(
    { host: upHost, port: upPort, method: req.method, path: req.url, headers },
    (upRes) => { res.writeHead(upRes.statusCode || 502, upRes.headers); upRes.pipe(res); }
  );
  up.on('error', () => { try { res.writeHead(502); res.end('proxy error'); } catch {} });
  req.pipe(up);
});

server.on('connect', (req, clientSocket, head) => {
  const up = net.connect(upPort, upHost, () => {
    up.write(
      `CONNECT ${req.url} HTTP/1.1\r\nHost: ${req.url}\r\n` +
      `Proxy-Authorization: ${auth}\r\nProxy-Connection: keep-alive\r\n\r\n`
    );
  });
  let buf = Buffer.alloc(0);
  const onData = (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    const idx = buf.indexOf('\r\n\r\n');
    if (idx === -1) return;
    up.removeListener('data', onData);
    const firstLine = buf.slice(0, idx).toString('latin1').split('\r\n')[0];
    const rest = buf.slice(idx + 4);
    if (/ 200/.test(firstLine)) {
      clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (rest.length) clientSocket.write(rest);
      if (head && head.length) up.write(head);
      up.pipe(clientSocket);
      clientSocket.pipe(up);
    } else {
      console.log('CONNECT refused:', req.url, firstLine);
      try { clientSocket.write('HTTP/1.1 502 Bad Gateway\r\n\r\n'); } catch {}
      clientSocket.end();
      up.end();
    }
  };
  up.on('data', onData);
  up.on('error', () => { try { clientSocket.end(); } catch {} });
  clientSocket.on('error', () => { try { up.end(); } catch {} });
});

server.listen(PORT, '127.0.0.1', () => console.log(`shim listening on 127.0.0.1:${PORT}`));
