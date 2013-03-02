all: build test
build: tromp

tromp: tromp.coffee funcQueues.coffee 
	coffee -bc *.coffee

test: tromp
	node test/demo.js

clean:
	rm *.js
