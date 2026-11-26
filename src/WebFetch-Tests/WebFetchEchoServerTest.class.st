"
I test `WebFetch` against a public echo server, the one of https://websocket.org/tools/websocket-echo-server/, when `WebFetch isAvailable` and `self class server` (defaulting to `WEB_FETCH_ECHO_SERVER` in the environment, for example `https://echo.websocket.org`) is set. Without it I skip myself, so that no run of the tests goes to the Internet unasked.

That server has three faces:

- `wss://echo.websocket.org`, a WebSocket echo, which `WebFetch` does not speak (it makes HTTP requests);
- `https://echo.websocket.org/.sse`, Server-Sent Events: an event `server`, an event `request`, then an event `time` every second, without end, numbered from 1 by their `id`; it answers every origin (`Access-Control-Allow-Origin: *`). I read it with `WebFetchEventSource`;
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

{ #category : 'running' }
WebFetchEchoServerTest >> tearDown [
	WebFetch isAvailable ifTrue: [ WebFetch abortAll ].
	super tearDown
]

{ #category : 'tests' }
WebFetchEchoServerTest >> testEventStreamSendsTheTime [
	"Read the first events of /.sse with WebFetchEventSource, then close it: the call ends with it."

	| base source events event times |
	base := self baseUrl.
	source := WebFetch eventSource: base , '/.sse'.
	events := OrderedCollection new.
	[
		[ (events count: [ :each | each type = 'time' ]) < 3 ] whileTrue: [
			event := source nextTimeout: 10 seconds.
			self assert: event notNil.
			events add: event ] ]
		ensure: [ source close ].
	self assert: source response status equals: 200.
	self assert: source response mediaType equals: 'text/event-stream'.
	self assert: events first type equals: 'server'.
	self assert: (events anySatisfy: [ :each |
		each type = 'request' and: [ each data beginsWith: 'GET /.sse HTTP/' ] ]).
	times := events select: [ :each | each type = 'time' ].
	self assert: times size equals: 3.
	times do: [ :each |
		"2026-11-26T08:15:10Z"
		self assert: each data size equals: 20.
		self assert: (each data at: 11) equals: $T.
		self assert: each data last equals: $Z ].
	"the server numbers its events from 1 with id:"
	self
		assert: (events collect: [ :each | each lastEventId ]) asArray
		equals: ((1 to: events size) collect: [ :i | i printString ]) asArray.
	self assert: source lastEventId equals: events last lastEventId.
	self assert: events first origin equals: base.
	self assert: source readyState equals: #closed.
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
