all: build test
build: tromp

tromp: tromp.coffee funcQueues.coffee 
	./node_modules/.bin/coffee -bc *.coffee

test: tromp
	node test/demo.js

clean:
	rm *.js
