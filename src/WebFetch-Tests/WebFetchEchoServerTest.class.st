"
I test `WebFetch` against a public echo server, the one of https://websocket.org/tools/websocket-echo-server/, when `WebFetch isAvailable` and `self class server` (defaulting to `WEB_FETCH_ECHO_SERVER` in the environment, for example `https://echo.websocket.org`) is set. Without it I skip myself, so that no run of the tests goes to the Internet unasked.

That server has three faces:

- `wss://echo.websocket.org`, a WebSocket echo, which `WebFetch` does not speak (it makes HTTP requests);
- `https://echo.websocket.org/.sse`, Server-Sent Events: an event `server`, an event `request`, then an event `time` every second, without end; it answers every origin (`Access-Control-Allow-Origin: *`);
- any other path, an HTTP echo, whose `text/plain` answer shows the request: its line, its headers and its body; it sends no CORS header, so a browser refuses its answer to the pages, and only the node VM reads it.

In the pages, `WebFetchEchoServerTest server: 'https://echo.websocket.org'` turns me on.
"
Class {
	#name : 'WebFetchEchoServerTest',
	#superclass : 'TestCase',
	#classVars : [
		'Server'
	],
	#category : 'WebFetch-Tests-Live',
	#package : 'WebFetch-Tests',
	#tag : 'Live'
}

{ #category : 'accessing' }
WebFetchEchoServerTest class >> defaultTimeLimit [
	^ 60 seconds
]

{ #category : 'accessing' }
WebFetchEchoServerTest class >> server [
	"Base URL of the echo server (e.g. https://echo.websocket.org), or nil."

	Server ifNotNil: [ ^ Server ].
	^ OSEnvironment current at: 'WEB_FETCH_ECHO_SERVER' ifAbsent: [ nil ]
]

{ #category : 'accessing' }
WebFetchEchoServerTest class >> server: aUrlStringOrNil [
	Server := aUrlStringOrNil
]

{ #category : 'helpers' }
WebFetchEchoServerTest >> baseUrl [
	WebFetch isAvailable ifFalse: [ ^ self skip: 'WebFetch is not available' ].
	^ self class server ifNil: [ self skip: 'WEB_FETCH_ECHO_SERVER is not set' ]
]

{ #category : 'helpers' }
WebFetchEchoServerTest >> nextEventFrom: aStream [
	"Answer the next event of aStream, an event stream, as an Association of its name (or 'message') and its data lines joined by line feeds, or nil at its end. An event ends with an empty line; comments (lines that begin with a colon) and ids are left out."

	| name data line |
	data := OrderedCollection new.
	[
		line := self nextLineFrom: aStream.
		line isNil or: [ line isEmpty and: [ name notNil or: [ data notEmpty ] ] ] ] whileFalse: [
			(line beginsWith: 'event:') ifTrue: [ name := (line allButFirst: 6) trimLeft ].
			(line beginsWith: 'data:') ifTrue: [
				data add: ((line allButFirst: 5) withoutPrefix: ' ') ] ].
	(line isNil and: [ name isNil and: [ data isEmpty ] ]) ifTrue: [ ^ nil ].
	^ (name ifNil: [ 'message' ]) -> (String lf join: data)
]

{ #category : 'helpers' }
WebFetchEchoServerTest >> nextLineFrom: aStream [
	"Answer the next line of aStream, a binary stream of UTF-8, without its end (LF or CR LF), or nil at the end of aStream."

	| bytes byte |
	bytes := WriteStream on: (ByteArray new: 80).
	[ (byte := aStream next) isNil or: [ byte = 10 ] ] whileFalse: [ bytes nextPut: byte ].
	(byte isNil and: [ bytes position = 0 ]) ifTrue: [ ^ nil ].
	^ (bytes contents utf8Decoded) withoutSuffix: String cr
]

{ #category : 'running' }
WebFetchEchoServerTest >> tearDown [
	WebFetch isAvailable ifTrue: [ WebFetch abortAll ].
	super tearDown
]

{ #category : 'tests' }
WebFetchEchoServerTest >> testEventStreamSendsTheTime [
	"Read the first events of /.sse, then close the stream: the call ends with it."

	| base events response |
	base := self baseUrl.
	events := OrderedCollection new.
	(WebFetch request: base , '/.sse')
		headerAt: 'Accept' put: 'text/event-stream';
		timeout: 30 seconds;
		stream: [ :stream |
			| event |
			response := stream response.
			[
				event := self nextEventFrom: stream.
				event notNil and: [ events add: event. (events count: [ :each | each key = 'time' ]) < 3 ] ]
					whileTrue ].
	self assert: response status equals: 200.
	self assert: ((response headerAt: 'Content-Type' ifAbsent: [ '' ]) beginsWith: 'text/event-stream').
	self assert: events first key equals: 'server'.
	self assert: (events anySatisfy: [ :each |
		each key = 'request' and: [ each value beginsWith: 'GET /.sse HTTP/' ] ]).
	(events select: [ :each | each key = 'time' ]) do: [ :each |
		"2026-11-26T08:15:10Z"
		self assert: each value size equals: 20.
		self assert: (each value at: 11) equals: $T.
		self assert: each value last equals: $Z ].
	self assert: (events count: [ :each | each key = 'time' ]) equals: 3.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchEchoServerTest >> testPostIsEchoed [
	"The HTTP echo shows the request it got. A browser refuses its answer, which has no CORS header."

	| base path body response text |
	base := self baseUrl.
	path := '/webfetch-echo-' , Time millisecondClockValue printString.
	body := '{"greeting":"ciao, è WebFetch"}'.
	response := [ WebFetch post: base , path body: body type: 'application/json' ]
		on: WebFetchNetworkError
		do: [ :error |
			self skip: 'refused (in a browser the HTTP echo answers no CORS request): ' , error messageText ].
	self assert: response isSuccess.
	self assert: ((response headerAt: 'Content-Type' ifAbsent: [ '' ]) beginsWith: 'text/plain').
	text := response contents.
	self assert: (text includesSubstring: 'POST ' , path , ' HTTP/').
	self assert: (text includesSubstring: 'Content-Type: application/json').
	self assert: (text includesSubstring: body)
]
