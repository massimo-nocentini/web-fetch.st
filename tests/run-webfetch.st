"run-webfetch.st - run the tests of the WebFetch packages that the image has

	WEB_FETCH_SERVER=http://127.0.0.1:<port> pharo --headless X.image --no-default-preferences st --quit run-webfetch.st

 The live tests need a running tests/wasm/lib/fetch-http.mjs of the VM,

	node tests/wasm/lib/fetch-http.mjs

 whose URL is in the environment, or in the file webfetch.lane of the working directory (its first
 word), which a VM without an environment reads.  They skip themselves without it, and off wasm.

 It prints for each of WebFetch-Tests and WebFetch-Zinc-Tests

	<package>: <run> run, <failures> failures, <errors> errors, <skipped> skipped, <availability>

 then each test that failed, raised an error or was skipped, as 'failed Class>>#selector', 'error ...'
 or 'skipped ...', one per line.  The classes go through the globals, so that the file compiles on
 any image."

| out lineEnd testCase server |
out := Stdio stdout.
lineEnd := OSPlatform current lineEnding.
testCase := Smalltalk globals at: #TestCase.
server := 'webfetch.lane' asFileReference.
server exists ifTrue: [
	Smalltalk globals at: #WebFetchLiveTest ifPresent: [ :live | live server: server contents substrings first ] ].
#( 'WebFetch-Tests' 'WebFetch-Zinc-Tests' ) do: [ :package |
	| classes suite result |
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
		nextPutAll: (Smalltalk globals at: #WebFetch) availability;
		nextPutAll: lineEnd.
	{ 'failed' -> result failures. 'error' -> result errors. 'skipped' -> result skipped } do: [ :kind |
		kind value asArray do: [ :each |
			out
				nextPutAll: kind key;
				nextPutAll: ' ';
				nextPutAll: each printString;
				nextPutAll: lineEnd ] ].
	out flush ].
