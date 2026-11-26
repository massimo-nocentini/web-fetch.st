"
I read Server-Sent Events, an event stream (`text/event-stream`), as the `EventSource` of a browser does, over `WebFetchCall` and `WebFetchBodyStream`: `WebFetch eventSource: url`, or `(WebFetch request: url) ... ; eventSource` for any method, headers and body.

Each connection is one streaming call (1 MiB window), with `Accept: text/event-stream` unless the request has an `Accept`, `Last-Event-ID` (the UTF-8 of `lastEventId`) when it is not empty, the cache mode no-store, and no timeout: a `timeout` of the request becomes my `connectTimeout`, the longest wait for a head. A VM that refuses the cache mode gets `Cache-Control: no-cache` instead, from then on. `WebFetchEventParser` parses the bodies.

- At the end of a body, and after a network error, a timeout or `WebFetchTooManyOpen`, I connect again after the reconnection time (`reconnectDelay`, changed by the `retry` of the server, at least `minimumReconnectDelay`, doubled for each connection in a row that gave no event, up to `maximumReconnectDelay`). By default only a GET reconnects (`reconnects:`). Without reconnection a clean end closes me and a broken body fails me.
- Before my first open, every error is terminal unless `retriesFirstConnection: true`.
- A status other than 200, or a media type other than `text/event-stream`, fails me with `WebFetchBadResponse`; so do the errors of the table of the README (`WebFetchNetworkOff`, `WebFetchTooLarge`, `WebFetchSessionEnded`, ...). The events queued before a failure are answered first.

`next` answers the next event, waiting through reconnections, or nil once I am closed (by `close`, or a clean end without reconnection), and signals my terminal error; `nextTimeout:` answers nil when the time passes; `do:` reads them all and closes me. One process reads; `close` comes from any process. A wait that is curtailed (Stop, `terminate`, an unwinding) closes me and aborts my request. `lastEventId` is the id of the last event delivered: a new source given it resumes where the code stopped.

`start` forks a reader instead, for tools and the UI: a process at the priority of the caller that gives each connection opened to `onOpen:`, each event to `onEvent:`, each interruption to `onReconnect:` (nil at the end of a body, else the transient error) and the terminal error to `onError:`, then ends; terminating it closes me. The blocks run in that process, not deferred to the UI: a slow block slows the reading, and a block that updates a morph defers to the UI itself (`UIManager default defer:`). A started source survives Stop of the Console and the Notebook; `openSources` lists the sources from their first connection to their close, and `closeAll` or `WebFetch abortAll` closes them. A source never goes on after the image resumed: it fails with `WebFetchSessionEnded`, unless it was closed before. A close leaves no error, also when it lands while the reader is ending the source with one.

Settings, set before the first connection: `reconnectDelay:`, `minimumReconnectDelay:`, `maximumReconnectDelay:` (Durations, or Numbers of seconds), `reconnects:`, `retriesFirstConnection:`, `connectTimeout:`, `idleTimeout:`, `maximumEventSize:`, `lastEventId:`.
"
Class {
	#name : 'WebFetchEventSource',
	#superclass : 'Object',
	#instVars : [
		'request',
		'host',
		'session',
		'readyState',
		'call',
		'stream',
		'parser',
		'response',
		'error',
		'errorSignalled',
		'closedByClient',
		'wakeup',
		'mutex',
		'reconnectAt',
		'delay',
		'misses',
		'hadEvent',
		'hasOpened',
		'connections',
		'connectStartedAt',
		'consumedId',
		'lastByteAt',
		'buffer',
		'initialDelay',
		'minimumDelay',
		'maximumDelay',
		'reconnects',
		'retriesFirstConnection',
		'connectTimeout',
		'idleTimeout',
		'pulled',
		'process',
		'onOpen',
		'onEvent',
		'onReconnect',
		'onError'
	],
	#classVars : [
		'NoStoreRefusedBy',
		'OpenSources',
		'OpenSourcesMutex'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'control' }
WebFetchEventSource class >> closeAll [
	"Close every open source, outside the mutex of the open sources"

	self openSources do: [ :each | each close ]
]

