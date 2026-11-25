"
I test concurrency, session-boundary, and error-handling invariants of `WebFetchCall` and `WebFetchCloser`.
"
Class {
	#name : 'WebFetchInvariantTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchInvariantTest >> assertEndedSessionCall: call [
	self assert: call state equals: 0.
	self assert: call isClosed.
	self assert: (call error isKindOf: WebFetchSessionEnded)
]

{ #category : 'helpers' }
WebFetchInvariantTest >> withEndedSessionCallDo: aBlock [
	"Start a pending call, switch it to a foreign session, run aBlock with (call, callsBefore, semsBefore), and clean up."

	| call id callsBefore semsBefore |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/session') start.
	id := host lastId.
	call session: Object new.
	callsBefore := host hostCalls.
	semsBefore := self registeredSemaphoreCount.
	[ aBlock value: call value: callsBefore value: semsBefore ]
		ensure: [
			call close.
			Smalltalk unregisterExternalObject: call semaphore.
			host close: id ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testEndedSessionMakesNoHostCall [
	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self should: [ call state ] raise: WebFetchSessionEnded.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call.
		self assert: host hostCalls equals: callsBefore ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self should: [ call availableBytes ] raise: WebFetchSessionEnded.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self assert: call isDone.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self
			should: [ call readInto: (ByteArray new: 8) startingAt: 1 count: 8 ]
			raise: WebFetchSessionEnded.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self should: [ call headResponse ] raise: WebFetchSessionEnded.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self assert: (call waitTimeout: 100 milliSeconds).
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self should: [ call waitUntil: [ call isDone ] timeout: 100 ] raise: WebFetchSessionEnded.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assertEndedSessionCall: call ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		call abort.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assert: call state equals: 0.
		self assert: call isClosed.
		self assert: (call error isKindOf: WebFetchAborted) ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		call close.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore.
		self assert: call state equals: 0.
		self assert: call isClosed.
		self assert: (call error isKindOf: WebFetchAborted) ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		self deny: call closer close.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore ].

	self withEndedSessionCallDo: [ :call :callsBefore :semsBefore |
		call closer finalize.
		self assert: host hostCalls equals: callsBefore.
		self assert: self registeredSemaphoreCount equals: semsBefore ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testFinishWholeBodyConcurrentResponseReadsOnce [
	| call readCount done results errors procs |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'whole-body-payload'.
	call := (WebFetch request: 'http://example.test/whole') start.
	self assert: (call waitTimeout: 2 seconds).
	readCount := 0.
	host onRead: [ :id |
		readCount := readCount + 1.
		readCount = 1 ifTrue: [ (Delay forMilliseconds: 50) wait ] ].
	done := Semaphore new.
	results := Array new: 2.
	errors := Array new: 2.
	procs := OrderedCollection new.
	[
		1 to: 2 do: [ :i |
			procs add: ([
				[ results at: i put: call response contents ]
					on: Error
					do: [ :e | errors at: i put: e ].
				done signal ] fork) ].
		2 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
		self assert: (errors at: 1) isNil.
		self assert: (errors at: 2) isNil.
		self assert: (results at: 1) equals: 'whole-body-payload'.
		self assert: (results at: 2) equals: 'whole-body-payload'.
		self assert: readCount equals: 1 ]
		ensure: [
			host onRead: nil.
			procs do: [ :p | p terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testStartUpTrueDoesNotBlockOnOldMutexAndWakesWaiters [
	| call waiterStarted waiterDone waiterErr holding release startupDone oldMutex waiterProc holderProc startupProc |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/startup') start.
	waiterStarted := Semaphore new.
	waiterDone := Semaphore new.
	waiterErr := nil.
	holding := Semaphore new.
	release := Semaphore new.
	startupDone := Semaphore new.
	waiterProc := nil.
	holderProc := nil.
	startupProc := nil.
	[
		waiterProc := [
			waiterStarted signal.
			[ call response ] on: WebFetchSessionEnded do: [ :e | waiterErr := e ].
			waiterDone signal ] fork.
		self deny: (waiterStarted waitTimeoutMilliseconds: 2000).
		(Delay forMilliseconds: 30) wait.

		oldMutex := WebFetchCall classPool at: #OpenCallsMutex.
		holderProc := [
			oldMutex critical: [
				holding signal.
				release waitTimeoutMilliseconds: 5000 ] ] fork.
		self deny: (holding waitTimeoutMilliseconds: 2000).

		startupProc := [
			WebFetchCall startUp: true.
			startupDone signal ] fork.
		self deny: (startupDone waitTimeoutMilliseconds: 2000).
		self deny: (waiterDone waitTimeoutMilliseconds: 2000).
		self assert: (waiterErr isKindOf: WebFetchSessionEnded).
		self assert: WebFetchCall openCount equals: 0.
		self assert: call state equals: 0.
		self assert: call isClosed ]
		ensure: [
			release signal.
			startupProc ifNotNil: [ startupProc terminate ].
			holderProc ifNotNil: [ holderProc terminate ].
			waiterProc ifNotNil: [ waiterProc terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWaitFiveWaitersWakeOnSingleFail [
	| call id started done results procs |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w-wait') start.
	id := host lastId.
	started := Semaphore new.
	done := Semaphore new.
	results := Array new: 5.
	procs := OrderedCollection new.
	[
		1 to: 5 do: [ :i |
			procs add: ([
				started signal.
				results at: i put: call wait.
				done signal ] fork) ].
		5 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
		(Delay forMilliseconds: 50) wait.
		host fail: id kind: #network message: 'boom'.
		5 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
		self assert: (results allSatisfy: [ :each | each == call ]) ]
		ensure: [
			procs do: [ :p | p terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWaitTimeoutFiveWaitersWakeOnSingleFail [
	| call id started done results procs |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w-timeout') start.
	id := host lastId.
	started := Semaphore new.
	done := Semaphore new.
	results := Array new: 5.
	procs := OrderedCollection new.
	[
		1 to: 5 do: [ :i |
			procs add: ([
				started signal.
				results at: i put: (call waitTimeout: 10 seconds).
				done signal ] fork) ].
		5 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
		(Delay forMilliseconds: 50) wait.
		host fail: id kind: #network message: 'boom'.
		5 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
		self assert: (results allSatisfy: [ :each | each ]) ]
		ensure: [
			procs do: [ :p | p terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWaitUntilFalseAtFinalStateFiveWaitersWakeOnSingleFail [
	| call id started done results procs |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w-until-false') start.
	id := host lastId.
	started := Semaphore new.
	done := Semaphore new.
	results := Array new: 5.
	procs := OrderedCollection new.
	[
		1 to: 5 do: [ :i |
			procs add: ([
				started signal.
				results at: i put: (call waitUntil: [ call state = 3 ] timeout: 10000).
				done signal ] fork) ].
		5 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
		(Delay forMilliseconds: 50) wait.
		host fail: id kind: #network message: 'boom'.
		5 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
		self assert: (results allSatisfy: [ :each | each not ]) ]
		ensure: [
			procs do: [ :p | p terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWaitUntilFinalStateDetectsSessionChangeDuringBlock [
	| call id done result proc |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w-sess-block') start.
	id := host lastId.
	done := Semaphore new.
	result := nil.
	proc := nil.
	[
		proc := [
			result := call waitUntil: [ call session: Object new. false ] timeout: 10000.
			done signal ] fork.
		self deny: (done waitTimeoutMilliseconds: 1000).
		self assert: result not ]
		ensure: [
			proc ifNotNil: [ proc terminate ].
			call close.
			Smalltalk unregisterExternalObject: call semaphore.
			host close: id ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWaitUntilTrueAtEndFiveWaitersWakeOnSingleFail [
	| call id started done results procs |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w-until-true') start.
	id := host lastId.
	started := Semaphore new.
	done := Semaphore new.
	results := Array new: 5.
	procs := OrderedCollection new.
	[
		1 to: 5 do: [ :i |
			procs add: ([
				started signal.
				results at: i put: (call waitUntil: [ call state = 4 ] timeout: 10000).
				done signal ] fork) ].
		5 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
		(Delay forMilliseconds: 50) wait.
		host fail: id kind: #network message: 'boom'.
		5 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
		self assert: (results allSatisfy: [ :each | each ]) ]
		ensure: [
			procs do: [ :p | p terminate ].
			call abort ]
]

{ #category : 'tests' }
WebFetchInvariantTest >> testWhenDoneDeliversOutOfMemoryToErrorBlock [
	| call done gotResp gotErr proc |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'payload'.
	call := (WebFetch request: 'http://example.test/oom') start.
	self assert: (call waitTimeout: 2 seconds).
	host onRead: [ :id | OutOfMemory signal: 'simulated OOM' ].
	done := Semaphore new.
	gotResp := nil.
	gotErr := nil.
	proc := nil.
	[
		proc := call
			whenDone: [ :r | gotResp := r. done signal ]
			ifError: [ :e | gotErr := e. done signal ].
		self deny: (done waitTimeoutMilliseconds: 2000).
		self assert: gotResp isNil.
		self assert: (gotErr isKindOf: OutOfMemory).
		self assert: host openCount equals: 0.
		self assert: WebFetchCall openCount equals: 0 ]
		ensure: [
			host onRead: nil.
			proc ifNotNil: [ proc terminate ].
			call abort ]
]
