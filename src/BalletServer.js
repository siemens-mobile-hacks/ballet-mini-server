import { REQUEST_MANGLE_DICT, OPTIONS_MANGLE_DICT } from './data/mangle.js';
import { Obml } from './Obml.js';
import { Browser } from './Browser.js';

export class BalletServer {
	constructor() {
		
	}
	
	async handle(body) {
		let encType = (body[0] << 8) | body[1];
		if (encType == 0) { // unecrypted 3.x
			body = body.slice(2);
		} else if (encType == 1) { // encrypted 3.x
			console.error(`Secure protocol in 3.x not supported.`);
			return { status: 403, body: "" };
		}
		
		// Parse request
		let request = {};
		for (let pair of body.toString('utf-8').split(/\0/)) {
			let index = pair.indexOf('=');
			if (index >= 0) {
				let key = pair.substr(0, index);
				let value = pair.substr(index + 1);
				key = key in REQUEST_MANGLE_DICT ? REQUEST_MANGLE_DICT[key] : `unk_${key}`;
				request[key] = value;
			}
		}
		
		// Parse options
		request.options = {};
		if (request.optionsStr) {
			for (let pair of request.optionsStr.split(/;/)) {
				let index = pair.indexOf(':');
				if (index >= 0) {
					let key = pair.substr(0, index);
					let value = pair.substr(index + 1);
					key = key in OPTIONS_MANGLE_DICT ? OPTIONS_MANGLE_DICT[key] : `unk_${key}`;
					request.options[key] = value;
				}
			}
		}
		
		// Detect version
		request.browserVersion = this.detectBrowserVersion(request);
		
		// Parse request URL
		[request.part, request.url] = this.parseRequestUrl(request.rawUrl);
		
		// Normalize URL
		if (!request.url.match(/^([\w\d_-]+):/)) {
			if (request.url.startsWith('//')) {
				request.url = "http:" + request.url;
			} else {
				request.url = "http://" + request.url;
			}
		}
		
		console.log(`Request: ${request.url}`);
		
		let obml;
		if (['server:test', 'server:t0'].includes(request.url)) {
			request.compression = "none"; // reset compression
			obml = await this.handleConnectionTest(request);
		} else {
			obml = await this.handleRequest(request);
		}
		
		console.log(request);
		
		let binary = await obml.build(request.compression);
		return {
			status: 200,
			body: binary,
			headers: {
				'Content-Type':		'application/octet-stream',
				'Content-Length':	binary.length
			}
		};
	}
	
	async handleRequest(request) {
		try {
			let obml = new Obml(request.browserVersion);
			let browser = new Browser({
				language:	request.language,
				userAgent:	request.userAgent,
				width:		+request.options.width,
				height:		+request.options.height,
			});
			await browser.start();
			await browser.loadPage(obml, request.url);
			return obml;
		} catch (e) {
			return await this.showError(request, e.message);
		}
	}
	
	async handleConnectionTest(request) {
		let obml = new Obml(request.browserVersion);
		obml.setUrl(request.url);
		obml.style({bold: true, pad: 2})
			.plus()
			.text(request.url)
			.plus()
			.background(0xFFFFFF)
			.style()
			.text("OK")
			.end();
		return obml;
	}
	
	async showError(request, message) {
		let obml = new Obml(request.browserVersion);
		obml.setUrl(request.url);
		obml.setTitle('Request error');
		obml.style({bold: true, pad: 2})
			.plus()
			.text(obml.title)
			.plus()
			.background(0xf9e1d9)
			.style({color: 0xff6837})
			.text(`An error occurred while executing the request to: `)
			.link(request.url)
			.style({color: 0x0000FF})
			.text(request.url)
			.linkEnd()
			.hr(0xff6837)
			.style({color: 0xff6837})
			.text(message)
			.hr(0xff6837)
			.link(request.url)
			.style({color: 0x0000FF})
			.text(`Repeat request.`)
			.linkEnd()
			.end();
		return obml;
	}
	
	parseRequestUrl(url) {
		let m;
		if (url && (m = url.match(/^\/obml(?:\/(\d+))?\/(.*?)$/i)))
			return [m[1] ? +m[1] : 1, m[2]];
		console.error(`Unknown URI: ${url}`);
		return [1, 'about:blank'];
	}
	
	detectBrowserVersion(request) {
		let version = 1;
		if (request.browserType == 285 || request.browserType == 29) {
			version = 3;
		} else if (request.browserType == 280) {
			version = 2;
		}
		
		if (request.version) {
			let m = request.version.match(/^([^\/]+)\/(\d+)/);
			if (m && m[2] >= 0 && m[2] <= 3)
				version = +m[2];
		}
		
		// 0.x == 1.x
		return version < 1 ? 1 : version;
	}
}