{ #category : 'constants' }
WebFetchEventSource class >> defaultMaximumEventSize [
	"1 MiB of data in one event"

	^ 1048576
]

{ #category : 'constants' }
WebFetchEventSource class >> defaultMaximumReconnectDelay [
	^ 60 seconds
]

{ #category : 'constants' }
WebFetchEventSource class >> defaultMinimumReconnectDelay [
	^ 250 milliSeconds
]

{ #category : 'constants' }
WebFetchEventSource class >> defaultReconnectDelay [
	^ 3 seconds
]

{ #category : 'class initialization' }
WebFetchEventSource class >> initialize [
	self resetOpenSources.
	SessionManager default registerNetworkClassNamed: self name
]

{ #category : 'accessing' }
WebFetchEventSource class >> openCount [
	^ self openSources size
]

{ #category : 'accessing' }
WebFetchEventSource class >> openSources [
	"Answer a snapshot Array of the sources from their first connection to their close"

	| mutex |
	mutex := OpenSourcesMutex.
	mutex ifNil: [ ^ #( ) ].
	^ mutex critical: [
		Array streamContents: [ :stream |
			OpenSources do: [ :each |
				each ifNotNil: [ each isClosed ifFalse: [ stream nextPut: each ] ] ] ] ]
]

{ #category : 'constants' }
WebFetchEventSource class >> refusedBodyLimit [
	"The most bytes kept of the body of a refused answer"

	^ 65536
]

{ #category : 'constants' }
WebFetchEventSource class >> refusedBodyTime [
	"The longest wait for the body of a refused answer"

	^ 5 seconds
]

{ #category : 'private' }
WebFetchEventSource class >> register: aSource [
	OpenSourcesMutex critical: [ OpenSources add: aSource ]
]

{ #category : 'instance creation' }
WebFetchEventSource class >> request: aWebFetchRequest [
	"A source of a copy of aWebFetchRequest, not yet connected. A Last-Event-ID header of it is the initial lastEventId, and its timeout the connectTimeout"

	^ self new
		setRequest: aWebFetchRequest;
		yourself
]

{ #category : 'private' }
WebFetchEventSource class >> resetOpenSources [
	OpenSources := WeakSet new.
	OpenSourcesMutex := Mutex new
]

{ #category : 'system startup' }
WebFetchEventSource class >> startUp: resuming [
	"On image resume, a fresh set of open sources without taking the old mutex; each old source is marked ended, without closing its call or its stream"

	| old |
	resuming ifFalse: [ ^ self ].
	old := OpenSources.
	self resetOpenSources.
	NoStoreRefusedBy := nil.
	old ifNotNil: [
		old do: [ :each | each ifNotNil: [ each markSessionEnded ] ] ]
]

{ #category : 'class initialization' }
WebFetchEventSource class >> unload [
	SessionManager default unregisterClassNamed: self name
]

{ #category : 'private' }
WebFetchEventSource class >> unregister: aSource [
	| mutex |
	mutex := OpenSourcesMutex.
	mutex ifNil: [ ^ self ].
	mutex critical: [ OpenSources remove: aSource ifAbsent: [ ] ]
]

{ #category : 'private' }
WebFetchEventSource >> abandon [
	"A wait was curtailed: close, unless the source already failed"

	error ifNil: [ self close ]
]

{ #category : 'private' }
WebFetchEventSource >> checkHead: aResponse before: deadline [
	"The head came: open on an event stream, else fail with WebFetchBadResponse"

	| refusal |
	(aResponse status = 200 and: [ aResponse mediaType = 'text/event-stream' ]) ifFalse: [
		self readRefusedBodyOf: aResponse before: deadline.
		refusal := aResponse status = 200
			ifTrue: [ 'answer of type ' , (aResponse mediaType ifEmpty: [ 'none' ]) , ', not text/event-stream' ]
			ifFalse: [ 'answer status ' , aResponse status printString , ', not 200' ].
		^ self failWith: ((WebFetchError kind: #response message: refusal)
			response: aResponse;
			yourself) ].
	mutex critical: [
		closedByClient ifFalse: [
			stream := WebFetchBodyStream on: call response: aResponse.
			readyState := #open ] ].
	closedByClient ifTrue: [ ^ #again ].
	parser
		startConnection;
		origin: (self originOf: aResponse url).
	response := aResponse.
	hasOpened := true.
	hadEvent := false.
	lastByteAt := Time millisecondClockValue.
	^ #open -> aResponse
]

{ #category : 'private' }
WebFetchEventSource >> checkReader [
	process ifNotNil: [ self error: 'the events of a started source go to its blocks' ]
]

{ #category : 'private' }
WebFetchEventSource >> checkSession [
	"A source never goes on in another session; one that was closed before keeps its end"

	(session notNil and: [ readyState ~~ #closed and: [ session ~~ Smalltalk session ] ]) ifTrue: [
		self markSessionEnded ]
]

{ #category : 'private' }
WebFetchEventSource >> checkSettable [
	session ifNotNil: [ self error: 'set before the first connection' ]
]

{ #category : 'closing' }
WebFetchEventSource >> close [
	"Close the source from any process: abort its connection, cut a reconnection wait short. next answers nil from then on, and the queued events are dropped"

	| closing |
	closedByClient := true.
	mutex critical: [
		closing := call.
		readyState := #closed ].
	closing ifNotNil: [ closing close ].
	wakeup signal.
	self class unregister: self
]

{ #category : 'private' }
WebFetchEventSource >> closeCleanly [
	"The body ended and the source does not reconnect"

	self dropConnection.
	mutex critical: [ readyState := #closed ].
	reconnectAt := nil.
	self class unregister: self.
	^ #again
]

{ #category : 'accessing' }
WebFetchEventSource >> connectTimeout [
	"The longest wait for the head of a connection, or nil"

	^ connectTimeout ifNotNil: [ :ms | Duration milliSeconds: ms ]
]

{ #category : 'settings' }
WebFetchEventSource >> connectTimeout: aDurationOrSecondsOrNil [
	"The longest wait for the head of a connection (more than 0), or nil to wait without end"

	| ms |
	self checkSettable.
	aDurationOrSecondsOrNil ifNil: [
		connectTimeout := nil.
		^ self ].
	ms := self milliseconds: aDurationOrSecondsOrNil of: 'connectTimeout'.
	ms > 0 ifFalse: [ WebFetchBadRequest signal: 'connectTimeout must be more than 0' ].
	connectTimeout := ms
]

{ #category : 'private' }
WebFetchEventSource >> connectBefore: deadline [
	"Start a connection"

	| copy refused |
	session ifNil: [
		session := Smalltalk session.
		self class register: self ].
	copy := self connectionRequest.
	refused := nil.
	[ copy buildForDefaultTimeout: nil ]
		on: WebFetchBadRequest
		do: [ :e | refused := e ].
	refused ifNotNil: [ ^ self failWith: refused ].
	hadEvent := false.
	[
		mutex critical: [
			closedByClient ifFalse: [
				call := WebFetchCall startRequest: copy window: WebFetchCall defaultStreamWindow ] ] ]
		on: WebFetchBadRequest , WebFetchTooManyOpen , WebFetchUnavailable
		do: [ :e | refused := e ].
	refused ifNotNil: [
		((refused isKindOf: WebFetchBadRequest) and: [ copy isNoStore ]) ifTrue: [
			"a VM before the cache mode no-store: Cache-Control: no-cache from now on"
			NoStoreRefusedBy := host.
			^ #again ].
		^ self endConnection: refused ].
	closedByClient ifTrue: [ ^ #again ].
	connections := connections + 1.
	connectStartedAt := Time millisecondClockValue.
	^ #again
]

{ #category : 'private' }
WebFetchEventSource >> connectOrWaitBefore: deadline [
	"No connection: wait for the reconnection time, then connect"

	| now wait |
	reconnectAt ifNil: [ ^ self connectBefore: deadline ].
	now := Time millisecondClockValue.
	reconnectAt <= now ifTrue: [
		reconnectAt := nil.
		^ self connectBefore: deadline ].
	wait := reconnectAt - now.
	deadline ifNotNil: [ wait := wait min: deadline - now ].
	wait <= 0 ifTrue: [ ^ nil ].
	WebFetchCall checkMayWait: host.
	[ wakeup waitTimeoutMilliseconds: wait ] ifCurtailed: [ self abandon ].
	^ #again
]

{ #category : 'private' }
WebFetchEventSource >> connectionRequest [
	"The request of the next connection: a copy of mine, with the headers of the source and no timeout"

	| copy |
	copy := request copy.
	copy timeout: nil.
	(self request: copy hasHeader: 'Accept') ifFalse: [ copy headerAt: 'Accept' put: 'text/event-stream' ].
	parser lastEventId ifNotEmpty: [ :id |
		"the characters of the header are the bytes of the UTF-8 of the id"
		copy headerAt: 'Last-Event-ID' put: id utf8Encoded asString ].
	NoStoreRefusedBy == host
		ifTrue: [
			(self request: copy hasHeader: 'Cache-Control') ifFalse: [
				copy headerAt: 'Cache-Control' put: 'no-cache' ] ]
		ifFalse: [ copy noStore: true ].
	^ copy
]

{ #category : 'accessing' }
WebFetchEventSource >> connections [
	"How many connections were started"

	^ connections
]

{ #category : 'private' }
WebFetchEventSource >> deliver [
	"Answer the first queued event; its id is the one consumed"

	| event |
	event := parser nextEvent.
	consumedId := event lastEventId.
	parser hasEvents ifFalse: [ consumedId := parser lastEventId ].
	^ event
]

{ #category : 'enumerating' }
WebFetchEventSource >> do: aBlock [
	"Evaluate aBlock with each event until next answers nil, then close the source, also when aBlock unwinds"

	| event |
	self checkReader.
	pulled := true.
	session ifNil: [ WebFetchCall checkMayWait: host ].
	[ [ (event := self next) notNil ] whileTrue: [ aBlock value: event ] ] ensure: [ self close ]
]

{ #category : 'private' }
WebFetchEventSource >> dispatch: anItem [
	"Give an event or a notice of the loop to its block"

	(anItem isKindOf: WebFetchEvent) ifTrue: [ ^ onEvent ifNotNil: [ :block | block cull: anItem ] ].
	anItem key == #open ifTrue: [ ^ onOpen ifNotNil: [ :block | block cull: anItem value ] ].
	anItem key == #reconnect ifTrue: [ ^ onReconnect ifNotNil: [ :block | block cull: anItem value ] ]
]

{ #category : 'private' }
WebFetchEventSource >> dropConnection [
	"Close the stream and the call of the connection, if any"

	| s c |
	s := stream.
	c := call.
	stream := nil.
	s ifNotNil: [ s close ].
	c ifNotNil: [ c close ].
	mutex critical: [
		call := nil.
		readyState == #closed ifFalse: [ readyState := #connecting ] ]
]

{ #category : 'private' }
WebFetchEventSource >> endConnection: anErrorOrNil [
	"The connection ended: nil at the end of its body, else the error. Reconnect, close, or fail"

	| reason |
	reason := anErrorOrNil.
	closedByClient ifTrue: [
		self dropConnection.
		^ #again ].
	reason ifNotNil: [
		(self isTransient: reason) ifFalse: [ ^ self failWith: reason ].
		(hasOpened or: [ retriesFirstConnection ]) ifFalse: [ ^ self failWith: reason ] ].
	self willReconnect ifFalse: [
		^ reason
			ifNil: [ self closeCleanly ]
			ifNotNil: [ self failWith: reason ] ].
	self dropConnection.
	reconnectAt := Time millisecondClockValue + self reconnectionDelay.
	^ #reconnect -> reason
]

{ #category : 'accessing' }
WebFetchEventSource >> error [
	"The terminal error, or nil"

	^ error
]

{ #category : 'private' }
WebFetchEventSource >> failWith: anError [
	"Close the source with a terminal error, which next signals after the queued events; after a close of the client, without one"

	closedByClient ifFalse: [ error ifNil: [ error := anError ] ].
	self dropConnection.
	mutex critical: [ readyState := #closed ].
	reconnectAt := nil.
	self class unregister: self.
	^ #again
]

{ #category : 'accessing' }
WebFetchEventSource >> idleTimeout [
	^ idleTimeout ifNotNil: [ :ms | Duration milliSeconds: ms ]
]

{ #category : 'settings' }
WebFetchEventSource >> idleTimeout: aDurationOrSecondsOrNil [
	"When no byte came for that long (a comment of the server counts), drop the connection and reconnect; nil for none"

	| ms |
	self checkSettable.
	aDurationOrSecondsOrNil ifNil: [
		idleTimeout := nil.
		^ self ].
	ms := self milliseconds: aDurationOrSecondsOrNil of: 'idleTimeout'.
	ms > 0 ifFalse: [ WebFetchBadRequest signal: 'idleTimeout must be more than 0' ].
	idleTimeout := ms
]

{ #category : 'initialization' }
WebFetchEventSource >> initialize [
	super initialize.
	host := WebFetchHost default.
	readyState := #connecting.
	parser := WebFetchEventParser new.
	parser maximumEventSize: self class defaultMaximumEventSize.
	errorSignalled := false.
	closedByClient := false.
	wakeup := Semaphore new.
	mutex := Mutex new.
	misses := 0.
	hadEvent := false.
	hasOpened := false.
	connections := 0.
	consumedId := ''.
	buffer := ByteArray new: 16384.
	initialDelay := self class defaultReconnectDelay asMilliSeconds.
	delay := initialDelay.
	minimumDelay := self class defaultMinimumReconnectDelay asMilliSeconds.
	maximumDelay := self class defaultMaximumReconnectDelay asMilliSeconds.
	retriesFirstConnection := false.
	pulled := false
]

{ #category : 'testing' }
WebFetchEventSource >> isClosed [
	^ readyState == #closed
]

{ #category : 'testing' }
WebFetchEventSource >> isOpen [
	^ readyState == #open
]

{ #category : 'private' }
WebFetchEventSource >> isTransient: anError [
	"The errors after which a source reconnects"

	^ (anError isKindOf: WebFetchNetworkError)
		or: [ (anError isKindOf: WebFetchTimeout)
		or: [ anError isKindOf: WebFetchTooManyOpen ] ]
]

{ #category : 'accessing' }
WebFetchEventSource >> lastEventId [
	"The id to resume from: the lastEventId of the last event delivered, or of the stream when no event is queued"

	^ consumedId
]

{ #category : 'settings' }
WebFetchEventSource >> lastEventId: aString [
	"The id to resume from, sent as Last-Event-ID with the first connection already"

	| bytes |
	self checkSettable.
	aString isString ifFalse: [ WebFetchBadRequest signal: 'lastEventId must be a String' ].
	(aString includesAny: { Character cr. Character lf. Character value: 0 }) ifTrue: [
		WebFetchBadRequest signal: 'lastEventId must not contain CR, LF or NUL' ].
	bytes := aString utf8Encoded.
	bytes size > WebFetchEventParser maximumFieldSize ifTrue: [
		WebFetchBadRequest signal: 'lastEventId longer than ' , WebFetchEventParser maximumFieldSize printString , ' bytes' ].
	parser lastEventId: aString asString.
	consumedId := aString asString
]

{ #category : 'private' }
WebFetchEventSource >> loopError: anError [
	"An error of the source's own loop: fail with it, and pass it on as it is"

	(anError isKindOf: WebFetchInCallback) ifTrue: [ ^ anError pass ].
	closedByClient ifFalse: [
		self failWith: anError.
		errorSignalled := true ].
	^ anError pass
]

{ #category : 'private' }
WebFetchEventSource >> markSessionEnded [
	"The image resumed: the source is ended, without a host call. A closed source keeps its end"

	readyState == #closed ifTrue: [ ^ self ].
	error ifNil: [
		error := WebFetchSessionEnded new messageText: 'Smalltalk session ended while the event source was open' ].
	readyState := #closed.
	reconnectAt := nil.
	wakeup signal
]

{ #category : 'accessing' }
WebFetchEventSource >> maximumEventSize [
	^ parser maximumEventSize
]

{ #category : 'settings' }
WebFetchEventSource >> maximumEventSize: anInteger [
	"The most bytes of the data of one event, 1 to 2^31-2: its UTF-8 with the line feeds between its lines"

	self checkSettable.
	(anInteger isInteger and: [ anInteger between: 1 and: WebFetchRequest maxWindowSize - 1 ]) ifFalse: [
		WebFetchBadRequest signal: 'maximumEventSize out of range 1..2^31-2' ].
	parser maximumEventSize: anInteger
]

{ #category : 'accessing' }
WebFetchEventSource >> maximumReconnectDelay [
	^ Duration milliSeconds: maximumDelay
]

{ #category : 'settings' }
WebFetchEventSource >> maximumReconnectDelay: aDurationOrSeconds [
	"The cap of the backoff (more than 0); a retry of the server above it is still honoured"

	| ms |
	self checkSettable.
	ms := self milliseconds: aDurationOrSeconds of: 'maximumReconnectDelay'.
	ms > 0 ifFalse: [ WebFetchBadRequest signal: 'maximumReconnectDelay must be more than 0' ].
	maximumDelay := ms
]

{ #category : 'private' }
WebFetchEventSource >> milliseconds: aDurationOrSeconds of: aName [
	| ms |
	aDurationOrSeconds isNumber
		ifTrue: [ ms := aDurationOrSeconds * 1000 ]
		ifFalse: [
			(aDurationOrSeconds isKindOf: Duration) ifFalse: [
				WebFetchBadRequest signal: aName , ' must be a Duration or a Number of seconds' ].
			ms := aDurationOrSeconds asMilliSeconds ].
	ms < 0 ifTrue: [ WebFetchBadRequest signal: aName , ' must not be negative' ].
	^ ms truncated min: WebFetchRequest maxWindowSize
]

{ #category : 'accessing' }
WebFetchEventSource >> minimumReconnectDelay [
	^ Duration milliSeconds: minimumDelay
]

{ #category : 'settings' }
WebFetchEventSource >> minimumReconnectDelay: aDurationOrSeconds [
	"The floor of every reconnection delay, the retry of the server included (at least 0)"

	self checkSettable.
	minimumDelay := self milliseconds: aDurationOrSeconds of: 'minimumReconnectDelay'
]

{ #category : 'reading' }
WebFetchEventSource >> next [
	"Answer the next event, waiting through reconnections, or nil once the source is closed. Signal the terminal error, after the events queued before it"

	| item |
	self checkReader.
	pulled := true.
	session ifNil: [ WebFetchCall checkMayWait: host ].
	[
		item := self nextItemBefore: nil.
		item isNil or: [ item isKindOf: WebFetchEvent ] ] whileFalse.
	^ item
]

{ #category : 'private' }
WebFetchEventSource >> nextItemBefore: deadlineOrNil [
	"Answer the next event, a notice (#open -> response, #reconnect -> reasonOrNil), or nil when the source is closed or the deadline (a millisecond clock value) passed. Signal the terminal error"

	| item |
	item := [ self stepsBefore: deadlineOrNil ]
		on: Error
		do: [ :e | self loopError: e ].
	item == #closed ifTrue: [ ^ self signalEnd ].
	^ item
]

{ #category : 'reading' }
WebFetchEventSource >> nextTimeout: aDurationOrSeconds [
	"As next, but answer nil also when aDurationOrSeconds passes; the source stays as it was. Zero never waits"

	| ms deadline item |
	self checkReader.
	pulled := true.
	ms := self milliseconds: aDurationOrSeconds of: 'nextTimeout:'.
	(ms > 0 and: [ session isNil ]) ifTrue: [ WebFetchCall checkMayWait: host ].
	deadline := Time millisecondClockValue + ms.
	[
		item := self nextItemBefore: deadline.
		item isNil or: [ item isKindOf: WebFetchEvent ] ] whileFalse.
	^ item
]

{ #category : 'reader' }
WebFetchEventSource >> onError: aBlock [
	"The forked reader evaluates aBlock with the terminal error once the source is closed: a WebFetchError, OutOfMemory, or another Error of the source's loop. Not after close"

	onError := aBlock
]

{ #category : 'reader' }
WebFetchEventSource >> onEvent: aBlock [
	"The forked reader evaluates aBlock with each WebFetchEvent"

	onEvent := aBlock
]

{ #category : 'reader' }
WebFetchEventSource >> onOpen: aBlock [
	"The forked reader evaluates aBlock with the WebFetchResponse of each connection that opens on an event stream"

	onOpen := aBlock
]

{ #category : 'reader' }
WebFetchEventSource >> onReconnect: aBlock [
	"The forked reader evaluates aBlock at each interruption, before the reconnection delay: with nil at the end of a body, else with the transient WebFetchError"

	onReconnect := aBlock
]

{ #category : 'connecting' }
WebFetchEventSource >> open [
	"Connect and wait until the source is open, through reconnections. Signal the terminal errors"

	| item |
	self checkReader.
	pulled := true.
	session ifNil: [ WebFetchCall checkMayWait: host ].
	[ readyState == #open or: [ parser hasEvents ] ] whileFalse: [
		item := self nextItemBefore: nil.
		item ifNil: [ ^ self ] ].
	^ self
]

{ #category : 'private' }
WebFetchEventSource >> originOf: aUrlString [
	"scheme://host[:port] of aUrlString"

	| scheme end |
	aUrlString ifNil: [ ^ nil ].
	scheme := aUrlString indexOfSubCollection: '://'.
	scheme = 0 ifTrue: [ ^ aUrlString ].
	end := scheme + 3.
	[ end <= aUrlString size and: [ ('/?#' includes: (aUrlString at: end)) not ] ] whileTrue: [ end := end + 1 ].
	^ aUrlString copyFrom: 1 to: end - 1
]

{ #category : 'printing' }
WebFetchEventSource >> printOn: aStream [
	aStream
		nextPutAll: self class name;
		nextPut: $(;
		print: readyState;
		space;
		nextPutAll: self url asString;
		nextPut: $)
]

{ #category : 'accessing' }
WebFetchEventSource >> process [
	"The forked reader, or nil"

	^ process
]

{ #category : 'private' }
WebFetchEventSource >> readBefore: deadline [
	"The source is open: read and parse the next bytes"

	| ready failure n tooLarge waited |
	waited := false.
	failure := nil.
	ready := [ stream isReadReady ]
		on: WebFetchError
		do: [ :e |
			failure := e.
			true ].
	failure ifNotNil: [ ^ self endConnection: failure ].
	ready ifFalse: [
		| now limit idleAt remaining |
		now := Time millisecondClockValue.
		idleAt := idleTimeout ifNotNil: [ :ms | lastByteAt + ms ].
		limit := deadline.
		idleAt ifNotNil: [ limit := limit ifNil: [ idleAt ] ifNotNil: [ limit min: idleAt ] ].
		remaining := limit ifNotNil: [ limit - now ].
		(remaining notNil and: [ remaining <= 0 ]) ifTrue: [
			(idleAt notNil and: [ idleAt <= now ]) ifTrue: [
				^ self endConnection: (WebFetchError
					kind: #timeout
					message: 'no byte for ' , idleTimeout printString , ' ms') ].
			^ nil ].
		WebFetchCall checkMayWait: host.
		[
			ready := [ stream waitTimeout: (remaining ifNotNil: [ Duration milliSeconds: remaining ]) ]
				on: WebFetchError
				do: [ :e |
					failure := e.
					true ] ] ifCurtailed: [ self abandon ].
		failure ifNotNil: [ ^ self endConnection: failure ].
		ready ifFalse: [ ^ #again ].
		waited := true ].
	n := [ stream readInto: buffer startingAt: 1 count: buffer size ]
		on: WebFetchError
		do: [ :e |
			failure := e.
			0 ].
	failure ifNotNil: [ ^ self endConnection: failure ].
	n = 0 ifTrue: [
		parser endOfStream.
		^ self endConnection: nil ].
	lastByteAt := Time millisecondClockValue.
	tooLarge := nil.
	[ parser feed: buffer count: n ]
		on: WebFetchTooLarge
		do: [ :e | tooLarge := e ].
	parser takeRetry ifNotNil: [ :ms | delay := ms ].
	parser hasEvents
		ifTrue: [
			hadEvent := true.
			misses := 0 ]
		ifFalse: [ consumedId := parser lastEventId ].
	tooLarge ifNotNil: [ self failWith: tooLarge ].
	"a reader that always finds bytes lets the other processes of its priority run"
	waited ifFalse: [ Processor yield ].
	^ #again
]

{ #category : 'private' }
WebFetchEventSource >> readRefusedBodyOf: aResponse before: deadline [
	"Keep at most refusedBodyLimit bytes of the body of a refused answer, read within refusedBodyTime and the deadline; with no time left, or in an FFI callback, only the bytes already there"

	| refused bytes size limit mayWait done |
	refused := WebFetchBodyStream on: call response: aResponse.
	bytes := ByteArray new: self class refusedBodyLimit.
	size := 0.
	limit := Time millisecondClockValue + self class refusedBodyTime asMilliSeconds.
	deadline ifNotNil: [ limit := limit min: deadline ].
	mayWait := WebFetchCall mayWaitWith: host.
	done := false.
	[
		[
			[ done or: [ size >= bytes size ] ] whileFalse: [
				| remaining ready n |
				remaining := limit - Time millisecondClockValue.
				ready := (mayWait and: [ remaining > 0 ])
					ifTrue: [ refused waitTimeout: (Duration milliSeconds: remaining) ]
					ifFalse: [ refused isReadReady ].
				ready
					ifTrue: [
						n := refused readInto: bytes startingAt: size + 1 count: bytes size - size.
						size := size + n.
						done := n = 0 ]
					ifFalse: [ done := true ] ] ]
			on: WebFetchError
			do: [ :e | ] ] ifCurtailed: [ self abandon ].
	aResponse rawContents: (bytes copyFrom: 1 to: size)
]

{ #category : 'accessing' }
WebFetchEventSource >> readyState [
	"#connecting, #open or #closed"

	^ readyState
]

{ #category : 'accessing' }
WebFetchEventSource >> reconnectDelay [
	"The current reconnection time: the setting, or the last retry of the server"

	^ Duration milliSeconds: delay
]

{ #category : 'settings' }
WebFetchEventSource >> reconnectDelay: aDurationOrSeconds [
	"The reconnection time until the server sends retry (at least 0)"

	self checkSettable.
	initialDelay := self milliseconds: aDurationOrSeconds of: 'reconnectDelay'.
	delay := initialDelay
]

{ #category : 'private' }
WebFetchEventSource >> reconnectionDelay [
	"The milliseconds to wait before the next connection: the reconnection time, at least the floor, doubled for each connection in a row without an event, up to the cap"

	| base |
	base := delay max: minimumDelay.
	hadEvent ifTrue: [ ^ base ].
	misses := misses + 1.
	^ base * (2 raisedTo: (misses - 1 min: 16)) min: (maximumDelay max: base)
]

{ #category : 'settings' }
WebFetchEventSource >> reconnects: aBooleanOrNil [
	"nil: reconnect a GET only (the default); true: any method; false: never"

	self checkSettable.
	(aBooleanOrNil isNil or: [ aBooleanOrNil isKindOf: Boolean ]) ifFalse: [
		WebFetchBadRequest signal: 'reconnects must be nil, true or false' ].
	reconnects := aBooleanOrNil
]

{ #category : 'accessing' }
WebFetchEventSource >> request [
	"A copy of the request of the source"

	^ request copy
]

{ #category : 'private' }
WebFetchEventSource >> request: aRequest hasHeader: aName [
	| lower |
	lower := aName asLowercase.
	^ aRequest headers anySatisfy: [ :each | each key asLowercase = lower ]
]

{ #category : 'accessing' }
WebFetchEventSource >> response [
	"The WebFetchResponse of the last connection that had a head, or nil"

	^ response
]

{ #category : 'settings' }
WebFetchEventSource >> retriesFirstConnection: aBoolean [
	"false (the default): an error before the first head of an event stream is terminal; true: it is transient, as it is later"

	self checkSettable.
	(aBoolean isKindOf: Boolean) ifFalse: [ WebFetchBadRequest signal: 'retriesFirstConnection must be true or false' ].
	retriesFirstConnection := aBoolean
]

{ #category : 'private' }
WebFetchEventSource >> runReader [
	"The loop of the forked reader: the blocks are evaluated here, outside the handlers of the loop. It closes the source when it ends"

	| item failure |
	[
		[
			failure := nil.
			item := [ self nextItemBefore: nil ]
				on: Error
				do: [ :e |
					failure := e.
					nil ].
			item notNil ] whileTrue: [ self dispatch: item ].
		(failure notNil and: [ closedByClient not ]) ifTrue: [
			onError ifNotNil: [ :block | block cull: failure ] ] ]
		ensure: [ self close ]
]

{ #category : 'initialization' }
WebFetchEventSource >> setRequest: aWebFetchRequest [
	| copy timeout |
	copy := aWebFetchRequest copy.
	(copy headers detect: [ :each | each key asLowercase = 'last-event-id' ] ifNone: [ nil ]) ifNotNil: [ :header |
		self lastEventId: header value.
		copy removeHeaderNamed: 'Last-Event-ID' ].
	request := copy.
	timeout := copy timeout.
	timeout ifNotNil: [
		timeout isZero ifFalse: [ self connectTimeout: timeout ] ]
]

{ #category : 'private' }
WebFetchEventSource >> signalEnd [
	"The source is closed: answer nil, or signal its terminal error"

	error ifNil: [ ^ nil ].
	errorSignalled := true.
	^ error copy signal
]

{ #category : 'reader' }
WebFetchEventSource >> start [
	"Fork the reader, a process at the priority of the caller that connects and gives the events and notices to the blocks of onOpen:, onEvent:, onReconnect: and onError:, and answer it. The process ends when the source closes, and closes it when it is terminated"

	process ifNotNil: [ self error: 'the source is started already' ].
	pulled ifTrue: [ self error: 'the events of this source are read with next' ].
	process := [ self runReader ] newProcess.
	process
		name: 'WebFetchEventSource ' , self url asString;
		priority: Processor activePriority.
	process resume.
	^ process
]

{ #category : 'private' }
WebFetchEventSource >> stepsBefore: deadline [
	"Answer the next item, #closed, or nil when the deadline passed"

	| item |
	[
		self checkSession.
		closedByClient ifTrue: [
			self dropConnection.
			^ nil ].
		parser hasEvents ifTrue: [ ^ self deliver ].
		readyState == #closed ifTrue: [
			self dropConnection.
			^ #closed ].
		item := stream
			ifNotNil: [ self readBefore: deadline ]
			ifNil: [
				call
					ifNotNil: [ self waitForHeadBefore: deadline ]
					ifNil: [ self connectOrWaitBefore: deadline ] ].
		item == #again ] whileTrue.
	^ item
]

{ #category : 'accessing' }
WebFetchEventSource >> url [
	^ request url
]

{ #category : 'private' }
WebFetchEventSource >> waitForHeadBefore: deadline [
	"A connection was started: wait for its head, until the deadline or the connectTimeout"

	| ready failure head |
	failure := nil.
	ready := [ call refreshState ~= 1 ]
		on: WebFetchError
		do: [ :e |
			failure := e.
			true ].
	failure ifNotNil: [ ^ self endConnection: failure ].
	ready ifFalse: [
		| now limit connectAt remaining |
		now := Time millisecondClockValue.
		connectAt := connectTimeout ifNotNil: [ :ms | connectStartedAt + ms ].
		limit := deadline.
		connectAt ifNotNil: [ limit := limit ifNil: [ connectAt ] ifNotNil: [ limit min: connectAt ] ].
		remaining := limit ifNotNil: [ limit - now ].
		(remaining notNil and: [ remaining <= 0 ]) ifTrue: [
			(connectAt notNil and: [ connectAt <= now ]) ifTrue: [
				^ self endConnection: (WebFetchError
					kind: #timeout
					message: 'no head after ' , connectTimeout printString , ' ms') ].
			^ nil ].
		WebFetchCall checkMayWait: host.
		[
			[ call waitUntil: [ call refreshState ~= 1 ] timeout: remaining ]
				on: WebFetchError
				do: [ :e | failure := e ] ] ifCurtailed: [ self abandon ].
		failure ifNotNil: [ ^ self endConnection: failure ].
		^ #again ].
	head := [ call headResponse ]
		on: WebFetchError
		do: [ :e |
			failure := e.
			nil ].
	failure ifNotNil: [ ^ self endConnection: failure ].
	^ self checkHead: head before: deadline
]

{ #category : 'private' }
WebFetchEventSource >> willReconnect [
	^ reconnects ifNil: [ request method asString asUppercase = 'GET' ]
]
