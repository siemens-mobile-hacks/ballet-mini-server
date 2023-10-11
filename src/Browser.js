import puppeteer from 'puppeteer-core';
import { transformHtml } from './Render.js';
import sharp from 'sharp';

export class Browser {
	constructor(options) {
		this.options = {
			userAgent:	'Opera/9.80 (J2ME/MIDP; Opera Mini/4.2.22228/191.310; U; fi) Presto/2.12.423 Version/12.16',
			width:		240,
			height:		320,
			...options
		};
		this.resources = {};
		this.image2ref = {};
	}
	
	async start() {
		this.browser = await puppeteer.launch({
			headless: true,
			executablePath: '/opt/google/chrome/google-chrome',
			userDataDir: '.chrome'
		});
		this.page = await this.browser.newPage();
		await this.page.setCacheEnabled(true);
		await this.page.setUserAgent(this.options.userAgent);
		await this.page.setViewport({
			width:		this.options.width,
			height:		this.options.height,
			hasTouch:	false,
			isMobile:	true,
		});
		await this.page.setJavaScriptEnabled(false);
		
		this.page.on('response', async (response) => {
			if (Math.floor(response.status() / 100) != 2)
				return;
			
			try {
				this.resources[response.url()] = await response.buffer();
			} catch (e) { }
		});
		
		this.page.on('console', msg => console.log('CONSOLE:', msg.text()));
	}
	
	async loadPage(obml, url) {
		console.log(`Load page: ${url}`);
		
		this.resources = {};
		this.image2ref = {};
		
		await this.page.goto(url, { waitUntil: 'networkidle0' });
		
		await this.page.screenshot({
			path: '/tmp/screenshot.png'
		});
		
		let title = await this.page.evaluate(() => document.title);
		let location = await this.page.evaluate(() => location.href);
		let tokens = await this.page.evaluate(transformHtml);
		
		obml.setUrl(location);
		obml.setTitle(title);
		
		await this.convertToObml(obml, tokens);
		await this.browser.close();
	}
	
	async convertToObml(obml, tokens) {
		obml.style({bold: true, pad: 2})
			.plus()
			.text(obml.title || obml.url)
			.plus();
		
		let current_bg = 0xFFFFFF;
		
		for (let [tok, value] of tokens) {
			switch (tok) {
				case "BG":
					current_bg = value;
					obml.background(value);
				break;
				
				case "STYLE":
					obml.style(value);
				break;
				
				case "BR":
					obml.br();
				break;
				
				case "IMG":
					let width = value.width;
					let height = value.height;
					
					if (width > this.options.width) {
						height = Math.round(height / width * this.options.width);
						width = this.options.width;
					}
					
					let cache_key_png = `${value.src}-${width}-${height}`;
					let cache_key_jpg = `${value.src}-${width}-${height}-${current_bg}`;
					
					if (width > 0 && height > 0) {
						if ((cache_key_png in this.image2ref)) {
							obml.imageRef(width, height, this.image2ref[cache_key_png]);
						} else if ((cache_key_jpg in this.image2ref)) {
							obml.imageRef(width, height, this.image2ref[cache_key_jpg]);
						} else if ((value.src in this.resources)) {
							let buffer = this.resources[value.src];
							let new_type, new_buffer;
							try {
								[new_type, new_buffer] = await this.processImage(await buffer, width, height, current_bg);
							} catch (e) {
								console.error(`[processImage] src: ${value.src}, error: `, e);
							}
							if (!new_buffer) {
								obml.placeholder(width, height);
							} else if (new_buffer.length <= 0xFFFF) {
								let ref_id = obml.image(width, height, new_buffer);
								if (new_type == 'png') {
									this.image2ref[cache_key_png] = ref_id;
								} else {
									this.image2ref[cache_key_jpg] = ref_id;
								}
							} else {
								console.error(`Image is too big: ${value.src} (${new_buffer.lenth / 1024} Kb)`);
								obml.placeholder(width, height);
							}
						} else {
							obml.placeholder(width, height);
						}
					}
				break;
				
				case "TEXT":
					if (value.length > 0)
						obml.text(value);
				break;
				
				case "LINK":
					obml.link(value.url);
				break;
				
				case "LINK_END":
					obml.linkEnd();
				break;
			}
		}
		
		obml.end();
	}
	
	async processImage(buffer, width, height, bg) {
		let img = sharp(buffer);
		let meta = await img.metadata();
		
		if (meta.width != width || meta.height != height)
			await img.resize({ width, height });
		
		if ((meta.format == 'png') && meta.size < 30000)
			return ['png', await img.png({ quality: 85, palette: true }).toBuffer()];
		
		await img.flatten({ background: '#' + bg.toString(16).padStart(6, '0') });
		return ['jpg', await img.jpeg({ quality: 85 }).toBuffer()];
	}
}
