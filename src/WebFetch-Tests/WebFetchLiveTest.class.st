"
I test `WebFetch` against a live local HTTP server (`tests/wasm/lib/fetch-http.mjs`) when `WebFetch isAvailable` and `self class server` (defaulting to `WEB_FETCH_SERVER` in the environment) is set.
"
Class {
	#name : 'WebFetchLiveTest',
	#superclass : 'TestCase',
	#classVars : [
		'Server'
	],
	#category : 'WebFetch-Tests-Live',
	#package : 'WebFetch-Tests',
	#tag : 'Live'
}

{ #category : 'accessing' }
WebFetchLiveTest class >> server [
	"Base URL of the live test server (e.g. http://127.0.0.1:12345), or nil"

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
WebFetchLiveTest >> closedCountFromServer [
	| resp text idx rest |
	resp := WebFetch get: self baseUrl , '/_stats'.
	text := resp contents.
	idx := text findString: '"closed":'.
	idx = 0 ifTrue: [ ^ 0 ].
	rest := text copyFrom: idx + 9 to: text size.
	^ rest asInteger ifNil: [ 0 ]
]

{ #category : 'helpers' }
WebFetchLiveTest >> resetServer [
	(WebFetch request: self baseUrl , '/_reset') method: #POST; fetch
]

{ #category : 'tests' }
WebFetchLiveTest >> testAbortTerminateAndDroppedStreamCloseServer [
	| base before call proc |
	base := self baseUrl.
	self resetServer.
	before := self closedCountFromServer.

	call := (WebFetch request: base , '/hang') start.
	(Delay forMilliseconds: 80) wait.
	call abort.

	proc := [ (WebFetch request: base , '/hang') timeout: 30 seconds; fetch ] fork.
	(Delay forMilliseconds: 80) wait.
	proc terminate.

	(WebFetch request: base , '/endless') stream: [ :s | s next: 10 ].

	(Delay forMilliseconds: 150) wait.
	self assert: self closedCountFromServer >= (before + 3)
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
WebFetchLiveTest >> testBodySizesZeroOneExactPlusOneAndFiveMB [
	| base resp |
	base := self baseUrl.
	resp := (WebFetch request: base , '/n?n=0') maximumBodySize: 0; fetch.
	self assert: resp rawContents size equals: 0.

	resp := (WebFetch request: base , '/n?n=1') maximumBodySize: 1; fetch.
	self assert: resp rawContents size equals: 1.

	resp := (WebFetch request: base , '/n?n=4096') maximumBodySize: 4096; fetch.
	self assert: resp rawContents size equals: 4096.

	self
		should: [ (WebFetch request: base , '/n?n=4097') maximumBodySize: 4096; fetch ]
		raise: WebFetchTooLarge.

	resp := (WebFetch request: base , '/n?n=5242880') fetch.
	self assert: resp rawContents size equals: 5242880
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
WebFetchLiveTest >> testFinalizationOf100DroppedCalls [
	| base deadline |
	base := self baseUrl.
	5 timesRepeat: [
		20 timesRepeat: [
			| c |
			c := (WebFetch request: base , '/hello') start.
			c := nil ].
		Smalltalk garbageCollect.
		(Delay forMilliseconds: 30) wait ].
	deadline := Time millisecondClockValue + 8000.
	[ WebFetchCall openCount > 0 and: [ Time millisecondClockValue < deadline ] ] whileTrue: [
		Smalltalk garbageCollect.
		(Delay forMilliseconds: 50) wait ].
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchLiveTest >> testGzipHeadPostAndRedirect [
	| base resp |
	base := self baseUrl.

	resp := WebFetch get: base , '/gzip'.
	self assert: resp status equals: 200.
	self assert: resp rawContents size equals: 20000.

	resp := (WebFetch request: base , '/hello') method: #HEAD; fetch.
	self assert: resp status equals: 200.
	self assert: resp rawContents isEmpty.

	resp := WebFetch post: base , '/echo' body: 'hello world' type: 'text/plain'.
	self assert: (resp contents beginsWith: 'POST|/echo|text/plain|').
	self assert: (resp contents endsWith: '|11|hello world').

	resp := WebFetch post: base , '/echo' body: #[ 65 66 67 ] type: 'application/octet-stream'.
	self assert: (resp contents endsWith: '|3|ABC').

	resp := WebFetch get: base , '/redir'.
	self assert: resp status equals: 200.
	self assert: resp isRedirected.
	self assert: resp contents equals: 'hello'.

	resp := (WebFetch request: base , '/redir') dontFollowRedirects; fetch.
	self assert: (resp status between: 300 and: 399)
]

{ #category : 'tests' }
WebFetchLiveTest >> testSixtyFiveOpenLimit [
	| base calls |
	base := self baseUrl.
	calls := OrderedCollection new.
	[
		64 timesRepeat: [ calls add: (WebFetch request: base , '/hang') start ].
		self should: [ (WebFetch request: base , '/hang') start ] raise: WebFetchTooManyOpen ]
		ensure: [ calls do: [ :c | c abort ] ]
]

{ #category : 'tests' }
WebFetchLiveTest >> testTimeoutAndTruncatedBody [
	| base |
	base := self baseUrl.
	self
		should: [ (WebFetch request: base , '/hang') timeout: 150 milliSeconds; fetch ]
		raise: WebFetchTimeout.
	self
		should: [ WebFetch get: base , '/trunc' ]
		raise: WebFetchNetworkError
]
