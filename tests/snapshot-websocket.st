"snapshot-websocket.st - an image saved while processes wait on WebSockets, then restarted

	pharo --headless X.image --no-default-preferences st snapshot-websocket.st     (twice, on one copy)

 With the server of run-websocket.st (websocket.lane: its URL, then the port of its listener that
 never answers), on an image that has WebFetch-WebSocket.  The first run starts what waits: a
 connect: that never opens, a next, a nextTimeout:, a send on a full buffer (to a server that does not
 read) and a whenMessage:whenClosed:, and keeps a socket that the server closed with two messages
 unread; it saves the image, and goes on: it prints

	saved, then an echo: ciao

 and exits.  The second one, in the image that was saved, prints what each of the waiting processes
 got, 'WebFetchSessionEnded' for all of them, what the closed socket answers, and that the image opens
 a socket again:

	restarted: <n> of <n> WebFetchSessionEnded, the closed socket: 1 2 4000 saved, open 0, then ciao"

| out environment lane base hang webSocket names results wait deadline echo |
out := [ :text | Stdio stdout nextPutAll: text; nextPutAll: OSPlatform current lineEnding; flush ].
environment := OSEnvironment current.
lane := 'websocket.lane' asFileReference exists
	ifTrue: [ 'websocket.lane' asFileReference contents substrings ]
	ifFalse: [ #(  ) ].
base := environment at: 'WEB_FETCH_SERVER' ifAbsent: [ lane first ].
base := 'ws' , (base allButFirst: 4).
hang := environment at: 'WEB_FETCH_HANG_PORT' ifAbsent: [ lane second ].
webSocket := Smalltalk globals at: #WebFetchWebSocket.
echo := [
	| ws answer |
	ws := webSocket connect: base , '/ws/echo?t=snap-echo'.
	ws sendText: 'ciao'.
	answer := ws nextTimeout: 10 seconds.
	ws close.
	answer ].
names := #( connect next nextTimeout send whenMessage ).
(Smalltalk globals at: #WebSocketSnapshot ifAbsent: [ nil ])
	ifNil: [
		| full closed session |
		results := Dictionary new.
		Smalltalk globals at: #WebSocketSnapshot put: results.
		wait := [ :name :block |
			[ results at: name put: ([ block value. 'nothing' ] on: Error do: [ :error | error class name asString ]) ] fork ].
		wait value: #connect value: [
			(webSocket url: 'ws://127.0.0.1:' , hang , '/ws/hang?t=snap-connect')
				timeout: nil;
				connect ].
		wait value: #next value: [ (webSocket connect: base , '/ws/echo?t=snap-next') next ].
		wait value: #nextTimeout value: [ (webSocket connect: base , '/ws/echo?t=snap-timeout') nextTimeout: 100 seconds ].
		full := (webSocket url: base , '/ws/slow-read?resume=0&t=snap-send')
			timeout: nil;
			connect.
		wait value: #send value: [ [ full sendBytes: (ByteArray new: 4 * 1024 * 1024) ] repeat ].
		(webSocket connect: base , '/ws/echo?t=snap-reader')
			whenMessage: [ :message | ]
			whenClosed: [ :socket | results at: #whenMessage put: socket error class name asString ].
		closed := webSocket connect: base , '/ws/push?n=2&close=4000&reason=saved&type=text&t=snap-closed'.
		Smalltalk globals at: #WebSocketSnapshotClosed put: closed.
		deadline := Time millisecondClockValue + 10000.
		[ (closed state == #closed and: [ full bufferedAmount > (8 * 1024 * 1024) ]) or: [ Time millisecondClockValue > deadline ] ]
			whileFalse: [ (Delay forMilliseconds: 50) wait ].
		(Delay forMilliseconds: 300) wait.
		"in a process of its own, since the one of the command line ends the restarted image"
		session := Smalltalk session.
		[ Smalltalk snapshot: true andQuit: false.
		Smalltalk session == session ifTrue: [
			out value: 'saved, then an echo: ' , (echo value ifNil: [ 'none' ]).
			Smalltalk exit: 0 ] ] fork.
		Semaphore new wait ]
	ifNotNil: [ :saved |
		| closed answers |
		deadline := Time millisecondClockValue + 10000.
		[ (names allSatisfy: [ :each | saved includesKey: each ]) or: [ Time millisecondClockValue > deadline ] ]
			whileFalse: [ (Delay forMilliseconds: 50) wait ].
		names do: [ :each |
			(saved at: each ifAbsent: [ 'still waits' ]) = 'WebFetchSessionEnded' ifFalse: [
				out value: each , ': ' , (saved at: each ifAbsent: [ 'still waits' ]) ] ].
		closed := Smalltalk globals at: #WebSocketSnapshotClosed.
		answers := OrderedCollection new.
		[ answers add: (closed nextTimeout: 1 second) printString ] on: Error do: [ :error | answers add: error class name ].
		[ answers add: (closed nextTimeout: 1 second) printString ] on: Error do: [ :error | answers add: error class name ].
		[ closed next. answers add: 'a third message' ]
			on: (Smalltalk globals at: #WebFetchWebSocketClosed)
			do: [ :error | answers add: error code printString , ' ' , error reason ].
		out value: 'restarted: ' , (names count: [ :each | (saved at: each ifAbsent: [ nil ]) = 'WebFetchSessionEnded' ]) printString
			, ' of ' , names size printString , ' WebFetchSessionEnded, the closed socket: '
			, (' ' join: (answers collect: [ :each | each asString copyWithout: $' ]))
			, ', open ' , webSocket openCount printString
			, ', then ' , (echo value ifNil: [ 'none' ]).
		Smalltalk exit: 0 ]
