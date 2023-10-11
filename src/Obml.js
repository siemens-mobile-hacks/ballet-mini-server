import zlib from 'zlib';
import util from 'util';
import { BinaryWriter } from './BinaryWriter.js';
import { OBML_TAGS } from './data/tags.js'

export class Obml {
	constructor(version) {
		this.version = version;
		this.images_cnt = 0;
		this.tags = [];
	}
	
	setUrl(url) {
		this.url = url;
	}
	
	setTitle(title) {
		this.title = title;
	}
	
	tag(tag, data, options = {}) {
        if (options.deduplicate && this.tags.length > 0) {
			for (let i = this.tags.length - 1; i >= 0 ; i--) {
				if (options.siblings && options.siblings.includes(this.tags[i].id))
					continue;
				if (this.tags[i].id == tag) {
					this.tags[i].data = data;
					return this;
				}
				break;
			}
		}
		
        this.tags.push({ id: tag, data });
        return this;
    }
    
    plus() {
		return this.tag("PLUS");
	}
	
	image(width, height, buffer) {
		this.tag("IMAGE", { width, height, buffer });
		return this.images_cnt++;
	}
	
	imageRef(width, height, index) {
		return this.tag("IMAGE_REF", { width, height, index });
	}
	
	alert(title, message) {
		return this.tag("ALERT", { title, message });
	}
	
	text(text) {
		return this.tag("TEXT", text);
	}
	
	phoneNumber(text) {
		return this.tag("PHONE_NUMBER", text);
	}
	
	link(text) {
		return this.tag("LINK_OPEN", text);
	}
	
	linkEnd() {
		return this.tag("LINK_CLOSE");
	}
	
	placeholder(width, height) {
		return this.tag("PLACEHOLDER", { width, height });
	}
	
	formPassword(name, value) {
		return this.tag("FORM_PASSWORD", { name, value });
	}
	
	formText(name, value, multiline) {
		return this.tag("FORM_TEXT", { name, value, multiline });
	}
	
	formCheckbox(name, value, checked) {
		return this.tag("FORM_CHECKBOX", { name, value, checked });
	}
	
	formRadio(name, value, checked) {
		return this.tag("FORM_RADIO", { name, value, checked });
	}
	
	formSelect(name, multiple, options) {
		this.formSelectOpen(name, multiple, options.length);
		for (const opt of options) {
			this.formSelectOption(opt.title, opt.value, opt.checked);
		}
		return this.formSelectClose();
	}
	
	formSelectOpen(name, multiple, count) {
		return this.tag("FORM_SELECT_OPEN", { name, multiple, count });
	}
	
	formSelectOption(title, value, checked) {
		return this.tag("FORM_OPTION", { title, value, checked });
	}
	
	formSelectClose() {
		return this.tag("FORM_SELECT_CLOSE");
	}
	
	formHidden(name, value) {
		return this.tag("FORM_HIDDEN", { name, value });
	}
	
	formReset(name, value) {
		return this.tag("FORM_RESET", { name, value });
	}
	
	formImage(name, value) {
		return this.tag("FORM_IMAGE", { name, value });
	}
	
	formButton(name, value) {
		return this.tag("FORM_BUTTON", { name, value });
	}
	
	formSubmitOnChange() {
		return this.tag("FORM_SUBMIT_FLAG");
	}
	
	formUpload(name) {
		return this.tag("FORM_UPLOAD", { name });
	}
	
	style(style) {
		style = style || {};
		style = {
			color: 0,
			monospace: false,
			bold: false,
			italic: false,
			underline: false,
			align: "left",
			pad: 2,
			...style,
		};
		
		return this.tag("STYLE", style, {
			deduplicate:	true,
			siblings:		["BACKGROUND"]
		});
	}
	
	background(color) {
		return this.tag("BACKGROUND", color, {
			deduplicate:	true,
			siblings:		["STYLE"]
		});
	}
	
	hr(color) {
		return this.tag("HR", color);
	}
	
