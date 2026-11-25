"
I am a pure-Smalltalk fake host with the same protocol as `WebFetchHost`, for testing `WebFetch` and `WebFetch-Zinc` natively without WebAssembly.

I validate arguments like `WebFetchPlugin`, signal registered semaphores via `Smalltalk specialObjectsArray at: 39`, enforce window backpressure, and never signal inside `startSemaphore:...` (automatic answers are delivered asynchronously by a forked process).
"
Class {
	#name : 'WebFetchTestHost',
	#superclass : 'Object',
	#instVars : [
		'mutex',
		'availability',
		'mayWait',
		'maxOpen',
		'autoDeliver',
		'nextId',
		'open',
		'requests',
		'closedCount',
		'maxBufferedBytes',
		'scriptQueue',
		'requestHandler',
		'readHook',
		'stateHook',
		'startHook'
	],
	#category : 'WebFetch-Tests-Host',
	#package : 'WebFetch-Tests',
	#tag : 'Host'
}

{ #category : 'accessing' }
WebFetchTestHost >> autoDeliver [
	^ autoDeliver
]

{ #category : 'accessing' }
WebFetchTestHost >> autoDeliver: aBoolean [
	autoDeliver := aBoolean
]

{ #category : 'host protocol' }
WebFetchTestHost >> availability [
	^ availability
]

{ #category : 'accessing' }
WebFetchTestHost >> availability: anInteger [
	availability := anInteger
]

{ #category : 'host protocol' }
WebFetchTestHost >> close: handle [
	| entry |
	handle isInteger ifFalse: [ ^ false ].
	entry := mutex critical: [ open removeKey: handle ifAbsent: [ nil ] ].
	entry ifNil: [ ^ false ].
	mutex critical: [
		closedCount := closedCount + 1.
		(entry at: #request) at: #closed put: true.
		entry at: #closed put: true ].
	^ true
]

{ #category : 'inspection' }
WebFetchTestHost >> closedCount [
	^ mutex critical: [ closedCount ]
]

{ #category : 'manual stepping' }
WebFetchTestHost >> deliverHeadFor: id status: code reason: reason url: url type: type redirected: aBoolean headers: headerAssociations [
	| sem |
	sem := mutex critical: [
		| entry lines headBytes |
		entry := open at: id ifAbsent: [ ^ self ].
		lines := String streamContents: [ :out |
			out
				print: code; lf;
				nextPutAll: (reason ifNil: [ '' ]); lf;
				nextPutAll: (url ifNil: [ '' ]); lf;
				nextPutAll: (type ifNil: [ 'basic' ]); lf;
				nextPutAll: (aBoolean ifTrue: [ '1' ] ifFalse: [ '0' ]).
			headerAssociations ifNotNil: [
				headerAssociations do: [ :assoc |
					out lf; nextPutAll: assoc key; nextPutAll: ': '; nextPutAll: assoc value ] ] ].
		headBytes := lines utf8Encoded.
		entry at: #head put: headBytes.
		entry at: #state put: 2.
		entry at: #semIndex ].
	self signalSemaphoreIndex: sem
]

{ #category : 'private' }
WebFetchTestHost >> deliverScript: script forId: id [
	| kind |
	kind := script at: #type.
	kind == #pending ifTrue: [ ^ self ].
	kind == #error ifTrue: [
		self fail: id kind: (script at: #kind) message: (script at: #message).
		^ self ].
	kind == #response ifTrue: [
		| body bytes chunkSize reqUrl finalUrl |
		reqUrl := mutex critical: [
			| entry |
			entry := open at: id ifAbsent: [ ^ self ].
			(entry at: #request) at: #url ].
		finalUrl := (script at: #url) ifNil: [ reqUrl ].
		body := script at: #body.
		bytes := body
			ifNil: [ #[ ] ]
			ifNotNil: [ body isString ifTrue: [ body utf8Encoded ] ifFalse: [ body ] ].
		chunkSize := script at: #chunkSize.
		mutex critical: [
			| entry |
			entry := open at: id ifAbsent: [ ^ self ].
			entry at: #remaining put: bytes.
			entry at: #remainingAt put: 1.
			entry at: #chunkSize put: chunkSize ].
		self
			deliverHeadFor: id
			status: (script at: #status)
			reason: (script at: #reason)
			url: finalUrl
			type: (script at: #responseType ifAbsent: [ 'basic' ])
			redirected: (script at: #redirected ifAbsent: [ false ])
			headers: (script at: #headers).
		self pumpBodyFor: id ]
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueErrorKind: kindSymbol message: aString [
	mutex critical: [
		scriptQueue add: (Dictionary new
			at: #type put: #error;
			at: #kind put: kindSymbol;
			at: #message put: aString;
			yourself) ]
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueuePending [
	mutex critical: [
		scriptQueue add: (Dictionary new
			at: #type put: #pending;
			yourself) ]
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueRedirectTo: finalUrl status: code headers: headerAssociations body: bytesOrString [
	mutex critical: [
		scriptQueue add: (Dictionary new
			at: #type put: #response;
			at: #status put: code;
			at: #reason put: 'OK';
			at: #url put: finalUrl;
			at: #redirected put: true;
			at: #headers put: (headerAssociations ifNil: [ #() ]);
			at: #body put: bytesOrString;
			at: #chunkSize put: nil;
			yourself) ]
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueStatus: code headers: headerAssociations body: bytesOrString [
	self
		enqueueStatus: code
		reason: 'OK'
		headers: headerAssociations
		body: bytesOrString
		chunkSize: nil
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueStatus: code headers: headerAssociations body: bytesOrString chunkSize: chunkSizeOrNil [
	self
		enqueueStatus: code
		reason: 'OK'
		headers: headerAssociations
		body: bytesOrString
		chunkSize: chunkSizeOrNil
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueStatus: code reason: reason headers: headerAssociations body: bytesOrString [
	self
		enqueueStatus: code
		reason: reason
		headers: headerAssociations
		body: bytesOrString
		chunkSize: nil
]

{ #category : 'scripting' }
WebFetchTestHost >> enqueueStatus: code reason: reason headers: headerAssociations body: bytesOrString chunkSize: chunkSizeOrNil [
	mutex critical: [
		scriptQueue add: (Dictionary new
			at: #type put: #response;
			at: #status put: code;
			at: #reason put: reason;
			at: #url put: nil;
			at: #redirected put: false;
			at: #headers put: (headerAssociations ifNil: [ #() ]);
			at: #body put: bytesOrString;
			at: #chunkSize put: chunkSizeOrNil;
			yourself) ]
]

{ #category : 'manual stepping' }
WebFetchTestHost >> fail: id kind: kindSymbol message: aString [
	| sem |
	sem := mutex critical: [
		| entry |
		entry := open at: id ifAbsent: [ ^ self ].
		entry at: #state put: 4.
		entry at: #head put: (kindSymbol asString , String lf , (aString ifNil: [ '' ])) utf8Encoded.
		entry at: #buffer put: OrderedCollection new.
		entry at: #bufferedSize put: 0.
		entry at: #remaining put: #[ ].
		entry at: #semIndex ].
	self signalSemaphoreIndex: sem
]

{ #category : 'manual stepping' }
WebFetchTestHost >> finish: id [
	| sem |
	sem := mutex critical: [
		| entry |
		entry := open at: id ifAbsent: [ ^ self ].
		(entry at: #state) = 4 ifTrue: [ ^ self ].
		entry at: #state put: 3.
		entry at: #semIndex ].
	self signalSemaphoreIndex: sem
]

{ #category : 'host protocol' }
WebFetchTestHost >> headOf: handle [
	handle isInteger ifFalse: [ PrimitiveFailed signal: 'primitiveFetchHead: bad argument' ].
	^ mutex critical: [
		| entry |
		entry := open at: handle ifAbsent: [
			WebFetchSessionEnded signal: 'primitiveFetchHead: handle not found' ].
		(entry at: #state) = 1
			ifTrue: [ nil ]
			ifFalse: [ (entry at: #head) copy ] ]
]

{ #category : 'initialization' }
WebFetchTestHost >> initialize [
	super initialize.
	mutex := Mutex new.
	self reset
]

{ #category : 'inspection' }
WebFetchTestHost >> lastId [
	^ mutex critical: [
		requests isEmpty ifTrue: [ nil ] ifFalse: [ requests last at: #id ] ]
]

{ #category : 'inspection' }
WebFetchTestHost >> lastRequest [
	^ mutex critical: [
		requests isEmpty ifTrue: [ nil ] ifFalse: [ requests last ] ]
]

{ #category : 'inspection' }
WebFetchTestHost >> maxBufferedBytes [
	^ mutex critical: [ maxBufferedBytes ]
]

{ #category : 'accessing' }
WebFetchTestHost >> maxOpen [
	^ maxOpen
]

{ #category : 'accessing' }
WebFetchTestHost >> maxOpen: anInteger [
	maxOpen := anInteger
]

{ #category : 'host protocol' }
WebFetchTestHost >> mayWait [
	^ mayWait
]

{ #category : 'accessing' }
WebFetchTestHost >> mayWait: aBoolean [
	mayWait := aBoolean
]

{ #category : 'manual stepping' }
WebFetchTestHost >> networkOff [
	| ids |
	ids := mutex critical: [
		availability := 2.
		open keys asArray ].
	ids do: [ :id | self fail: id kind: #off message: 'network access is off' ]
]

{ #category : 'scripting' }
WebFetchTestHost >> onRead: aBlock [
	"Optional hook evaluated during read:into:startingAt:count: outside mutex (for race/error tests)"

	mutex critical: [ readHook := aBlock ]
]

{ #category : 'scripting' }
WebFetchTestHost >> onRequest: aBlock [
	"Register a handler [ :reqDict | ... ] invoked asynchronously after start"

	mutex critical: [ requestHandler := aBlock ]
]

{ #category : 'scripting' }
WebFetchTestHost >> onStart: aBlock [
	"Optional hook evaluated during startSemaphore:... outside mutex before allocating the handle"

	mutex critical: [ startHook := aBlock ]
]

{ #category : 'scripting' }
WebFetchTestHost >> onState: aBlock [
	"Optional hook evaluated during stateOf: outside mutex (for concurrent-close tests)"

	mutex critical: [ stateHook := aBlock ]
]

{ #category : 'inspection' }
WebFetchTestHost >> openCount [
	^ mutex critical: [ open size ]
]

{ #category : 'private' }
WebFetchTestHost >> parseHeadBytes: headBytes [
	| text lines headers |
	text := headBytes utf8Decoded.
	lines := WebFetchResponse splitOnLF: text.
	headers := OrderedCollection new.
	3 to: lines size do: [ :i |
		| line colon name val |
		line := lines at: i.
		colon := line indexOf: $:.
		colon > 0 ifTrue: [
			name := line copyFrom: 1 to: colon - 1.
			val := line copyFrom: colon + 1 to: line size.
			(val notEmpty and: [ val first = Character space ]) ifTrue: [ val := val allButFirst ].
			headers add: name -> val ] ].
	^ { lines first. lines second. headers }
]

{ #category : 'private' }
WebFetchTestHost >> pumpBodyFor: id [
	"Feed remaining scripted bytes into the entry buffer up to window, finishing at EOF"

	| shouldSignal semIndex |
	shouldSignal := false.
	semIndex := nil.
	mutex critical: [
		| entry rem at window buffered chunkSize |
		entry := open at: id ifAbsent: [ ^ self ].
		(entry at: #state) = 2 ifFalse: [ ^ self ].
		rem := entry at: #remaining ifAbsent: [ nil ].
		rem ifNil: [ ^ self ].
		at := entry at: #remainingAt.
		window := entry at: #window.
		buffered := entry at: #bufferedSize.
		chunkSize := entry at: #chunkSize.
		semIndex := entry at: #semIndex.
		[ at <= rem size and: [ buffered < window ] ] whileTrue: [
			| take slice |
			take := rem size - at + 1.
			chunkSize ifNotNil: [ take := take min: chunkSize ].
			take := take min: (window - buffered).
			slice := rem copyFrom: at to: at + take - 1.
			(entry at: #buffer) add: slice.
			buffered = 0 ifTrue: [ shouldSignal := true ].
			buffered := buffered + take.
			buffered >= window ifTrue: [ shouldSignal := true ].
			buffered > maxBufferedBytes ifTrue: [ maxBufferedBytes := buffered ].
			at := at + take ].
		entry at: #remainingAt put: at.
		entry at: #bufferedSize put: buffered.
		(at > rem size and: [ buffered < window or: [ rem isEmpty ] ]) ifTrue: [
			entry at: #state put: 3.
			shouldSignal := true ] ].
	shouldSignal ifTrue: [ self signalSemaphoreIndex: semIndex ]
]

{ #category : 'manual stepping' }
WebFetchTestHost >> pushBytes: aByteArray for: id [
	| shouldSignal semIndex |
	aByteArray isEmpty ifTrue: [ ^ self ].
	shouldSignal := false.
	semIndex := nil.
	mutex critical: [
		| entry prev next |
		entry := open at: id ifAbsent: [ ^ self ].
		(entry at: #state) = 2 ifFalse: [ ^ self ].
		prev := entry at: #bufferedSize.
		(entry at: #buffer) add: aByteArray copy.
		next := prev + aByteArray size.
		entry at: #bufferedSize put: next.
		next > maxBufferedBytes ifTrue: [ maxBufferedBytes := next ].
		shouldSignal := prev = 0 or: [ next >= (entry at: #window) ].
		semIndex := entry at: #semIndex ].
	shouldSignal ifTrue: [ self signalSemaphoreIndex: semIndex ]
]

{ #category : 'host protocol' }
WebFetchTestHost >> read: handle into: aByteArray startingAt: startIndex count: count [
	| hook copied |
	handle isInteger ifFalse: [ PrimitiveFailed signal: 'primitiveFetchRead: bad argument' ].
	(aByteArray isKindOf: ByteArray) ifFalse: [ PrimitiveFailed signal: 'primitiveFetchRead: bad argument' ].
	aByteArray isReadOnlyObject ifTrue: [ PrimitiveFailed signal: 'primitiveFetchRead: no modification' ].
	(startIndex isInteger and: [ count isInteger and: [ startIndex >= 1 and: [ count >= 0 and: [ startIndex + count - 1 <= aByteArray size ] ] ] ])
		ifFalse: [ PrimitiveFailed signal: 'primitiveFetchRead: bad index' ].
	hook := mutex critical: [ readHook ].
	hook ifNotNil: [ hook cull: handle ].
	copied := mutex critical: [
		| entry chunks written |
		entry := open at: handle ifAbsent: [
			WebFetchSessionEnded signal: 'primitiveFetchRead: handle not found' ].
		((entry at: #state) = 1 or: [ (entry at: #state) = 4 ])
			ifTrue: [ 0 ]
			ifFalse: [
				chunks := entry at: #buffer.
				written := 0.
				[ written < count and: [ chunks notEmpty ] ] whileTrue: [
					| first avail take |
					first := chunks first.
					avail := first size.
					take := (count - written) min: avail.
					aByteArray
						replaceFrom: startIndex + written
						to: startIndex + written + take - 1
						with: first
						startingAt: 1.
					written := written + take.
					take = avail
						ifTrue: [ chunks removeFirst ]
						ifFalse: [ chunks at: 1 put: (first copyFrom: take + 1 to: avail) ] ].
				entry at: #bufferedSize put: (entry at: #bufferedSize) - written.
				written ] ].
	self pumpBodyFor: handle.
	^ copied
]

{ #category : 'inspection' }
WebFetchTestHost >> requests [
	^ mutex critical: [ requests copy ]
]

{ #category : 'initialization' }
WebFetchTestHost >> reset [
	mutex critical: [
		availability := 1.
		mayWait := true.
		maxOpen := 64.
		autoDeliver := true.
		nextId := 1.
		open := Dictionary new.
		requests := OrderedCollection new.
		closedCount := 0.
		maxBufferedBytes := 0.
		scriptQueue := OrderedCollection new.
		requestHandler := nil.
		readHook := nil.
		stateHook := nil.
		startHook := nil ]
]

{ #category : 'private' }
WebFetchTestHost >> signalSemaphoreIndex: semIndex [
	| table sem |
	semIndex ifNil: [ ^ self ].
	table := Smalltalk specialObjectsArray at: 39.
	(semIndex between: 1 and: table size) ifFalse: [ ^ self ].
	sem := table at: semIndex.
	sem ifNotNil: [ sem signal ]
]

{ #category : 'host protocol' }
WebFetchTestHost >> startSemaphore: semIndex head: headBytes body: bodyBytesOrNil window: windowBytes timeout: timeoutMs flags: flags [
	| table parsed reqRecord id entry script handler hook |
	hook := mutex critical: [ startHook ].
	hook ifNotNil: [ hook value ].
	availability = 0 ifTrue: [ WebFetchUnavailable signal: 'WebFetch is not available' ].
	availability = 2 ifTrue: [ WebFetchNetworkOff signal: 'Network access is off' ].
	table := Smalltalk specialObjectsArray at: 39.
	(semIndex isInteger and: [ semIndex between: 1 and: table size ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid semaphore index' ].
	((headBytes isKindOf: ByteArray) and: [ headBytes size between: 1 and: 1048576 ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid head ByteArray' ].
	(bodyBytesOrNil isNil or: [ bodyBytesOrNil isKindOf: ByteArray ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid body ByteArray' ].
	(windowBytes isInteger and: [ windowBytes between: 1 and: 2147483647 ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid window size' ].
	(timeoutMs isInteger and: [ timeoutMs between: 0 and: 2147483647 ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid timeout' ].
	(flags = 0 or: [ flags = 1 ]) ifFalse: [
		WebFetchBadRequest signal: 'Invalid flags' ].
	parsed := self parseHeadBytes: headBytes.
	script := nil.
	handler := nil.
	id := mutex critical: [
		| allocated |
		open size >= maxOpen ifTrue: [
			WebFetchTooManyOpen signal: 'Too many open WebFetch requests' ].
		allocated := nextId.
		nextId := nextId + 1.
		reqRecord := Dictionary new
			at: #id put: allocated;
			at: #method put: (parsed at: 1);
			at: #url put: (parsed at: 2);
			at: #headers put: (parsed at: 3);
			at: #body put: (bodyBytesOrNil ifNotNil: [ bodyBytesOrNil copy ]);
			at: #window put: windowBytes;
			at: #timeout put: timeoutMs;
			at: #flags put: flags;
			at: #closed put: false;
			yourself.
		entry := Dictionary new
			at: #id put: allocated;
			at: #semIndex put: semIndex;
			at: #state put: 1;
			at: #head put: nil;
			at: #buffer put: OrderedCollection new;
			at: #bufferedSize put: 0;
			at: #window put: windowBytes;
			at: #request put: reqRecord;
			at: #closed put: false;
			yourself.
		open at: allocated put: entry.
		requests add: reqRecord.
		autoDeliver ifTrue: [
			scriptQueue notEmpty
				ifTrue: [ script := scriptQueue removeFirst ]
				ifFalse: [ handler := requestHandler ] ].
		allocated ].
	"Never signal synchronously inside startSemaphore:..."
	(script notNil or: [ handler notNil ]) ifTrue: [
		[
			script
				ifNotNil: [ self deliverScript: script forId: id ]
				ifNil: [ handler value: reqRecord ] ] forkAt: Processor activePriority ].
	^ id
]

{ #category : 'host protocol' }
WebFetchTestHost >> stateOf: handle [
	| hook |
	handle isInteger ifFalse: [ PrimitiveFailed signal: 'primitiveFetchState: bad argument' ].
	hook := mutex critical: [ stateHook ].
	hook ifNotNil: [ hook cull: handle ].
	^ mutex critical: [
		| entry |
		entry := open at: handle ifAbsent: [
			WebFetchSessionEnded signal: 'primitiveFetchState: handle not found' ].
		(entry at: #state) + ((entry at: #bufferedSize) * 8) ]
]
