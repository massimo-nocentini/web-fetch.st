"
I test `WebFetchWebSocket` against the WebSocket echo of the public server of https://websocket.org/tools/websocket-echo-server/, `wss://echo.websocket.org`, when `WebFetchWebSocket isAvailable` and `self class server` is set: by default `WEB_FETCH_ECHO_SERVER` of the environment, the variable of `WebFetchEchoServerTest` (`https://echo.websocket.org` there; its `https:` becomes `wss:` here). Without it I skip myself, so that no run of the tests goes to the Internet unasked.

The server sends a first message of its own (`Request served by ...`), then echoes each message with its type. A WebSocket has no CORS, so I work in the pages too: there `WebFetchWebSocketEchoServerTest server: 'wss://echo.websocket.org'` turns me on.
"
Class {
	#name : 'WebFetchWebSocketEchoServerTest',
	#superclass : 'TestCase',
	#classVars : [
		'Server'
	],
	#category : 'WebFetch-WebSocket-Tests-Live',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Live'
}

{ #category : 'accessing' }
WebFetchWebSocketEchoServerTest class >> defaultTimeLimit [
	^ 60 seconds
]

{ #category : 'accessing' }
WebFetchWebSocketEchoServerTest class >> server [
	"URL of the echo (e.g. wss://echo.websocket.org), or nil"

	| url |
	Server ifNotNil: [ ^ Server ].
	url := OSEnvironment current at: 'WEB_FETCH_ECHO_SERVER' ifAbsent: [ ^ nil ].
	(url beginsWith: 'https://') ifTrue: [ ^ 'wss://' , (url allButFirst: 8) ].
	(url beginsWith: 'http://') ifTrue: [ ^ 'ws://' , (url allButFirst: 7) ].
	^ url
]

{ #category : 'accessing' }
WebFetchWebSocketEchoServerTest class >> server: aUrlStringOrNil [
	Server := aUrlStringOrNil
]

{ #category : 'helpers' }
WebFetchWebSocketEchoServerTest >> connect [
	| ws first |
	WebFetchWebSocket isAvailable ifFalse: [ ^ self skip: 'WebFetchWebSocket is not available' ].
	ws := WebFetchWebSocket connect: (self class server ifNil: [ ^ self skip: 'WEB_FETCH_ECHO_SERVER is not set' ]).
	first := ws nextTimeout: 30 seconds.
	self assert: first isString.
	self assert: (first beginsWith: 'Request served by').
	^ ws
]

{ #category : 'running' }
WebFetchWebSocketEchoServerTest >> tearDown [
	WebFetchWebSocket isAvailable ifTrue: [ WebFetchWebSocket closeAll ].
	super tearDown
]

{ #category : 'tests' }
WebFetchWebSocketEchoServerTest >> testTextAndBytesComeBack [
	| ws text bytes |
	ws := self connect.
	text := 'ciao, è WebSocket'.
	ws sendText: text.
	self assert: (ws nextTimeout: 30 seconds) equals: text.
	bytes := (0 to: 255) asByteArray.
	ws sendBytes: bytes.
	self assert: (ws nextTimeout: 30 seconds) equals: bytes.
	self assert: ws close.
	self assert: (ws waitForCloseTimeout: 30 seconds).
	"The server ends TCP about 5 s after the close frames (measured with node 24), and only then does the WebSocket of node tell the close: the close timer of the host, of 5 s, may end the socket first"
	self assert: ((ws closeCode = 1000 and: [ ws wasClean ])
		or: [ ws closeCode = 1006 and: [ ws closeReason = 'closing handshake timed out' ] ]).
	self assert: WebFetchWebSocket openCount equals: 0
]
