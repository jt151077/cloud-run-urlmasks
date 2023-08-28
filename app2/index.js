import http from 'http';

const port = parseInt(process.env.PORT) || 8080;

async function main() {
  const server = http.createServer(async function (req, res) {
    if (req.url == '/pri/runservice2') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.write(JSON.stringify({"message": "App2 served by nodejs app"}));
        res.end()
    }
  }).listen(port);
}
main().catch(console.error);