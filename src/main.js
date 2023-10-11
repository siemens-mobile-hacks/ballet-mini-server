import express from 'express';
import bodyParser from 'body-parser';
import { BalletServer } from './BalletServer.js';

const SERVER_PORT = 9123;

let app = express();
let balletServer = new BalletServer();

app.use(bodyParser.raw({
	inflate: true,
	limit: '10mb',
	type: 'application/xml'
}));

app.post('/*', async (req, res) => {
	console.log(`${req.method}`, req.url);
	
	let response = await balletServer.handle(req.body);
	if ('headers' in response) {
		for (let k in response.headers)
			res.set(k, response.headers[k]);
	}
	
	if ('status' in response)
		res.status(response.status);
	
	if ('body' in response)
		res.send(response.body);
}).all('/*', (req, res) => {
	console.log(`${req.method}`, req.url);
});

app.listen(SERVER_PORT, () => {
	console.log(`Example app listening on port ${SERVER_PORT}`)
});
