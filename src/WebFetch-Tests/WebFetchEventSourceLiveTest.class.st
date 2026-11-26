"
I test `WebFetchEventSource` against the event streams of the live test server, `/sse` of `tests/wasm/lib/fetch-http.mjs` (the comment at its top says its parameters), when `WebFetchLiveTest` would run: I am its subclass, and share its server, `isBrowser` and helpers, but run only my own tests.

Each test has a tag of its own (`tagFor:`), which is the `key` of its connections: the server counts them per key, and the log of the server is read per tag. In a browser each connection that sends `Last-Event-ID` is preceded by a preflight (an OPTIONS of the same URL), so the assertions on headers read the GETs only (`getsForTag:`).

The sources made by `sourceOn:` reconnect after 50 ms, or after the `retry` of the server, at least 10 ms.
"
Class {
	#name : 'WebFetchEventSourceLiveTest',
	#superclass : 'WebFetchLiveTest',
	#category : 'WebFetch-Tests-Live',
	#package : 'WebFetch-Tests',
	#tag : 'Live'
}

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> drain: aSource [
	"Read aSource to its end: answer the events and the WebFetchError that ended it, or nil"

	| events error event |
	events := OrderedCollection new.
	error := [
		[ (event := aSource next) notNil ] whileTrue: [ events add: event ].
		nil ]
			on: WebFetchError
			do: [ :e | e ].
	^ { events asArray. error }
]

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> idsOf: events [
	^ (events collect: [ :each | each lastEventId ]) asArray
]

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> jsonOf: anEvent [
	"The JSON of the first data line of an event of /sse"

	^ STONJSON fromString: (anEvent data copyUpTo: Character lf)
]

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> sourceOn: aUrlString [
	^ (WebFetch eventSource: aUrlString)
		reconnectDelay: 50 milliSeconds;
		minimumReconnectDelay: 10 milliSeconds;
		yourself
]

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> sse: aQuery tag: tag [
	"The URL of /sse with the key tag and the parameters of aQuery"

	^ self baseUrl , '/sse?key=' , tag , (aQuery ifEmpty: [ '' ] ifNotEmpty: [ '&' , aQuery ])
]

