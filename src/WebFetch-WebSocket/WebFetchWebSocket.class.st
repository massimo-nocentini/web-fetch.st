"
I am a WebSocket client connection, made by the `WebSocket` of the host (of the worker in a browser, of node in the node VM) through the `WebSocketPlugin`. I send and receive whole messages, text (a String) or binary (a ByteArray), while the VM and the other processes go on.

```
| ws |
ws := WebFetchWebSocket connect: 'wss://echo.websocket.org'.
ws next.
ws sendText: 'ciao, è WebSocket'.
ws next.
ws close
```

- Configure, before `start`: `protocols:`, `timeout:` (of the handshake and of the waits of the sends, 30 seconds by default; nil none), `maximumMessageSize:` and `maximumQueuedBytes:` (16 MiB each by default, at most 256 MiB, what the host queues in all its sockets).
- Open: `start` (does not wait), `connect` (waits until it is open or failed), `waitForOpen`, `waitForOpenTimeout:`.
- Send: `sendText:`, `sendBytes:`, `send:`; in `#connecting` they wait for the open, on a full send buffer for room, both within `timeout`; `flushTimeout:`.
- Receive: `next`, `nextTimeout:`, `nextOrNil`, `nextRaw` (`{isText. utf8Bytes}`), `atEnd`, `do:`, `whenMessage:whenClosed:`.
- Close: `close`, `close:reason:`, `waitForCloseTimeout:`, `release` (forgets the socket at once).

A socket is `#new`, then `#connecting`, `#open`, `#closing`, and ends `#closed` (`closeCode`, `closeReason`, `wasClean`) or `#failed` (`error`). The messages that came before the end stay readable: `next` answers them, then signals `WebFetchWebSocketClosed`, or the error of the failure. When I first see the end, I read what is queued into the image and release the host record (I am settled): what I hold then survives an image save. After a resume the sockets that were not settled end with `WebFetchSessionEnded`.

No Mutex is held while a process waits: `lock` guards only the primitive calls and the state that I record. Each wait is on one of three semaphores: `state` (the open and the end), `read` (a message) and `write` (room to send). In the UI process, `connect:`, `next` and a send that waits freeze the world, as a native socket does; tools use `start` and `whenMessage:whenClosed:` with `UIManager default defer:`. In an FFI callback a wait signals `WebFetchInCallback`; `start`, `state`, `nextOrNil`, a send with room, `close` and `release` work there.

`WebFetch abortAll` does not touch WebSockets; `WebFetchWebSocket closeAll` releases them.
"
Class {
	#name : 'WebFetchWebSocket',
	#superclass : 'Object',
	#instVars : [
		'host',
		'session',
		'closer',
		'handle',
		'lock',
		'semaphores',
		'url',
		'protocols',
		'timeout',
		'maximumMessageSize',
		'maximumQueuedBytes',
		'stateCode',
		'settled',
		'openedBeforeFailure',
		'queuedCount',
		'pending',
		'dropped',
		'protocol',
		'extensions',
		'closeCode',
		'closeReason',
		'wasClean',
		'error'
	],
	#classVars : [
		'OpenSockets',
		'OpenSocketsMutex'
	],
	#category : 'WebFetch-WebSocket-Core',
	#package : 'WebFetch-WebSocket',
	#tag : 'Core'
}

