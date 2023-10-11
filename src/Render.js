export function transformHtml() {
	const TOKEN = {
		CONTENT:	0, 
		SPACE:		1, 
		BR:			2, 
		BLOCK:		3,
	};
	
	let colors_cache = {};
	
	let canvas = document.createElement("canvas");
	let ctx = canvas.getContext("2d", { willReadFrequently: true });
	canvas.width = 1;
	canvas.height = 1;
	
	let current_bg;
	let current_style;
	let last_token = TOKEN.CONTENT;
	let tokens = [];
	let bgcolors_stack = [0xFFFFFF];
	let last_space_token;
	
	_walkNodes(document.body, 0);
	
	function _walkNodes(node, level) {
		//console.log(`${level} / ${node.tagName}`);
		
		if (node.nodeType == Node.TEXT_NODE) {
			let is_visible = isNodeVisible(node.parentNode);
			if (!is_visible)
				return;
			
			let text = node.textContent.replace(/\s+/g, ' ');
			let style = window.getComputedStyle(node.parentNode);
			
			if (last_token != TOKEN.CONTENT)
				text = text.replace(/^\s+/g, '');
			
			if (text.length > 0) {
				if (last_token == TOKEN.SPACE) // restore space
					last_space_token[1] += " ";
				
				if (text.match(/\s+$/)) {
					last_token = TOKEN.SPACE;
					text = text.replace(/\s+$/g, ''); // cut space
				} else {
					last_token = TOKEN.CONTENT;
				}
				
				let text_transform = style.textTransform.toLowerCase();
				if (text_transform == "uppercase") {
					text = text.toUpperCase();
				} else if (text_transform == "lowercase") {
					text = text.toLowerCase();
				} else if (text_transform == "capitalize") {
					text = text.substr(0, 1).toUpperCase() + text.substr(1);
				}
				
				tokens.push(["TEXT", text]);
				
				if (last_token == TOKEN.SPACE)
					last_space_token = tokens[tokens.length - 1];
			}
		} else if (node.nodeType == Node.ELEMENT_NODE) {
			let is_visible = isNodeVisible(node);
			let style = window.getComputedStyle(node);
			
			if (is_visible) {
				if (node.tagName == "BR") {
					last_token = TOKEN.BR;
					tokens.push(["BR"]);
					return;
				}
				
				if (isNodeHasStyle(node.tagName)) {
					let parent_bg = bgcolors_stack[bgcolors_stack.length - 1];
					let new_background = resolveColor(style.backgroundColor, parent_bg);
					let new_style = getStyle(style, new_background);
					
					if (!current_bg || current_bg != new_background) {
						current_bg = new_background;
						tokens.push(["BG", new_background]);
					}
					
					if (!current_style || isStyleChanged(current_style, new_style)) {
						current_style = new_style;
						tokens.push(["STYLE", new_style]);
					}
					
					console.log(`parent_bg=${parent_bg} style.backgroundColor=${style.backgroundColor} BG: ${new_background.toString(16)}, FG: ${new_style.color.toString(16)}`);
				}
				
				if (node.tagName == "IMG") {
					tokens.push(["IMG", {
						src: node.src,
						alt: node.alt,
						width: node.offsetWidth,
						height: node.offsetHeight
					}]);
				} else if (node.tagName == "A") {
					tokens.push(["LINK", { url: node.href }]);
				} else if (node.tagName == "FORM") {
					tokens.push(["FORM", {
						action: node.action,
						method: node.method,
					}]);
				}
			}
			
			bgcolors_stack.push(current_bg);
			for (let child of node.childNodes)
				_walkNodes(child, level + 1);
			bgcolors_stack.pop();
			
			if (is_visible) {
				if (node.tagName == "A") {
					tokens.push(["LINK_END"]);
				} else if (node.tagName == "FORM") {
					tokens.push(["FORM_END"]);
				}
				
				if (["block", "table", "table-caption"].includes(style.display)) {
					if (last_token != TOKEN.BLOCK && last_token != TOKEN.BR) {
						tokens.push(["BR"]);
						last_token = TOKEN.BLOCK;
					}
				} else {
					last_token = TOKEN.CONTENT;
				}
			}
		}
	}
	
	function isNodeVisible(node) {
		return node.offsetParent !== null || node.tagName == "BODY";
	}
	
	function intToColor(color) {
		return [(color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 1];
	}
	
	function colorToInt(color) {
		return (color[0] << 16) | (color[1] << 8) | color[2];
	}
	
	function resolveColor(color_str, bg) {
		let color = parseColor(color_str);
		if (color[3] < 1)
			return colorToInt(alphaBlend(intToColor(bg), color));
		return colorToInt(color);
	}
	
	function parseColor(color) {
		if ((color in colors_cache))
			return colors_cache[color];
		
		ctx.clearRect(0, 0, 1, 1);
		ctx.fillStyle = color;
		ctx.fillRect(0, 0, 1, 1);
		
		let [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
		colors_cache[color] = [r, g, b, a / 255];
		
		return colors_cache[color];
	}
	
	function isNodeHasStyle(tag) {
		return !["BR", "INPUT", "BUTTON", "TEXTAREA", "SELECT"].includes(tag);
	}
	
	function isStyleChanged(a, b) {
		for (let k in a) {
			if (a[k] !== b[k])
				return true;
		}
		return false;
	}
	
	function getStyle(style, bgcolor) {
		return {
			color:			resolveColor(style.color, bgcolor),
			monospace:		!!style.fontFamily.match(/monospace/i),
			bold:			style.fontWeight >= 700,
			italic:			["italic", "oblique"].includes(style.fontStyle),
			underline:		!!style.textDecorationLine.match(/underline/i),
			strike:			!!style.textDecorationLine.match(/line-through/i),
			align:			["left", "right", "center"].includes(style.textAlign) ? style.textAlign : "left",
		};
	}
	
	function alphaBlend(base, added) {
		let mix = [];
		mix[3] = 1 - (1 - added[3]) * (1 - base[3]); // alpha
		mix[0] = Math.round((added[0] * added[3] / mix[3]) + (base[0] * base[3] * (1 - added[3]) / mix[3])); // red
		mix[1] = Math.round((added[1] * added[3] / mix[3]) + (base[1] * base[3] * (1 - added[3]) / mix[3])); // green
		mix[2] = Math.round((added[2] * added[3] / mix[3]) + (base[2] * base[3] * (1 - added[3]) / mix[3])); // blue
		return mix;
	}
	
	return tokens;
}
