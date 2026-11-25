"
I represent one in-flight or completed HTTP exchange and act as its future.

A whole-body call (`WebFetchRequest >> start` or `fetch`) starts with `window = maximumBodySize + 1` and reads its body once via `response`. A streaming call (`startRequest:window:` or `WebFetchRequest >> stream:`) leaves body bytes unread in the host until read via `readInto:startingAt:count:`. Only one process should read a call's body.

In the UI process, `wait`, `response` and `waitForHead` block the UI until the call finishes or times out; UI tools should use `whenDone:ifError:` instead.
"
Class {
	#name : 'WebFetchCall',
	#superclass : 'Object',
	#instVars : [
		'host',
		'session',
		'semaphore',
		'handle',
		'closer',
		'request',
		'maximumBodySize',
		'isWholeBody',
		'state',
		'availableBytes',
		'headResponse',
		'response',
		'error',
		'finished',
		'finishMutex'
	],
	#classVars : [
		'OpenCalls',
		'OpenCallsMutex'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'control' }
WebFetchCall class >> abortAll [
	"Abort every open call without holding OpenCallsMutex during abort"

	self openCalls do: [ :each | each abort ]
]

{ #category : 'constants' }
WebFetchCall class >> defaultStreamWindow [
	"1 MiB streaming window"

	^ 1048576
]

{ #category : 'class initialization' }
WebFetchCall class >> initialize [
	OpenCalls := WeakSet new.
	OpenCallsMutex := Mutex new.
	SessionManager default registerNetworkClassNamed: self name
]

{ #category : 'accessing' }
WebFetchCall class >> openCalls [
	"Snapshot Array of currently open calls"

	| mutex |
	mutex := OpenCallsMutex.
	mutex ifNil: [ ^ #() ].
	^ mutex critical: [
		Array streamContents: [ :stream |
			OpenCalls do: [ :each | each ifNotNil: [ stream nextPut: each ] ] ] ]
]

{ #category : 'accessing' }
WebFetchCall class >> openCount [
	^ self openCalls size
]

{ #category : 'private' }
WebFetchCall class >> registerCall: aCall [
	| mutex |
	mutex := OpenCallsMutex ifNil: [
		OpenCalls := WeakSet new.
		OpenCallsMutex := Mutex new ].
	mutex critical: [ OpenCalls add: aCall ]
]

{ #category : 'system startup' }
WebFetchCall class >> startUp: resuming [
	"On image resume, replace the open table without locking the old mutex and wake waiters with SessionEnded"

	| old |
	resuming ifFalse: [ ^ self ].
	old := OpenCalls.
	OpenCalls := WeakSet new.
	OpenCallsMutex := Mutex new.
	old ifNotNil: [
		old do: [ :each | each ifNotNil: [ each markSessionEnded ] ] ]
]

{ #category : 'instance creation' }
WebFetchCall class >> startRequest: aWebFetchRequest window: windowBytes [
	"Start a streaming call whose body stays unread until readInto:startingAt:count:"

	^ self new
		startRequest: aWebFetchRequest
		window: windowBytes
		defaultTimeout: nil
		wholeBody: false;
		yourself
]

{ #category : 'instance creation' }
WebFetchCall class >> startWholeRequest: aWebFetchRequest defaultTimeout: defaultDuration [
	"Start a whole-body call with window = maximumBodySize + 1"

	^ self new
		startRequest: aWebFetchRequest
		window: aWebFetchRequest maximumBodySize + 1
		defaultTimeout: defaultDuration
		wholeBody: true;
		yourself
]

{ #category : 'class initialization' }
WebFetchCall class >> unload [
	SessionManager default unregisterClassNamed: self name
]

{ #category : 'private' }
WebFetchCall class >> unregisterCall: aCall [
	| mutex |
	mutex := OpenCallsMutex.
	mutex ifNil: [ ^ self ].
	mutex critical: [ OpenCalls remove: aCall ifAbsent: [ ] ]
]

{ #category : 'control' }
WebFetchCall >> abort [
	"Abort an in-progress call; does nothing on an already finished call"

	self
		endWith: (WebFetchAborted new messageText: 'WebFetch call was aborted')
		state: 0
]

{ #category : 'accessing' }
WebFetchCall >> availableBytes [
	"Ready unread body bytes; 0 when pending, failed or closed"

	self refreshState.
	^ availableBytes
]

{ #category : 'private' }
WebFetchCall >> checkMayWait [
	host mayWait ifFalse: [
		WebFetchInCallback signal: 'Cannot wait on WebFetch inside an FFI callback' ]
]

{ #category : 'private' }
WebFetchCall >> checkSession [
	session == Smalltalk session ifFalse: [
		self markSessionEnded.
		error copy signal ]
]

{ #category : 'control' }
WebFetchCall >> close [
	"Close an in-progress call; does nothing on an already finished call"

	self
		endWith: (WebFetchAborted new messageText: 'WebFetch call was closed')
		state: 0
]

{ #category : 'private' }
WebFetchCall >> closer [
	^ closer
]

{ #category : 'private' }
WebFetchCall >> endWith: anErrorOrNil state: anInteger [
	"Single terminal transition for every call ending; idempotent once finished"

	finished ifTrue: [ ^ self ].
	state := anInteger.
	availableBytes := 0.
	error := anErrorOrNil.
	finished := true.
	self class unregisterCall: self.
	closer ifNotNil: [ closer close ].
	semaphore ifNotNil: [ semaphore signal ]
]

{ #category : 'accessing' }
WebFetchCall >> error [
	"Unsignalled WebFetchError for a failed, aborted or session-ended call, else nil"

	(finished not and: [ session == Smalltalk session ]) ifTrue: [
		[ self refreshState ] on: WebFetchSessionEnded do: [ :e | ] ].
	^ error
]

{ #category : 'private' }
WebFetchCall >> fetchErrorAndClose [
	"Read the host error record once, end the call in state 4, and wake waiters"

	| raw text lines kind msg err |
	finished ifTrue: [ ^ self ].
	raw := self hostDo: [ host headOf: handle ] onFinished: [ nil ].
	finished ifTrue: [ ^ self ].
	err := raw
		ifNotNil: [
			text := [ raw utf8Decoded ] on: Error do: [ :e | raw asString ].
			lines := WebFetchResponse splitOnLF: text.
			kind := (lines size >= 1 and: [ (lines at: 1) notEmpty ])
				ifTrue: [ (lines at: 1) asSymbol ]
				ifFalse: [ #network ].
			msg := lines size >= 2 ifTrue: [ lines at: 2 ] ifFalse: [ '' ].
			WebFetchError kind: kind message: msg ]
		ifNil: [
			WebFetchNetworkError kind: #network message: 'Request failed' ].
	self endWith: err state: 4
]

{ #category : 'private' }
WebFetchCall >> finishStream [
	"Mark a streaming call cleanly completed at EOF (state stays 3)"

	self endWith: nil state: 3
]

{ #category : 'private' }
WebFetchCall >> finishWholeBody [
	"Finalize a whole-body call under finishMutex; abort on curtailment or read failure"

	| toSignal result |
	toSignal := nil.
	result := nil.
	[
		finishMutex critical: [
			finished ifFalse: [ self finishWholeBodyLocked ].
			toSignal := error.
			result := response ] ]
		ifCurtailed: [ self abort ].
	toSignal ifNotNil: [ toSignal copy signal ].
	^ result
]

{ #category : 'private' }
WebFetchCall >> finishWholeBodyLocked [
	| resp total bytes offset |
	session == Smalltalk session ifFalse: [
		self markSessionEnded.
		^ self ].
	[ self refreshState ] on: WebFetchSessionEnded do: [ :e | ^ self ].
	finished ifTrue: [ ^ self ].
	availableBytes > maximumBodySize ifTrue: [
		self
			endWith: (WebFetchTooLarge new
				messageText: 'Response body exceeds maximumBodySize (' , maximumBodySize asString , ' bytes)')
			state: 4.
		^ self ].
	resp := self readHeadLocked.
	finished ifTrue: [ ^ self ].
	total := availableBytes.
	bytes := ByteArray new: total.
	offset := 1.
	[ offset <= total and: [ finished not ] ] whileTrue: [
		| n |
		n := self
			hostDo: [ host read: handle into: bytes startingAt: offset count: total - offset + 1 ]
			onFinished: [ nil ].
		finished ifTrue: [ ^ self ].
		n = 0
			ifTrue: [ offset := total + 1 ]
			ifFalse: [ offset := offset + n ] ].
	finished ifTrue: [ ^ self ].
	resp rawContents: bytes.
	response := resp.
	self endWith: nil state: 3
]

{ #category : 'private' }
WebFetchCall >> finishedReadResult [
	state = 3 ifTrue: [ ^ 0 ].
	error ifNotNil: [ :e | e copy signal ].
	WebFetchAborted signal: 'WebFetch call is closed'
]

{ #category : 'testing' }
WebFetchCall >> hasHead [
	"True when status and headers are available (state 2 or 3)"

	| s |
	s := self state.
	^ s = 2 or: [ s = 3 ]
]

{ #category : 'accessing' }
WebFetchCall >> headResponse [
	"Parsed WebFetchResponse (body unread) once state is 2 or 3; nil in state 1; signals error on 4 or abort"

	finished ifTrue: [
		(state = 4 or: [ state = 0 ]) ifTrue: [
			error ifNotNil: [ :e | e copy signal ].
			WebFetchAborted signal: 'WebFetch call is closed' ].
		^ headResponse ].
	headResponse ifNotNil: [ ^ headResponse ].
	self refreshState.
	finished ifTrue: [
		(state = 4 or: [ state = 0 ]) ifTrue: [
			error ifNotNil: [ :e | e copy signal ].
			WebFetchAborted signal: 'WebFetch call is closed' ].
		^ headResponse ].
	state = 1 ifTrue: [ ^ nil ].
	^ self readHeadLocked
]

{ #category : 'private' }
WebFetchCall >> hostDo: aBlock onFinished: finishedBlock [
	"Run a host operation on handle; map a concurrent close to finishedBlock and a lost id to SessionEnded"

	finished ifTrue: [ ^ finishedBlock value ].
	self checkSession.
	^ [ aBlock value ]
		on: WebFetchSessionEnded
		do: [ :e |
			finished
				ifTrue: [ finishedBlock value ]
				ifFalse: [
					self
						endWith: (WebFetchSessionEnded new messageText: e messageText)
						state: 0.
					error copy signal ] ]
]

{ #category : 'testing' }
WebFetchCall >> isClosed [
	^ finished and: [ state = 0 ]
]

{ #category : 'testing' }
WebFetchCall >> isDone [
	"True when nothing more will arrive for the caller (whole body ready/read, failed, too large, closed, or session ended). Never signals SessionEnded. Use state = 3 for streaming EOF."

	finished ifTrue: [ ^ true ].
	session == Smalltalk session ifFalse: [
		self markSessionEnded.
		^ true ].
	[ self refreshState ] on: WebFetchSessionEnded do: [ :e | ^ true ].
	(finished or: [ state = 3 or: [ state = 4 or: [ state = 0 ] ] ]) ifTrue: [ ^ true ].
	(isWholeBody and: [ state = 2 and: [ availableBytes > maximumBodySize ] ]) ifTrue: [ ^ true ].
	^ false
]

{ #category : 'testing' }
WebFetchCall >> isFailed [
	^ self state = 4
]

{ #category : 'private' }
WebFetchCall >> isFinalState [
	finished ifTrue: [ ^ true ].
	session == Smalltalk session ifFalse: [ ^ true ].
	(state = 0 or: [ state = 3 or: [ state = 4 ] ]) ifTrue: [ ^ true ].
	(isWholeBody and: [ state = 2 and: [ availableBytes > maximumBodySize ] ]) ifTrue: [ ^ true ].
	^ false
]

{ #category : 'testing' }
WebFetchCall >> isPending [
	^ self state = 1
]

{ #category : 'private' }
WebFetchCall >> markSessionEnded [
	"Mark an unfinished call ended on image resume without calling primitives or unregistering"

	self
		endWith: (WebFetchSessionEnded new
			messageText: 'Smalltalk session ended while WebFetch call was in progress')
		state: 0
]

{ #category : 'private' }
WebFetchCall >> readHeadLocked [
	| rawHead |
	headResponse ifNotNil: [ ^ headResponse ].
	rawHead := self hostDo: [ host headOf: handle ] onFinished: [ nil ].
	finished ifTrue: [ ^ headResponse ].
	rawHead ifNil: [ ^ nil ].
	headResponse := WebFetchResponse fromHeadBytes: rawHead.
	^ headResponse
]

{ #category : 'reading' }
WebFetchCall >> readInto: aByteArray startingAt: startIndex count: maxCount [
	"Copy up to maxCount ready bytes into aByteArray at 1-based startIndex; answer bytes copied"

	| n |
	finished ifTrue: [ ^ self finishedReadResult ].
	n := self
		hostDo: [ host read: handle into: aByteArray startingAt: startIndex count: maxCount ]
		onFinished: [ nil ].
	finished ifTrue: [ ^ self finishedReadResult ].
	availableBytes := (availableBytes - n) max: 0.
	^ n
]

{ #category : 'private' }
WebFetchCall >> refreshState [
	| raw |
	finished ifTrue: [ ^ state ].
	raw := self hostDo: [ host stateOf: handle ] onFinished: [ nil ].
	finished ifTrue: [ ^ state ].
	raw ifNil: [ ^ state ].
	state := raw bitAnd: 7.
	availableBytes := raw bitShift: -3.
	state = 4 ifTrue: [ self fetchErrorAndClose ].
	^ state
]

{ #category : 'accessing' }
WebFetchCall >> response [
	"Wait for the whole response and answer WebFetchResponse, or signal the call's error"

	finished ifTrue: [
		error ifNotNil: [ :e | e copy signal ].
		^ response ].
	self isDone ifFalse: [
		self checkMayWait.
		[ self waitUntil: [ self isDone ] timeout: nil ] ifCurtailed: [ self abort ] ].
	^ self finishWholeBody
]

{ #category : 'private' }
WebFetchCall >> semaphore [
	^ semaphore
]

{ #category : 'private' }
WebFetchCall >> session: aSession [
	"Private hook for session-end tests"

	session := aSession.
	closer ifNotNil: [ closer session: aSession ]
]

{ #category : 'initialization' }
WebFetchCall >> startRequest: aWebFetchRequest window: windowBytes defaultTimeout: defaultDuration wholeBody: aBoolean [
	| built headBytes bodyBytes timeoutMs flags semIndex |
	built := aWebFetchRequest buildForDefaultTimeout: defaultDuration.
	headBytes := built at: 1.
	bodyBytes := built at: 2.
	timeoutMs := built at: 3.
	flags := built at: 4.
	host := aWebFetchRequest effectiveHost.
	session := Smalltalk session.
	semaphore := Semaphore new.
	request := aWebFetchRequest.
	maximumBodySize := aWebFetchRequest maximumBodySize.
	isWholeBody := aBoolean.
	state := 1.
	availableBytes := 0.
	finished := false.
	finishMutex := Mutex new.
	closer := WebFetchCloser host: host semaphore: semaphore session: session.
	FinalizationRegistry default add: self finalizer: closer.
	self class registerCall: self.
	[
		semIndex := Smalltalk registerExternalObject: semaphore.
		self checkSession.
		handle := closer
			startSemaphore: semIndex
			head: headBytes
			body: bodyBytes
			window: windowBytes
			timeout: timeoutMs
			flags: flags ]
		ifCurtailed: [
			self
				endWith: (WebFetchAborted new messageText: 'WebFetch start was curtailed')
				state: 0 ]
]

{ #category : 'accessing' }
WebFetchCall >> state [
	"1 PENDING, 2 HEAD, 3 DONE, 4 FAILED, 0 closed/aborted early"

	^ self refreshState
]

{ #category : 'waiting' }
WebFetchCall >> wait [
	"Wait until isDone (aborts if curtailed); answers self and does not signal exchange errors"

	self isDone ifTrue: [ ^ self ].
	self checkMayWait.
	[ self waitUntil: [ self isDone ] timeout: nil ] ifCurtailed: [ self abort ].
	^ self
]

{ #category : 'waiting' }
WebFetchCall >> waitForHead [
	"Wait until response head arrives (aborts if curtailed); answers headResponse or signals error"

	headResponse ifNotNil: [
		(state = 4 or: [ state = 0 ]) ifTrue: [ error ifNotNil: [ :e | e copy signal ] ].
		^ headResponse ].
	finished ifTrue: [
		error ifNotNil: [ :e | e copy signal ].
		^ headResponse ].
	self checkMayWait.
	[ self waitUntil: [ self state >= 2 ] timeout: nil ] ifCurtailed: [ self abort ].
	^ self headResponse
]

{ #category : 'waiting' }
WebFetchCall >> waitTimeout: aDuration [
	"Wait up to aDuration for isDone; answers isDone without aborting on expiry or curtailment"

	| ms |
	self isDone ifTrue: [ ^ true ].
	ms := aDuration isNumber
		ifTrue: [ (aDuration * 1000) truncated ]
		ifFalse: [ aDuration asMilliSeconds truncated ].
	ms < 0 ifTrue: [ ms := 0 ].
	self waitUntil: [ self isDone ] timeout: ms.
	^ self isDone
]

{ #category : 'waiting' }
WebFetchCall >> waitUntil: aBlock timeout: millisecondsOrNil [
	"Answer whether aBlock became true within millisecondsOrNil (nil = forever). Does not abort. aBlock must query the call (e.g. state, availableBytes, isDone) so state is current."

	| deadline |
	deadline := millisecondsOrNil ifNotNil: [ Time millisecondClockValue + millisecondsOrNil ].
	[
		self checkSession.
		aBlock value ifTrue: [
			self isFinalState ifTrue: [ semaphore signal ].
			^ true ].
		self isFinalState ifTrue: [
			semaphore signal.
			^ aBlock value ].
		self checkMayWait.
		deadline
			ifNil: [ semaphore wait ]
			ifNotNil: [
				| remaining expired |
				remaining := deadline - Time millisecondClockValue.
				remaining <= 0 ifTrue: [
					self checkSession.
					^ aBlock value ].
				expired := semaphore waitTimeoutMilliseconds: remaining.
				expired ifTrue: [
					self checkSession.
					^ aBlock value ] ] ] repeat
]

{ #category : 'waiting' }
WebFetchCall >> whenDone: doneBlock ifError: errorBlock [
	"Fork a process at the caller's priority to run doneBlock or errorBlock when the call finishes"

	| process |
	process := [
		| ok resp err |
		ok := false.
		resp := nil.
		err := nil.
		[
			self waitUntil: [ self isDone ] timeout: nil.
			resp := self finishWholeBody.
			ok := true ]
			on: WebFetchError , OutOfMemory
			do: [ :e | err := e ].
		ok
			ifTrue: [ doneBlock cull: resp ]
			ifFalse: [ errorBlock cull: err ] ] newProcess.
	process
		name: 'WebFetch whenDone';
		priority: Processor activePriority;
		resume.
	^ process
]