{ #category : 'accessing' }
WebFetchWebSocket class >> availability [
	"Answer #unavailable, #ready or #off"

	| code |
	code := WebFetchWebSocketHost default availability.
	code = 1 ifTrue: [ ^ #ready ].
	code = 2 ifTrue: [ ^ #off ].
	^ #unavailable
]

{ #category : 'control' }
WebFetchWebSocket class >> closeAll [
	"Release every socket that is not settled (WebFetch abortAll does not touch WebSockets)"

	self openSockets do: [ :each | each release ]
]

{ #category : 'instance creation' }
WebFetchWebSocket class >> connect: aUrlOrString [
	"Answer a socket to aUrlOrString once it is open; signal the error of a failed handshake"

	^ (self url: aUrlOrString) connect
]

{ #category : 'instance creation' }
WebFetchWebSocket class >> connect: aUrlOrString protocols: aCollection [
	"Answer a socket to aUrlOrString that offered the subprotocols of aCollection, once it is open"

	^ (self url: aUrlOrString)
		protocols: aCollection;
		connect
]

{ #category : 'constants' }
WebFetchWebSocket class >> defaultMaximumMessageSize [
	^ 16 * 1024 * 1024
]

{ #category : 'constants' }
WebFetchWebSocket class >> defaultMaximumQueuedBytes [
	^ 16 * 1024 * 1024
]

{ #category : 'constants' }
WebFetchWebSocket class >> defaultTimeout [
	^ 30 seconds
]

{ #category : 'errors' }
WebFetchWebSocket class >> errorKind: aSymbol message: aString [
	"Answer an unsignalled error for the kind of an error record of the host"

	| errorClass |
	errorClass := aSymbol == #overflow
		ifTrue: [ WebFetchWebSocketOverflow ]
		ifFalse: [
			aSymbol == #closed
				ifTrue: [ WebFetchWebSocketClosed ]
				ifFalse: [ WebFetchError classForKind: aSymbol ] ].
	^ errorClass new
		kind: aSymbol;
		messageText: (aString ifNil: [ '' ]);
		yourself
]

{ #category : 'class initialization' }
WebFetchWebSocket class >> initialize [
	self resetOpenSockets.
	SessionManager default registerNetworkClassNamed: self name
]

{ #category : 'testing' }
WebFetchWebSocket class >> isAvailable [
	^ self availability == #ready
]

{ #category : 'private' }
WebFetchWebSocket class >> isToken: aString [
	"Whether aString is a token of RFC 7230, which a subprotocol must be"

	aString isEmpty ifTrue: [ ^ false ].
	^ aString allSatisfy: [ :each |
		each isCharacter and: [
			(each asInteger between: 48 and: 57)
				or: [ (each asInteger between: 65 and: 90)
				or: [ (each asInteger between: 97 and: 122)
				or: [ '!#$%&''*+-.^_`|~' includes: each ] ] ] ] ]
]

{ #category : 'constants' }
WebFetchWebSocket class >> maximumMessageSizeLimit [
	"The largest maximumMessageSize and maximumQueuedBytes: 256 MiB, the most that the host queues in all its sockets"

	^ 1 bitShift: 28
]

{ #category : 'constants' }
WebFetchWebSocket class >> maximumProtocols [
	^ 32
]

{ #category : 'constants' }
WebFetchWebSocket class >> maximumRecordSize [
	"The largest open record (the URL and the subprotocols, in UTF-8)"

	^ 65536
]

{ #category : 'constants' }
WebFetchWebSocket class >> maximumSendSize [
	"The largest message that a socket sends"

	^ 64 * 1024 * 1024
]

{ #category : 'accessing' }
WebFetchWebSocket class >> openCount [
	^ self openSockets size
]

{ #category : 'accessing' }
WebFetchWebSocket class >> openSockets [
	"Answer an Array of the sockets that have a host record (started and not settled). A dropped socket that the finalizer released stays in the set until the next garbage collection, and is not answered"

	| mutex |
	mutex := OpenSocketsMutex.
	mutex ifNil: [ ^ #() ].
	^ mutex critical: [
		Array streamContents: [ :stream |
			OpenSockets do: [ :each |
				each ifNotNil: [ each hasHostRecord ifTrue: [ stream nextPut: each ] ] ] ] ]
]

{ #category : 'private' }
WebFetchWebSocket class >> registerSocket: aSocket [
	OpenSocketsMutex critical: [ OpenSockets add: aSocket ]
]

{ #category : 'private' }
WebFetchWebSocket class >> resetOpenSockets [
	OpenSockets := WeakSet new.
	OpenSocketsMutex := Mutex new
]

{ #category : 'system startup' }
WebFetchWebSocket class >> shutDown: quitting [
	"Before a save or a quit, settle the sockets that the host has closed or failed, so that what they received is in the image"

	self openSockets do: [ :each | [ each state ] on: Error do: [ :e | ] ]
]

{ #category : 'system startup' }
WebFetchWebSocket class >> startUp: resuming [
	"On an image resume, install a new table of open sockets, and end the sockets of the old one that were not settled with WebFetchSessionEnded, waking their waiters; they never call the host, whose ids belong to the VM that saved the image"

	| old |
	resuming ifFalse: [ ^ self ].
	old := OpenSockets.
	self resetOpenSockets.
	old ifNotNil: [
		old do: [ :each | each ifNotNil: [ each markSessionEnded ] ] ]
]

{ #category : 'class initialization' }
WebFetchWebSocket class >> unload [
	SessionManager default unregisterClassNamed: self name
]

{ #category : 'private' }
WebFetchWebSocket class >> unregisterSocket: aSocket [
	| mutex |
	mutex := OpenSocketsMutex.
	mutex ifNil: [ ^ self ].
	mutex critical: [ OpenSockets remove: aSocket ifAbsent: [ ] ]
]

{ #category : 'instance creation' }
WebFetchWebSocket class >> url: aUrlOrString [
	"Answer a socket to aUrlOrString, an absolute ws: or wss: URL, to configure and start"

	^ self new setUrl: aUrlOrString
]

{ #category : 'testing' }
WebFetchWebSocket >> atEnd [
	"Whether the socket is over and no message is left"

	self checkStarted.
	^ self locked: [
		self refreshLocked.
		settled and: [ pending isEmpty ] ]
]

{ #category : 'private' }
WebFetchWebSocket >> await: index for: aBlock deadline: deadlineOrNil [
	"Evaluate aBlock until it answers something else than nil, and answer that; between two looks wait on the semaphore at index (1 state, 2 read, 3 write). Answer nil at the deadline (a value of Time millisecondClockValue; nil waits as long as it takes). A waiter that waited and got what it waited for, and one that finds the socket over, signal the semaphore once more, so that another waiter looks again."

	| semaphore waited result remaining |
	semaphore := semaphores at: index.
	waited := false.
	[
		result := aBlock value.
		result ifNotNil: [
			(waited or: [ settled ]) ifTrue: [ semaphore signal ].
			^ result ].
		remaining := deadlineOrNil ifNotNil: [ deadlineOrNil - Time millisecondClockValue ].
		(remaining notNil and: [ remaining <= 0 ]) ifTrue: [ ^ nil ].
		self checkMayWait.
		waited := true.
		remaining
			ifNil: [ semaphore wait ]
			ifNotNil: [ semaphore waitTimeoutMilliseconds: remaining ] ] repeat
]

{ #category : 'accessing' }
WebFetchWebSocket >> bufferedAmount [
	"Answer the bytes sent that the host has not handed to the network yet; 0 when the socket is over"

	stateCode = 0 ifTrue: [ ^ 0 ].
	^ self locked: [ self bufferedLocked ]
]

{ #category : 'private' }
WebFetchWebSocket >> bufferedLocked [
	| answer |
	settled ifTrue: [ ^ 0 ].
	answer := self hostDo: [ host bufferedOf: handle ] onReleased: [ 0 ].
	^ answer ifNil: [ 0 ]
]

{ #category : 'private' }
WebFetchWebSocket >> checkMayWait [
	WebFetchCall checkMayWait: host
]

{ #category : 'private' }
WebFetchWebSocket >> checkNotStarted [
	stateCode = 0 ifFalse: [
		WebFetchBadRequest signal: 'A WebFetchWebSocket is configured before its start' ]
]

{ #category : 'private' }
WebFetchWebSocket >> checkStarted [
	stateCode = 0 ifTrue: [ self error: 'The WebFetchWebSocket is not started (start or connect)' ]
]

{ #category : 'private' }
WebFetchWebSocket >> checkUrl: aString [
	"Signal WebFetchBadRequest unless aString is an absolute ws: or wss: URL with no user name, no password, no fragment, and no CR, LF or NUL (the host checks it again)"

	| lower rest authority end |
	(aString anySatisfy: [ :each | each = Character cr or: [ each = Character lf or: [ each asInteger = 0 ] ] ])
		ifTrue: [ WebFetchBadRequest signal: 'A WebSocket URL with a CR, a LF or a NUL' ].
	lower := aString asLowercase.
	rest := (lower beginsWith: 'ws://')
		ifTrue: [ aString allButFirst: 5 ]
		ifFalse: [
			(lower beginsWith: 'wss://')
				ifTrue: [ aString allButFirst: 6 ]
				ifFalse: [ WebFetchBadRequest signal: 'Not an absolute ws: or wss: URL: ' , aString ] ].
	(aString includes: $#) ifTrue: [ WebFetchBadRequest signal: 'A WebSocket URL with a fragment: ' , aString ].
	end := rest findFirst: [ :each | each = $/ or: [ each = $? ] ].
	authority := end = 0
		ifTrue: [ rest ]
		ifFalse: [ rest copyFrom: 1 to: end - 1 ].
	authority isEmpty ifTrue: [ WebFetchBadRequest signal: 'A WebSocket URL without a host: ' , aString ].
	(authority includes: $@) ifTrue: [
		WebFetchBadRequest signal: 'A WebSocket URL with a user name or a password: ' , aString ]
]

{ #category : 'closing' }
WebFetchWebSocket >> close [
	"Start the closing handshake with the code 1000 and no reason; answer whether it started it"

	^ self close: 1000 reason: ''
]

{ #category : 'closing' }
WebFetchWebSocket >> close: code reason: aString [
	"Start the closing handshake with code (1000 or 3000..4999) and aString (at most 123 bytes of UTF-8); answer true when it started it, false when the socket was closing or over. The messages queued stay readable"

	| bytes |
	(code isInteger and: [ code = 1000 or: [ code between: 3000 and: 4999 ] ]) ifFalse: [
		WebFetchBadRequest signal: 'A WebSocket close code is 1000 or in 3000..4999, not ' , code printString ].
	bytes := (aString ifNil: [ '' ]) asString utf8Encoded.
	bytes size > 123 ifTrue: [
		WebFetchBadRequest signal: 'A WebSocket close reason has at most 123 bytes of UTF-8, not ' , bytes size printString ].
	stateCode = 0 ifTrue: [ ^ false ].
	^ self locked: [
		settled
			ifTrue: [ false ]
			ifFalse: [
				self
					hostDo: [ host close: handle code: code reason: (bytes ifEmpty: [ nil ] ifNotEmpty: [ bytes ]) ]
					onReleased: [ false ] ] ]
]

{ #category : 'accessing' }
WebFetchWebSocket >> closeCode [
	"The close code once the socket is closed (1006 when the connection was lost), else nil"

	self refresh.
	^ closeCode
]

{ #category : 'accessing' }
WebFetchWebSocket >> closeReason [
	"The reason of the close once the socket is closed, else nil"

	self refresh.
	^ closeReason
]

{ #category : 'opening' }
WebFetchWebSocket >> connect [
	"Start the socket and wait until it is open; signal the error of a failed handshake. A curtailed connect releases the socket"

	[ self start ] ifCurtailed: [ self release ].
	^ self waitForOpen
]

{ #category : 'private' }
WebFetchWebSocket >> deadlineAfter: aDurationOrSecondsOrNil [
	"Answer the value of Time millisecondClockValue after aDurationOrSecondsOrNil, nil for none (nil or zero)"

	| ms |
	aDurationOrSecondsOrNil ifNil: [ ^ nil ].
	ms := self millisecondsOf: aDurationOrSecondsOrNil.
	ms = 0 ifTrue: [ ^ nil ].
	^ Time millisecondClockValue + ms
]

{ #category : 'private' }
WebFetchWebSocket >> decode: aMessage [
	"A text message as a String, a binary one as a ByteArray"

	^ (aMessage at: 1)
		ifTrue: [ (aMessage at: 2) utf8Decoded ]
		ifFalse: [ aMessage at: 2 ]
]

{ #category : 'enumerating' }
WebFetchWebSocket >> do: aBlock [
	"Evaluate aBlock with each message until the socket is closed, cleanly or not (closeCode says why); signal the error of a failure"

	[
		| message |
		message := [ self next ]
			on: WebFetchWebSocketClosed
			do: [ :e | ^ self ].
		aBlock value: message ] repeat
]

{ #category : 'private' }
WebFetchWebSocket >> endLocked [
	"Release the host record and the semaphores, and wake every waiter: the socket is settled"

	settled ifTrue: [ ^ self ].
	settled := true.
	closer ifNotNil: [ closer close ].
	self class unregisterSocket: self.
	semaphores ifNotNil: [ semaphores do: [ :each | each signal ] ]
]

{ #category : 'private' }
WebFetchWebSocket >> endStartWith: anError [
	"The start failed or was curtailed"

	settled ifTrue: [ ^ self ].
	stateCode := 5.
	error := anError.
	self endLocked
]

{ #category : 'accessing' }
WebFetchWebSocket >> error [
	"Answer the unsignalled error of a failed socket, or nil"

	self refresh.
	^ error
]

{ #category : 'accessing' }
WebFetchWebSocket >> extensions [
	"The extensions that the server took (for example permessage-deflate), empty for none; nil before the open"

	self refresh.
	^ extensions
]

{ #category : 'flushing' }
WebFetchWebSocket >> flushTimeout: aDurationOrSeconds [
	"Wait up to aDurationOrSeconds until the host has handed every byte sent to the network; answer whether it has"

	self checkStarted.
	self
		await: 3
		for: [ self locked: [ (settled or: [ self bufferedLocked = 0 ]) ifTrue: [ true ] ifFalse: [ nil ] ] ]
		deadline: (self deadlineAfter: aDurationOrSeconds).
	^ self bufferedAmount = 0
]

{ #category : 'private' }
WebFetchWebSocket >> hostDo: aBlock onReleased: releasedBlock [
	"Evaluate a host call on handle. On a settled socket evaluate releasedBlock and call no host; a socket whose host record is gone (a 'not found' of the host, a new session) ends with WebFetchSessionEnded, and then releasedBlock is evaluated too. Never signals"

	settled ifTrue: [ ^ releasedBlock value ].
	session == Smalltalk session ifFalse: [
		self markSessionEnded.
		^ releasedBlock value ].
	^ [ aBlock value ]
		on: WebFetchSessionEnded
		do: [ :e |
			settled ifFalse: [ self markSessionEnded ].
			releasedBlock value ]
]

{ #category : 'initialization' }
WebFetchWebSocket >> initialize [
	super initialize.
	lock := Mutex new.
	stateCode := 0.
	settled := false.
	openedBeforeFailure := false.
	queuedCount := 0.
	pending := OrderedCollection new.
	protocols := #(  ).
	timeout := self class defaultTimeout.
	maximumMessageSize := self class defaultMaximumMessageSize.
	maximumQueuedBytes := self class defaultMaximumQueuedBytes
]

{ #category : 'private' }
WebFetchWebSocket >> hasHostRecord [
	"Whether the host has a record of the socket: started, not settled, and not released by the finalizer"

	^ settled not and: [ closer notNil and: [ closer handle notNil ] ]
]

{ #category : 'testing' }
WebFetchWebSocket >> isOpen [
	^ self state == #open
]

{ #category : 'testing' }
WebFetchWebSocket >> isOver [
	"Whether the socket is closed or failed"

	| s |
	s := self state.
	^ s == #closed or: [ s == #failed ]
]

{ #category : 'private' }
WebFetchWebSocket >> linesOf: aByteArray [
	| text |
	text := [ aByteArray utf8Decoded ] on: Error do: [ :e | aByteArray asString ].
	^ WebFetchResponse splitOnLF: text
]

{ #category : 'private' }
WebFetchWebSocket >> locked: aBlock [
	"Evaluate aBlock under lock, which no wait ever holds; an error that aBlock signals is signalled again once lock is free"

	| result failure |
	lock critical: [
		result := aBlock
			on: Error
			do: [ :e |
				failure := e.
				nil ] ].
	failure ifNotNil: [ ^ failure signal ].
	^ result
]

{ #category : 'private' }
WebFetchWebSocket >> makeRoom [
	"Make room in the object memory for a message: a garbage collection alone does not, growing the memory does"

	Smalltalk garbageCollect.
	[ Smalltalk growMemoryByAtLeast: maximumMessageSize + 1048576 ] on: Error do: [ :e | ]
]

{ #category : 'private' }
WebFetchWebSocket >> markSessionEnded [
	"End a socket that was not settled after an image resume (also when the host lost its record); call no host, wake the waiters"

	(settled or: [ stateCode = 0 ]) ifTrue: [ ^ self ].
	stateCode := 5.
	error := WebFetchSessionEnded new
		messageText: 'The Smalltalk session ended while the WebFetchWebSocket was open';
		yourself.
	self endLocked
]

{ #category : 'accessing' }
WebFetchWebSocket >> maximumMessageSize [
	^ maximumMessageSize
]

{ #category : 'configuring' }
WebFetchWebSocket >> maximumMessageSize: anInteger [
	"The largest message that the socket takes (1..2^28); a larger one fails it with tooLarge (WebFetchTooLarge) and the server gets 4009"

	self checkNotStarted.
	maximumMessageSize := self validLimit: anInteger named: 'maximumMessageSize'
]

{ #category : 'accessing' }
WebFetchWebSocket >> maximumQueuedBytes [
	^ maximumQueuedBytes
]

{ #category : 'configuring' }
WebFetchWebSocket >> maximumQueuedBytes: anInteger [
	"The most bytes of messages received and not read (1..2^28); more fail the socket with overflow (WebFetchWebSocketOverflow) and the server gets 4008"

	self checkNotStarted.
	maximumQueuedBytes := self validLimit: anInteger named: 'maximumQueuedBytes'
]

{ #category : 'private' }
WebFetchWebSocket >> millisecondsOf: aDurationOrSeconds [
	| ms |
	ms := aDurationOrSeconds isNumber
		ifTrue: [ (aDurationOrSeconds * 1000) truncated ]
		ifFalse: [ aDurationOrSeconds asMilliSeconds truncated ].
	^ ms max: 0
]

{ #category : 'receiving' }
WebFetchWebSocket >> next [
	"Answer the next message, a String for text, a ByteArray for binary, waiting for it (in #connecting too). When the socket is over and no message is left, signal WebFetchWebSocketClosed after a close, the error after a failure"

	^ self decode: self nextRaw
]

{ #category : 'receiving' }
WebFetchWebSocket >> nextOrNil [
	"Answer the next message if one is there, else nil; never waits, never signals the end"

	| message |
	self checkStarted.
	message := self locked: [ self takeLocked ].
	(message isNil or: [ message == #end ]) ifTrue: [ ^ nil ].
	^ self decode: message
]

{ #category : 'receiving' }
WebFetchWebSocket >> nextRaw [
	"As next, but answer the message as {isText. bytes}: a text message as its UTF-8 bytes, decoded by nobody"

	^ self nextRawBefore: nil
]

{ #category : 'private' }
WebFetchWebSocket >> nextRawBefore: deadlineOrNil [
	"The next message as {isText. bytes}, nil at the deadline"

	| message |
	self checkStarted.
	message := self await: 2 for: [ self locked: [ self takeLocked ] ] deadline: deadlineOrNil.
	message == #end ifTrue: [ ^ self signalEnd ].
	^ message
]

{ #category : 'receiving' }
WebFetchWebSocket >> nextTimeout: aDurationOrSeconds [
	"Answer the next message, or nil when none came within aDurationOrSeconds; at the end, signal as next does"

	| message |
	message := self nextRawBefore: ((self deadlineAfter: aDurationOrSeconds) ifNil: [ Time millisecondClockValue ]).
	^ message ifNotNil: [ self decode: message ]
]

{ #category : 'opening' }
WebFetchWebSocket >> openRecord [
	| bytes |
	bytes := (String lf join: { url } , protocols) utf8Encoded.
	bytes size > self class maximumRecordSize ifTrue: [
		WebFetchBadRequest signal: 'The URL and the subprotocols of a WebSocket have more than 65536 bytes' ].
	^ bytes
]

{ #category : 'printing' }
WebFetchWebSocket >> printOn: aStream [
	super printOn: aStream.
	aStream nextPut: $(; nextPutAll: (url ifNil: [ '' ]); space; nextPutAll: self recordedState; nextPut: $)
]

{ #category : 'accessing' }
WebFetchWebSocket >> protocol [
	"The subprotocol that the server chose, empty for none; nil before the open"

	self refresh.
	^ protocol
]

{ #category : 'accessing' }
WebFetchWebSocket >> protocols [
	^ protocols
]

{ #category : 'configuring' }
WebFetchWebSocket >> protocols: aCollection [
	"The subprotocols to offer, in order of preference: tokens of RFC 7230, no two alike ignoring case, at most 32"

	| list |
	self checkNotStarted.
	list := (aCollection ifNil: [ #(  ) ]) asArray collect: [ :each | each asString ].
	list size > self class maximumProtocols ifTrue: [
		WebFetchBadRequest signal: 'At most 32 WebSocket subprotocols, not ' , list size printString ].
	list do: [ :each |
		(self class isToken: each) ifFalse: [
			WebFetchBadRequest signal: 'A WebSocket subprotocol is a token: ' , each printString ] ].
	(list collect: [ :each | each asLowercase ]) asSet size = list size ifFalse: [
		WebFetchBadRequest signal: 'A WebSocket subprotocol offered twice (ignoring case): ' , list printString ].
	protocols := list
]

{ #category : 'accessing' }
WebFetchWebSocket >> queuedCount [
	"The number of messages received and not read yet"

	self refresh.
	^ settled
		ifTrue: [ pending size ]
		ifFalse: [ queuedCount ]
]

{ #category : 'private' }
WebFetchWebSocket >> readEndRecord: aByteArray [
	"The info record of state 4 (protocol, extensions, URL, code, reason, clean) or the error record of state 5 (kind, message, protocol, extensions, URL)"

	| lines at |
	lines := self linesOf: aByteArray.
	at := [ :index | lines at: index ifAbsent: [ '' ] ].
	stateCode = 4
		ifTrue: [
			protocol := at value: 1.
			extensions := at value: 2.
			closeCode := (at value: 4) asInteger.
			closeReason := at value: 5.
			wasClean := (at value: 6) = '1' ]
		ifFalse: [
			(at value: 3) ifNotEmpty: [ :p | protocol := p ].
			(at value: 4) ifNotEmpty: [ :e | extensions := e ].
			(at value: 5) ifNotEmpty: [ openedBeforeFailure := true ].
			error := self class
				errorKind: ((at value: 1) ifEmpty: [ #network ] ifNotEmpty: [ :kind | kind asSymbol ])
				message: (at value: 2) ]
]

{ #category : 'private' }
WebFetchWebSocket >> readInfoLocked [
	"The info record of an open or closing socket: protocol, extensions, URL"

	| bytes lines |
	bytes := self hostDo: [ host infoOf: handle ] onReleased: [ nil ].
	(bytes isNil or: [ bytes == #noMemory ]) ifTrue: [ ^ self ].
	lines := self linesOf: bytes.
	protocol := lines at: 1 ifAbsent: [ '' ].
	extensions := lines at: 2 ifAbsent: [ '' ]
]

{ #category : 'private' }
WebFetchWebSocket >> receiveLocked [
	"The next message of the host queue as {isText. bytes}, or nil. Without the object memory for it, make room and try once more; then drop it, which fails the socket with tooLarge (the server gets 4009), and go on with the next one: a queue never stays blocked by a message that the image cannot hold"

	| message |
	[
		message := self hostDo: [ host receive: handle ] onReleased: [ nil ].
		message == #noMemory ifTrue: [
			self makeRoom.
			message := self hostDo: [ host receive: handle ] onReleased: [ nil ] ].
		message == #noMemory ] whileTrue: [
			| size |
			size := self hostDo: [ host drop: handle ] onReleased: [ nil ].
			size ifNil: [ ^ nil ].
			dropped := size ].
	^ message
]

{ #category : 'private' }
WebFetchWebSocket >> recordedState [
	^ #( #connecting #open #closing #closed #failed ) at: stateCode ifAbsent: [ #new ]
]

{ #category : 'private' }
WebFetchWebSocket >> refresh [
	stateCode = 0 ifTrue: [ ^ self ].
	settled ifTrue: [ ^ self ].
	self locked: [ self refreshLocked ]
]

{ #category : 'private' }
WebFetchWebSocket >> refreshLocked [
	"Ask the host for the state once; read the info record on the first look at an open socket, and settle one that is closed or failed. Answer the state code"

	| raw code |
	(settled or: [ stateCode = 0 ]) ifTrue: [ ^ stateCode ].
	raw := self hostDo: [ host stateOf: handle ] onReleased: [ nil ].
	raw ifNil: [ ^ stateCode ].
	code := raw bitAnd: 7.
	queuedCount := raw bitShift: -3.
	stateCode := code.
	code = 2 ifTrue: [ openedBeforeFailure := true ].
	((code = 2 or: [ code = 3 ]) and: [ protocol isNil ]) ifTrue: [ self readInfoLocked ].
	code >= 4 ifTrue: [ self settleLocked ].
	^ stateCode
]

{ #category : 'closing' }
WebFetchWebSocket >> release [
	"Forget the socket at once: the host closes it with 1000 'released' unless it is closing, what is queued is lost, and a waiter gets WebFetchAborted"

	self locked: [
		pending removeAll.
		settled ifFalse: [
			stateCode := 5.
			error := WebFetchAborted new
				messageText: 'The WebFetchWebSocket was released';
				yourself.
			self endLocked ] ]
]

{ #category : 'sending' }
WebFetchWebSocket >> send: aStringOrByteArray [
	"Send a String as text, anything else as binary"

	^ aStringOrByteArray isString
		ifTrue: [ self sendText: aStringOrByteArray ]
		ifFalse: [ self sendBytes: aStringOrByteArray ]
]

{ #category : 'private' }
WebFetchWebSocket >> send: aByteArray isText: aBoolean [
	"Send one message, waiting within timeout for the open and for room in the send buffer"

	| result |
	self checkStarted.
	aByteArray size > self class maximumSendSize ifTrue: [
		WebFetchTooLarge signal: 'A WebSocket message of ' , aByteArray size printString , ' bytes is more than 64 MiB' ].
	result := self
		await: 3
		for: [ self locked: [ self sendLocked: aByteArray isText: aBoolean ] ]
		deadline: (self deadlineAfter: timeout).
	result ifNil: [
		WebFetchTimeout signal: 'The WebSocket did not open, or had no room to send, within ' , timeout printString ].
	result == #closed ifTrue: [ self signalClosed ].
	result == #failed ifTrue: [ self signalEnd ]
]

{ #category : 'sending' }
WebFetchWebSocket >> sendBytes: aByteArray [
	"Send aByteArray as a binary message"

	self send: aByteArray asByteArray isText: false
]

{ #category : 'private' }
WebFetchWebSocket >> sendLocked: aByteArray isText: aBoolean [
	"Answer bufferedAmount after the send, nil to wait (no room, or not open yet), #closed or #failed"

	| answer |
	settled ifTrue: [ ^ stateCode = 4 ifTrue: [ #closed ] ifFalse: [ #failed ] ].
	answer := self hostDo: [ host send: handle bytes: aByteArray isText: aBoolean ] onReleased: [ #notOpen ].
	answer isInteger ifTrue: [ ^ answer ].
	answer == #full ifTrue: [ ^ nil ].
	self refreshLocked.
	(stateCode = 1 or: [ stateCode = 2 ]) ifTrue: [ ^ nil ].
	^ stateCode = 5
		ifTrue: [ #failed ]
		ifFalse: [ #closed ]
]

{ #category : 'sending' }
WebFetchWebSocket >> sendText: aString [
	"Send aString as a text message (its UTF-8)"

	self send: aString asString utf8Encoded isText: true
]

{ #category : 'initialization' }
WebFetchWebSocket >> setUrl: aUrlOrString [
	| string |
	string := aUrlOrString asString.
	self checkUrl: string.
	url := string
]

{ #category : 'private' }
WebFetchWebSocket >> settleLocked [
	"The host closed or failed the socket: read what is queued into pending, read its info or error record, release the host record and the semaphores, and wake every waiter"

	| message record |
	settled ifTrue: [ ^ self ].
	[ (message := self receiveLocked) notNil ] whileTrue: [ pending add: message ].
	record := self hostDo: [ host infoOf: handle ] onReleased: [ nil ].
	(record isNil or: [ record == #noMemory ]) ifFalse: [ self readEndRecord: record ].
	(dropped notNil and: [ stateCode = 4 ]) ifTrue: [
		stateCode := 5.
		error := WebFetchTooLarge new
			kind: #tooLarge;
			messageText: 'A message of ' , dropped printString , ' bytes is larger than the image can hold';
			yourself ].
	(stateCode = 5 and: [ error isNil ]) ifTrue: [
		error := WebFetchNetworkError new
			kind: #network;
			messageText: 'The WebSocket failed';
			yourself ].
	self endLocked
]

{ #category : 'private' }
WebFetchWebSocket >> signalClosed [
	^ (WebFetchWebSocketClosed code: closeCode reason: closeReason wasClean: wasClean) signal
]

{ #category : 'private' }
WebFetchWebSocket >> signalEnd [
	"Signal the end of an over socket: its error, or WebFetchWebSocketClosed"

	error ifNotNil: [ :e | ^ e copy signal ].
	^ self signalClosed
]

{ #category : 'opening' }
WebFetchWebSocket >> start [
	"Open the socket without waiting for the handshake; answer self in #connecting. Does nothing on a socket that was started"

	| record indexes |
	stateCode = 0 ifFalse: [ ^ self ].
	record := self openRecord.
	host := WebFetchWebSocketHost default.
	session := Smalltalk session.
	semaphores := { Semaphore new. Semaphore new. Semaphore new }.
	closer := WebFetchWebSocketCloser host: host semaphores: semaphores session: session.
	stateCode := 1.
	FinalizationRegistry default add: self finalizer: closer.
	[
		[
			indexes := semaphores collect: [ :each | Smalltalk registerExternalObject: each ].
			handle := closer
				openSemaphores: indexes
				record: record
				maxMessage: maximumMessageSize
				maxQueued: maximumQueuedBytes
				timeout: self timeoutMilliseconds.
			self class registerSocket: self ]
			on: Error
			do: [ :e |
				self endStartWith: e.
				e pass ] ]
		ifCurtailed: [
			self endStartWith: (WebFetchAborted new
				messageText: 'The start of the WebFetchWebSocket was curtailed';
				yourself) ]
]

{ #category : 'accessing' }
WebFetchWebSocket >> state [
	"Answer #new, #connecting, #open, #closing, #closed or #failed"

	self refresh.
	^ self recordedState
]

{ #category : 'private' }
WebFetchWebSocket >> takeLocked [
	"The next message as {isText. bytes}, #end when the socket is over and none is left, or nil"

	| message |
	pending ifNotEmpty: [ ^ pending removeFirst ].
	settled ifTrue: [ ^ #end ].
	message := self receiveLocked.
	message ifNotNil: [ ^ message ].
	self refreshLocked.
	pending ifNotEmpty: [ ^ pending removeFirst ].
	^ settled
		ifTrue: [ #end ]
		ifFalse: [ nil ]
]

{ #category : 'accessing' }
WebFetchWebSocket >> timeout [
	^ timeout
]

{ #category : 'configuring' }
WebFetchWebSocket >> timeout: aDurationOrSecondsOrNil [
	"The time for the handshake, and for a send to wait for the open or for room: a Duration, a Number of seconds, or nil (or Duration zero) for none"

	| duration |
	self checkNotStarted.
	aDurationOrSecondsOrNil ifNil: [
		timeout := nil.
		^ self ].
	duration := aDurationOrSecondsOrNil isNumber
		ifTrue: [ Duration milliSeconds: (aDurationOrSecondsOrNil * 1000) truncated ]
		ifFalse: [ aDurationOrSecondsOrNil ].
	(duration isKindOf: Duration) ifFalse: [
		WebFetchBadRequest signal: 'A WebSocket timeout is a Duration, a Number of seconds, or nil' ].
	(duration < Duration zero or: [ duration asMilliSeconds > 2147483647 ]) ifTrue: [
		WebFetchBadRequest signal: 'A WebSocket timeout is between 0 and 2^31-1 milliseconds' ].
	timeout := duration = Duration zero
		ifTrue: [ nil ]
		ifFalse: [ duration ]
]

{ #category : 'private' }
WebFetchWebSocket >> timeoutMilliseconds [
	^ timeout
		ifNil: [ 0 ]
		ifNotNil: [ :d | d asMilliSeconds truncated ]
]

{ #category : 'accessing' }
WebFetchWebSocket >> url [
	^ url
]

{ #category : 'private' }
WebFetchWebSocket >> validLimit: anInteger named: aString [
	(anInteger isInteger and: [ anInteger between: 1 and: self class maximumMessageSizeLimit ]) ifFalse: [
		WebFetchBadRequest signal: aString , ' is in 1..2^28, not ' , anInteger printString ].
	^ anInteger
]

{ #category : 'opening' }
WebFetchWebSocket >> waitForCloseTimeout: aDurationOrSeconds [
	"Wait up to aDurationOrSeconds until the socket is over; answer whether it is"

	self checkStarted.
	self
		await: 1
		for: [ self locked: [ self refreshLocked >= 4 ifTrue: [ true ] ifFalse: [ nil ] ] ]
		deadline: ((self deadlineAfter: aDurationOrSeconds) ifNil: [ Time millisecondClockValue ]).
	^ self isOver
]

{ #category : 'opening' }
WebFetchWebSocket >> waitForOpen [
	"Wait until the socket is no more #connecting, with no deadline of its own (the handshake timeout of the host ends it); signal the error of a socket that failed before it opened. A curtailed wait releases the socket"

	self checkStarted.
	[ self await: 1 for: [ self locked: [ self refreshLocked = 1 ifTrue: [ nil ] ifFalse: [ true ] ] ] deadline: nil ]
		ifCurtailed: [ self release ].
	(stateCode = 5 and: [ openedBeforeFailure not ]) ifTrue: [ self signalEnd ].
	^ self
]

{ #category : 'opening' }
WebFetchWebSocket >> waitForOpenTimeout: aDurationOrSeconds [
	"Wait up to aDurationOrSeconds until the socket is no more #connecting; answer whether it is open. Does not release it"

	self checkStarted.
	self
		await: 1
		for: [ self locked: [ self refreshLocked = 1 ifTrue: [ nil ] ifFalse: [ true ] ] ]
		deadline: ((self deadlineAfter: aDurationOrSeconds) ifNil: [ Time millisecondClockValue ]).
	^ self isOpen
]

{ #category : 'accessing' }
WebFetchWebSocket >> wasClean [
	"Whether the socket was closed by the closing handshake of both sides; nil before the close"

	self refresh.
	^ wasClean
]

{ #category : 'receiving' }
WebFetchWebSocket >> whenMessage: messageBlock whenClosed: closedBlock [
	"Fork a reader process at the caller's priority that evaluates messageBlock with each message, then closedBlock with the socket at its end (a close, a failure, a session end or a release: socket error says why when it is not a close), and answer it. An error in messageBlock is not caught: the process stops in a debugger, and the socket stays open"

	| process |
	self checkStarted.
	process := [
		| ended |
		ended := false.
		[ ended ] whileFalse: [
			| message |
			message := [ self next ]
				on: WebFetchError
				do: [ :e |
					ended := true.
					nil ].
			ended ifFalse: [ messageBlock cull: message ] ].
		closedBlock cull: self ] newProcess.
	process
		name: 'WebFetchWebSocket reader';
		priority: Processor activePriority;
		resume.
	^ process
]
