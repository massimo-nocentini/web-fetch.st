"
I am a fake `WebFetchWebSocketHost` in Smalltalk, for testing `WebFetchWebSocket` natively, without WebAssembly. I am a subclass so that my failures go through the failure methods of the real host: I fail as the `WebSocketPlugin` does (the same codes for the same arguments) and the mapping is the real one.

I model the VM, not only the protocol: each socket has three semaphore indexes, which I signal by the table of `web-socket.js` (entering 2, 4 or 5: all three; the queue going from empty to one message: read; a drain: write) through `Smalltalk specialObjectsArray at: 39`; `newSession` forgets every socket (the ids of an image that was saved); `onNextPrimitive:` runs a block before the next primitive call, to fail, release or deliver there; `readyStateClosing:` is a close frame of the server, seen with no event; released sockets may linger (`lingerOnRelease:`) and count towards `maxOpen`; `failReceives:with:` makes Receive fail.

What the server does is scripted: `deliverOpen:protocol:extensions:`, `deliverText:to:`, `deliverBytes:to:`, `deliverCloseTo:code:reason:clean:`, `fail:kind:message:`, `buffered:for:`, `drain:`, `networkOff`. With `autoOpen` (the default) a socket opens by itself, after the primitive, choosing the first subprotocol offered; with `autoClose` (the default) a close of the image is answered; with `echo:` what is sent comes back.
"
Class {
	#name : 'WebFetchWebSocketTestHost',
	#superclass : 'WebFetchWebSocketHost',
	#instVars : [
		'mutex',
		'availability',
		'mayWait',
		'maxOpen',
		'highWater',
		'autoOpen',
		'autoClose',
		'echo',
		'holdSends',
		'lingerOnRelease',
		'nextId',
		'records',
		'lingering',
		'opens',
		'sent',
		'closes',
		'drops',
		'releasedCount',
		'hostCalls',
		'receiveFailures',
		'receiveFailureCode',
		'nextPrimitive'
	],
	#category : 'WebFetch-WebSocket-Tests-Host',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Host'
}

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> autoClose: aBoolean [
	autoClose := aBoolean
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> autoOpen: aBoolean [
	autoOpen := aBoolean
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> availability [
	^ availability
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> availability: anInteger [
	availability := anInteger
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> bufferedOf: id [
	^ (self primitive: id failWith: [ :code | self queryFailed: code operation: 'primitiveWebSocketBuffered' ])
		at: #buffered
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> buffered: anInteger for: id [
	"Set the bufferedAmount of a socket, as a send to a peer that does not read"

	mutex critical: [ (records at: id ifAbsent: [ ^ self ]) at: #buffered put: anInteger ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> close: id code: code reason: reasonBytesOrNil [
	| record started |
	self runNextPrimitive.
	(code isInteger and: [ code = 1000 or: [ code between: 3000 and: 4999 ] ]) ifFalse: [
		^ self closeFailed: #'bad argument' ].
	(reasonBytesOrNil isNil or: [ (self isByteArray: reasonBytesOrNil) and: [ reasonBytesOrNil size <= 123 ] ])
		ifFalse: [ ^ self closeFailed: #'bad argument' ].
	(reasonBytesOrNil isNil or: [ self isUTF8: reasonBytesOrNil ]) ifFalse: [ ^ self closeFailed: #'bad argument' ].
	(id isInteger and: [ id between: 1 and: 16r7FFFFFFF ]) ifFalse: [ ^ self closeFailed: #'not found' ].
	started := mutex critical: [
		record := records at: id ifAbsent: [ nil ].
		record ifNotNil: [
			(record at: #state) >= 3
				ifTrue: [ false ]
				ifFalse: [
					record at: #closedConnecting put: (record at: #state) = 1.
					record at: #state put: 3.
					closes add: { id. code. reasonBytesOrNil ifNotNil: [ reasonBytesOrNil utf8Decoded ] }.
					true ] ] ].
	record ifNil: [ ^ self closeFailed: #'not found' ].
	(started and: [ autoClose ]) ifTrue: [
		self later: [
			(record at: #closedConnecting)
				ifTrue: [ self deliverCloseTo: id code: 1006 reason: 'closed before it was open' clean: false ]
				ifFalse: [
					self
						deliverCloseTo: id
						code: code
						reason: (reasonBytesOrNil ifNil: [ '' ] ifNotNil: [ reasonBytesOrNil utf8Decoded ])
						clean: true ] ] ].
	^ started
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> closes [
	"The closes that the server got: {id. code. reason or nil}"

	^ mutex critical: [ closes copy ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliver: aMessage to: id [
	"A message of the server: queued, or the socket fails with tooLarge or overflow"

	| record bytes signal |
	bytes := aMessage at: 2.
	signal := mutex critical: [
		record := records at: id ifAbsent: [ ^ self ].
		((record at: #state) between: 2 and: 3) ifFalse: [ ^ self ].
		bytes size > (record at: #maxMessage)
			ifTrue: [ #tooLarge ]
			ifFalse: [
				(((record at: #queue) notEmpty and: [ (record at: #queuedBytes) + bytes size > (record at: #maxQueued) ])
					or: [ (record at: #queue) size >= 65536 ])
					ifTrue: [ #overflow ]
					ifFalse: [
						(record at: #queue) add: { aMessage at: 1. bytes copy }.
						record at: #queuedBytes put: (record at: #queuedBytes) + bytes size.
						(record at: #queue) size = 1 ] ] ].
	signal == #tooLarge ifTrue: [
		^ self fail: id kind: #tooLarge message: 'a message of ' , bytes size printString , ' bytes is more than the maximum' closing: 4009 reason: 'message too large' ].
	signal == #overflow ifTrue: [
		^ self fail: id kind: #overflow message: 'more than the bytes queued at most' closing: 4008 reason: 'too many unread messages' ].
	signal ifTrue: [ self signal: record at: #read ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliverBytes: aByteArray to: id [
	self deliver: { false. aByteArray } to: id
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliverCloseTo: id code: code reason: aString clean: aBoolean [
	"The close event: state 4, all three semaphores signalled"

	| record |
	mutex critical: [
		record := records at: id ifAbsent: [ ^ self ].
		(record at: #state) >= 4 ifTrue: [ ^ self ].
		record
			at: #state put: 4;
			at: #code put: code;
			at: #reason put: aString;
			at: #clean put: aBoolean ].
	self signalAll: record
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliverOpen: id [
	"The open event, the first subprotocol offered chosen"

	| offered |
	offered := mutex critical: [ (records at: id ifAbsent: [ ^ self ]) at: #offered ].
	self
		deliverOpen: id
		protocol: (offered ifEmpty: [ '' ] ifNotEmpty: [ offered first ])
		extensions: ''
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliverOpen: id protocol: aString extensions: extensionsString [
	"The open event: state 2, all three semaphores signalled"

	| record |
	mutex critical: [
		record := records at: id ifAbsent: [ ^ self ].
		(record at: #state) = 1 ifFalse: [ ^ self ].
		record
			at: #state put: 2;
			at: #opened put: true;
			at: #protocol put: aString;
			at: #extensions put: extensionsString ].
	self signalAll: record
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> deliverText: aString to: id [
	self deliver: { true. aString utf8Encoded } to: id
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> drain: id [
	"The send buffer is empty again: write signalled"

	| record |
	mutex critical: [
		record := records at: id ifAbsent: [ ^ self ].
		record at: #buffered put: 0 ].
	self signal: record at: #write
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> drop: id [
	| record message |
	record := self primitive: id failWith: [ :code | self queryFailed: code operation: 'primitiveWebSocketDrop' ].
	message := mutex critical: [
		(record at: #queue) ifEmpty: [ nil ] ifNotEmpty: [ :queue |
			| m |
			m := queue removeFirst.
			record at: #queuedBytes put: (record at: #queuedBytes) - (m at: 2) size.
			drops add: { id. (m at: 2) size }.
			m ] ].
	message ifNil: [ ^ nil ].
	(record at: #state) <= 3 ifTrue: [
		self
			fail: id
			kind: #tooLarge
			message: 'a message of ' , (message at: 2) size printString , ' bytes is larger than the image can hold'
			closing: 4009
			reason: 'message too large' ].
	^ (message at: 2) size
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> drops [
	"The messages dropped: {id. size}"

	^ mutex critical: [ drops copy ]
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> echo: aBoolean [
	"Whether what is sent comes back"

	echo := aBoolean
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> endLingering [
	"The close events of the released sockets came"

	mutex critical: [ lingering removeAll ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> fail: id kind: kindSymbol message: aString [
	"The socket fails: state 5, its queue kept, all three semaphores signalled"

	self fail: id kind: kindSymbol message: aString closing: nil reason: nil
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> fail: id kind: kindSymbol message: aString closing: codeOrNil reason: reasonString [
	| record |
	mutex critical: [
		record := records at: id ifAbsent: [ ^ self ].
		(record at: #state) >= 4 ifTrue: [ ^ self ].
		record
			at: #state put: 5;
			at: #errorKind put: kindSymbol;
			at: #errorMessage put: aString.
		codeOrNil ifNotNil: [ closes add: { id. codeOrNil. reasonString } ] ].
	self signalAll: record
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> failReceives: anInteger with: errorCode [
	"Make the next anInteger Receives fail with errorCode (#'insufficient object memory'); the message stays queued"

	mutex critical: [
		receiveFailures := anInteger.
		receiveFailureCode := errorCode ]
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> holdSends: aBoolean [
	"Whether a send adds its size to bufferedAmount (a peer that does not read)"

	holdSends := aBoolean
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> hostCalls [
	^ mutex critical: [ hostCalls ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> infoOf: id [
	| record lines |
	record := self primitive: id failWith: [ :code | self queryFailed: code operation: 'primitiveWebSocketInfo' ].
	lines := mutex critical: [
		| state base |
		state := record at: #state.
		state = 1 ifTrue: [ ^ nil ].
		base := { record at: #protocol. record at: #extensions. record at: #url }.
		state = 4
			ifTrue: [ base , { (record at: #code) printString. record at: #reason. (record at: #clean) ifTrue: [ '1' ] ifFalse: [ '0' ] } ]
			ifFalse: [
				state = 5
					ifTrue: [
						{ (record at: #errorKind) asString. record at: #errorMessage. record at: #protocol. record at: #extensions.
						(record at: #opened) ifTrue: [ record at: #url ] ifFalse: [ '' ] } ]
					ifFalse: [ base ] ] ].
	^ (String lf join: (lines collect: [ :each | each copyReplaceAll: String lf with: ' ' ])) utf8Encoded
]

{ #category : 'initialization' }
WebFetchWebSocketTestHost >> initialize [
	super initialize.
	mutex := Mutex new.
	availability := 1.
	mayWait := true.
	maxOpen := 32.
	highWater := 16 * 1024 * 1024.
	autoOpen := true.
	autoClose := true.
	echo := false.
	holdSends := false.
	lingerOnRelease := false.
	nextId := 1.
	records := Dictionary new.
	lingering := Set new.
	opens := OrderedCollection new.
	sent := OrderedCollection new.
	closes := OrderedCollection new.
	drops := OrderedCollection new.
	releasedCount := 0.
	hostCalls := 0.
	receiveFailures := 0
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> isByteArray: anObject [
	"As the plugin: a ByteArray, and a CompiledMethod is none"

	^ anObject class == ByteArray
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> isUTF8: aByteArray [
	^ [
		aByteArray utf8Decoded.
		true ]
		on: Error
		do: [ :e | false ]
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> lastId [
	^ mutex critical: [ opens ifEmpty: [ nil ] ifNotEmpty: [ opens last at: #id ] ]
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> lastOpen [
	"What the last open got: #id, #url, #protocols, #maxMessage, #maxQueued, #timeout, #indexes"

	^ mutex critical: [ opens ifEmpty: [ nil ] ifNotEmpty: [ opens last ] ]
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> later: aBlock [
	"Evaluate aBlock after the primitive, as an event of the host"

	[ aBlock value ] forkAt: Processor activePriority
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> lingerOnRelease: aBoolean [
	"Whether a released socket that is not over lingers (counts towards maxOpen) until endLingering"

	lingerOnRelease := aBoolean
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> lingeringCount [
	^ mutex critical: [ lingering size ]
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> maxOpen: anInteger [
	maxOpen := anInteger
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> mayWait [
	^ mayWait
]

{ #category : 'accessing' }
WebFetchWebSocketTestHost >> mayWait: aBoolean [
	mayWait := aBoolean
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> networkOff [
	"The network is turned off: every socket in 1, 2 or 3 fails with off, its queue kept"

	| ids |
	ids := mutex critical: [
		availability := 2.
		(records select: [ :each | (each at: #state) <= 3 ]) keys asArray ].
	ids do: [ :id |
		self fail: id kind: #off message: 'network access is off' closing: 1000 reason: 'network access is off' ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> newSession [
	"Forget every socket, as the VM of a resumed image has none: their ids are not found"

	mutex critical: [
		records removeAll.
		lingering removeAll ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> onNextPrimitive: aBlock [
	"Evaluate aBlock once, at the start of the next primitive call, outside the mutex"

	mutex critical: [ nextPrimitive := aBlock ]
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> openCount [
	^ mutex critical: [ records size ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> openState: stateIndex read: readIndex write: writeIndex record: recordBytes maxMessage: maxMessage maxQueued: maxQueued timeout: timeoutMs [
	| table indexes lines id record |
	self runNextPrimitive.
	table := Smalltalk specialObjectsArray at: 39.
	indexes := { stateIndex. readIndex. writeIndex }.
	((indexes allSatisfy: [ :each | each isInteger and: [ each between: 1 and: table size ] ])
		and: [ indexes asSet size = 3
		and: [ (self isByteArray: recordBytes)
		and: [ (recordBytes size between: 1 and: 65536)
		and: [ (maxMessage isInteger and: [ maxMessage between: 1 and: 268435456 ])
		and: [ (maxQueued isInteger and: [ maxQueued between: 1 and: 268435456 ])
		and: [ timeoutMs isInteger and: [ timeoutMs between: 0 and: 2147483647 ] ] ] ] ] ] ])
		ifFalse: [ ^ self openFailed: #'bad argument' ].
	availability = 1 ifFalse: [ ^ self openFailed: #'unsupported operation' ].
	lines := WebFetchResponse splitOnLF: recordBytes utf8Decoded.
	id := mutex critical: [
		records size + lingering size >= maxOpen ifTrue: [ nil ] ifFalse: [
			| allocated |
			allocated := nextId.
			nextId := nextId + 1.
			record := Dictionary new
				at: #id put: allocated;
				at: #indexes put: indexes;
				at: #url put: lines first;
				at: #offered put: lines allButFirst asArray;
				at: #maxMessage put: maxMessage;
				at: #maxQueued put: maxQueued;
				at: #timeout put: timeoutMs;
				at: #state put: 1;
				at: #opened put: false;
				at: #closedConnecting put: false;
				at: #readyStateClosing put: false;
				at: #queue put: OrderedCollection new;
				at: #queuedBytes put: 0;
				at: #buffered put: 0;
				at: #protocol put: '';
				at: #extensions put: '';
				yourself.
			records at: allocated put: record.
			opens add: (Dictionary new
				at: #id put: allocated;
				at: #url put: lines first;
				at: #protocols put: lines allButFirst asArray;
				at: #maxMessage put: maxMessage;
				at: #maxQueued put: maxQueued;
				at: #timeout put: timeoutMs;
				at: #indexes put: indexes;
				yourself).
			allocated ] ].
	id ifNil: [ ^ self openFailed: #'resource limit exceeded' ].
	autoOpen ifTrue: [ self later: [ self deliverOpen: id ] ].
	^ id
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> opens [
	^ mutex critical: [ opens copy ]
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> primitive: id failWith: failBlock [
	"Count the call, run the hook of onNextPrimitive:, and answer the record of id, or the value of failBlock with the code of the plugin"

	self runNextPrimitive.
	id isInteger ifFalse: [ ^ failBlock value: #'bad argument' ].
	^ (mutex critical: [ records at: id ifAbsent: [ nil ] ]) ifNil: [ failBlock value: #'not found' ]
]

{ #category : 'scripting' }
WebFetchWebSocketTestHost >> readyStateClosing: id [
	"A close frame of the server, which no event tells: the state becomes 3 when it is asked for, and a send is refused"

	mutex critical: [ (records at: id ifAbsent: [ ^ self ]) at: #readyStateClosing put: true ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> receive: id [
	| record |
	record := self primitive: id failWith: [ :code | self queryFailed: code operation: 'primitiveWebSocketReceive' ].
	mutex critical: [
		receiveFailures > 0 ifTrue: [
			receiveFailures := receiveFailures - 1.
			^ self queryFailed: receiveFailureCode operation: 'primitiveWebSocketReceive' ] ].
	^ mutex critical: [
		(record at: #queue) ifEmpty: [ nil ] ifNotEmpty: [ :queue |
			| m |
			m := queue removeFirst.
			record at: #queuedBytes put: (record at: #queuedBytes) - (m at: 2) size.
			{ m at: 1. (m at: 2) copy } ] ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> release: id [
	| record |
	self runNextPrimitive.
	id isInteger ifFalse: [ ^ false ].
	mutex critical: [
		record := records removeKey: id ifAbsent: [ nil ].
		record ifNotNil: [
			releasedCount := releasedCount + 1.
			(lingerOnRelease and: [ (record at: #state) <= 3 ]) ifTrue: [ lingering add: id ] ] ].
	^ record notNil
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> releasedCount [
	^ mutex critical: [ releasedCount ]
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> runNextPrimitive [
	| hook |
	hook := mutex critical: [
		hostCalls := hostCalls + 1.
		nextPrimitive ifNotNil: [ :block |
			nextPrimitive := nil.
			block ] ].
	hook ifNotNil: [ hook value ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> send: id bytes: aByteArray isText: aBoolean [
	| record answer |
	self runNextPrimitive.
	((self isByteArray: aByteArray) and: [ (aBoolean == true or: [ aBoolean == false ]) and: [ aByteArray size <= (64 * 1024 * 1024) ] ])
		ifFalse: [ ^ self sendFailed: #'bad argument' ].
	id isInteger ifFalse: [ ^ self sendFailed: #'bad argument' ].
	record := mutex critical: [ records at: id ifAbsent: [ nil ] ].
	record ifNil: [ ^ self sendFailed: #'not found' ].
	(aBoolean and: [ (self isUTF8: aByteArray) not ]) ifTrue: [ ^ self sendFailed: #'bad argument' ].
	answer := mutex critical: [
		| buffered |
		buffered := record at: #buffered.
		((record at: #state) = 2 and: [ (record at: #readyStateClosing) not ])
			ifFalse: [ #'inappropriate operation' ]
			ifTrue: [
				(buffered > 0 and: [ buffered + aByteArray size > highWater ])
					ifTrue: [ #'resource limit exceeded' ]
					ifFalse: [
						sent add: { id. aBoolean. aByteArray copy }.
						holdSends ifTrue: [ record at: #buffered put: buffered + aByteArray size ].
						record at: #buffered ] ] ].
	answer isSymbol ifTrue: [ ^ self sendFailed: answer ].
	echo ifTrue: [
		| copy |
		copy := { aBoolean. aByteArray copy }.
		self later: [ self deliver: copy to: id ] ].
	^ answer
]

{ #category : 'inspection' }
WebFetchWebSocketTestHost >> sent [
	"The messages sent: {id. isText. bytes}"

	^ mutex critical: [ sent copy ]
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> signal: record at: aSymbol [
	"Signal the semaphore of the socket for #state, #read or #write, while the socket is known"

	| index table semaphore |
	(mutex critical: [ (records at: (record at: #id) ifAbsent: [ nil ]) == record ]) ifFalse: [ ^ self ].
	index := (record at: #indexes) at: (#( #state #read #write ) indexOf: aSymbol).
	table := Smalltalk specialObjectsArray at: 39.
	(index between: 1 and: table size) ifFalse: [ ^ self ].
	semaphore := table at: index.
	semaphore ifNotNil: [ semaphore signal ]
]

{ #category : 'private' }
WebFetchWebSocketTestHost >> signalAll: record [
	#( #state #read #write ) do: [ :each | self signal: record at: each ]
]

{ #category : 'host protocol' }
WebFetchWebSocketTestHost >> stateOf: id [
	| record |
	record := self primitive: id failWith: [ :code | self queryFailed: code operation: 'primitiveWebSocketState' ].
	^ mutex critical: [
		((record at: #state) = 2 and: [ record at: #readyStateClosing ]) ifTrue: [ record at: #state put: 3 ].
		(record at: #state) + ((record at: #queue) size * 8) ]
]
