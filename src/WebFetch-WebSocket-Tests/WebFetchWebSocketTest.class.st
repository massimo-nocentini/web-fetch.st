"
I test `WebFetchWebSocket` on the fake host: the open, the checks made before the host is called, the sends and their waits, the reads and the end of a socket, the close and the release, and how the failures of the host map to errors.
"
Class {
	#name : 'WebFetchWebSocketTest',
	#superclass : 'WebFetchWebSocketTestCase',
	#category : 'WebFetch-WebSocket-Tests-Tests',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Tests'
}

{ #category : 'tests' }
WebFetchWebSocketTest >> testBadUrlsAndProtocolsSignalBadRequestBeforeTheHost [
	| many |
	{ 'http://example.test/a'. 'https://example.test/a'. 'example.test/a'. 'ws://example.test/a#f'.
	'ws://user@example.test/'. 'ws://user:secret@example.test/'. 'ws://'. 'ws:///a'.
	'ws://example.test/a' , String cr. 'ws://example.test/' , String lf , 'b'.
	'ws://example.test/' , (String with: (Character value: 0)) } do: [ :each |
		self should: [ WebFetchWebSocket url: each ] raise: WebFetchBadRequest ].
	many := (1 to: 33) collect: [ :i | 'p' , i printString ].
	{ #( 'a' 'A' ). #( 'a b' ). #( '' ). #( 'a,b' ). #( 'chat' 'Chat' ). many } do: [ :each |
		self should: [ (WebFetchWebSocket url: (self urlOf: '/a')) protocols: each ] raise: WebFetchBadRequest ].
	self should: [ WebFetchWebSocket connect: (self urlOf: '/a') protocols: #( 'v1' 'V1' ) ] raise: WebFetchBadRequest.
	self assert: host hostCalls equals: 0.
	self assert: ((WebFetchWebSocket url: 'WSS://Example.test:8443/a?b=c') protocols: (many first: 32)) protocols size equals: 32
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testCloseAnswersWhetherItStartedTheHandshake [
	| ws |
	ws := self connect: '/close'.
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 2 seconds).
	self assert: ws state equals: #closed.
	self assert: ws closeCode equals: 1000.
	self assert: ws closeReason equals: ''.
	self assert: ws wasClean.
	self deny: ws close.
	self assert: host closes equals: { { self idOf: ws. 1000. nil } } asOrderedCollection.
	ws := self connect: '/reason'.
	host autoClose: false.
	self assert: (ws close: 4000 reason: 'bye, è').
	self assert: ws state equals: #closing.
	self deny: (ws close: 4001 reason: '').
	self assert: host closes last allButFirst equals: { 4000. 'bye, è' }.
	host deliverCloseTo: (self idOf: ws) code: 4000 reason: 'bye, è' clean: true.
	self assert: (ws waitForCloseTimeout: 2 seconds).
	self assert: ws closeReason equals: 'bye, è'
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testCloseArgumentsAreCheckedBeforeTheHost [
	| ws calls |
	ws := self connect: '/args'.
	calls := host hostCalls.
	{ 999. 1001. 2999. 5000. nil. '1000' } do: [ :code |
		self should: [ ws close: code reason: '' ] raise: WebFetchBadRequest ].
	self should: [ ws close: 1000 reason: (String new: 124 withAll: $x) ] raise: WebFetchBadRequest.
	self should: [ ws close: 1000 reason: (String new: 62 withAll: (Character value: 232)) ] raise: WebFetchBadRequest.
	self assert: host hostCalls equals: calls.
	self assert: host closes isEmpty.
	self assert: (ws close: 1000 reason: (String new: 123 withAll: $x)).
	self assert: (ws waitForCloseTimeout: 2 seconds)
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testCloseDuringTheHandshake [
	| ws |
	host autoOpen: false.
	ws := (WebFetchWebSocket url: (self urlOf: '/early')) start.
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 2 seconds).
	self assert: ws closeCode equals: 1006.
	self assert: ws closeReason equals: 'closed before it was open'.
	self deny: ws wasClean.
	self should: [ ws next ] raise: WebFetchWebSocketClosed
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testConnectWaitsForTheOpen [
	| box ws |
	host autoOpen: false.
	box := self background: [ WebFetchWebSocket connect: (self urlOf: '/open') ].
	self assert: (self waitUntil: [ host openCount = 1 ]).
	self settle.
	self deny: (self isDone: box).
	host deliverOpen: host lastId protocol: '' extensions: 'permessage-deflate'.
	self assert: (self waitUntil: [ self isDone: box ]).
	ws := box at: #value.
	self assert: ws isOpen.
	self assert: ws protocol equals: ''.
	self assert: ws extensions equals: 'permessage-deflate'.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testCurtailedConnectReleases [
	host autoOpen: false.
	[ WebFetchWebSocket connect: (self urlOf: '/curtailed') ] valueWithin: 50 milliSeconds onTimeout: [  ].
	self assert: host openCount equals: 0.
	self assert: host releasedCount equals: 1.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testCurtailedNextDoesNotRelease [
	| ws |
	ws := self connect: '/stay'.
	[ ws next ] valueWithin: 50 milliSeconds onTimeout: [  ].
	self assert: ws isOpen.
	self assert: host openCount equals: 1.
	host deliverText: 'after' to: (self idOf: ws).
	self assert: ws next equals: 'after'.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testDoEndsQuietlyAtACloseAndSignalsAFailure [
	| ws got |
	{ 1000 -> true. 1006 -> false } do: [ :each |
		ws := self connect: '/do'.
		got := OrderedCollection new.
		host deliverText: 'a' to: (self idOf: ws).
		host deliverBytes: #[ 1 ] to: (self idOf: ws).
		host deliverCloseTo: (self idOf: ws) code: each key reason: '' clean: each value.
		ws do: [ :message | got add: message ].
		self assert: got asArray equals: { 'a'. #[ 1 ] }.
		self assert: ws closeCode equals: each key.
		self assert: ws wasClean equals: each value ].
	ws := self connect: '/do-fail'.
	got := OrderedCollection new.
	host deliverText: 'a' to: (self idOf: ws).
	host fail: (self idOf: ws) kind: #off message: 'network access is off'.
	self should: [ ws do: [ :message | got add: message ] ] raise: WebFetchNetworkOff.
	self assert: got asArray equals: #( 'a' )
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testErrorKindsMapToTheirClasses [
	{
		#request -> WebFetchBadRequest.
		#network -> WebFetchNetworkError.
		#timeout -> WebFetchTimeout.
		#off -> WebFetchNetworkOff.
		#tooLarge -> WebFetchTooLarge.
		#overflow -> WebFetchWebSocketOverflow.
		#closed -> WebFetchWebSocketClosed } do: [ :each |
		| error |
		error := WebFetchWebSocket errorKind: each key message: 'why'.
		self assert: error class equals: each value.
		self assert: error kind equals: each key.
		self assert: error messageText equals: 'why' ].
	self assert: (WebFetchWebSocketOverflow inheritsFrom: WebFetchTooLarge).
	self assert: (WebFetchWebSocketClosed inheritsFrom: WebFetchError)
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testFailedHandshakeSignalsItsError [
	| box |
	{
		#network -> WebFetchNetworkError.
		#request -> WebFetchBadRequest.
		#off -> WebFetchNetworkOff } do: [ :each |
		host autoOpen: false.
		box := self background: [ WebFetchWebSocket connect: (self urlOf: '/fail') ].
		self assert: (self waitUntil: [ host openCount = 1 ]).
		host fail: host lastId kind: each key message: 'the handshake failed'.
		self assert: (self waitUntil: [ self isDone: box ]).
		self assert: (self errorOf: box) equals: each value.
		self assert: (box at: #error) messageText equals: 'the handshake failed'.
		self assert: host openCount equals: 0 ]
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testFailureCodesOfThePrimitives [
	| real |
	real := WebFetchWebSocketHost new.
	host availability: 2.
	self should: [ host openFailed: #'unsupported operation' ] raise: WebFetchNetworkOff.
	host availability: 0.
	self should: [ host openFailed: #'unsupported operation' ] raise: WebFetchUnavailable.
	self
		should: [ real openFailed: #'resource limit exceeded' ]
		raise: WebFetchTooManyOpen
		whoseDescriptionIncludes: 'limit 32'
		description: 'the limit'.
	self should: [ real openFailed: #'bad argument' ] raise: WebFetchBadRequest.
	self should: [ real openFailed: #'insufficient C memory' ] raise: OutOfMemory.
	self should: [ real openFailed: #'not found' ] raise: WebFetchUnavailable.
	self should: [ real openFailed: nil ] raise: WebFetchUnavailable.
	self should: [ real queryFailed: #'not found' operation: 'x' ] raise: WebFetchSessionEnded.
	self assert: (real queryFailed: #'insufficient object memory' operation: 'x') equals: #noMemory.
	self should: [ real queryFailed: #'bad argument' operation: 'x' ] raise: PrimitiveFailed.
	self assert: (real sendFailed: #'resource limit exceeded') equals: #full.
	self assert: (real sendFailed: #'inappropriate operation') equals: #notOpen.
	self should: [ real sendFailed: #'bad argument' ] raise: WebFetchBadRequest.
	self should: [ real sendFailed: #'insufficient C memory' ] raise: OutOfMemory.
	self should: [ real sendFailed: #'not found' ] raise: WebFetchSessionEnded.
	self should: [ real closeFailed: #'bad argument' ] raise: WebFetchBadRequest.
	self should: [ real closeFailed: #'not found' ] raise: WebFetchSessionEnded
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testFailureKeepsTheQueue [
	{
		#overflow -> WebFetchWebSocketOverflow.
		#off -> WebFetchNetworkOff.
		#tooLarge -> WebFetchTooLarge.
		#network -> WebFetchNetworkError } do: [ :each |
		| ws |
		ws := self connect: '/fail-' , each key.
		host deliverText: 'one' to: (self idOf: ws).
		host deliverText: 'two' to: (self idOf: ws).
		host fail: (self idOf: ws) kind: each key message: 'why'.
		self assert: ws next equals: 'one'.
		self assert: ws state equals: #failed.
		self assert: host openCount equals: 0.
		self assert: ws queuedCount equals: 1.
		self deny: ws atEnd.
		self assert: ws next equals: 'two'.
		self assert: ws atEnd.
		self should: [ ws next ] raise: each value.
		self assert: ws error class equals: each value.
		self assert: ws error kind equals: each key ]
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testFlushTimeout [
	| ws box |
	ws := self connect: '/flush'.
	self assert: (ws flushTimeout: 1 second).
	host buffered: 100 for: (self idOf: ws).
	self assert: ws bufferedAmount equals: 100.
	self deny: (ws flushTimeout: 30 milliSeconds).
	box := self background: [ ws flushTimeout: 2 seconds ].
	self settle.
	host drain: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (box at: #value).
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testHandshakeTimeoutOfTheHost [
	| box |
	host autoOpen: false.
	box := self background: [
		(WebFetchWebSocket url: (self urlOf: '/slow'))
			timeout: 1 second;
			connect ].
	self assert: (self waitUntil: [ host openCount = 1 ]).
	self assert: (host lastOpen at: #timeout) equals: 1000.
	host fail: host lastId kind: #timeout message: 'not open within 1000 ms'.
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (self errorOf: box) equals: WebFetchTimeout.
	self assert: host openCount equals: 0.
	self assert: host releasedCount equals: 1
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testInsufficientMemoryTwiceDropsTheMessage [
	| ws |
	ws := (WebFetchWebSocket url: (self urlOf: '/memory'))
		maximumMessageSize: 1024;
		connect.
	#( 'a' 'b' 'c' ) do: [ :each | host deliverText: each to: (self idOf: ws) ].
	self assert: ws next equals: 'a'.
	host failReceives: 2 with: #'insufficient object memory'.
	self assert: ws next equals: 'c'.
	self assert: host drops equals: { { self idOf: ws. 1 } } asOrderedCollection.
	self assert: host closes last allButFirst equals: { 4009. 'message too large' }.
	self should: [ ws next ] raise: WebFetchTooLarge.
	ws := (WebFetchWebSocket url: (self urlOf: '/memory-once'))
		maximumMessageSize: 1024;
		connect.
	host deliverText: 'kept' to: (self idOf: ws).
	host failReceives: 1 with: #'insufficient object memory'.
	self assert: ws next equals: 'kept'.
	self assert: ws isOpen.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testLimitsAreCheckedWhenSet [
	| ws |
	ws := WebFetchWebSocket url: (self urlOf: '/limits').
	{ 0. -1. (1 bitShift: 30) + 1. nil. '1' } do: [ :each |
		self should: [ ws maximumMessageSize: each ] raise: WebFetchBadRequest.
		self should: [ ws maximumQueuedBytes: each ] raise: WebFetchBadRequest ].
	self should: [ ws timeout: -1 second ] raise: WebFetchBadRequest.
	self should: [ ws timeout: 'soon' ] raise: WebFetchBadRequest.
	ws
		maximumMessageSize: (1 bitShift: 30);
		maximumQueuedBytes: 1;
		timeout: Duration zero.
	self assert: ws timeout equals: nil.
	ws timeout: 2.5.
	self assert: ws timeout equals: 2500 milliSeconds.
	ws start.
	self assert: (host lastOpen at: #maxMessage) equals: (1 bitShift: 30).
	self assert: (host lastOpen at: #maxQueued) equals: 1.
	self assert: (host lastOpen at: #timeout) equals: 2500.
	self should: [ ws protocols: #( 'late' ) ] raise: WebFetchBadRequest.
	self should: [ ws timeout: nil ] raise: WebFetchBadRequest.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testMessagesOfTheServerAfterItsClose [
	| ws error |
	ws := self connect: '/push'.
	host deliverText: 'one' to: (self idOf: ws).
	host deliverBytes: #[ 1 2 ] to: (self idOf: ws).
	host deliverCloseTo: (self idOf: ws) code: 4321 reason: 'bye' clean: true.
	self assert: ws state equals: #closed.
	self assert: host openCount equals: 0.
	self assert: host releasedCount equals: 1.
	self assert: ws queuedCount equals: 2.
	self assert: ws next equals: 'one'.
	self assert: ws next equals: #[ 1 2 ].
	error := [ ws next. nil ] on: WebFetchWebSocketClosed do: [ :e | e ].
	self assert: error code equals: 4321.
	self assert: error reason equals: 'bye'.
	self assert: error wasClean.
	self assert: ws closeCode equals: 4321.
	self assert: ws closeReason equals: 'bye'.
	self assert: ws isOver.
	self assert: ws atEnd.
	self assert: ws nextOrNil equals: nil
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testNextOrNilNeverWaits [
	| ws |
	host autoOpen: false.
	ws := (WebFetchWebSocket url: (self urlOf: '/poll')) start.
	self assert: ws nextOrNil equals: nil.
	host deliverOpen: (self idOf: ws).
	self assert: ws nextOrNil equals: nil.
	host deliverText: 'x' to: (self idOf: ws).
	self assert: ws nextOrNil equals: 'x'.
	self assert: ws nextOrNil equals: nil.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testNextRawAnswersTheBytesOfText [
	| ws text |
	ws := self connect: '/raw'.
	text := 'è ' , (String with: (Character value: 8364)).
	host deliverText: text to: (self idOf: ws).
	host deliverBytes: #[ 7 ] to: (self idOf: ws).
	self assert: ws nextRaw equals: { true. text utf8Encoded }.
	self assert: ws nextRaw equals: { false. #[ 7 ] }.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testNextTimeoutAnswersNil [
	| ws box |
	ws := self connect: '/timeout'.
	self assert: (ws nextTimeout: 30 milliSeconds) equals: nil.
	self assert: (ws nextTimeout: 0) equals: nil.
	box := self background: [ ws nextTimeout: 2 seconds ].
	self settle.
	host deliverText: 'late' to: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (box at: #value) equals: 'late'.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testNextWaitsAlsoWhileConnecting [
	| ws box |
	host autoOpen: false.
	ws := (WebFetchWebSocket url: (self urlOf: '/wait')) start.
	box := self background: [ ws next ].
	self settle.
	host deliverOpen: (self idOf: ws).
	self settle.
	self deny: (self isDone: box).
	host deliverText: 'hi' to: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (box at: #value) equals: 'hi'.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testNotStartedSocket [
	| ws |
	ws := WebFetchWebSocket url: (self urlOf: '/new').
	self assert: ws state equals: #new.
	self should: [ ws next ] raise: Error.
	self should: [ ws sendText: 'x' ] raise: Error.
	self deny: ws close.
	self assert: ws bufferedAmount equals: 0.
	self assert: host hostCalls equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testOpenRecordHoldsTheUrlAndTheProtocols [
	| ws open |
	ws := WebFetchWebSocket connect: (self urlOf: '/chat?room=è') protocols: #( 'v2.chat' 'v1.chat' ).
	open := host lastOpen.
	self assert: (open at: #url) equals: (self urlOf: '/chat?room=è').
	self assert: (open at: #protocols) equals: #( 'v2.chat' 'v1.chat' ).
	self assert: (open at: #maxMessage) equals: 16 * 1024 * 1024.
	self assert: (open at: #maxQueued) equals: 16 * 1024 * 1024.
	self assert: (open at: #timeout) equals: 30000.
	self assert: (open at: #indexes) asSet size equals: 3.
	self assert: ws protocol equals: 'v2.chat'.
	self assert: ws url equals: (self urlOf: '/chat?room=è').
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testReleaseWakesAWaiterWithAborted [
	| ws box |
	ws := self connect: '/release'.
	host deliverText: 'lost' to: (self idOf: ws).
	self assert: ws queuedCount equals: 1.
	box := self background: [ ws next. ws next ].
	self settle.
	ws release.
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (self errorOf: box) equals: WebFetchAborted.
	self assert: ws state equals: #failed.
	self assert: host openCount equals: 0.
	self should: [ ws sendText: 'x' ] raise: WebFetchAborted
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendAfterTheCloseOfTheServerSignalsClosed [
	| ws |
	ws := self connect: '/closing'.
	host readyStateClosing: (self idOf: ws).
	self should: [ ws sendText: 'x' ] raise: WebFetchWebSocketClosed.
	self assert: ws state equals: #closing.
	self assert: host sent isEmpty.
	host deliverCloseTo: (self idOf: ws) code: 1000 reason: '' clean: true.
	self should: [ ws sendBytes: #[ 1 ] ] raise: WebFetchWebSocketClosed
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendLargerThan64MiBSignalsTooLarge [
	| ws |
	ws := self connect: '/big'.
	self should: [ ws sendBytes: (ByteArray new: 64 * 1024 * 1024 + 1) ] raise: WebFetchTooLarge.
	self assert: ws isOpen.
	self assert: host sent isEmpty.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendOnAFullBufferTimesOut [
	| ws |
	ws := (WebFetchWebSocket url: (self urlOf: '/full'))
		timeout: 100 milliSeconds;
		connect.
	host buffered: 16 * 1024 * 1024 for: (self idOf: ws).
	self should: [ ws sendText: 'x' ] raise: WebFetchTimeout.
	self assert: ws isOpen.
	self assert: host sent isEmpty.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendOnAFullBufferWaitsForRoom [
	| ws box |
	ws := self connect: '/room'.
	host buffered: 16 * 1024 * 1024 for: (self idOf: ws).
	box := self background: [ ws sendText: 'x' ].
	self settle.
	self deny: (self isDone: box).
	host drain: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (self errorOf: box) equals: nil.
	self assert: host sent size equals: 1.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendTextAndBytes [
	| ws id |
	ws := self connect: '/send'.
	id := self idOf: ws.
	ws sendText: 'ciao, è'.
	ws sendBytes: #[ 1 2 3 ].
	ws send: 'text'.
	ws send: #[ 4 ].
	ws sendText: (String with: (Character value: 16rFEFF)) , 'a'.
	self
		assert: host sent asArray
		equals: {
			{ id. true. 'ciao, è' utf8Encoded }.
			{ id. false. #[ 1 2 3 ] }.
			{ id. true. 'text' utf8Encoded }.
			{ id. false. #[ 4 ] }.
			{ id. true. #[ 16rEF 16rBB 16rBF 97 ] } }.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testSendWhileConnectingWaitsForTheOpen [
	| ws box |
	host autoOpen: false.
	ws := (WebFetchWebSocket url: (self urlOf: '/early-send')) start.
	box := self background: [ ws sendText: 'early' ].
	self settle.
	self deny: (self isDone: box).
	self assert: host sent isEmpty.
	host deliverOpen: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (self errorOf: box) equals: nil.
	self assert: host sent size equals: 1.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testStates [
	| ws |
	host autoOpen: false.
	host autoClose: false.
	ws := WebFetchWebSocket url: (self urlOf: '/states').
	self assert: ws state equals: #new.
	ws start.
	self assert: ws state equals: #connecting.
	self deny: ws isOpen.
	host deliverOpen: (self idOf: ws).
	self assert: ws state equals: #open.
	self assert: ws isOpen.
	ws close.
	self assert: ws state equals: #closing.
	self deny: ws isOver.
	host deliverCloseTo: (self idOf: ws) code: 1000 reason: '' clean: true.
	self assert: ws state equals: #closed.
	self assert: ws isOver.
	self assert: ws error equals: nil
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testTextIsAStringAndBinaryAByteArray [
	| ws wide |
	ws := self connect: '/types'.
	wide := 'costa ' , (String with: (Character value: 8364)).
	host deliverText: 'è' to: (self idOf: ws).
	host deliverText: wide to: (self idOf: ws).
	host deliverText: '' to: (self idOf: ws).
	host deliverBytes: #[  ] to: (self idOf: ws).
	host deliverBytes: #[ 0 255 ] to: (self idOf: ws).
	self assert: ws next equals: 'è'.
	self assert: ws next equals: wide.
	self assert: ws next equals: ''.
	self assert: ws next equals: #[  ].
	self assert: ws next equals: #[ 0 255 ].
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testWaitForOpenTimeoutDoesNotRelease [
	| ws |
	host autoOpen: false.
	ws := (WebFetchWebSocket url: (self urlOf: '/hang')) start.
	self deny: (ws waitForOpenTimeout: 30 milliSeconds).
	self assert: ws state equals: #connecting.
	self assert: host openCount equals: 1.
	host deliverOpen: (self idOf: ws).
	self assert: (ws waitForOpenTimeout: 1 second).
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketTest >> testWhenMessageWhenClosed [
	| ws got ended process |
	ws := self connect: '/reader'.
	got := OrderedCollection new.
	process := ws
		whenMessage: [ :message | got add: message ]
		whenClosed: [ :socket | ended := socket ].
	self assert: process name equals: 'WebFetchWebSocket reader'.
	#( 'a' 'b' 'c' ) do: [ :each | host deliverText: each to: (self idOf: ws) ].
	host deliverCloseTo: (self idOf: ws) code: 1000 reason: '' clean: true.
	self assert: (self waitUntil: [ ended notNil ]).
	self assert: got asArray equals: #( 'a' 'b' 'c' ).
	self assert: ended identicalTo: ws.
	self assert: ended error equals: nil.
	self assert: (self waitUntil: [ process isTerminated ]).
	ws := self connect: '/reader-fail'.
	ended := nil.
	ws whenMessage: [ :message | ] whenClosed: [ :socket | ended := socket ].
	host fail: (self idOf: ws) kind: #overflow message: 'full'.
	self assert: (self waitUntil: [ ended notNil ]).
	self assert: ended error class equals: WebFetchWebSocketOverflow
]
