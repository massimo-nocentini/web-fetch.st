"
I represent one in-flight or completed HTTP exchange and act as its future.

A whole-body call (`WebFetchRequest >> start` or `fetch`) starts with `window = maximumBodySize + 1` and reads its body once via `response`. A streaming call (`startRequest:window:` or `WebFetchRequest >> stream:`) leaves body bytes unread in the host until read via `readInto:startingAt:count:`. Only one process should read a call's body. `response`, `wait` and `whenDone:ifError:` of a streaming call signal an error: without a reader its body may never end.

In the UI process, `wait`, `response` and `waitForHead` block the UI until the call finishes or times out; UI tools should use `whenDone:ifError:` instead.

A process inside an FFI callback cannot wait (`WebFetchInCallback`): no event of the host comes before the callback returns. The other processes may wait meanwhile, and `whenDone:ifError:` works in a callback, its blocks being evaluated after it. A callback must not wait for another process that waits for a call.
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
	"Abort every open call without holding the open-calls mutex during abort."

	self openCalls do: [ :each | each abort ]
]

{ #category : 'private' }
WebFetchCall class >> checkMayWait: aHost [
	"While an FFI callback runs no event of the host comes: a wait of the callback itself would never end.
	The wait of another process ends after the callback"

	(self mayWaitWith: aHost) ifFalse: [
		WebFetchInCallback signal: 'Cannot wait on WebFetch inside an FFI callback' ]
]

{ #category : 'constants' }
WebFetchCall class >> defaultStreamWindow [
	"Answer the default 1 MiB streaming window."

	^ 1048576
]

{ #category : 'class initialization' }
WebFetchCall class >> initialize [
	self resetOpenCalls.
	SessionManager default registerNetworkClassNamed: self name
]

{ #category : 'private' }
WebFetchCall class >> isInCallback [
	"Answer whether the active process evaluates an FFI callback"

	| invocation context |
	invocation := Smalltalk globals at: #TFCallbackInvocation ifAbsent: [ ^ false ].
	context := thisContext sender.
	[ (context receiver class includesBehavior: invocation) ifTrue: [ ^ true ].
	context := context sender.
	context isNil ] whileFalse.
	^ false
]

{ #category : 'private' }
WebFetchCall class >> mayWaitWith: aHost [
	"Answer whether the active process may wait for an event of aHost: false only in an FFI callback"

	^ aHost mayWait or: [ self isInCallback not ]
]

{ #category : 'accessing' }
WebFetchCall class >> openCalls [
	"Answer a snapshot Array of currently open calls. A dropped call that the finalizer closed stays in the set until the next garbage collection."

	| mutex |
	mutex := OpenCallsMutex.
	mutex ifNil: [ ^ #() ].
	^ mutex critical: [
		Array streamContents: [ :stream |
			OpenCalls do: [ :each |
				each ifNotNil: [ each hasHandle ifTrue: [ stream nextPut: each ] ] ] ] ]
]

{ #category : 'accessing' }
WebFetchCall class >> openCount [
	^ self openCalls size
]

{ #category : 'private' }
WebFetchCall class >> registerCall: aCall [
	OpenCallsMutex critical: [ OpenCalls add: aCall ]
]

{ #category : 'private' }
WebFetchCall class >> resetOpenCalls [
	OpenCalls := WeakSet new.
	OpenCallsMutex := Mutex new
]

{ #category : 'instance creation' }
WebFetchCall class >> startRequest: aWebFetchRequest window: windowBytes [
	"Start a streaming call whose body stays unread until readInto:startingAt:count:."

	^ self new
		startRequest: aWebFetchRequest
		window: windowBytes
		defaultTimeout: nil
		wholeBody: false;
		yourself
]

{ #category : 'system startup' }
WebFetchCall class >> startUp: resuming [
	"On image resume, install a fresh open table without locking the old mutex and wake waiters with SessionEnded."

	| old |
	resuming ifFalse: [ ^ self ].
	old := OpenCalls.
	self resetOpenCalls.
	old ifNotNil: [
		old do: [ :each | each ifNotNil: [ each markSessionEnded ] ] ]
]

{ #category : 'instance creation' }
WebFetchCall class >> startWholeRequest: aWebFetchRequest defaultTimeout: defaultDuration [
	"Start a whole-body call with window = maximumBodySize + 1."

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
	"Abort an in-progress call. Does nothing on an already finished call."

	self
		endWith: (WebFetchAborted new messageText: 'WebFetch call was aborted')
		state: 0
]

{ #category : 'accessing' }
WebFetchCall >> availableBytes [
	"Answer the count of ready unread body bytes, or 0 when pending, failed or closed."

	self refreshState.
	^ availableBytes
]

{ #category : 'private' }
WebFetchCall >> checkMayWait [
	self class checkMayWait: host
]

{ #category : 'private' }
WebFetchCall >> checkSession [
	"Verify the call belongs to the current session; a call that finished cleanly remains usable."

	session == Smalltalk session ifTrue: [ ^ self ].
	self markSessionEnded.
	error ifNotNil: [ :e | e copy signal ]
]

{ #category : 'private' }
WebFetchCall >> checkWholeBody [
	isWholeBody ifFalse: [
		self error: 'The body of a streaming call is read with readInto:startingAt:count:' ]
]

{ #category : 'control' }
WebFetchCall >> close [
	"Close an in-progress call. Does nothing on an already finished call."

	self
		endWith: (WebFetchAborted new messageText: 'WebFetch call was closed')
		state: 0
]

{ #category : 'private' }
WebFetchCall >> endWith: anErrorOrNil state: anInteger [
	"Transition the call to its final state once, release host resources, and wake any waiters."

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
	"Answer the unsignalled WebFetchError for a failed, aborted or session-ended call, or nil."

	(finished not and: [ session == Smalltalk session ]) ifTrue: [
		[ self refreshState ] on: WebFetchSessionEnded do: [ :e | ] ].
	^ error
]

{ #category : 'private' }
WebFetchCall >> fetchErrorAndClose [
	"Read the host error record once, transition to state 4, and wake waiters."

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
	"Mark a streaming call cleanly completed at end-of-body so its state remains 3."

	self endWith: nil state: 3
]

{ #category : 'private' }
WebFetchCall >> finishWholeBody [
	"Finalize a whole-body call under finishMutex, aborting if curtailed or if reading fails."

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
		n = 0 ifTrue: [
			self
				endWith: (WebFetchNetworkError
					kind: #body
					message: 'Unexpected end of response body before all bytes were read')
				state: 4.
			^ self ].
		offset := offset + n ].
	finished ifTrue: [ ^ self ].
	resp rawContents: bytes.
	response := resp.
	self endWith: nil state: 3
]

{ #category : 'private' }
WebFetchCall >> finishedReadResult [
	state = 3 ifTrue: [ ^ 0 ].
	self signalErrorOfEnded
]

{ #category : 'private' }
WebFetchCall >> hasHandle [
	^ closer handle notNil
]

{ #category : 'testing' }
WebFetchCall >> hasHead [
	"Answer true when status and headers are available (state 2 or 3)."

	| s |
	s := self state.
	^ s = 2 or: [ s = 3 ]
]

{ #category : 'accessing' }
WebFetchCall >> headResponse [
	"Answer the cached WebFetchResponse (body unread) once state is 2 or 3, nil in state 1, or signal the error if failed or aborted."

	finished ifTrue: [
		(state = 4 or: [ state = 0 ]) ifTrue: [ self signalErrorOfEnded ].
		^ headResponse ].
	headResponse ifNotNil: [ ^ headResponse ].
	self refreshState.
	finished ifTrue: [
		(state = 4 or: [ state = 0 ]) ifTrue: [ self signalErrorOfEnded ].
		^ headResponse ].
	state = 1 ifTrue: [ ^ nil ].
	^ self readHeadLocked
]

{ #category : 'private' }
WebFetchCall >> hostDo: aBlock onFinished: finishedBlock [
	"Evaluate a host operation on handle, mapping a concurrent close to finishedBlock and a lost handle to SessionEnded."

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
	"Answer true when nothing more will arrive for the caller (body ready or read, failed, too large, closed, or session ended). Never signals SessionEnded. Use state = 3 for streaming EOF."

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
	"Mark an unfinished call ended after an image resume."

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
	"Copy up to maxCount ready bytes into aByteArray at 1-based startIndex and answer the count copied."

	| n |
	finished ifTrue: [ ^ self finishedReadResult ].
	n := self
		hostDo: [ host read: handle into: aByteArray startingAt: startIndex count: maxCount ]
		onFinished: [ nil ].
	finished ifTrue: [ ^ self finishedReadResult ].
	availableBytes := (availableBytes - n) max: 0.
	^ n
]

{ #category : 'updating' }
WebFetchCall >> recordedAvailableBytes [
	"Answer the ready byte count from the most recent state refresh without calling the host."

	^ availableBytes
]

{ #category : 'updating' }
WebFetchCall >> recordedState [
	"Answer the state from the most recent state refresh without calling the host."

	^ state
]

{ #category : 'updating' }
WebFetchCall >> refreshState [
	"Query the host once to update state and availableBytes, and answer the updated state."

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
	"Wait for the whole response and answer WebFetchResponse, or signal the call's error."

	self checkWholeBody.
	finished ifTrue: [
		error ifNotNil: [ self signalErrorOfEnded ].
		^ response ].
	self isDone ifFalse: [
		self checkMayWait.
		[ self waitUntil: [ self isDone ] timeout: nil ] ifCurtailed: [ self abort ] ].
	^ self finishWholeBody
]

{ #category : 'private' }
WebFetchCall >> signalErrorOfEnded [
	"Signal a fresh copy of the recorded error, or WebFetchAborted if none was recorded."

	error ifNotNil: [ :e | e copy signal ].
	WebFetchAborted signal: 'WebFetch call is closed'
]

{ #category : 'initialization' }
WebFetchCall >> startRequest: aWebFetchRequest window: windowBytes defaultTimeout: defaultDuration wholeBody: aBoolean [
	| built headBytes bodyBytes timeoutMs flags semIndex |
	built := aWebFetchRequest buildForDefaultTimeout: defaultDuration.
	headBytes := built at: 1.
	bodyBytes := built at: 2.
	timeoutMs := built at: 3.
	flags := built at: 4.
	host := WebFetchHost default.
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
	[
		semIndex := Smalltalk registerExternalObject: semaphore.
		self checkSession.
		handle := closer
			startSemaphore: semIndex
			head: headBytes
			body: bodyBytes
			window: windowBytes
			timeout: timeoutMs
			flags: flags.
		self class registerCall: self ]
		ifCurtailed: [
			self
				endWith: (WebFetchAborted new messageText: 'WebFetch start was curtailed')
				state: 0 ]
]

{ #category : 'accessing' }
WebFetchCall >> state [
	"Answer 1 PENDING, 2 HEAD, 3 DONE, 4 FAILED, or 0 if closed or aborted early."

	^ self refreshState
]

{ #category : 'waiting' }
WebFetchCall >> wait [
	"Wait until isDone, aborting if curtailed. Answers self without signalling exchange errors."

	self checkWholeBody.
	self isDone ifTrue: [ ^ self ].
	self checkMayWait.
	[ self waitUntil: [ self isDone ] timeout: nil ] ifCurtailed: [ self abort ].
	^ self
]

{ #category : 'waiting' }
WebFetchCall >> waitForHead [
	"Wait until response headers arrive, aborting if curtailed. Answers headResponse or signals error."

	headResponse ifNotNil: [
		(state = 4 or: [ state = 0 ]) ifTrue: [ self signalErrorOfEnded ].
		^ headResponse ].
	finished ifTrue: [
		error ifNotNil: [ self signalErrorOfEnded ].
		^ headResponse ].
	self checkMayWait.
	[ self waitUntil: [ self state >= 2 ] timeout: nil ] ifCurtailed: [ self abort ].
	^ self headResponse
]

{ #category : 'waiting' }
WebFetchCall >> waitTimeout: aDuration [
	"Wait up to aDuration for isDone. Answers isDone without aborting on expiry or curtailment."

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
	"Wait until aBlock answers true or millisecondsOrNil expires (nil waits indefinitely). Does not abort. aBlock must query the call so the recorded state is current."

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
	"Fork a process at the caller's priority to evaluate doneBlock or errorBlock when the call finishes."

	| process |
	self checkWholeBody.
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
