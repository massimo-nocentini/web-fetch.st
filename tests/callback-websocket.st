"callback-websocket.st - WebSockets while a real FFI callback runs

	WEB_FETCH_SERVER=http://127.0.0.1:<port> pharo --headless X.image --no-default-preferences st --quit callback-websocket.st

 With the server of run-websocket.st, on a wasm VM with the FFI and an image that has
 WebFetch-WebSocket. The callback is the comparison of qsort. A wait inside the callback signals
 WebFetchInCallback; start, state, nextOrNil, a send with room, close and release answer there, also
 while another process waits in next, whose wait ends after the callback. It prints each check that
 fails, then

	callback: <passed> of <all>"

| out environment base webSocket inCallback got passed all check done read ws other |
out := [ :text | Stdio stdout nextPutAll: text; nextPutAll: OSPlatform current lineEnding; flush ].
environment := OSEnvironment current.
base := environment at: 'WEB_FETCH_SERVER' ifAbsent: [ 'websocket.lane' asFileReference contents substrings first ].
base := 'ws' , (base allButFirst: 4).
webSocket := Smalltalk globals at: #WebFetchWebSocket.
((FFILibrary << #WebSocketCallbackLibC) package: 'WebSocketCallback') install.
(Smalltalk globals at: #WebSocketCallbackLibC) compile: 'unixLibraryName
	^ ''libc.so.6'''.
((Object << #WebSocketCallback) package: 'WebSocketCallback') install.
(Smalltalk globals at: #WebSocketCallback) compile: 'qsort: base count: n size: s with: c
	^ self ffiCall: #(void qsort(ByteArray base, size_t n, size_t s, FFICallback c)) library: WebSocketCallbackLibC'.
inCallback := [ :block |
	(Smalltalk globals at: #WebSocketCallback) new
		qsort: (ByteArray new: 8)
		count: 2
		size: 4
		with: (FFICallback signature: #( int #( void * a #, void * b ) ) block: [ :a :b | block value. 0 ]) ].
passed := all := 0.
check := [ :name :value :expected |
	all := all + 1.
	value = expected
		ifTrue: [ passed := passed + 1 ]
		ifFalse: [ out value: name , ': ' , value printString ] ].
got := [ :block | [ block value ] on: Error do: [ :error | error class name asString ] ].

"waits of the callback itself"
inCallback value: [ read := got value: [ webSocket connect: base , '/ws/echo?t=cb-connect' ] ].
check value: 'connect: in the callback' value: read value: 'WebFetchInCallback'.
check value: 'the socket of connect: released' value: webSocket openCount value: 0.
ws := webSocket connect: base , '/ws/echo?t=cb-next'.
inCallback value: [ read := got value: [ ws next ] ].
check value: 'next in the callback' value: read value: 'WebFetchInCallback'.
inCallback value: [ read := got value: [ ws nextTimeout: 1 second ] ].
check value: 'nextTimeout: in the callback' value: read value: 'WebFetchInCallback'.
check value: 'the socket stays open' value: ws state value: #open.

"what answers in the callback while another process waits in next"
done := Semaphore new.
other := 'nothing'.
[
	other := got value: [ ws next ].
	done signal ] fork.
(Delay forMilliseconds: 50) wait.
inCallback value: [
	read := got value: [
		{ ws nextOrNil. ws state. ws sendText: 'from the callback'. ws bufferedAmount isInteger } ] ].
check value: 'nextOrNil, state and a send in the callback' value: read value: { nil. #open. ws. true }.
done waitTimeoutSeconds: 5.
check value: 'next of the other process, after the callback' value: other value: 'from the callback'.

"start, close and release in the callback; the waits after it"
inCallback value: [ read := got value: [ (webSocket url: base , '/ws/echo?t=cb-start') start ] ].
check value: 'start in the callback' value: (read isString ifTrue: [ read ] ifFalse: [ read state ]) value: #connecting.
check value: 'connect after the callback' value: (got value: [ read waitForOpen state ]) value: #open.
inCallback value: [ read := got value: [ ws close ] ].
check value: 'close in the callback' value: read value: true.
check value: 'the close ends after the callback' value: (ws waitForCloseTimeout: 5 seconds) value: true.
ws := webSocket connect: base , '/ws/echo?t=cb-release'.
inCallback value: [ read := got value: [ ws release. ws state ] ].
check value: 'release in the callback' value: read value: #failed.

"whenMessage:whenClosed: forked in a callback"
ws := webSocket connect: base , '/ws/push?n=3&t=cb-reader'.
done := Semaphore new.
other := OrderedCollection new.
inCallback value: [
	ws
		whenMessage: [ :message | other add: message ]
		whenClosed: [ :socket | done signal ] ].
done waitTimeoutSeconds: 5.
check value: 'whenMessage:whenClosed: of a callback' value: other asArray value: #( '1' '2' '3' ).
webSocket closeAll.
check value: 'open at the end' value: webSocket openCount value: 0.
out value: 'callback: ' , passed printString , ' of ' , all printString
