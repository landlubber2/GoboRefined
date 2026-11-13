// Tiny static file server for the lab VM (guest reaches it at http://10.0.2.2:8766/).
// Serves vm/serve/ and installer/. Usage: node vm/serve.js
const http = require('http'), fs = require('fs'), path = require('path');
const roots = [path.join(__dirname, 'serve'), path.join(__dirname, '..', 'installer')];
http.createServer((req, res) => {
  const name = path.basename(decodeURIComponent(req.url.split('?')[0]));
  for (const r of roots) {
    const f = path.join(r, name);
    if (name && fs.existsSync(f) && fs.statSync(f).isFile()) {
      const binary = /\.(tgz|gz|png|iso|img)$/.test(name);
      // Text files: strip CR so scripts edited on Windows run cleanly in the guest.
      const body = binary ? fs.readFileSync(f)
        : Buffer.from(fs.readFileSync(f, 'latin1').replace(/\r\n/g, '\n'), 'latin1');
      res.writeHead(200, { 'Content-Type': binary ? 'application/octet-stream' : 'text/plain' });
      return res.end(body);
    }
  }
  res.writeHead(404); res.end('not found\n');
}).listen(8766, '127.0.0.1', () => console.log('serving on 127.0.0.1:8766'));
