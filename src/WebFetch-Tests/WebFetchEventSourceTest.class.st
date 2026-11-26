"
I test `WebFetchEventSource` against `WebFetchTestHost`. Each script of the host is one connection; a start without a script stays pending. The sources made with `source:` and `sourceOf:` reconnect after 10 ms (`reconnectDelay:` and `minimumReconnectDelay:`) unless a test says otherwise, and must be closed when the test ends.

The host joins the chunks of a script when the source reads, so the cuts of a body are tested by `WebFetchEventParserTest`; `testCutAcrossReads` pushes the pieces by hand, each read before the next.
"
Class {
	#name : 'WebFetchEventSourceTest',
	#superclass : 'WebFetchTestCase',
	#instVars : [
		'sources',
		'readers'
	],
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchEventSourceTest >> deliverHead [
	"The head of an event stream for the last request"

	self deliverHead: 200 type: 'text/event-stream'
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> deliverHead: status type: aString [
	host
		deliverHeadFor: host lastId
		status: status
		reason: 'OK'
		url: (host lastRequest at: #url)
		type: 'basic'
		redirected: false
		headers: { 'Content-Type' -> aString }
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> eventStream: aStringOrByteArray [
	"A connection whose answer is an event stream with this body, which then ends"

	host
		enqueueStatus: 200
		headers: { 'Content-Type' -> 'text/event-stream' }
		body: aStringOrByteArray
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> header: aName of: aRequestRecord [
	"The value of the header aName of a request of the host, or nil"

	| lower |
	lower := aName asLowercase.
	^ ((aRequestRecord at: #headers) detect: [ :each | each key asLowercase = lower ] ifNone: [ nil ])
		ifNotNil: [ :header | header value ]
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> headers: aName of: aRequestRecord [
	| lower |
	lower := aName asLowercase.
	^ (aRequestRecord at: #headers) select: [ :each | each key asLowercase = lower ]
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> nonLocalReturnFrom: aSource [
	aSource do: [ :event | ^ event ].
	^ nil
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> push: aString [
	"Bytes of the last request, which the next read finds in the host"

	host pushBytes: aString utf8Encoded for: host lastId
]

{ #category : 'running' }
WebFetchEventSourceTest >> setUp [
	super setUp.
	sources := OrderedCollection new.
	readers := OrderedCollection new
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> source: aPath [
	^ self sourceOf: (WebFetch request: 'http://example.test/' , aPath)
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> sourceOf: aRequest [
	| source |
	source := aRequest eventSource.
	source
		reconnectDelay: 10 milliSeconds;
		minimumReconnectDelay: 10 milliSeconds.
	sources add: source.
	^ source
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> startTimes [
	"Record the time of each start of a request"

	| times |
	times := OrderedCollection new.
	host onStart: [ times add: Time millisecondClockValue ].
	^ times
]

{ #category : 'running' }
WebFetchEventSourceTest >> tearDown [
	| left ended |
	left := sources reject: [ :each | each isClosed ].
	sources do: [ :each | each close ].
	ended := self waitUntil: [ readers allSatisfy: [ :each | each isTerminated ] ].
	readers do: [ :each | each terminate ].
	super tearDown.
	self assert: left isEmpty.
	self assert: ended
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> start: aSource [
	"Start the reader of aSource; tearDown waits until it ended"

	^ readers add: aSource start
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testBackoff [
	| source starts gaps |
	starts := self startTimes.
	5 timesRepeat: [ self eventStream: ': no event' , String lf ].
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'backoff')
		reconnectDelay: 250 milliSeconds;
		minimumReconnectDelay: 250 milliSeconds;
		maximumReconnectDelay: 1 second;
		yourself.
	self assert: source next data equals: 'a'.
	self assert: (source nextTimeout: 1 second) isNil.
	self assert: starts size equals: 7.
	gaps := (2 to: starts size) collect: [ :i | (starts at: i) - (starts at: i - 1) ].
	#( 250 500 1000 1000 1000 250 ) with: gaps do: [ :expected :gap |
		self assert: gap >= (expected - 5) description: gaps printString.
		self assert: gap < (expected + 200) description: gaps printString ].
	source close.
	"no LargeInteger, the cap"
	source := self source: 'misses'.
	source maximumReconnectDelay: 1 second.
	source misses: 40.
	self assert: source reconnectionDelay equals: 1000.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCloseDuringReconnectWait [
	| source result done start |
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'closewait') reconnectDelay: 10 seconds; yourself.
	self assert: source next data equals: 'a'.
	done := false.
	[
		result := source next.
		done := true ] fork.
	(Delay forMilliseconds: 50) wait.
	self deny: done.
	start := Time millisecondClockValue.
	source close.
	self assert: (self waitUntil: [ done ] timeoutMs: 200).
	self assert: Time millisecondClockValue - start < 200.
	self assert: result isNil.
	self assert: host requests size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCloseFromAnotherProcess [
	| source result done |
	"waiting for a head"
	host enqueuePending.
	source := self source: 'close1'.
	done := false.
	[
		result := source next.
		done := true ] fork.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	source close.
	self assert: (self waitUntil: [ done ]).
	self assert: result isNil.
	self assert: host openCount equals: 0.
	self assert: source isClosed.
	self assert: source next isNil.
	"open and silent"
	host enqueuePending.
	source := self source: 'close2'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead.
	done := false.
	[
		result := source next.
		done := true ] fork.
	self assert: (self waitUntil: [ source isOpen ]).
	(Delay forMilliseconds: 20) wait.
	source close.
	self assert: (self waitUntil: [ done ]).
	self assert: result isNil.
	self assert: host openCount equals: 0.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCloseRacesConnect [
	| source |
	source := self source: 'race'.
	host enqueuePending.
	host onStart: [
		[ source close ] fork.
		Processor yield ].
	self assert: source next isNil.
	self assert: source isClosed.
	self assert: (self waitUntil: [ host openCount = 0 ]).
	self assert: WebFetchCall openCount equals: 0.
	self assert: host requests size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCloseWhileReadingARefusal [
	"A close that lands while the reader keeps the body of a refused answer leaves no terminal error"

	| source result done |
	host enqueuePending.
	source := self source: 'refused-close'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead: 500 type: 'text/plain'.
	self push: 'partial'.
	done := false.
	[
		result := [ source next ] on: Error do: [ :e | e ].
		done := true ] fork.
	(Delay forMilliseconds: 50) wait.
	self deny: done.
	source close.
	self assert: (self waitUntil: [ done ]).
	self assert: result isNil.
	self assert: source error isNil.
	self assert: source isClosed.
	self assert: source next isNil.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testClosedSourceInAnotherSession [
	"A source that ended before the image resumed keeps its end: nil, or its own error"

	| clean closed failed |
	self eventStream: (self text: #( 'data: a' '' )).
	clean := (self source: 'session-clean') reconnects: false; yourself.
	self assert: clean next data equals: 'a'.
	self assert: clean next isNil.
	self eventStream: (self text: #( 'data: b' '' )).
	closed := self source: 'session-closed'.
	self assert: closed next data equals: 'b'.
	closed close.
	host enqueueStatus: 500 headers: { 'Content-Type' -> 'text/plain' } body: 'no'.
	failed := self source: 'session-failed'.
	self should: [ failed next ] raise: WebFetchBadResponse.
	{ clean. closed. failed } do: [ :each | each session: Object new ].
	self assert: clean next isNil.
	self assert: clean error isNil.
	self assert: (closed nextTimeout: 0 seconds) isNil.
	self assert: closed error isNil.
	self should: [ failed next ] raise: WebFetchBadResponse.
	self assert: (failed error isKindOf: WebFetchBadResponse).
	self assert: WebFetchEventSource openCount equals: 0.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testConnectTimeout [
	| source start |
	host enqueuePending.
	source := (self source: 'ct') connectTimeout: 50 milliSeconds; yourself.
	start := Time microsecondClockValue.
	self
		should: [ source next ]
		raise: WebFetchTimeout
		withExceptionDo: [ :error |
			self assert: error messageText equals: 'no head after 50 ms'.
			self assert: error kind equals: #timeout ].
	self assert: Time microsecondClockValue - start >= 45000.
	self assert: source isClosed.
	self assert: host openCount equals: 0.
	"after an open, a reconnection"
	self eventStream: (self text: #( 'data: a' '' )).
	host enqueuePending.
	self eventStream: (self text: #( 'data: c' '' )).
	source := (self source: 'ct2') connectTimeout: 50 milliSeconds; yourself.
	self assert: source next data equals: 'a'.
	self assert: source next data equals: 'c'.
	self assert: host requests size equals: 4.
	self assert: ((host requests at: 3) at: #closed).
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCutAcrossReads [
	"Pieces cut between CR and LF and inside the é, each read before the next"

	| source id |
	host enqueuePending.
	source := self source: 'cut'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	id := host lastId.
	self deliverHead.
	host pushBytes: ('id: 1' , String crlf , 'data: caf') utf8Encoded , #[ 16rC3 ] for: id.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self assert: (host stateOf: id) >> 3 equals: 0.
	host pushBytes: #[ 16rA9 ] , ' ✓' utf8Encoded , #[ 13 ] for: id.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self assert: (host stateOf: id) >> 3 equals: 0.
	host pushBytes: #[ 10 13 10 ] for: id.
	self assert: (source nextTimeout: 0 seconds) data equals: 'café ✓'.
	self assert: source lastEventId equals: '1'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testDoClosesAtTheEnd [
	| source events |
	self eventStream: (self text: #( 'data: a' '' 'data: b' '' )).
	source := (self source: 'do') reconnects: false; yourself.
	events := OrderedCollection new.
	source do: [ :event | events add: event data ].
	self assert: events asArray equals: #( 'a' 'b' ).
	self assert: source isClosed.
	self assert: source error isNil.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testEmptyIdSendsNoHeader [
	| source |
	self eventStream: (self text: #( 'id:' 'data: a' '' )).
	host enqueuePending.
	source := (self source: 'emptyid') lastEventId: 'x'; yourself.
	self assert: source next lastEventId equals: ''.
	self assert: (source nextTimeout: 0.2 seconds) isNil.
	self assert: host requests size equals: 2.
	self assert: (self header: 'Last-Event-ID' of: host requests first) equals: 'x'.
	self assert: (self header: 'Last-Event-ID' of: host requests second) isNil.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testEventsOfOneConnection [
	| source event record |
	self eventStream: (self text: #( 'id: 1' 'event: tick' 'data: a' '' 'id: 2' 'data: b' 'data: c' '' )).
	host enqueuePending.
	source := self source: 'one'.
	self assert: source readyState equals: #connecting.
	event := source next.
	self assert: event type equals: 'tick'.
	self assert: event data equals: 'a'.
	self assert: event lastEventId equals: '1'.
	self assert: event origin equals: 'http://example.test'.
	self assert: source readyState equals: #open.
	self assert: source response status equals: 200.
	event := source next.
	self assert: event type equals: 'message'.
	self assert: event data equals: 'b' , String lf , 'c'.
	self assert: event lastEventId equals: '2'.
	self assert: source lastEventId equals: '2'.
	record := host requests first.
	self assert: (record at: #method) equals: 'GET'.
	self assert: (record at: #url) equals: 'http://example.test/one'.
	self assert: (self header: 'Accept' of: record) equals: 'text/event-stream'.
	self assert: (self header: 'Last-Event-ID' of: record) isNil.
	self assert: (self header: 'Cache-Control' of: record) isNil.
	self assert: (record at: #flags) equals: 2.
	self assert: (record at: #timeout) equals: 0.
	self assert: (record at: #window) equals: WebFetchCall defaultStreamWindow.
	"the end of the body: a reconnection, pending"
	self assert: (source nextTimeout: 100 milliSeconds) isNil.
	self assert: source readyState equals: #connecting.
	self assert: source connections equals: 2.
	self assert: (self header: 'Last-Event-ID' of: host requests second) equals: '2'.
	self assert: source printString equals: 'WebFetchEventSource(#connecting http://example.test/one)'.
	source close.
	self assert: source readyState equals: #closed.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testFirstNetworkErrorFails [
	| source |
	host enqueueErrorKind: #network message: 'connect ECONNREFUSED'.
	source := self source: 'refused'.
	self
		should: [ source next ]
		raise: WebFetchNetworkError
		withExceptionDo: [ :error | self assert: (error messageText includesSubstring: 'ECONNREFUSED') ].
	self assert: source isClosed.
	self assert: (source error isKindOf: WebFetchNetworkError).
	self should: [ source next ] raise: WebFetchNetworkError.
	self should: [ source nextTimeout: 0 seconds ] raise: WebFetchNetworkError.
	self assert: host requests size equals: 1.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testIdleTimeout [
	| source item pinger before |
	host enqueuePending.
	host enqueuePending.
	source := (self source: 'idle') idleTimeout: 50 milliSeconds; yourself.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead.
	item := source nextItemBefore: nil.
	self assert: item key equals: #open.
	item := source nextItemBefore: nil.
	self assert: item key equals: #reconnect.
	self assert: (item value isKindOf: WebFetchTimeout).
	self assert: item value messageText equals: 'no byte for 50 ms'.
	self assert: (self waitUntil: [ (host requests first at: #closed) ]).
	self assert: (source nextTimeout: 50 milliSeconds) isNil.
	self assert: host requests size equals: 2.
	source close.
	"a comment of the server counts"
	host enqueuePending.
	before := host requests size.
	source := (self source: 'ping') idleTimeout: 100 milliSeconds; yourself.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead.
	pinger := [
		15 timesRepeat: [
			(Delay forMilliseconds: 20) wait.
			self push: ': ping' , String lf ] ] fork.
	self assert: (source nextTimeout: 300 milliSeconds) isNil.
	pinger terminate.
	self assert: source isOpen.
	self assert: host requests size equals: before + 1.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testInCallback [
	| source events |
	host enqueuePending.
	source := self source: 'cb'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead.
	self push: (self text: #( 'data: a' '' 'data: b' '' )).
	events := OrderedCollection new.
	self inCallback: [
		events add: source next data.
		events add: source next data.
		self should: [ source next ] raise: WebFetchInCallback.
		self should: [ source nextTimeout: 1 second ] raise: WebFetchInCallback.
		self assert: (source nextTimeout: 0 seconds) isNil ].
	self assert: events asArray equals: #( 'a' 'b' ).
	self assert: source isOpen.
	self assert: host openCount equals: 1.
	self push: (self text: #( 'data: c' '' )).
	self assert: source next data equals: 'c'.
	source close.
	"a new source starts no request in a callback"
	source := self source: 'cb2'.
	self inCallback: [
		self should: [ source next ] raise: WebFetchInCallback.
		self should: [ source open ] raise: WebFetchInCallback.
		self should: [ source do: [ :event | ] ] raise: WebFetchInCallback ].
	self assert: host requests size equals: 1.
	self deny: source isClosed.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testLastEventIdHeaderOfTheRequest [
	| request source |
	request := (WebFetch request: 'http://example.test/lid')
		headerAt: 'last-event-id' put: '7';
		yourself.
	source := self sourceOf: request.
	self assert: source lastEventId equals: '7'.
	self assert: (source request headers noneSatisfy: [ :each | each key asLowercase = 'last-event-id' ]).
	self eventStream: (self text: #( 'data: a' '' )).
	host enqueuePending.
	self assert: source next lastEventId equals: '7'.
	self assert: (self headers: 'Last-Event-ID' of: host requests first) size equals: 1.
	self assert: (self header: 'Last-Event-ID' of: host requests first) equals: '7'.
	self assert: request headers size equals: 1.
	source close.
	self
		should: [
			(WebFetch request: 'http://example.test/lid')
				headerAt: 'Last-Event-ID' put: 'a' , String cr , 'b';
				eventSource ]
		raise: WebFetchBadRequest
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testLastEventIdIsTheConsumedOne [
	| source |
	self eventStream: (self text: #( 'id: 1' 'data: a' '' 'id: 2' 'data: b' '' 'id: 3' 'data: c' '' )).
	source := self source: 'consumed'.
	self assert: source next data equals: 'a'.
	self assert: source lastEventId equals: '1'.
	self assert: source parser lastEventId equals: '3'.
	source close.
	self assert: source lastEventId equals: '1'.
	self assert: source next isNil.
	self eventStream: (self text: #( 'id: 1' 'data: a' '' 'id: 2' 'data: b' '' 'id: 3' 'data: c' '' 'id: 4' '' )).
	host enqueuePending.
	source := self source: 'consumed2'.
	self assert: source next lastEventId equals: '1'.
	self assert: source next lastEventId equals: '2'.
	self assert: source next lastEventId equals: '3'.
	self assert: source lastEventId equals: '4'.
	self assert: (source nextTimeout: 0.1 seconds) isNil.
	self assert: (self header: 'Last-Event-ID' of: host requests last) equals: '4'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testNetworkOff [
	| source |
	host enqueuePending.
	source := self source: 'off'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self assert: source isOpen.
	host networkOff.
	self should: [ source next ] raise: WebFetchNetworkOff.
	self assert: source isClosed.
	self assert: host requests size equals: 1.
	"off during the reconnection wait"
	host availability: 1.
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'off2') reconnectDelay: 100 milliSeconds; yourself.
	self assert: source next data equals: 'a'.
	host networkOff.
	self should: [ source next ] raise: WebFetchNetworkOff.
	self assert: host requests size equals: 2.
	self assert: source isClosed
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testNextTimeout [
	| source start |
	host enqueuePending.
	source := self source: 'nt'.
	self assert: (source nextTimeout: 50 milliSeconds) isNil.
	self deliverHead.
	start := Time microsecondClockValue.
	self assert: (source nextTimeout: 50 milliSeconds) isNil.
	self assert: Time microsecondClockValue - start >= 45000.
	self assert: source isOpen.
	self deny: source isClosed.
	self push: (self text: #( 'data: x' '' )).
	self assert: source next data equals: 'x'.
	source close.
	"in a reconnection wait, which is not restarted"
	self eventStream: (self text: #( 'data: a' '' )).
	self eventStream: (self text: #( 'data: b' '' )).
	source := (self source: 'nt2') reconnectDelay: 400 milliSeconds; yourself.
	self assert: source next data equals: 'a'.
	self assert: (source nextTimeout: 200 milliSeconds) isNil.
	self assert: host requests size equals: 2.
	start := Time millisecondClockValue.
	self assert: source next data equals: 'b'.
	self assert: Time millisecondClockValue - start < 300.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testNextTimeoutZero [
	| source start id check |
	host enqueuePending.
	source := (self source: 'zero') reconnectDelay: 10 seconds; yourself.
	check := [
		start := Time millisecondClockValue.
		self assert: (source nextTimeout: 0 seconds) isNil.
		self assert: Time millisecondClockValue - start < 50.
		self inCallback: [ self assert: (source nextTimeout: 0 seconds) isNil ] ].
	"pending"
	check value.
	self assert: host requests size equals: 1.
	check value.
	id := host lastId.
	self deliverHead.
	"open and silent"
	check value.
	self assert: source isOpen.
	check value.
	"in the reconnection wait"
	host finish: id.
	check value.
	self assert: source readyState equals: #connecting.
	check value.
	self assert: host requests size equals: 1.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testNoStoreFallback [
	| source record starts |
	host maximumFlags: 1.
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'old') reconnects: false; yourself.
	self assert: source next data equals: 'a'.
	self assert: host requests size equals: 1.
	record := host requests first.
	self assert: (record at: #flags) equals: 0.
	self assert: (self header: 'Cache-Control' of: record) equals: 'no-cache'.
	"a second source on that host starts with flags 0 at once"
	starts := self startTimes.
	self eventStream: (self text: #( 'data: b' '' )).
	source := (self sourceOf: ((WebFetch request: 'http://example.test/old2') headerAt: 'Cache-Control' put: 'max-age=0'; yourself))
		reconnects: false;
		yourself.
	self assert: source next data equals: 'b'.
	self assert: starts size equals: 1.
	self assert: (host requests last at: #flags) equals: 0.
	self assert: (self headers: 'Cache-Control' of: host requests last) size equals: 1.
	self assert: (self header: 'Cache-Control' of: host requests last) equals: 'max-age=0'.
	"another host starts with flag 2"
	host := WebFetchTestHost new.
	WebFetchHost default: host.
	self eventStream: (self text: #( 'data: c' '' )).
	source := (self source: 'new') reconnects: false; yourself.
	self assert: source next data equals: 'c'.
	self assert: (host requests first at: #flags) equals: 2.
	self assert: (self header: 'Cache-Control' of: host requests first) isNil.
	sources do: [ :each | each close ]
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testPostDoesNotReconnectByDefault [
	| request source |
	request := (WebFetch request: 'http://example.test/post')
		method: #POST;
		body: '{"stream":true}';
		yourself.
	self eventStream: (self text: #( 'data: a' '' )).
	source := self sourceOf: request.
	self assert: source next data equals: 'a'.
	self assert: source next isNil.
	self assert: source isClosed.
	self assert: source error isNil.
	self assert: host requests size equals: 1.
	self assert: (host requests first at: #method) equals: 'POST'.
	self assert: (host requests first at: #body) equals: '{"stream":true}' utf8Encoded.
	self eventStream: (self text: #( 'data: a' '' )).
	self eventStream: (self text: #( 'data: b' '' )).
	host enqueuePending.
	source := (self sourceOf: request) reconnects: true; yourself.
	self assert: source next data equals: 'a'.
	self assert: source next data equals: 'b'.
	self assert: host requests size equals: 3.
	self assert: ((host requests at: 3) at: #method) equals: 'POST'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testReconnectAfterBodyError [
	| source id item |
	host enqueuePending.
	self eventStream: (self text: #( 'data: b' '' )).
	source := self source: 'broken'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	id := host lastId.
	self deliverHead.
	self push: (self text: #( 'id: 1' 'data: a' '' )).
	self assert: source next data equals: 'a'.
	self assert: (host stateOf: id) >> 3 equals: 0.
	host fail: id kind: #body message: 'the body broke'.
	item := source nextItemBefore: nil.
	self assert: item key equals: #reconnect.
	self assert: (item value isKindOf: WebFetchNetworkError).
	self assert: item value kind equals: #body.
	item := source nextItemBefore: nil.
	self assert: item key equals: #open.
	item := source nextItemBefore: nil.
	self assert: item data equals: 'b'.
	self assert: (self header: 'Last-Event-ID' of: host requests second) equals: '1'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testReconnectAtEndSendsLastEventId [
	| source items |
	self eventStream: (self text: #( 'id: 7' 'data: a' '' )).
	self eventStream: (self text: #( 'data: b' '' )).
	host enqueuePending.
	source := self source: 'end'.
	items := OrderedCollection new.
	[ items size < 6 ] whileTrue: [ items add: (source nextItemBefore: nil) ].
	self assert: items first key equals: #open.
	self assert: (items at: 2) data equals: 'a'.
	self assert: (items at: 3) equals: #reconnect -> nil.
	self assert: (items at: 4) key equals: #open.
	self assert: (items at: 5) data equals: 'b'.
	self assert: (items at: 5) lastEventId equals: '7'.
	self assert: (items at: 6) equals: #reconnect -> nil.
	self assert: (self header: 'Last-Event-ID' of: host requests first) isNil.
	self assert: (self header: 'Last-Event-ID' of: host requests second) equals: '7'.
	self assert: (source nextTimeout: 0.1 seconds) isNil.
	self assert: (self header: 'Last-Event-ID' of: (host requests at: 3)) equals: '7'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testReconnectsFalse [
	| source |
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'once') reconnects: false; yourself.
	self assert: source next data equals: 'a'.
	self assert: source next isNil.
	self assert: source next isNil.
	self assert: source error isNil.
	self assert: source isClosed.
	self assert: host requests size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testReconnectsFalseBrokenBodySignals [
	| source id |
	host enqueuePending.
	source := (self source: 'oncebroken') reconnects: false; yourself.
	self assert: (source nextTimeout: 0 seconds) isNil.
	id := host lastId.
	self deliverHead.
	self push: (self text: #( 'data: a' '' 'data: b' '' )).
	self assert: source next data equals: 'a'.
	self assert: (host stateOf: id) >> 3 equals: 0.
	host fail: id kind: #body message: 'the body broke'.
	self assert: source next data equals: 'b'.
	self should: [ source next ] raise: WebFetchNetworkError.
	self assert: source isClosed.
	self assert: host requests size equals: 1
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRefusalAfterReconnect [
	| source |
	self eventStream: (self text: #( 'data: a' '' )).
	host enqueueStatus: 204 headers: #( ) body: nil.
	source := self source: 'stop'.
	self assert: source next data equals: 'a'.
	self
		should: [ source next ]
		raise: WebFetchBadResponse
		withExceptionDo: [ :error | self assert: error response status equals: 204 ].
	self assert: source isClosed.
	self assert: host requests size equals: 2.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRefusalHonoursNextTimeout [
	| source start |
	host enqueuePending.
	source := self source: 'refusal0'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self deliverHead: 500 type: 'application/json'.
	self push: '{"error":'.
	start := Time millisecondClockValue.
	self
		should: [ source nextTimeout: 0 seconds ]
		raise: WebFetchBadResponse
		withExceptionDo: [ :error |
			self assert: error response status equals: 500.
			self assert: error response rawContents equals: '{"error":' utf8Encoded.
			self assert: error messageText equals: 'answer status 500, not 200' ].
	self assert: Time millisecondClockValue - start < 50.
	self assert: host openCount equals: 0.
	host enqueuePending.
	source := self source: 'refusal1'.
	[
		self waitUntil: [ host requests size = 2 ].
		self deliverHead: 500 type: 'text/plain'.
		self push: 'not yet' ] fork.
	start := Time millisecondClockValue.
	self
		should: [ source nextTimeout: 0.1 seconds ]
		raise: WebFetchBadResponse
		withExceptionDo: [ :error | self assert: error response rawContents equals: 'not yet' utf8Encoded ].
	self assert: Time millisecondClockValue - start < 200.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRefusals [
	| refuse source |
	refuse := [ :status :type :body |
		| before |
		before := host requests size.
		host enqueueStatus: status headers: { 'Content-Type' -> type } body: body.
		source := self source: 'refusal' , status printString.
		self
			should: [ source next ]
			raise: WebFetchBadResponse
			withExceptionDo: [ :error |
				self assert: error kind equals: #response.
				self assert: error response status equals: status.
				self assert: error response rawContents equals: body utf8Encoded ].
		self assert: source isClosed.
		self should: [ source nextTimeout: 0 seconds ] raise: WebFetchBadResponse.
		self assert: host requests size equals: before + 1 ].
	refuse value: 500 value: 'application/json' value: '{"error":"status 500"}'.
	refuse value: 204 value: 'text/event-stream' value: ''.
	refuse value: 301 value: 'text/event-stream' value: ''.
	refuse value: 200 value: 'text/plain' value: 'data: a' , String lf , String lf.
	refuse value: 200 value: 'text/event-streams' value: ''.
	self
		should: [ source next ]
		raise: WebFetchBadResponse
		withExceptionDo: [ :error | self assert: error messageText equals: 'answer of type text/event-streams, not text/event-stream' ].
	"the type is matched without parameters and case"
	#( 'text/event-stream;charset=UTF-8' 'TEXT/Event-Stream' ) do: [ :type |
		host enqueueStatus: 200 headers: { 'Content-Type' -> type } body: (self text: #( 'data: a' '' )).
		source := (self source: 'type') reconnects: false; yourself.
		self assert: source next data equals: 'a'.
		self assert: source next isNil ].
	"a refused body is kept to 64 KiB"
	host enqueueStatus: 500 headers: { 'Content-Type' -> 'text/plain' } body: (ByteArray new: 100 * 1024 withAll: 120).
	source := self source: 'big'.
	self
		should: [ source next ]
		raise: WebFetchBadResponse
		withExceptionDo: [ :error | self assert: error response rawContents size equals: 65536 ].
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRequestHeadersAndReuse [
	| request source |
	request := (WebFetch request: 'http://example.test/h')
		headerAt: 'Authorization' put: 'Bearer t';
		headerAt: 'Accept' put: 'application/json';
		yourself.
	source := (self sourceOf: request) lastEventId: 'x'; yourself.
	self eventStream: (self text: #( 'data: a' '' )).
	host enqueuePending.
	self assert: source next data equals: 'a'.
	self assert: (self header: 'Authorization' of: host requests first) equals: 'Bearer t'.
	self assert: (self headers: 'Accept' of: host requests first) size equals: 1.
	self assert: (self header: 'Accept' of: host requests first) equals: 'application/json'.
	self assert: (self header: 'Last-Event-ID' of: host requests first) equals: 'x'.
	self assert: request headers size equals: 2.
	source request headerAt: 'X-Late' put: '1'.
	self assert: (source nextTimeout: 0.1 seconds) isNil.
	self assert: host requests size equals: 2.
	self assert: (self header: 'X-Late' of: host requests second) isNil.
	self assert: (self header: 'Last-Event-ID' of: host requests second) equals: 'x'.
	self assert: (self header: 'Authorization' of: host requests second) equals: 'Bearer t'.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRequestTimeoutIsTheConnectTimeout [
	| source pusher events |
	host enqueuePending.
	source := self sourceOf: ((WebFetch request: 'http://example.test/rt') timeout: 0.1 seconds; yourself).
	self assert: source connectTimeout equals: 100 milliSeconds.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self assert: (host requests first at: #timeout) equals: 0.
	self deliverHead.
	pusher := [
		1 to: 3 do: [ :i |
			(Delay forMilliseconds: 100) wait.
			self push: (self text: { 'data: ' , i printString. '' }) ] ] fork.
	events := (1 to: 3) collect: [ :i | source next data ].
	self assert: events equals: #( '1' '2' '3' ).
	self assert: host requests size equals: 1.
	self assert: source isOpen.
	source close.
	self assert: (WebFetch request: 'http://example.test/rt') eventSource connectTimeout isNil.
	self assert: ((WebFetch request: 'http://example.test/rt') timeout: 0; eventSource) connectTimeout isNil
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRetriesFirstConnection [
	| source |
	host enqueueErrorKind: #network message: 'connect ECONNREFUSED'.
	host enqueueErrorKind: #tooManyOpen message: 'busy'.
	self eventStream: (self text: #( 'data: b' '' )).
	host enqueuePending.
	source := (self source: 'retries') retriesFirstConnection: true; yourself.
	self assert: source next data equals: 'b'.
	self assert: host requests size equals: 3.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testRetrySetsTheDelay [
	| source starts |
	starts := self startTimes.
	self eventStream: (self text: #( 'retry: 200' 'data: a' '' )).
	host enqueuePending.
	source := self source: 'retry'.
	self assert: source next data equals: 'a'.
	self assert: source reconnectDelay equals: 200 milliSeconds.
	self assert: (source nextTimeout: 0.5 seconds) isNil.
	self assert: starts size equals: 2.
	self assert: starts second - starts first >= 195.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testMinimumDelay [
	| source starts |
	starts := self startTimes.
	3 timesRepeat: [ self eventStream: (self text: #( 'retry: 0' 'data: a' '' )) ].
	host enqueuePending.
	source := (self source: 'floor') minimumReconnectDelay: 250 milliSeconds; yourself.
	3 timesRepeat: [ self assert: source next data equals: 'a' ].
	self assert: source reconnectDelay equals: 0 milliSeconds.
	self assert: starts size equals: 3.
	self assert: starts second - starts first >= 245.
	self assert: starts third - starts second >= 245.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testSettingsValidation [
	| source |
	source := self source: 'settings'.
	self should: [ source maximumEventSize: 0 ] raise: WebFetchBadRequest.
	self should: [ source maximumEventSize: 2147483647 ] raise: WebFetchBadRequest.
	self should: [ source reconnectDelay: -1 ] raise: WebFetchBadRequest.
	self should: [ source reconnectDelay: 'soon' ] raise: WebFetchBadRequest.
	self should: [ source maximumReconnectDelay: 0 ] raise: WebFetchBadRequest.
	self should: [ source connectTimeout: 0 ] raise: WebFetchBadRequest.
	self should: [ source idleTimeout: -1 ] raise: WebFetchBadRequest.
	self should: [ source reconnects: 1 ] raise: WebFetchBadRequest.
	self should: [ source retriesFirstConnection: nil ] raise: WebFetchBadRequest.
	self should: [ source lastEventId: 'a' , String lf ] raise: WebFetchBadRequest.
	self should: [ source lastEventId: (String with: (Character value: 0)) ] raise: WebFetchBadRequest.
	self should: [ source lastEventId: (String new: 4097 withAll: $a) ] raise: WebFetchBadRequest.
	self should: [ source lastEventId: (String new: 2049 withAll: $é) ] raise: WebFetchBadRequest.
	source lastEventId: (String new: 2048 withAll: $é).
	source
		maximumEventSize: 2147483646;
		reconnectDelay: 0;
		minimumReconnectDelay: 0.5;
		maximumReconnectDelay: 2 minutes;
		connectTimeout: 1;
		idleTimeout: nil;
		reconnects: nil.
	self assert: source minimumReconnectDelay equals: 500 milliSeconds.
	self assert: source maximumReconnectDelay equals: 2 minutes.
	self assert: source connectTimeout equals: 1 second.
	self assert: source reconnectDelay equals: 0 seconds.
	host enqueuePending.
	self assert: (source nextTimeout: 0 seconds) isNil.
	#( #reconnectDelay: #minimumReconnectDelay: #maximumReconnectDelay: #connectTimeout: #idleTimeout: #maximumEventSize: ) do: [ :selector |
		self
			should: [ source perform: selector with: 1 ]
			raise: Error
			withExceptionDo: [ :error |
				self assert: error class equals: Error.
				self assert: error messageText equals: 'set before the first connection' ] ].
	self should: [ source lastEventId: 'x' ] raise: Error.
	self should: [ source reconnects: false ] raise: Error.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testTerminateReaderCloses [
	| source process |
	host enqueuePending.
	source := self source: 'term'.
	process := [ source next ] fork.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	process terminate.
	self assert: (self waitUntil: [ host openCount = 0 ]).
	self assert: source isClosed.
	self assert: source error isNil.
	"the reconnection wait, curtailed"
	self eventStream: (self text: #( 'data: a' '' )).
	source := (self source: 'term2') reconnectDelay: 10 seconds; yourself.
	self assert: source next data equals: 'a'.
	process := [ source next ] fork.
	(Delay forMilliseconds: 30) wait.
	process terminate.
	self assert: (self waitUntil: [ source isClosed ]).
	self assert: host requests size equals: 2
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testTooLargeAfterGoodEventsInOneChunk [
	| source |
	self eventStream: (self text: { 'data: a'. ''. 'data: b'. ''. 'data: ' , (String new: 101 withAll: $x). ''. 'data: c'. '' }).
	host enqueuePending.
	source := (self source: 'large') maximumEventSize: 100; yourself.
	self assert: source next data equals: 'a'.
	self assert: source isClosed.
	self assert: source next data equals: 'b'.
	self
		should: [ source next ]
		raise: WebFetchTooLarge
		withExceptionDo: [ :error | self assert: error messageText equals: 'event data longer than 100 bytes' ].
	self should: [ source next ] raise: WebFetchTooLarge.
	self assert: host requests size equals: 1.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testTooManyOpenAtReconnect [
	| source item |
	self eventStream: (self text: #( 'data: a' '' )).
	source := self source: 'busy'.
	self assert: source next data equals: 'a'.
	host maxOpen: 0.
	item := source nextItemBefore: nil.
	self assert: item equals: #reconnect -> nil.
	item := source nextItemBefore: nil.
	self assert: item key equals: #reconnect.
	self assert: (item value isKindOf: WebFetchTooManyOpen).
	host maxOpen: 64.
	self eventStream: (self text: #( 'data: b' '' )).
	host enqueuePending.
	self assert: source next data equals: 'b'.
	self assert: host requests size equals: 2.
	source close.
	"terminal at the first connection"
	host maxOpen: 0.
	source := self source: 'busy2'.
	self should: [ source next ] raise: WebFetchTooManyOpen.
	self assert: source isClosed
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testUnwindingCloses [
	| source |
	self eventStream: (self text: #( 'data: a' '' 'data: b' '' )).
	source := self source: 'unwind'.
	self assert: (self nonLocalReturnFrom: source) data equals: 'a'.
	self assert: source isClosed.
	self assert: host openCount equals: 0.
	"an exception that unwinds a wait"
	host enqueuePending.
	source := self source: 'unwind2'.
	[ source next ] valueWithin: 50 milliSeconds onTimeout: [ ].
	self assert: source isClosed.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testUtf8LastEventId [
	| source value |
	self eventStream: (self text: #( 'id: città' 'data: a' '' )).
	host enqueuePending.
	source := self source: 'utf8id'.
	self assert: source next lastEventId equals: 'città'.
	self assert: (source nextTimeout: 0.2 seconds) isNil.
	value := self header: 'Last-Event-ID' of: host requests second.
	self assert: value equals: 'città' utf8Encoded asString.
	self assert: value last equals: (Character value: 16rA0).
	self assert: source lastEventId equals: 'città'.
	source close
]

{ #category : 'helpers' }
WebFetchEventSourceTest >> text: lines [
	^ String streamContents: [ :stream |
		lines do: [ :each | stream nextPutAll: each; lf ] ]
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testAbortAll [
	| open waiting results |
	host enqueuePending.
	open := self source: 'abort1'.
	self assert: (open nextTimeout: 0 seconds) isNil.
	self deliverHead.
	self assert: (open nextTimeout: 0 seconds) isNil.
	self eventStream: (self text: #( 'data: a' '' )).
	waiting := (self source: 'abort2') reconnectDelay: 10 seconds; yourself.
	self assert: waiting next data equals: 'a'.
	self assert: (waiting nextTimeout: 0 seconds) isNil.
	self assert: waiting readyState equals: #connecting.
	self assert: WebFetchEventSource openCount equals: 2.
	self assert: (WebFetchEventSource openSources includes: open).
	self assert: (WebFetchEventSource openSources collect: [ :each | each printString ]) asSet equals: #( 'WebFetchEventSource(#open http://example.test/abort1)' 'WebFetchEventSource(#connecting http://example.test/abort2)' ) asSet.
	results := OrderedCollection new.
	{ open. waiting } do: [ :each | [ results add: each next ] fork ].
	(Delay forMilliseconds: 20) wait.
	WebFetch abortAll.
	self assert: (self waitUntil: [ results size = 2 ]).
	self assert: (results allSatisfy: [ :each | each isNil ]).
	self assert: WebFetchEventSource openCount equals: 0.
	self assert: host openCount equals: 0.
	"WebFetchCall abortAll alone is an abort the source did not ask for"
	host enqueuePending.
	open := self source: 'abort3'.
	self assert: (open nextTimeout: 0 seconds) isNil.
	self deliverHead.
	self assert: (open nextTimeout: 0 seconds) isNil.
	WebFetchCall abortAll.
	self should: [ open next ] raise: WebFetchAborted.
	self assert: open isClosed.
	self assert: WebFetchEventSource openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testCloseAllRacesConnects [
	"30 sources connecting in their own processes while closeAll runs in a loop"

	| group done deadline |
	group := (1 to: 30) collect: [ :i | self source: 'many' , i printString ].
	done := 0.
	group do: [ :each |
		[
			each next.
			done := done + 1 ] fork ].
	deadline := Time millisecondClockValue + 2000.
	[ done < 30 and: [ Time millisecondClockValue < deadline ] ] whileTrue: [
		WebFetchEventSource closeAll.
		Processor yield ].
	self assert: done equals: 30.
	self assert: (group allSatisfy: [ :each | each isClosed ]).
	self assert: WebFetchEventSource openCount equals: 0.
	self assert: host openCount equals: 0.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testFairness [
	"A reader that always finds bytes lets a process of its priority run"

	| body total count counter counterProcess first last source ended |
	total := 104857.
	body := String new: total * 10.
	1 to: total do: [ :i |
		body replaceFrom: i - 1 * 10 + 1 to: i * 10 with: 'data: ab' , String lf , String lf startingAt: 1 ].
	self eventStream: body.
	count := 0.
	counter := 0.
	counterProcess := [
		[
			counter := counter + 1.
			Processor yield ] repeat ] forkAt: Processor activePriority.
	source := (self source: 'fair')
		reconnects: false;
		onEvent: [ :event |
			count := count + 1.
			count = 1 ifTrue: [ first := counter ].
			count = total ifTrue: [
				last := counter.
				ended signal ] ];
		yourself.
	"the test process waits once, so that no wake of its own interrupts the reader"
	ended := Semaphore new.
	[
		self start: source.
		self deny: (ended waitTimeoutMilliseconds: 20000) ] ensure: [ counterProcess terminate ].
	self assert: count equals: total.
	self assert: last - first > 10 description: (last - first) printString
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testLoopErrorGoesToOnError [
	| source errors |
	host enqueuePending.
	errors := OrderedCollection new.
	source := (self source: 'loop')
		onError: [ :error | errors add: error ];
		yourself.
	self start: source.
	self assert: (self waitUntil: [ host requests size = 1 ]).
	host onRead: [ PrimitiveFailed signal: 'primitiveFetchRead failed: x' ].
	self deliverHead.
	self push: (self text: #( 'data: a' '' )).
	self assert: (self waitUntil: [ source isClosed ]).
	self assert: (self waitUntil: [ readers first isTerminated ]).
	self assert: errors size equals: 1.
	self assert: (errors first isKindOf: PrimitiveFailed).
	self assert: source error equals: errors first.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testReaderRules [
	| source |
	host enqueuePending.
	source := self source: 'rules'.
	self start: source.
	self should: [ source next ] raise: Error withExceptionDo: [ :error | self assert: error messageText equals: 'the events of a started source go to its blocks' ].
	self should: [ source nextTimeout: 0 seconds ] raise: Error.
	self should: [ source open ] raise: Error.
	self should: [ source do: [ :event | ] ] raise: Error.
	self should: [ source start ] raise: Error withExceptionDo: [ :error | self assert: error messageText equals: 'the source is started already' ].
	self deny: source isClosed.
	source close.
	source := self source: 'rules2'.
	self assert: (source nextTimeout: 0 seconds) isNil.
	self should: [ source start ] raise: Error withExceptionDo: [ :error | self assert: error messageText equals: 'the events of this source are read with next' ].
	self assert: source process isNil.
	source close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testSessionEnded [
	"WebFetchEventSource startUp: true before WebFetchCall startUp: true, then after it"

	#( true false ) do: [ :sourcesFirst |
		| reading waiting results stale |
		host enqueuePending.
		reading := self source: 'resume1'.
		self assert: (reading nextTimeout: 0 seconds) isNil.
		self deliverHead.
		self eventStream: (self text: #( 'data: a' '' )).
		waiting := (self source: 'resume2') reconnectDelay: 10 seconds; yourself.
		self assert: waiting next data equals: 'a'.
		results := OrderedCollection new.
		{ reading. waiting } do: [ :each |
			[ results add: ([ each next ] on: WebFetchSessionEnded do: [ :e | e ]) ] fork ].
		(Delay forMilliseconds: 20) wait.
		sourcesFirst
			ifTrue: [
				WebFetchEventSource startUp: true.
				WebFetchCall startUp: true ]
			ifFalse: [
				WebFetchCall startUp: true.
				WebFetchEventSource startUp: true ].
		self assert: (self waitUntil: [ results size = 2 ]).
		self assert: (results allSatisfy: [ :each | each isKindOf: WebFetchSessionEnded ]).
		self assert: reading isClosed.
		self assert: waiting isClosed.
		self should: [ waiting next ] raise: WebFetchSessionEnded.
		self assert: WebFetchEventSource openCount equals: 0.
		self assert: host openCount equals: 0.
		"a source of another session ends at its next step"
		self eventStream: (self text: #( 'data: b' '' )).
		stale := (self source: 'resume3') reconnectDelay: 10 seconds; yourself.
		self assert: stale next data equals: 'b'.
		stale session: Object new.
		self should: [ stale nextTimeout: 0 seconds ] raise: WebFetchSessionEnded.
		self assert: stale isClosed ].
	"a new source works"
	self eventStream: (self text: #( 'data: c' '' )).
	self assert: ((self source: 'resume4') reconnects: false; next) data equals: 'c'.
	sources last close
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testStartBlocks [
	| source log errors |
	self eventStream: (self text: #( 'data: a' '' 'data: b' '' )).
	self eventStream: (self text: #( 'data: c' '' )).
	host enqueueStatus: 204 headers: #( ) body: nil.
	log := OrderedCollection new.
	source := (self source: 'blocks')
		onOpen: [ :response | log add: #open -> response status ];
		onEvent: [ :event | log add: event data ];
		onReconnect: [ :reason | log add: #reconnect -> reason ];
		onError: [ :error | log add: error ];
		yourself.
	self assert: (self start: source) name equals: 'WebFetchEventSource http://example.test/blocks'.
	self assert: source process equals: readers first.
	self assert: (self waitUntil: [ readers first isTerminated ]).
	self assert: (log first: 7) asArray equals: { #open -> 200. 'a'. 'b'. #reconnect -> nil. #open -> 200. 'c'. #reconnect -> nil }.
	self assert: log size equals: 8.
	self assert: (log last isKindOf: WebFetchBadResponse).
	self assert: log last response status equals: 204.
	self assert: source isClosed.
	"close gives no onError:"
	host enqueuePending.
	errors := OrderedCollection new.
	source := (self source: 'blocks2')
		onError: [ :error | errors add: error ];
		yourself.
	self start: source.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	source close.
	self assert: (self waitUntil: [ readers last isTerminated ]).
	self assert: errors isEmpty.
	"terminating the reader closes the source"
	host enqueuePending.
	source := self source: 'blocks3'.
	self start: source.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	readers last terminate.
	self assert: (self waitUntil: [ source isClosed ]).
	self assert: host openCount equals: 0.
	"an error of a block is the error of the block"
	self eventStream: (self text: #( 'data: a' '' )).
	errors := OrderedCollection new.
	source := (self source: 'blocks4')
		onEvent: [ :event | WebFetchBadRequest signal: 'a block' ];
		onError: [ :error | errors add: error ];
		yourself.
	self should: [ source runReader ] raise: WebFetchBadRequest.
	self assert: errors isEmpty.
	self assert: source isClosed
]

{ #category : 'tests' }
WebFetchEventSourceTest >> testStartInCallback [
	| source events |
	self eventStream: (self text: #( 'data: a' '' 'data: b' '' )).
	events := OrderedCollection new.
	source := (self source: 'startcb')
		reconnects: false;
		onEvent: [ :event | events add: event data ];
		yourself.
	self inCallback: [
		self start: source.
		self assert: events isEmpty ].
	self assert: (self waitUntil: [ source isClosed ]).
	self assert: events asArray equals: #( 'a' 'b' )
]
