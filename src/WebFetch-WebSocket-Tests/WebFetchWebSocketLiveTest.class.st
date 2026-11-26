"
I test `WebFetchWebSocket` against the WebSocket endpoints of the local test server of the VM (`tests/wasm/lib/fetch-http.mjs`, whose `lib/ws-server.mjs` has them) when `WebFetchWebSocket isAvailable` and `self class server` (defaulting to `WEB_FETCH_SERVER` in the environment) is set. The handshake that never ends goes to the second listener of the server, on `self class hangPort` (`WEB_FETCH_HANG_PORT`); without it that test skips.

What the server got (the close codes, the pongs) is read from its `/_stats`, with `WebFetch`: each test tags the URLs of its sockets.
"
Class {
	#name : 'WebFetchWebSocketLiveTest',
	#superclass : 'TestCase',
	#instVars : [
		'tag'
	],
	#classVars : [
		'HangPort',
		'Server'
	],
	#category : 'WebFetch-WebSocket-Tests-Live',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Live'
}

{ #category : 'accessing' }
WebFetchWebSocketLiveTest class >> defaultTimeLimit [
	^ 60 seconds
]

{ #category : 'accessing' }
WebFetchWebSocketLiveTest class >> hangPort [
	"The port of the listener of the server that never answers, or nil"

	HangPort ifNotNil: [ ^ HangPort ].
	^ (OSEnvironment current at: 'WEB_FETCH_HANG_PORT' ifAbsent: [ nil ]) ifNotNil: [ :port | port asInteger ]
]

{ #category : 'accessing' }
WebFetchWebSocketLiveTest class >> hangPort: anIntegerOrNil [
	HangPort := anIntegerOrNil
]

{ #category : 'accessing' }
WebFetchWebSocketLiveTest class >> server [
	"Base URL of the live test server (e.g. http://127.0.0.1:12345), or nil"

	Server ifNotNil: [ ^ Server ].
	^ OSEnvironment current at: 'WEB_FETCH_SERVER' ifAbsent: [ nil ]
]

{ #category : 'accessing' }
WebFetchWebSocketLiveTest class >> server: aUrlStringOrNil [
	Server := aUrlStringOrNil
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> connect: path [
	^ WebFetchWebSocket connect: (self urlOf: path)
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> endedEntryFor: aTag [
	"The entry of the log of the server for the connection tagged aTag once it ended (at most 6 s)"

	| deadline entry |
	deadline := Time millisecondClockValue + 6000.
	[
		entry := (self logFor: aTag) detect: [ :each | each at: 'ended' ] ifNone: [ nil ].
		entry isNil and: [ Time millisecondClockValue < deadline ] ] whileTrue: [ (Delay forMilliseconds: 50) wait ].
	self assert: entry notNil description: 'the server saw the connection ' , aTag , ' end'.
	^ entry
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> httpBase [
	WebFetchWebSocket isAvailable ifFalse: [ ^ self skip: 'WebFetchWebSocket is not available' ].
	^ self class server ifNil: [ self skip: 'WEB_FETCH_SERVER is not set' ]
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> logFor: aTag [
	"The connections of the log of the server whose URL has aTag"

	^ (STONJSON fromString: (WebFetch get: self httpBase , '/_stats?tag=' , aTag) contents) at: 'ws'
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> newTag [
	"A tag for the URLs of one connection: the microseconds of the UTC clock make it new at each run (millisecondClockValue counts from the start of the VM, so two runs on one server met at the same values), and the last hyphen keeps a tag from matching the start of a longer one"

	^ 't' , (tag := tag + 1) printString , '-' , testSelector , '-' , Time microsecondClockValue printString , '-'
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> pattern: size [
	^ (ByteArray new: size) collectWithIndex: [ :each :i | (i - 1) bitAnd: 255 ]
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> serverHost [
	"The host of the server's URL: in a browser it is not of the site's domain (a page served from
	 127.0.0.1 reaches the server as localhost), which the host refuses"

	^ self httpBase asUrl host
]

{ #category : 'running' }
WebFetchWebSocketLiveTest >> setUp [
	super setUp.
	tag := 0
]

{ #category : 'running' }
WebFetchWebSocketLiveTest >> tearDown [
	WebFetchWebSocket isAvailable ifTrue: [ WebFetchWebSocket closeAll ].
	super tearDown
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testABroadcastReachesTwoSockets [
	| room first second |
	room := self newTag.
	first := self connect: '/ws/broadcast?room=' , room.
	second := self connect: '/ws/broadcast?room=' , room.
	first sendText: 'to the room'.
	self assert: (first nextTimeout: 5 seconds) equals: 'to the room'.
	self assert: (second nextTimeout: 5 seconds) equals: 'to the room'.
	first close.
	second close.
	self assert: (first waitForCloseTimeout: 5 seconds).
	self assert: (second waitForCloseTimeout: 5 seconds)
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testAnAbruptEndIsAnUncleanClose [
	| ws |
	ws := self connect: '/ws/push?n=2&close=none&t=' , self newTag.
	self assert: (ws nextTimeout: 5 seconds) equals: '1'.
	ws := self connect: '/ws/close?abrupt=1&after=100&t=' , self newTag.
	self assert: (ws waitForCloseTimeout: 5 seconds).
	self assert: ws state equals: #closed.
	self assert: ws closeCode equals: 1006.
	self deny: ws wasClean.
	self should: [ ws next ] raise: WebFetchWebSocketClosed.
	WebFetchWebSocket closeAll
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testBackPressureOfASlowReader [
	"A server that does not read for 2 s: bufferedAmount grows, a send waits for room, and all goes once it reads"

	| ws chunk most sends |
	ws := self connect: '/ws/slow-read?resume=2000&t=' , self newTag.
	chunk := self pattern: 4 * 1024 * 1024.
	most := 0.
	sends := 0.
	8 timesRepeat: [
		ws sendBytes: chunk.
		sends := sends + 1.
		most := most max: ws bufferedAmount ].
	self assert: sends equals: 8.
	self assert: most > 0.
	self assert: (ws flushTimeout: 20 seconds).
	self assert: ws bufferedAmount equals: 0.
	self assert: ws close
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testCloseAgainstADeafServerEndsUncleanly [
	| ws started |
	ws := self connect: '/ws/deaf?t=' , self newTag.
	started := Time millisecondClockValue.
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 8 seconds).
	self assert: Time millisecondClockValue - started < 7000.
	self assert: ws closeCode equals: 1006.
	self assert: ws closeReason equals: 'closing handshake timed out'.
	self deny: ws wasClean
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testCloseCodesThatTheServerGot [
	| tags entry ws |
	tags := (1 to: 3) collect: [ :i | self newTag ].
	ws := self connect: '/ws/echo?t=' , (tags at: 1).
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 5 seconds).
	self assert: ws closeCode equals: 1000.
	self assert: ws wasClean.
	ws := self connect: '/ws/echo?t=' , (tags at: 2).
	self assert: (ws close: 4321 reason: 'bye, è').
	self assert: (ws waitForCloseTimeout: 5 seconds).
	self assert: ws closeCode equals: 4321.
	self assert: ws closeReason equals: 'bye, è'.
	ws := self connect: '/ws/echo?t=' , (tags at: 3).
	ws release.
	entry := self endedEntryFor: (tags at: 1).
	self assert: (entry at: 'code') equals: 1000.
	entry := self endedEntryFor: (tags at: 2).
	self assert: (entry at: 'code') equals: 4321.
	self assert: (entry at: 'reason') equals: 'bye, è'.
	entry := self endedEntryFor: (tags at: 3).
	self assert: (entry at: 'code') equals: 1000.
	self assert: (entry at: 'reason') equals: 'released'.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testCloseOfTheServerWithItsCode [
	| ws error |
	ws := self connect: '/ws/close?code=4321&reason=bye&t=' , self newTag.
	error := [ ws next. nil ] on: WebFetchWebSocketClosed do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 4321.
	self assert: error reason equals: 'bye'.
	self assert: error wasClean.
	self assert: ws closeCode equals: 4321.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testEchoOfTextAndBinary [
	| ws wide |
	ws := self connect: '/ws/echo?t=' , self newTag.
	wide := 'ciao, è ' , (String with: (Character value: 8364) with: (Character value: 16r1F600)).
	{ 'café'. ''. wide. String new: 70000 withAll: $x } do: [ :each |
		ws sendText: each.
		self assert: (ws nextTimeout: 10 seconds) equals: each ].
	{ #[  ]. #[ 0 255 1 ]. self pattern: 1024 * 1024. self pattern: 4 * 1024 * 1024 } do: [ :each |
		ws sendBytes: each.
		self assert: (ws nextTimeout: 10 seconds) equals: each ].
	ws sendText: 'raw è'.
	self assert: (ws nextTimeout: 10 seconds) equals: 'raw è'.
	ws sendText: 'raw è'.
	self assert: ws nextRaw equals: { true. 'raw è' utf8Encoded }.
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 5 seconds).
	self assert: ws wasClean.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testFloodOverTheQueueIsAnOverflow [
	| ws got error aTag |
	aTag := self newTag.
	ws := (WebFetchWebSocket url: (self urlOf: '/ws/flood?n=200&size=1024&t=' , aTag))
		maximumQueuedBytes: 20000;
		connect.
	(Delay forMilliseconds: 300) wait.
	got := 0.
	error := [ [ ws next. got := got + 1 ] repeat ] on: WebFetchError do: [ :e | e ].
	self assert: error class equals: WebFetchWebSocketOverflow.
	self assert: got > 0.
	self assert: got < 200.
	self assert: ((self endedEntryFor: aTag) at: 'code') equals: 4008
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testFragmentsAreJoined [
	| ws text |
	ws := self connect: '/ws/fragmented?parts=3&type=text&t=' , self newTag.
	text := 'fragmented:' , ((1 to: 3) inject: '' into: [ :all :i | all , ' café ' , (String with: (Character value: 16r2713)) ]).
	self assert: (ws nextTimeout: 5 seconds) equals: text.
	ws := self connect: '/ws/fragmented?parts=4&type=binary&t=' , self newTag.
	self assert: (ws nextTimeout: 5 seconds) equals: (self pattern: 64).
	WebFetchWebSocket closeAll
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testHungHandshakeTimesOut [
	| port started |
	port := self class hangPort ifNil: [ ^ self skip: 'WEB_FETCH_HANG_PORT is not set' ].
	self httpBase.
	started := Time millisecondClockValue.
	self
		should: [
			(WebFetchWebSocket url: 'ws://' , self serverHost , ':' , port printString , '/ws/hang?t=' , self newTag)
				timeout: 500 milliSeconds;
				connect ]
		raise: WebFetchTimeout.
	self assert: Time millisecondClockValue - started < 5000.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testMessageOverTheMaximumIsTooLarge [
	| ws aTag |
	aTag := self newTag.
	ws := (WebFetchWebSocket url: (self urlOf: '/ws/big?size=2000&t=' , aTag))
		maximumMessageSize: 1000;
		connect.
	self should: [ ws next ] raise: WebFetchTooLarge.
	self assert: ws error class equals: WebFetchTooLarge.
	self assert: ((self endedEntryFor: aTag) at: 'code') equals: 4009
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testPongOfThePing [
	| ws aTag deadline pongs |
	aTag := self newTag.
	ws := self connect: '/ws/ping?payload=hello&t=' , aTag.
	deadline := Time millisecondClockValue + 5000.
	[
		pongs := ((self logFor: aTag) ifEmpty: [ #(  ) ] ifNotEmpty: [ :log | log first at: 'pongs' ]).
		pongs isEmpty and: [ Time millisecondClockValue < deadline ] ] whileTrue: [ (Delay forMilliseconds: 50) wait ].
	self assert: pongs asArray equals: #( 'hello' ).
	ws close
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testPushOfAHundredInOrder [
	| ws got |
	ws := self connect: '/ws/push?n=100&close=1000&t=' , self newTag.
	got := OrderedCollection new.
	ws do: [ :each | got add: each ].
	self assert: got size equals: 100.
	got doWithIndex: [ :each :i | self assert: each equals: i printString ].
	self assert: ws closeCode equals: 1000.
	self assert: ws wasClean
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testRefusedHandshakesAreNetworkErrors [
	self should: [ self connect: '/ws/refuse?status=403&t=' , self newTag ] raise: WebFetchNetworkError.
	self should: [ WebFetchWebSocket connect: 'ws://' , self serverHost , ':1/nobody' ] raise: WebFetchNetworkError.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLiveTest >> testSubprotocolAndExtensions [
	| ws |
	ws := WebFetchWebSocket connect: (self urlOf: '/ws/echo?t=' , self newTag) protocols: #( 'v9.unknown' 'chat' ).
	self assert: ws protocol equals: 'chat'.
	self assert: ws extensions equals: ''.
	ws close.
	ws := self connect: '/ws/deflate?t=' , self newTag.
	self assert: (ws extensions beginsWith: 'permessage-deflate').
	ws sendText: 'deflated ' , (String new: 1000 withAll: $z).
	self assert: (ws nextTimeout: 5 seconds) equals: 'deflated ' , (String new: 1000 withAll: $z).
	ws close
]

{ #category : 'helpers' }
WebFetchWebSocketLiveTest >> urlOf: path [
	"The ws: URL of path on the server (wss: for https:)"

	^ 'ws' , (self httpBase allButFirst: 4) , path
]
