"run-websocket.st - run the tests of WebFetch-WebSocket-Tests, which the image has

	WEB_FETCH_SERVER=http://127.0.0.1:<port> pharo --headless X.image --no-default-preferences st --quit run-websocket.st

 The live tests need a running tests/wasm/lib/fetch-http.mjs of the VM, with the port of its second
 listener (which never answers),

	node tests/wasm/lib/fetch-http.mjs --hang-port

 whose URL is in the environment (WEB_FETCH_SERVER, and WEB_FETCH_HANG_PORT), or in the file
 websocket.lane of the working directory (its first two words, what the server prints), which a VM
 without an environment reads.  They skip themselves without it, and off wasm.

 It prints

	WebFetch-WebSocket-Tests: <run> run, <failures> failures, <errors> errors, <skipped> skipped, <availability>

 then each test that failed, raised an error or was skipped, as 'failed Class>>#selector', 'error ...'
 or 'skipped ...', one per line.  The classes go through the globals, so that the file compiles on
 any image."

| out lineEnd testCase lane package classes suite result |
out := Stdio stdout.
lineEnd := OSPlatform current lineEnding.
testCase := Smalltalk globals at: #TestCase.
(OSEnvironment current at: 'WEB_FETCH_SERVER' ifAbsent: [ nil ]) ifNil: [
	lane := 'websocket.lane' asFileReference.
	lane exists ifTrue: [
		Smalltalk globals at: #WebFetchWebSocketLiveTest ifPresent: [ :live |
			| words |
			words := lane contents substrings.
			live server: words first.
			words size >= 2 ifTrue: [ live hangPort: words second asInteger ] ] ] ].
package := 'WebFetch-WebSocket-Tests'.
classes := (Smalltalk globals allClasses select: [ :each |
	each package notNil
		and: [ each package name asString = package
		and: [ (each inheritsFrom: testCase)
		and: [ each isAbstract not ] ] ] ])
	asSortedCollection: [ :a :b | a name <= b name ].
suite := TestSuite named: package.
classes do: [ :each | suite addTests: each suite tests ].
result := suite run.
out
	nextPutAll: package;
	nextPutAll: ': ';
	print: result runCount;
	nextPutAll: ' run, ';
	print: result failureCount;
	nextPutAll: ' failures, ';
	print: result errorCount;
	nextPutAll: ' errors, ';
	print: result skippedCount;
	nextPutAll: ' skipped, ';
	nextPutAll: (Smalltalk globals at: #WebFetchWebSocket) availability;
	nextPutAll: lineEnd.
{ 'failed' -> result failures. 'error' -> result errors. 'skipped' -> result skipped } do: [ :kind |
	kind value asArray do: [ :each |
		out
			nextPutAll: kind key;
			nextPutAll: ' ';
			nextPutAll: each printString;
			nextPutAll: lineEnd ] ].
out flush
