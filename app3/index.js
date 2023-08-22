import http from 'http';

const port = parseInt(process.env.PORT) || 8080;

async function main() {
  const server = http.createServer(async function (req, res) {
    if (req.url == '/runservice3') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.write(JSON.stringify({"message": "App3 served by nodejs app"}));
        res.end()
    }
  }).listen(port);
}
main().catch(console.error);