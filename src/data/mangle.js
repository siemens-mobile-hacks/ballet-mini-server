export const OPTIONS_MANGLE_DICT = {
	w:	"width", 
	h:	"height", 
	c:	"colors", 
	m:	"maxPageSize", 
	i:	"images", 
	q:	"imagesQuality"
};

export const REQUEST_MANGLE_DICT = {
	k:			"imageType",
	o:			"browserType", // 280 - 2.x, 285 - 3.x
	'x-o':		"browserType", // 13 - 1.x
	
	u:			"rawUrl",
	'x-u':		"rawUrl", // 1.x
	
	q:			"language",
	'x-l':		"language", // 1.x
	
	v:			"version",
	'x-v':		"version", // 1.x
	
	i:			"userAgent",
	'x-ua':		"userAgent", // 1.x
	
	A:			"cldc",
	'x-m-c':	"cldc", // 1.x
	
	B:			"midp",
	'x-m-ps':	"midp", // 1.x
	
	C:			"phone",
	'x-m-pm':	"phone", // 1.x
	
	D:			"deviceLanguage",
	'x-m-l':	"deviceLanguage", // 1.x
	
	E:			"encoding",
	'x-m-e':	"encoding", // 1.x
	
	d:			"optionsStr",
	'x-dp':		"optionsStr", // 1.x
	
	b:			"build",
	'x-b':		"build", // 1.x
	
	y:			"country",
	'x-co':		"country", // 1.x
	
	h:			"authPrefix",
	c:			"authCode",
	'x-h':		"authPrefix", // 1.x
	'x-c':		"authCode", // 1.x
	
	f:			"referer",
	'x-rr':		"referer", // 1.x
	
	e:			"compression",
	'x-e':		"compression", // 1.x
	
	j:			"post",
	'x-var':	"post", // 1.x
	
	t:			"showPhoneAsLinks",
	w:			"parts",
	'x-sn':		"parts", // 1.x
	
	G:			"defaultSearch"
};