	br() {
		return this.tag("BR");
	}
	
	end() {
		return this.tag("END");
	}
	
	paragraph() {
		return this.tag("PARAGRAPH");
	}
	
	authPrefix(value) {
		return this.tag("AUTH", { type: 0, value });
	}
	
	authCode(value) {
		return this.tag("AUTH", { type: 1, value });
	}
	
	optimize() {
		this.styles_cnt = 0;
		
		let styles = {};
		for (let tag of this.tags) {
			if (tag.id == "STYLE") {
				let key = JSON.stringify(tag.data);
				if ((key in styles)) {
					let ref = styles[key];
					tag.id = ref <= 0xFF ? "STYLE_REF" : "STYLE_REF2";
					tag.data = ref;
				} else {
					styles[key] = this.styles_cnt++;
				}
			}
		}
	}
	
	buildPage() {
		this.optimize();
		
		let obml = new BinaryWriter();
		
		let special_response = Buffer.alloc(0);
		if (this.url === "server:test") {
			// OM 1.x - 2.x network test ACK
			special_response = Buffer.from(this.url);
		} else if (this.url === "server:t0") {
			// OM 3.x network test ACK
			obml.writeUInt16(0x24);
			obml.write(Buffer.from([0x00, 0x00, 0x00, 0x20]));
			obml.write(Buffer.alloc(0x20, 0xFF));
			return obml.data();
		}
		
		// Header
		obml.writeUInt16(special_response.length);
		if (special_response.length > 0)
			obml.write(special_response);
		if (special_response.length < 16)
			obml.write(Buffer.alloc(16 - special_response.length));
		
		obml.writeUInt16(this.tags.length) // tags count
		obml.writeUInt16(1) // current part
		obml.writeUInt16(1) // parts count
		obml.writeUInt16(0) // unk2
		obml.writeUInt16(this.styles_cnt) // styles count
		obml.writeUInt16(0).writeUInt8(0); // unk3
		obml.writeUInt16(0xFFFF); // cacheable
		
		if (this.version >= 2) // unk4
			obml.writeUInt16(0);
		
		obml.writeUnicode('1/' + this.url); // page url
		
		for (let tag of this.tags) {
			this.serializeTag(obml, tag);
		}
		
		return obml.data();
	}
	
	async build(compression = "none") {
		const VERSION_MAGIC = {
			1:	0x0d, 
			2:	0x18, 
			3:	0x1a
		};
		
		const COMPRESSION_TYPES = {
			"none":			0x33, 
			"def":			0x32, 
			"gzip":			0x31
		};
		
		if (!(compression in COMPRESSION_TYPES))
			compression = "none";
		
		let page = this.buildPage();
		if (compression == "def") {
			page = await util.promisify(zlib.deflateRaw)(page);
		} else if (compression == "gzip") {
			page = await util.promisify(zlib.gzip)(page);
		}
		
		let packet = new BinaryWriter();
		packet.writeUInt8(VERSION_MAGIC[this.version]); // obml version
		packet.writeUInt8(COMPRESSION_TYPES[compression]); // compression type
		packet.writeUInt32(page.length + 6); // total length
		packet.write(page);
		return packet.data();
	}
	
