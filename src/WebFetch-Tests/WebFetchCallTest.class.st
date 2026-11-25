"
I test `WebFetchCall` whole-body responses, size limits, error kinds, multiple waiters, `waitTimeout:` and `whenDone:ifError:`.
"
Class {
	#name : 'WebFetchCallTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'tests' }
WebFetchCallTest >> testAbortIdempotentAndAfterEndNoOp [
	| call resp |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'ok'.
	call := (WebFetch request: 'http://example.test/done') start.
	resp := call response.
	self assert: resp contents equals: 'ok'.
	call abort.
	call close.
	self assert: call state equals: 3.
	self assert: call response contents equals: 'ok'.
	self assert: (call readInto: (ByteArray new: 4) startingAt: 1 count: 4) equals: 0.

	host enqueuePending.
	call := (WebFetch request: 'http://example.test/ab2') start.
	call abort.
	call abort.
	self assert: call state equals: 0.
	self should: [ call response ] raise: WebFetchAborted.
	self should: [ call readInto: (ByteArray new: 4) startingAt: 1 count: 4 ] raise: WebFetchAborted
]

{ #category : 'tests' }
WebFetchCallTest >> testBodySizesZeroOneExactAndTooLarge [
	| r0 r1 rExact |
	host enqueueStatus: 200 headers: #( ) body: #[ ].
	r0 := (WebFetch request: 'http://example.test/0') maximumBodySize: 0; fetch.
	self assert: r0 rawContents equals: #[ ].

	host enqueueStatus: 200 headers: #( ) body: #[ 65 ].
	r1 := (WebFetch request: 'http://example.test/1') maximumBodySize: 1; fetch.
	self assert: r1 rawContents equals: #[ 65 ].

	host enqueueStatus: 200 headers: #( ) body: (ByteArray new: 100 withAll: 7).
	rExact := (WebFetch request: 'http://example.test/e1') maximumBodySize: 100; fetch.
	self assert: rExact rawContents size equals: 100.

	host enqueueStatus: 200 headers: #( ) body: (ByteArray new: 100 withAll: 8) chunkSize: 13.
	rExact := (WebFetch request: 'http://example.test/e2') maximumBodySize: 100; fetch.
	self assert: rExact rawContents size equals: 100.

	host enqueueStatus: 200 headers: #( ) body: (ByteArray new: 101 withAll: 9).
	self
		should: [ (WebFetch request: 'http://example.test/big1') maximumBodySize: 100; fetch ]
		raise: WebFetchTooLarge.

	host enqueueStatus: 200 headers: #( ) body: (ByteArray new: 101 withAll: 9) chunkSize: 17.
	self
		should: [ (WebFetch request: 'http://example.test/big2') maximumBodySize: 100; fetch ]
		raise: WebFetchTooLarge
]

{ #category : 'tests' }
WebFetchCallTest >> testTooLargeAcrossMultipleChunksWakesWaiter [
	| call started done gotTooLarge id |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/multi-big')
		maximumBodySize: 10;
		start.
	id := host lastId.
	started := Semaphore new.
	done := Semaphore new.
	gotTooLarge := false.
	[
		started signal.
		[ call response ] on: WebFetchTooLarge do: [ :e | gotTooLarge := true ].
		done signal ] fork.
	self deny: (started waitTimeoutMilliseconds: 2000).
	Processor yield.
	host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://example.test/multi-big' type: 'basic' redirected: false headers: #().
	host pushBytes: (ByteArray new: 6 withAll: 1) for: id.
	(Delay forMilliseconds: 20) wait.
	host pushBytes: (ByteArray new: 6 withAll: 2) for: id.
	self deny: (done waitTimeoutMilliseconds: 1000).
	self assert: gotTooLarge
]

{ #category : 'tests' }
WebFetchCallTest >> testCloseOfCallBeingRead [
	| call buf |
	host enqueueStatus: 200 headers: #() body: 'abcdefgh' chunkSize: 4.
	call := (WebFetch request: 'http://example.test/cr') startWithWindow: 1048576.
	call waitForHead.
	buf := ByteArray new: 2.
	call waitUntil: [ call availableBytes > 0 ] timeout: 2000.
	self assert: (call readInto: buf startingAt: 1 count: 2) equals: 2.
	call close.
	self assert: call state equals: 0.
	self should: [ call readInto: buf startingAt: 1 count: 2 ] raise: WebFetchAborted
]

{ #category : 'tests' }
WebFetchCallTest >> testErrorKindsAndCopySignalling [
	| pairs call |
	pairs := {
		#request -> WebFetchBadRequest.
		#redirect -> WebFetchBadRequest.
		#network -> WebFetchNetworkError.
		#body -> WebFetchNetworkError.
		#timeout -> WebFetchTimeout.
		#aborted -> WebFetchAborted.
		#off -> WebFetchNetworkOff
	}.
	pairs do: [ :assoc |
		| err |
		host enqueueErrorKind: assoc key message: 'boom'.
		call := (WebFetch request: 'http://example.test/err') start.
		call wait.
		self assert: call state equals: 4.
		self assert: call isFailed.
		err := [ call response. nil ] on: assoc value do: [ :e | e ].
		self assert: err notNil.
		self assert: err kind equals: assoc key.
		(assoc key == #network or: [ assoc key == #body ]) ifTrue: [
			self assert: (err messageText includesSubstring: 'CORS') ].
		self should: [ call response ] raise: assoc value ]
]

{ #category : 'tests' }
WebFetchCallTest >> testHttpErrorStatusIsAnAnswer [
	| resp |
	host enqueueStatus: 404 reason: 'Not Found' headers: { 'Content-Type' -> 'text/plain' } body: 'missing'.
	resp := WebFetch get: 'http://example.test/missing'.
	self assert: resp status equals: 404.
	self deny: resp isSuccess.
	self assert: resp contents equals: 'missing'
]

{ #category : 'tests' }
WebFetchCallTest >> testMultipleWaitersAllWake [
	| call done started results |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/w') start.
	done := Semaphore new.
	started := Semaphore new.
	results := OrderedCollection new.
	3 timesRepeat: [
		[
			started signal.
			results add: call response rawContents.
			done signal ] fork ].
	3 timesRepeat: [ self deny: (started waitTimeoutMilliseconds: 2000) ].
	Processor yield.
	host deliverHeadFor: host lastId status: 200 reason: 'OK' url: 'http://example.test/w' type: 'basic' redirected: false headers: #().
	host pushBytes: 'ok' utf8Encoded for: host lastId.
	host finish: host lastId.
	3 timesRepeat: [ self deny: (done waitTimeoutMilliseconds: 2000) ].
	self assert: results size equals: 3.
	results do: [ :each | self assert: each equals: 'ok' utf8Encoded ].
	self assert: call state equals: 3.
	self assert: call availableBytes equals: 0
]

{ #category : 'tests' }
WebFetchCallTest >> testWaitTimeoutPollsAndTerminateDoesNotAbort [
	| call proc started |
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/slow') start.
	self deny: (call waitTimeout: Duration zero).
	self deny: (call waitTimeout: 20 milliSeconds).
	self assert: host openCount equals: 1.

	"Terminating a process inside waitTimeout: must NOT abort the call"
	started := Semaphore new.
	proc := [
		started signal.
		call waitTimeout: 10 seconds ] fork.
	self deny: (started waitTimeoutMilliseconds: 2000).
	Processor yield.
	proc terminate.
	self assert: (self waitUntil: [ proc isTerminated ]).
	self assert: host openCount equals: 1.

	host deliverHeadFor: host lastId status: 200 reason: 'OK' url: 'http://example.test/slow' type: 'basic' redirected: false headers: #().
	host pushBytes: 'done' utf8Encoded for: host lastId.
	host finish: host lastId.
	self assert: (call waitTimeout: 2 seconds).
	self assert: call response rawContents equals: 'done' utf8Encoded
]

{ #category : 'tests' }
WebFetchCallTest >> testWhenDoneAlreadyDoneMultiplePriorityAndCallback [
	| call sem results proc err |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'ready'.
	call := (WebFetch request: 'http://example.test/wd1') start.
	call wait.
	sem := Semaphore new.
	results := OrderedCollection new.
	proc := call whenDone: [ :r | results add: r contents. sem signal ] ifError: [ :e | sem signal ].
	self assert: proc priority equals: Processor activePriority.
	call whenDone: [ :r | results add: r contents. sem signal ] ifError: [ :e | sem signal ].
	results add: call response contents.
	2 timesRepeat: [ self deny: (sem waitTimeoutMilliseconds: 2000) ].
	self assert: results asArray equals: #( 'ready' 'ready' 'ready' ).

	"whenDone in a callback gives WebFetchInCallback to errorBlock and leaves call open"
	host enqueuePending.
	call := (WebFetch request: 'http://example.test/wdcb') start.
	host mayWait: false.
	sem := Semaphore new.
	err := nil.
	[
		call whenDone: [ :r | sem signal ] ifError: [ :e | err := e. sem signal ].
		self deny: (sem waitTimeoutMilliseconds: 2000).
		self assert: (err isKindOf: WebFetchInCallback).
		self assert: host openCount equals: 1 ]
		ensure: [
			host mayWait: true.
			call abort ]
]

{ #category : 'tests' }
WebFetchCallTest >> testWhenDoneSuccessFailureAndUserError [
	| call sem gotResp gotErr userErr |
	host enqueueStatus: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'hi'.
	call := (WebFetch request: 'http://example.test/ok') start.
	sem := Semaphore new.
	gotResp := nil.
	call whenDone: [ :r | gotResp := r. sem signal ] ifError: [ :e | sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 2000).
	self assert: gotResp contents equals: 'hi'.

	host enqueueErrorKind: #timeout message: 'slow'.
	call := (WebFetch request: 'http://example.test/fail') start.
	sem := Semaphore new.
	gotErr := nil.
	call whenDone: [ :r | sem signal ] ifError: [ :e | gotErr := e. sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 2000).
	self assert: (gotErr isKindOf: WebFetchTimeout).

	host enqueueStatus: 200 headers: #() body: 'x'.
	call := (WebFetch request: 'http://example.test/uerr') start.
	sem := Semaphore new.
	gotErr := nil.
	userErr := false.
	call
		whenDone: [ :r |
			[ self error: 'user boom' ] on: Error do: [ :e | userErr := true. sem signal ] ]
		ifError: [ :e | gotErr := e. sem signal ].
	self deny: (sem waitTimeoutMilliseconds: 2000).
	self assert: userErr.
	self assert: gotErr isNil
]
