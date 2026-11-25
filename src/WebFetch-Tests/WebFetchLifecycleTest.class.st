"
I test `WebFetchCall` lifecycle: termination, unwinding, abort, `abortAll`, FFI callback refusal, 65-open limit, `availability` 0/2, `networkOff`, lost id, concurrent close/abort races, simulated session end, semaphore registration, GC finalization, TaskIt `future`, and code style.
"
Class {
	#name : 'WebFetchLifecycleTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'private' }
WebFetchLifecycleTest >> packageNamed: aName [
	"Compatible across Pharo 12 (RPackageOrganizer) and Pharo 13-15 (PackageOrganizer)."

	Smalltalk at: #PackageOrganizer ifPresent: [ :cls |
		^ cls default packageNamed: aName ifAbsent: [ nil ] ].
	Smalltalk at: #RPackageOrganizer ifPresent: [ :cls |
		^ cls default packageNamed: aName ifAbsent: [ nil ] ].
	^ nil
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testAbortAll [
	| calls |
	calls := (1 to: 5) collect: [ :i |
		host enqueuePending.
		(WebFetch request: 'http://example.test/' , i asString) start ].
	self assert: host openCount equals: 5.
	self assert: WebFetchCall openCount equals: 5.
	WebFetch abortAll.
	self assert: host openCount equals: 0.
	self assert: WebFetchCall openCount equals: 0.
	calls do: [ :c |
		self assert: c isClosed.
		self should: [ c response ] raise: WebFetchAborted ]
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testAbortAllDuringStartLeavesNewCallAlive [
	| call |
	host enqueuePending.
	host onStart: [ WebFetch abortAll ].
	call := (WebFetch request: 'http://example.test/start-race') start.
	host onStart: nil.
	[
		self assert: call isPending.
		self assert: host openCount equals: 1.
		self assert: WebFetchCall openCount equals: 1 ]
		ensure: [ call abort ]
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testAbortDuringFinishAndReadErrorCloseHost [
	| call |
	host enqueueStatus: 200 headers: #() body: 'payload'.
	call := (WebFetch request: 'http://example.test/r1') start.
	call wait.
	host onRead: [ :id | call abort ].
	self should: [ call response ] raise: WebFetchAborted.
	self assert: host openCount equals: 0.
	host onRead: nil.

	host enqueueStatus: 200 headers: #() body: 'payload'.
	call := (WebFetch request: 'http://example.test/r2') start.
	call wait.
	host onRead: [ :id | OutOfMemory signal: 'simulated OOM' ].
	self should: [ call response ] raise: OutOfMemory.
	self assert: host openCount equals: 0.
	host onRead: nil
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testAbortWhileAnotherWaits [
	| call started sem err |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/ab') start.
	started := Semaphore new.
	sem := Semaphore new.
	err := nil.
	[
		started signal.
		[ call response ] on: WebFetchAborted do: [ :e | err := e ].
		sem signal ] fork.
	self deny: (started waitTimeoutMilliseconds: 2000).
	Processor yield.
	call abort.
	self deny: (sem waitTimeoutMilliseconds: 2000).
	self assert: err notNil.
	self assert: host closedCount equals: 1
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testAvailabilityOffAndUnavailable [
	host availability: 0.
	self assert: WebFetch availability equals: #unavailable.
	self deny: WebFetch isAvailable.
	self should: [ (WebFetch request: 'http://example.test/u') start ] raise: WebFetchUnavailable.

	host availability: 2.
	self assert: WebFetch availability equals: #off.
	self deny: WebFetch isAvailable.
	self should: [ (WebFetch request: 'http://example.test/o') start ] raise: WebFetchNetworkOff
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testCallbackRefusesWaitingAndDoesNotStart [
	| call |
	host mayWait: false.
	self should: [ WebFetch get: 'http://example.test/cb1' ] raise: WebFetchInCallback.
	self should: [ (WebFetch request: 'http://example.test/cb2') stream: [ :s | ] ] raise: WebFetchInCallback.
	self assert: host requests isEmpty.

	host enqueuePending.
	call := (WebFetch request: 'http://example.test/cb3') start.
	[
		self should: [ call wait ] raise: WebFetchInCallback.
		self should: [ call response ] raise: WebFetchInCallback ] ensure: [ call abort ]
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testConcurrentCloseDuringStateOfNoPrimitiveFailed [
	| call |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/st') start.
	host onState: [ :id | call close ].
	self assert: call state equals: 0.
	host onState: nil
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testDoneCallSurvivesSessionForWhenDoneAndWaitUntil [
	| doneCall sem got |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'kept'.
	doneCall := (WebFetch request: 'http://example.test/kept') start.
	self assert: doneCall response contents equals: 'kept'.
	doneCall session: Object new.
	self assert: (doneCall waitUntil: [ doneCall isDone ] timeout: 0).
	sem := Semaphore new.
	got := nil.
	doneCall whenDone: [ :r | got := r contents. sem signal ] ifError: [ :e | sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 2000).
	self assert: got equals: 'kept'
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testFinalizationOf100DroppedCalls [
	| before deadline |
	before := self registeredSemaphoreCount.
	host maxOpen: 200.
	100 timesRepeat: [
		| calls |
		host enqueuePending.
		calls := (WebFetch request: 'http://example.test/gc') start.
		calls := nil ].
	deadline := Time millisecondClockValue + 5000.
	[ (host openCount > 0
		or: [ self registeredSemaphoreCount > before
		or: [ WebFetchCall openCount > 0 ] ])
		and: [ Time millisecondClockValue < deadline ] ] whileTrue: [
			Smalltalk garbageCollect.
			(Delay forMilliseconds: 50) wait ].
	self assert: host openCount equals: 0.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testLostIdSignalsSessionEndedAndUnregisters [
	| before call |
	before := self registeredSemaphoreCount.
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/lost') start.
	host close: host lastId.
	self should: [ call response ] raise: WebFetchSessionEnded.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testNetworkOffFailsOpenRequests [
	| call |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/no') start.
	host networkOff.
	self should: [ call response ] raise: WebFetchNetworkOff.
	self assert: WebFetch availability equals: #off.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testSemaphoreRegisteredAndUnregistered [
	| before call |
	before := self registeredSemaphoreCount.
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/sem') start.
	self assert: self registeredSemaphoreCount equals: before + 1.
	call abort.
	self assert: self registeredSemaphoreCount equals: before.

	host enqueueStatus: 200 headers: #() body: 'ok'.
	WebFetch get: 'http://example.test/sem2'.
	self assert: self registeredSemaphoreCount equals: before
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testSessionEndWakesAllWaitersAndAllowsNewCalls [
	| doneCall cResp cWhen cTimeout cStream started sem fakeSession results after |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'saved'.
	doneCall := (WebFetch request: 'http://example.test/done') start.
	self assert: doneCall response contents equals: 'saved'.

	host enqueuePending.
	cResp := (WebFetch request: 'http://example.test/p1') start.
	WebFetchCall startUp: false.
	self assert: cResp isPending.

	host enqueuePending.
	cWhen := (WebFetch request: 'http://example.test/p2') start.
	host enqueuePending.
	cTimeout := (WebFetch request: 'http://example.test/p3') start.
	host enqueuePending.
	cStream := (WebFetch request: 'http://example.test/p4') startWithWindow: WebFetchCall defaultStreamWindow.
	host deliverHeadFor: host lastId status: 200 reason: 'OK' url: 'http://example.test/p4' type: 'basic' redirected: false headers: #().

	started := Semaphore new.
	sem := Semaphore new.
	results := OrderedCollection new.
	[
		started signal.
		[ cResp response ] on: WebFetchSessionEnded do: [ :e | results add: #resp ].
		sem signal ] fork.
	cWhen whenDone: [ :r | sem signal ] ifError: [ :e |
		(e isKindOf: WebFetchSessionEnded) ifTrue: [ results add: #when ].
		sem signal ].
	[
		started signal.
		[ cTimeout waitTimeout: 10 seconds ] on: WebFetchSessionEnded do: [ :e | results add: #timeout ].
		sem signal ] fork.
	[
		| stream |
		stream := WebFetchBodyStream on: cStream response: cStream waitForHead.
		started signal.
		[ stream next ] on: WebFetchSessionEnded do: [ :e | results add: #stream ].
		sem signal ] fork.
	3 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
	Processor yield.

	fakeSession := Object new.
	{ cResp. cWhen. cTimeout. cStream } do: [ :c |
		c session: fakeSession.
		Smalltalk unregisterExternalObject: c semaphore ].
	host requests do: [ :r | host close: (r at: #id) ].

	WebFetchCall startUp: true.
	4 timesRepeat: [ self deny: (sem waitTimeoutMilliseconds: 2000) ].
	self assert: results size equals: 4.
	self assert: WebFetchCall openCount equals: 0.
	self assert: doneCall response contents equals: 'saved'.

	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'after'.
	after := WebFetch get: 'http://example.test/after'.
	self assert: after contents equals: 'after'
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testSixtyFifthOpenCallSignalsTooManyOpen [
	| calls |
	calls := OrderedCollection new.
	[
		64 timesRepeat: [
			host enqueuePending.
			calls add: (WebFetch request: 'http://example.test/lim') start ].
		self assert: host openCount equals: 64.
		self should: [ (WebFetch request: 'http://example.test/lim65') start ] raise: WebFetchTooManyOpen ]
		ensure: [ calls do: [ :c | c abort ] ]
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testStyleNoForbiddenNilPatterns [
	| eqNil isNilTrue isNilFalse |
	eqNil := '==' , ' nil'.
	isNilTrue := 'isNil' , ' ifTrue:'.
	isNilFalse := 'isNil' , ' ifFalse:'.
	#( 'WebFetch' 'WebFetch-Tests' ) do: [ :pkgName |
		| pkg |
		pkg := self packageNamed: pkgName.
		pkg ifNotNil: [
			pkg definedClasses do: [ :cls |
				{ cls. cls class } do: [ :behavior |
					behavior methods do: [ :m |
						| src |
						src := m sourceCode.
						self deny: (src includesSubstring: eqNil) description: m printString , ' uses ' , eqNil.
						self deny: (src includesSubstring: isNilTrue) description: m printString , ' uses ' , isNilTrue.
						self deny: (src includesSubstring: isNilFalse) description: m printString , ' uses ' , isNilFalse ] ] ] ] ]
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testTaskItFutureIfPresent [
	| future resp |
	(BlockClosure canUnderstand: #future) ifFalse: [ ^ self skip: 'TaskIt future not present' ].
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'async'.
	future := [ WebFetch get: 'http://example.test/tkt' ] future.
	resp := future synchronizeTimeout: 5 seconds.
	self assert: resp contents equals: 'async'
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testTerminateWaitingProcessAborts [
	| proc |
	host enqueuePending.
	proc := [ WebFetch get: 'http://example.test/hang' ] fork.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	proc terminate.
	self assert: (self waitUntil: [ host openCount = 0 ]).
	self assert: host closedCount equals: 1
]

{ #category : 'tests' }
WebFetchLifecycleTest >> testUnwindingAborts [
	| call |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/unw') start.
	[ call wait ] valueWithin: 30 milliSeconds onTimeout: [ ].
	self assert: host openCount equals: 0.
	self assert: host closedCount equals: 1.
	self assert: call isClosed
]