{ #category : 'helpers' }
WebFetchEventSourceLiveTest >> waitFor: aBlock seconds: seconds [
	| deadline |
	deadline := Time millisecondClockValue + (seconds * 1000).
	[ aBlock value ] whileFalse: [
		Time millisecondClockValue >= deadline ifTrue: [ ^ false ].
		(Delay forMilliseconds: 20) wait ].
	^ true
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testEventsAndClose [
	"Three events of a stream that stays open, then close: the server sees the connection closed"

	| tag source events gets headers |
	tag := self tagFor: 'events'.
	source := self sourceOn: (self sse: 'end=hang' tag: tag).
	events := (1 to: 3) collect: [ :i | source nextTimeout: 10 seconds ].
	self assert: (events allSatisfy: [ :each | each notNil ]).
	self assert: (events collect: [ :each | each type ]) asArray equals: #( 'tick' 'tick' 'tick' ).
	self assert: (self idsOf: events) equals: #( '1' '2' '3' ).
	events withIndexDo: [ :each :i |
		| json |
		json := self jsonOf: each.
		self assert: (json at: 'k') equals: i.
		self assert: (json at: 'conn') equals: 0.
		self assert: (json at: 'last') equals: '' ].
	self assert: events first origin equals: self baseUrl.
	self assert: source readyState equals: #open.
	self assert: source response status equals: 200.
	self assert: source lastEventId equals: '3'.
	source close.
	self assert: source readyState equals: #closed.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self waitUntilClosedCountForTag: tag atLeast: 1.
	self assert: WebFetchCall openCount equals: 0.
	gets := self getsForTag: tag.
	self assert: gets size equals: 1.
	headers := gets first at: 'headers'.
	self assert: (headers at: 'accept') equals: 'text/event-stream'.
	self deny: (headers includesKey: 'last-event-id').
	self class isBrowser ifFalse: [
		"what node's fetch sends for the cache mode no-store: flag 2 reached it"
		self assert: (headers at: 'pragma' ifAbsent: [ nil ]) equals: 'no-cache' ]
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testIdleTimeout [
	"A silent connection is dropped after idleTimeout and the source reconnects; a heartbeat (: ping) keeps it"

	| tag source events reasons pingTag pinged pingEvents pingReasons |
	tag := self tagFor: 'idle'.
	events := OrderedCollection new.
	reasons := OrderedCollection new.
	source := (self sourceOn: (self sse: 'end=hang' tag: tag))
		idleTimeout: 300 milliSeconds;
		onEvent: [ :event | events add: event ];
		onReconnect: [ :reason | reasons add: reason ];
		yourself.
	source start.
	self assert: (self waitFor: [ events size >= 6 ] seconds: 10).
	source close.
	self assert: (self idsOf: (events first: 6)) equals: #( '1' '2' '3' '4' '5' '6' ).
	self assert: (reasons first isKindOf: WebFetchTimeout).
	self assert: (self getsForTag: tag) size >= 2.

	pingTag := self tagFor: 'idle-ping'.
	pingEvents := OrderedCollection new.
	pingReasons := OrderedCollection new.
	pinged := (self sourceOn: (self sse: 'end=hang&ping=100' tag: pingTag))
		idleTimeout: 300 milliSeconds;
		onEvent: [ :event | pingEvents add: event ];
		onReconnect: [ :reason | pingReasons add: reason ];
		yourself.
	pinged start.
	(Delay forSeconds: 1) wait.
	self assert: pinged isOpen.
	pinged close.
	self assert: pingReasons isEmpty.
	self assert: pingEvents size equals: 3.
	self assert: (self getsForTag: pingTag) size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testIncompleteEvent [
	"An event without its empty line at the end of the body is dropped, with its id"

	| tag source result |
	tag := self tagFor: 'partial'.
	source := (self sourceOn: (self sse: 'end=partial' tag: tag))
		reconnects: false;
		yourself.
	result := self drain: source.
	self assert: (self idsOf: result first) equals: #( '1' '2' '3' ).
	self assert: result second isNil.
	self assert: source lastEventId equals: '3'.
	self assert: source readyState equals: #closed.
	self assert: (self getsForTag: tag) size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testLineEndsBomUtf8AndSplit [
	"Every line end, a BOM, UTF-8, and events written in two pieces give the same events. The host joins the pieces when they come together: WebFetchEventParserTest is the proof of the cuts"

	| smile |
	smile := String new: 0 streamContents: [ :out |
		out
			nextPutAll: 'café ';
			nextPut: (Character value: 16r2713);
			space;
			nextPut: (Character value: 16r1F642) ].
	#( 'eol=mixed&bom=1&utf8=1' 'eol=crlf&split=1' 'eol=cr&split=1' 'eol=lf&bom=1&split=1' ) withIndexDo: [ :query :i |
		| tag source result |
		tag := self tagFor: 'eol' , i printString.
		source := (self sourceOn: (self sse: query tag: tag))
			reconnects: false;
			yourself.
		result := self drain: source.
		self assert: result second isNil.
		self assert: (self idsOf: result first) equals: #( '1' '2' '3' ).
		self assert: (result first collect: [ :each | each type ]) asArray equals: #( 'tick' 'tick' 'tick' ).
		self
			assert: (result first collect: [ :each | each data ]) asArray
			equals: ((1 to: 3) collect: [ :k | '{"k":' , k printString , ',"conn":0,"last":""}' , String lf , smile ]) ]
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testNoReplayFromHttpCache [
	"A cacheable event stream is asked of the server at each connection: the cache mode is no-store. In node it passes trivially, since its fetch has no cache"

	| tag source result |
	tag := self tagFor: 'cache'.
	source := self sourceOn: (self sse: 'cc=max-age%3D60&n=1&until=2' tag: tag).
	result := self drain: source.
	self assert: (self idsOf: result first) equals: #( '1' '2' ).
	self assert: (result second isKindOf: WebFetchBadResponse).
	self assert: result second response status equals: 204.
	self assert: (result second response headerAt: 'Cache-Control' ifAbsent: [ nil ]) equals: 'max-age=60'.
	self assert: (self getsForTag: tag) size equals: 3
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testReconnectAfterBrokenBody [
	"Bodies that break after their events: the ids are contiguous from 1 and end at 6, however many connections it took"

	| tag source result |
	tag := self tagFor: 'broken'.
	source := self sourceOn: (self sse: 'end=destroy&retry=50&until=6' tag: tag).
	result := self drain: source.
	self assert: (self idsOf: result first) equals: #( '1' '2' '3' '4' '5' '6' ).
	self assert: (result second isKindOf: WebFetchBadResponse).
	self assert: result second response status equals: 204.
	"three events a connection, and the 204 at the end"
	self assert: (self getsForTag: tag) size >= 3
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testReconnectResumes [
	"The body ends after two events: the source reconnects after the retry of the server with Last-Event-ID, until the server answers 204"

	| tag source result events gets log |
	tag := self tagFor: 'resume'.
	source := self sourceOn: (self sse: 'n=2&retry=50&until=6' tag: tag).
	result := self drain: source.
	events := result first.
	self assert: (self idsOf: events) equals: #( '1' '2' '3' '4' '5' '6' ).
	self assert: (events collect: [ :each | (self jsonOf: each) at: 'conn' ]) asArray equals: #( 0 0 1 1 2 2 ).
	self assert: (events collect: [ :each | (self jsonOf: each) at: 'last' ]) asArray equals: #( '' '' '2' '2' '4' '4' ).
	self assert: (result second isKindOf: WebFetchBadResponse).
	self assert: result second response status equals: 204.
	self assert: source readyState equals: #closed.
	self assert: source reconnectDelay equals: 50 milliSeconds.
	self assert: source connections equals: 4.
	gets := self getsForTag: tag.
	self
		assert: (gets collect: [ :each | (each at: 'headers') at: 'last-event-id' ifAbsent: [ nil ] ]) asArray
		equals: #( nil '2' '4' '6' ).
	self class isBrowser ifTrue: [
		"Accept: text/event-stream is safelisted and the cache mode adds no header before the CORS decision; Last-Event-ID costs a preflight"
		log := (self fetchStatsForTag: tag) at: 'requests'.
		self assert: (log first at: 'method') equals: 'GET'.
		self assert: (self preflightsForTag: tag) size equals: 3 ]
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testRefusals [
	"A status other than 200, or another media type, fails the source with WebFetchBadResponse, which has the answer and its body; no second request"

	| tag result error |
	tag := self tagFor: 'refused-status'.
	result := self drain: (self sourceOn: (self sse: 'status=500' tag: tag)).
	self assert: result first isEmpty.
	error := result second.
	self assert: (error isKindOf: WebFetchBadResponse).
	self assert: error kind equals: #response.
	self assert: error response status equals: 500.
	self assert: error response rawContents utf8Decoded equals: '{"error":"status 500"}'.
	self assert: (self getsForTag: tag) size equals: 1.

	tag := self tagFor: 'refused-type'.
	result := self drain: (self sourceOn: (self sse: 'type=text/plain' tag: tag)).
	self assert: result first isEmpty.
	error := result second.
	self assert: (error isKindOf: WebFetchBadResponse).
	self assert: error response status equals: 200.
	self assert: error response mediaType equals: 'text/plain'.
	self assert: (error messageText includesSubstring: 'text/plain').
	self assert: (self getsForTag: tag) size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testStartInBackground [
	"The forked reader: the connection opened, three events, then the 204 of the server as the error"

	| tag done opened events failure source process |
	tag := self tagFor: 'start'.
	done := Semaphore new.
	opened := OrderedCollection new.
	events := OrderedCollection new.
	source := (self sourceOn: (self sse: 'n=3&until=3' tag: tag))
		onOpen: [ :response | opened add: response status ];
		onEvent: [ :event | events add: event lastEventId ];
		onError: [ :error |
			failure := error.
			done signal ];
		yourself.
	process := source start.
	self deny: (done waitTimeoutSeconds: 5).
	self assert: opened asArray equals: #( 200 ).
	self assert: events asArray equals: #( '1' '2' '3' ).
	self assert: (failure isKindOf: WebFetchBadResponse).
	self assert: failure response status equals: 204.
	self assert: source isClosed.
	self assert: (self waitFor: [ process isTerminated ] seconds: 2)
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testTerminateClosesServer [
	"Terminating a process that reads with do: closes the source: the server sees the connection closed"

	| tag source count process |
	tag := self tagFor: 'terminate'.
	source := self sourceOn: (self sse: 'end=hang' tag: tag).
	count := 0.
	process := [ source do: [ :event | count := count + 1 ] ] fork.
	self assert: (self waitFor: [ count = 3 ] seconds: 10).
	process terminate.
	self assert: (self waitFor: [ source isClosed ] seconds: 2).
	self waitUntilClosedCountForTag: tag atLeast: 1.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testTooLarge [
	"Data over maximumEventSize fails the source with WebFetchTooLarge, and closes its connection"

	| tag source result |
	tag := self tagFor: 'large'.
	source := self sourceOn: (self sse: 'size=2000000&end=hang' tag: tag).
	result := self drain: source.
	self assert: result first isEmpty.
	self assert: (result second isKindOf: WebFetchTooLarge).
	self assert: source isClosed.
	self waitUntilClosedCountForTag: tag atLeast: 1.
	self assert: (self getsForTag: tag) size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testTwoSourcesOnOneUrl [
	"Two sources on the very same URL, whose heads come late, both open: the cache of a browser does not make the second wait for the end of the first"

	| tag url first second started events |
	tag := self tagFor: 'two'.
	url := self sse: 'end=hang&headDelay=300' tag: tag.
	first := self sourceOn: url.
	second := self sourceOn: url.
	started := Time millisecondClockValue.
	self assert: (first nextTimeout: 0 seconds) isNil.
	self assert: (second nextTimeout: 0 seconds) isNil.
	events := { first nextTimeout: 5 seconds. second nextTimeout: 5 seconds }.
	self assert: (events allSatisfy: [ :each | each notNil ]).
	self assert: Time millisecondClockValue - started < 5000.
	self assert: (events collect: [ :each | (self jsonOf: each) at: 'conn' ]) asSet equals: #( 0 1 ) asSet.
	first close.
	second close.
	self waitUntilClosedCountForTag: tag atLeast: 2
]

{ #category : 'tests' }
WebFetchEventSourceLiveTest >> testUtf8LastEventId [
	"An id that is not ASCII is sent as its UTF-8, and its last byte, A0, arrives"

	| tag source event gets |
	tag := self tagFor: 'utf8-id'.
	source := (self sourceOn: (self sse: 'n=1&end=hang' tag: tag))
		lastEventId: 'città';
		yourself.
	event := source nextTimeout: 10 seconds.
	self assert: event notNil.
	self assert: ((self jsonOf: event) at: 'last') equals: 'città'.
	self assert: event lastEventId equals: '1'.
	source close.
	gets := self getsForTag: tag.
	self assert: gets size equals: 1.
	"the log of node has the bytes of the header, one character a byte"
	self assert: ((gets first at: 'headers') at: 'last-event-id') equals: 'città' utf8Encoded asString
]