	serializeTag(obml, tag) {
		const STYLES = {
			ITALIC:			1 << 0, 
			BOLD:			1 << 1, 
			UNDERLINE:		1 << 2, 
			STRIKE:			1 << 3, 
			ALIGN_CENTER:	1 << 4, 
			ALIGN_RIGHT:	1 << 5, 
			MONOSPACE:		1 << 6,
		};
		
		obml.writeChar(OBML_TAGS[tag.id]);
		
		switch (tag.id) {
			case "AUTH":
				obml.writeUInt8(tag.data.type);
				obml.writeUnicode(tag.data.value);
			break;
			
			case "FORM_PASSWORD":
			case "FORM_HIDDEN":
			case "FORM_IMAGE":
			case "FORM_BUTTON":
			case "FORM_RESET":
			case "FORM_HIDDEN":
				obml.writeUnicode(tag.data.name);
				obml.writeUnicode(tag.data.value);
			break;
			
			case "FORM_CHECKBOX":
			case "FORM_RADIO":
				obml.writeUnicode(tag.data.name);
				obml.writeUnicode(tag.data.value);
				obml.writeUInt8(tag.data.checked ? 1 : 0);
			break;
			
			case "FORM_TEXT":
				if (this.version > 1) {
					obml.writeUInt8(tag.data.multiline ? 1 : 0);
					obml.writeUnicode(tag.data.name);
					obml.writeUnicode(tag.data.value);
				} else {
					obml.writeUnicode(tag.data.name);
					obml.writeUnicode(tag.data.value);
				}
			break;
			
			case "FORM_UPLOAD":
				obml.writeUnicode(tag.data.name);
			break;
			
			case "FORM_SELECT_OPEN":
				obml.writeUnicode(tag.data.name);
				obml.writeUInt8(tag.data.multiline ? 1 : 0);
				obml.writeShort(tag.data.count);
			break;
			
			case "FORM_OPTION":
				obml.writeUnicode(tag.data.title);
				obml.writeUnicode(tag.data.value);
				obml.writeUInt8(tag.data.checked ? 1 : 0);
			break;
			
			case "ALERT":
				obml.writeUnicode(tag.data.title);
				obml.writeUnicode(tag.data.message);
			break;
			
			case "TEXT":
			case "PHONE_NUMBER":
			case "LINK_OPEN":
				obml.writeUnicode(tag.data);
			break;
			
			case "BACKGROUND":
			case "HR":
				if (this.version >= 3) {
					obml.writeUInt32(tag.data);
				} else {
					obml.writeUInt16(rgb24to565(tag.data));
				}
			break;
			
			case "IMAGE":
				obml.writeUInt16(tag.data.width); // w
				obml.writeUInt16(tag.data.height); // h
				obml.writeUInt16(tag.data.buffer.length); // len
				obml.writeUInt16(0); // pad
				obml.write(tag.data.buffer); // data
			break;
			
			case "IMAGE_REF":
				obml.writeUInt16(tag.data.width);
				obml.writeUInt16(tag.data.height);
				obml.writeUInt16(tag.data.index);
			break;
			
			case "PLACEHOLDER":
				obml.writeUInt16(tag.data.width);
				obml.writeUInt16(tag.data.height);
			break;
			
			case "STYLE_REF":
				obml.writeUInt8(tag.data);
			break;
			
			case "STYLE_REF2":
				obml.writeUInt16(tag.data);
			break;
			
			case "STYLE":
				let style = 0;
				
				if (tag.data.align === "center")
					style |= STYLES.ALIGN_CENTER;
				
				if (tag.data.align === "right")
					style |= STYLES.ALIGN_RIGHT;
				
				if (tag.data.bold)
					style |= STYLES.BOLD;
				
				if (tag.data.underline)
					style |= STYLES.UNDERLINE;
				
				if (tag.data.monospace)
					style |= STYLES.MONOSPACE;
				
				if (tag.data.italic)
					style |= STYLES.ITALIC;
				
				if (tag.data.strike)
					style |= STYLES.STRIKE;
				
				if (this.version >= 3) {
					obml.writeUInt8(style);
					obml.writeUInt32(tag.data.color);
					obml.writeUInt8(tag.data.pad);
				} else {
					obml.writeUInt8(style);
					obml.writeUInt16(rgb24to565(tag.data.color));
					obml.writeUInt8(tag.data.pad);
				}
			break;
		}
	}
}

function rgb24to565(color) {
	const red = (color >> 16) & 0xFF;
	const green = (color >> 8) & 0xFF;
	const blue = color & 0xFF;
	return ((red >> 3) | ((green & 0xFC) << 3) | ((blue & 0xF8) << 8));
}
