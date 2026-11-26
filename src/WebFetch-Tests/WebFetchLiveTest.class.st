"
I test `WebFetch` against a live local HTTP server (`tests/wasm/lib/fetch-http.mjs`) when `WebFetch isAvailable` and `self class server` (defaulting to `WEB_FETCH_SERVER` in the environment) is set.

The server logs every request it gets, with its method, URL and headers, and whether the client closed it before its end; `fetchStatsForTag:` reads the entries whose URL has a tag, `getsForTag:` and `preflightsForTag:` the GETs and the OPTIONS among them. `tagFor:` makes a tag that no other test, nor an earlier run, has.

A subclass, such as `WebFetchEventSourceLiveTest`, shares the server, `isBrowser` and the helpers, and runs only its own tests: `shouldInheritSelectors` is false for a subclass of a concrete class that has tests of its own.
"
Class {
	#name : 'WebFetchLiveTest',
	#superclass : 'TestCase',
	#classVars : [
		'IsBrowser',
		'Server'
	],
	#category : 'WebFetch-Tests-Live',
	#package : 'WebFetch-Tests',
	#tag : 'Live'
}

{ #category : 'accessing' }
WebFetchLiveTest class >> defaultTimeLimit [
	^ 60 seconds
]

{ #category : 'accessing' }
WebFetchLiveTest class >> isBrowser [
	"True when running inside a browser worker rather than Node."

	^ IsBrowser ifNil: [ false ]
]

{ #category : 'accessing' }
WebFetchLiveTest class >> isBrowser: aBoolean [
	IsBrowser := aBoolean
]

{ #category : 'accessing' }
WebFetchLiveTest class >> server [
	"Base URL of the live test server (e.g. http://127.0.0.1:12345), or nil."

	Server ifNotNil: [ ^ Server ].
	^ OSEnvironment current at: 'WEB_FETCH_SERVER' ifAbsent: [ nil ]
]

{ #category : 'accessing' }
WebFetchLiveTest class >> server: aUrlStringOrNil [
	Server := aUrlStringOrNil
]

{ #category : 'helpers' }
WebFetchLiveTest >> baseUrl [
	WebFetch isAvailable ifFalse: [ ^ self skip: 'WebFetch is not available' ].
	^ self class server ifNil: [ self skip: 'WEB_FETCH_SERVER is not set' ]
]

{ #category : 'helpers' }
WebFetchLiveTest >> closedCountForTag: tag [
	| stats |
	stats := self fetchStatsForTag: tag.
	^ ((stats at: 'requests') select: [ :each |
		((each at: 'url') includesSubstring: tag) and: [ each at: 'closed' ] ]) size
]

{ #category : 'helpers' }
WebFetchLiveTest >> fetchStatsForTag: tag [
	| resp |
	resp := WebFetch get: self baseUrl , '/_stats?tag=' , tag.
	^ STONJSON fromString: resp contents
]

{ #category : 'helpers' }
WebFetchLiveTest >> getsForTag: tag [
	"The entries of the log of the server for the GETs whose URL has tag"

	^ ((self fetchStatsForTag: tag) at: 'requests') select: [ :each | (each at: 'method') = 'GET' ]
]

{ #category : 'helpers' }
WebFetchLiveTest >> preflightsForTag: tag [
	"The entries of the log of the server for the OPTIONS (the preflights of a browser) whose URL has tag"

	^ ((self fetchStatsForTag: tag) at: 'requests') select: [ :each | (each at: 'method') = 'OPTIONS' ]
]

{ #category : 'helpers' }
WebFetchLiveTest >> registeredSemaphoreCount [
	| table count |
	table := Smalltalk specialObjectsArray at: 39.
	count := 0.
	table do: [ :each | each ifNotNil: [ count := count + 1 ] ].
	^ count
]

{ #category : 'helpers' }
WebFetchLiveTest >> seenCountForTag: tag [
	| stats |
	stats := self fetchStatsForTag: tag.
	^ ((stats at: 'requests') select: [ :each |
		(each at: 'url') includesSubstring: tag ]) size
]

{ #category : 'helpers' }
WebFetchLiveTest >> tagFor: aString [
	"A tag for the log of the server: the time makes it new at each run, and the last hyphen keeps k1 from matching k10"

	^ 'sse-' , aString , '-' , Time millisecondClockValue printString , '-'
]

{ #category : 'helpers' }
WebFetchLiveTest >> verifyPatternBytes: bytes [
	1 to: bytes size do: [ :i |
		(bytes at: i) = ((i - 1) bitAnd: 255) ifFalse: [
			self fail: 'Pattern mismatch at index ' , i asString ] ]
]

{ #category : 'helpers' }
WebFetchLiveTest >> waitUntilClosedCountForTag: tag atLeast: expected [
	| deadline count |
	deadline := Time millisecondClockValue + 3000.
	[
		count := self closedCountForTag: tag.
		count < expected and: [ Time millisecondClockValue < deadline ] ]
		whileTrue: [ (Delay forMilliseconds: 30) wait ].
	count < expected ifTrue: [ count := self closedCountForTag: tag ].
	self assert: count >= expected
]

{ #category : 'helpers' }
WebFetchLiveTest >> waitUntilSeenCountForTag: tag atLeast: expected [
	| deadline count |
	deadline := Time millisecondClockValue + 3000.
	[
		count := self seenCountForTag: tag.
		count < expected and: [ Time millisecondClockValue < deadline ] ]
		whileTrue: [ (Delay forMilliseconds: 30) wait ].
	count < expected ifTrue: [ count := self seenCountForTag: tag ].
	self assert: count >= expected
]

{ #category : 'running' }
WebFetchLiveTest >> tearDown [
	WebFetch isAvailable ifTrue: [ WebFetch abortAll ].
	super tearDown
]

{ #category : 'tests' }
WebFetchLiveTest >> testAbortAllClosesTenHangCalls [
	| base tag count |
	base := self baseUrl.
	tag := 'tag-abortall-' , Time millisecondClockValue asString.
	count := self class isBrowser ifTrue: [ 4 ] ifFalse: [ 10 ].
	1 to: count do: [ :i |
		(WebFetch request: base , '/hang?' , tag , '-' , i printString) start ].
	self waitUntilSeenCountForTag: tag atLeast: count.
	WebFetch abortAll.
	self assert: WebFetchCall openCount equals: 0.
	self waitUntilClosedCountForTag: tag atLeast: count
]

{ #category : 'tests' }
WebFetchLiveTest >> testAbortClosesServer [
	| base tag call |
	base := self baseUrl.
	tag := 'tag-abort-' , Time millisecondClockValue asString.
	call := (WebFetch request: base , '/hang?' , tag) start.
	self waitUntilSeenCountForTag: tag atLeast: 1.
	call abort.
	self waitUntilClosedCountForTag: tag atLeast: 1
]

{ #category : 'tests' }
WebFetchLiveTest >> testBadRequestsAndConnectionRefused [
	| base |
	base := self baseUrl.
	self should: [ WebFetch get: 'ftp://example.org/x' ] raise: WebFetchBadRequest.
	self should: [ WebFetch get: 'http://user:pass@127.0.0.1/' ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: base , '/hello') method: 'BAD METHOD'; fetch ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://127.0.0.1:1/') timeout: 5 seconds; fetch ] raise: WebFetchNetworkError
]

{ #category : 'tests' }
WebFetchLiveTest >> testBodySizesZeroOneExactPlusOneFiveMBAndStream3MB [
	| base resp pieces total |
	base := self baseUrl.
	resp := (WebFetch request: base , '/n?n=0') maximumBodySize: 0; fetch.
	self assert: resp rawContents size equals: 0.

	resp := (WebFetch request: base , '/n?n=1') maximumBodySize: 1; fetch.
	self assert: resp rawContents size equals: 1.

	resp := (WebFetch request: base , '/n?n=4096') maximumBodySize: 4096; fetch.
	self assert: resp rawContents size equals: 4096.
	self verifyPatternBytes: resp rawContents.

	self
		should: [ (WebFetch request: base , '/n?n=4097') maximumBodySize: 4096; fetch ]
		raise: WebFetchTooLarge.

	resp := (WebFetch request: base , '/n?n=5242880') fetch.
	self assert: resp rawContents size equals: 5242880.
	self verifyPatternBytes: resp rawContents.

	pieces := ByteArray streamContents: [ :out |
		(WebFetch request: base , '/n?n=3145728') stream: [ :s |
			| chunk |
			[ (chunk := s next: 7000) notEmpty ] whileTrue: [ out nextPutAll: chunk ] ] ].
	total := pieces size.
	self assert: total equals: 3145728.
	self verifyPatternBytes: pieces
]

{ #category : 'tests' }
WebFetchLiveTest >> testConcurrent30 [
	| base done results |
	base := self baseUrl.
	done := Semaphore new.
	results := OrderedCollection new.
	1 to: 30 do: [ :i |
		[
			| r |
			r := WebFetch get: base , '/n?n=' , (i * 100) asString.
			results add: r rawContents size.
			done signal ] fork ].
	30 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 15000) ].
	self assert: results size equals: 30
]

{ #category : 'tests' }
WebFetchLiveTest >> testDribbleStreamAndWaitTimeout [
	| base reads text call tag |
	base := self baseUrl.
	reads := 0.
	text := ByteArray streamContents: [ :out |
		(WebFetch request: base , '/dribble') stream: [ :s |
			| buf n |
			buf := ByteArray new: 64.
			[ (n := s readInto: buf startingAt: 1 count: buf size) > 0 ] whileTrue: [
				reads := reads + 1.
				out next: n putAll: buf startingAt: 1 ] ] ].
	self assert: text utf8Decoded equals: 'tick0tick1tick2tick3tick4'.
	self assert: reads > 1.

	tag := 'tag-wt-' , Time millisecondClockValue asString.
	call := (WebFetch request: base , '/hang?' , tag) start.
	self waitUntilSeenCountForTag: tag atLeast: 1.
	self deny: (call waitTimeout: 50 milliSeconds).
	call abort.
	self waitUntilClosedCountForTag: tag atLeast: 1
]

{ #category : 'tests' }
WebFetchLiveTest >> testEarlyStreamCloseClosesServer [
	| base tag |
	base := self baseUrl.
	tag := 'tag-stream-' , Time millisecondClockValue asString.
	(WebFetch request: base , '/endless?' , tag) stream: [ :s | s next: 10 ].
	self waitUntilClosedCountForTag: tag atLeast: 1
]

{ #category : 'tests' }
WebFetchLiveTest >> testFinalizationOf100DroppedCalls [
	| base tag before deadline batchSize batches |
	base := self baseUrl.
	tag := 'tag-gc-' , Time millisecondClockValue asString.
	before := self registeredSemaphoreCount.
	batchSize := self class isBrowser ifTrue: [ 4 ] ifFalse: [ 20 ].
	batches := 100 // batchSize.
	1 to: batches do: [ :batch |
		| batchCalls |
		batchCalls := (1 to: batchSize) collect: [ :i |
			(WebFetch request: base , '/hang?' , tag , '-' , batch printString , '-' , i printString) start ].
		self waitUntilSeenCountForTag: tag atLeast: batch * batchSize.
		batchCalls := nil.
		deadline := Time millisecondClockValue + 5000.
		[ WebFetchCall openCount > 0 and: [ Time millisecondClockValue < deadline ] ] whileTrue: [
			Smalltalk garbageCollect.
			(Delay forMilliseconds: 30) wait ] ].
	deadline := Time millisecondClockValue + 8000.
	[ (WebFetchCall openCount > 0 or: [ self registeredSemaphoreCount > before ])
		and: [ Time millisecondClockValue < deadline ] ] whileTrue: [
			Smalltalk garbageCollect.
			(Delay forMilliseconds: 50) wait ].
	self assert: WebFetchCall openCount equals: 0.
	self assert: self registeredSemaphoreCount equals: before.
	self waitUntilClosedCountForTag: tag atLeast: 100
]

{ #category : 'tests' }
WebFetchLiveTest >> testGzipHeadStatus204HeadersEchoNocorsAndRedirect [
	| base tag resp stats seen err |
	base := self baseUrl.

	tag := 'tag-hdr-' , Time millisecondClockValue asString.
	resp := (WebFetch request: base , '/hello?' , tag)
		headerAt: 'X-Test' put: 'val-1';
		fetch.
	self assert: resp status equals: 200.
	self assert: resp contents equals: 'hello'.
	self assert: (resp headerAt: 'X-A' ifAbsent: [ nil ]) equals: 'café'.
	stats := self fetchStatsForTag: tag.
	seen := (stats at: 'requests') detect: [ :each |
		((each at: 'url') includesSubstring: tag) and: [ (each at: 'preflight') not ] ].
	self assert: ((seen at: 'headers') at: 'x-test') equals: 'val-1'.

	resp := WebFetch get: base , '/gzip'.
	self assert: resp status equals: 200.
	self assert: resp rawContents size equals: 20000.

	resp := (WebFetch request: base , '/hello') method: #HEAD; fetch.
	self assert: resp status equals: 200.
	self assert: resp rawContents isEmpty.

	resp := WebFetch get: base , '/204'.
	self assert: resp status equals: 204.
	self assert: resp rawContents isEmpty.

	resp := WebFetch get: base , '/status?code=404'.
	self assert: resp status equals: 404.
	self deny: resp isSuccess.
	self assert: resp contents equals: '404'.

	resp := WebFetch post: base , '/echo' body: 'héllo café' type: 'text/plain; charset=utf-8'.
	self assert: (resp contents endsWith: '|12|héllo café').

	resp := WebFetch post: base , '/echo' body: #[ 65 66 67 ] type: 'application/octet-stream'.
	self assert: (resp contents endsWith: '|3|ABC').

	self class isBrowser ifFalse: [
		resp := (WebFetch request: base , '/echo')
			headerAt: 'User-Agent' put: 'WebFetchTest/1';
			fetch.
		self assert: (resp contents includesSubstring: '|WebFetchTest/1|') ].

	self class isBrowser
		ifTrue: [
			self should: [ WebFetch get: base , '/nocors' ] raise: WebFetchNetworkError ]
		ifFalse: [
			resp := WebFetch get: base , '/nocors'.
			self assert: resp status equals: 200.
			self assert: resp contents equals: 'nocors' ].

	resp := WebFetch get: base , '/redir'.
	self assert: resp status equals: 200.
	self assert: resp isRedirected.
	self assert: (resp url endsWith: '/hello').
	self assert: resp contents equals: 'hello'.

	self class isBrowser
		ifTrue: [
			err := [ (WebFetch request: base , '/redir') dontFollowRedirects; fetch. nil ]
				on: WebFetchBadRequest
				do: [ :e | e ].
			self assert: err notNil.
			self assert: err kind equals: #redirect ]
		ifFalse: [
			resp := (WebFetch request: base , '/redir') dontFollowRedirects; fetch.
			self assert: (resp status between: 300 and: 399) ]
]

{ #category : 'tests' }
WebFetchLiveTest >> testSixtyFiveOpenLimit [
	| base calls |
	base := self baseUrl.
	calls := OrderedCollection new.
	[
		1 to: 64 do: [ :i | calls add: (WebFetch request: base , '/hang?n=' , i printString) start ].
		self should: [ (WebFetch request: base , '/hang?n=65') start ] raise: WebFetchTooManyOpen ]
		ensure: [ calls do: [ :c | c abort ] ]
]

{ #category : 'tests' }
WebFetchLiveTest >> testTerminateClosesServer [
	| base tag proc |
	base := self baseUrl.
	tag := 'tag-term-' , Time millisecondClockValue asString.
	proc := [ (WebFetch request: base , '/hang?' , tag) timeout: 30 seconds; fetch ] fork.
	self waitUntilSeenCountForTag: tag atLeast: 1.
	proc terminate.
	self waitUntilClosedCountForTag: tag atLeast: 1
]

{ #category : 'tests' }
WebFetchLiveTest >> testTimeoutTruncatedAndWhenDone [
	| base sem gotResp gotErr |
	base := self baseUrl.
	self
		should: [ (WebFetch request: base , '/hang') timeout: 150 milliSeconds; fetch ]
		raise: WebFetchTimeout.
	self
		should: [ WebFetch get: base , '/trunc' ]
		raise: WebFetchNetworkError.

	sem := Semaphore new.
	gotResp := nil.
	((WebFetch request: base , '/hello') start)
		whenDone: [ :r | gotResp := r contents. sem signal ]
		ifError: [ :e | sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 5000).
	self assert: gotResp equals: 'hello'.

	sem := Semaphore new.
	gotErr := nil.
	((WebFetch request: base , '/trunc') start)
		whenDone: [ :r | sem signal ]
		ifError: [ :e | gotErr := e. sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 5000).
	self assert: (gotErr isKindOf: WebFetchNetworkError)
]

{ #category : 'tests' }
WebFetchLiveTest >> testTooLargeClosesServer [
	| base tag tagBig |
	base := self baseUrl.
	self
		should: [ (WebFetch request: base , '/n?n=5242880') maximumBodySize: 1000; fetch ]
		raise: WebFetchTooLarge.
	self
		should: [ (WebFetch request: base , '/n?n=1000001') maximumBodySize: 1000000; timeout: 10 seconds; fetch ]
		raise: WebFetchTooLarge.

	tag := 'tag-large-' , Time millisecondClockValue asString.
	self
		should: [ (WebFetch request: base , '/endless?' , tag) maximumBodySize: 1000; fetch ]
		raise: WebFetchTooLarge.
	self waitUntilClosedCountForTag: tag atLeast: 1.

	tagBig := 'tag-large-1m-' , Time millisecondClockValue asString.
	self
		should: [ (WebFetch request: base , '/endless?' , tagBig) maximumBodySize: 1000000; timeout: 10 seconds; fetch ]
		raise: WebFetchTooLarge.
	self waitUntilClosedCountForTag: tagBig atLeast: 1
]
