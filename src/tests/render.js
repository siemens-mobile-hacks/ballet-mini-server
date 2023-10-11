import { Browser } from '../Browser.js';
import { Obml } from '../Obml.js';

let test_url = 'https://sasisa.org/';

let obml = new Obml(2, test_url);

let browser = new Browser();
await browser.start();
await browser.loadPage(obml, test_url);
