all: tromp.js

tromp.js: tromp.coffee
	coffee -bc tromp.coffee

testDemo:
	node test/demo.js

test: tromp.js testDemo

