"
I test `WebFetchBodyStream` and `WebFetchRequest >> stream:`.
"
Class {
	#name : 'WebFetchStreamTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchStreamTest >> helperNonLocalReturn [
	host enqueuePending.
	[
		self waitUntil: [ host lastId notNil ].
		host deliverHeadFor: host lastId status: 200 reason: 'OK' url: 'http://example.test/nlr' type: 'basic' redirected: false headers: #().
		host pushBytes: 'abcdef' utf8Encoded for: host lastId ] fork.
	(WebFetch request: 'http://example.test/nlr') stream: [ :s |
		s next.
		^ #escaped ]
]

{ #category : 'tests' }
WebFetchStreamTest >> testEarlyCloseVsCloseAfterEof [
	| streamRef |
	host enqueueStatus: 200 headers: #() body: 'abcdef' chunkSize: 2.
	(WebFetch request: 'http://example.test/s1') stream: [ :s |
		self assert: s isBinary.
		self assert: s isStream.
		self assert: s response status equals: 200.
		self assert: s response rawContents isNil.
		self assert: s next equals: $a asciiValue.
		s close.
		streamRef := s ].
	self should: [ streamRef next ] raise: WebFetchAborted.
	self assert: host openCount equals: 0.

	host enqueueStatus: 200 headers: #() body: 'xy'.
	(WebFetch request: 'http://example.test/s2') stream: [ :s |
		self assert: s upToEnd equals: 'xy' utf8Encoded.
		self assert: s atEnd.
		streamRef := s ].
	self assert: streamRef next isNil.
	self assert: streamRef peek isNil
]

{ #category : 'tests' }
WebFetchStreamTest >> testErrorInBlockClosesAndPropagates [
	host enqueueStatus: 200 headers: #() body: 'abcdef'.
	self
		should: [
			(WebFetch request: 'http://example.test/err') stream: [ :s |
				s next.
				ZeroDivide signal ] ]
		raise: ZeroDivide.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchStreamTest >> testFailureMidBody [
	| id |
	host enqueuePending.
	[
		[ host lastId isNil ] whileTrue: [ (Delay forMilliseconds: 5) wait ].
		id := host lastId.
		host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://example.test/mid' type: 'basic' redirected: false headers: #().
		host pushBytes: 'abc' utf8Encoded for: id.
		(Delay forMilliseconds: 30) wait.
		host fail: id kind: #body message: 'truncated' ] fork.
	self
		should: [
			(WebFetch request: 'http://example.test/mid') stream: [ :s |
				self assert: (s next: 3) equals: 'abc' utf8Encoded.
				s next ] ]
		raise: WebFetchNetworkError
]

{ #category : 'tests' }
WebFetchStreamTest >> testNextPeekNextCountReadIntoDoAndBeyondEnd [
	| answer buf collected |
	host enqueueStatus: 200 headers: #() body: '0123456789abcdef' chunkSize: 3.
	answer := (WebFetch request: 'http://example.test/ch') stream: [ :s |
		self assert: s peek equals: $0 asciiValue.
		self assert: s peek equals: $0 asciiValue.
		self assert: s next equals: $0 asciiValue.
		buf := ByteArray new: 4.
		self assert: (s readInto: buf startingAt: 1 count: 2) equals: 2.
		self assert: (buf copyFrom: 1 to: 2) equals: '12' utf8Encoded.
		self assert: (s next: 5) equals: '34567' utf8Encoded.
		self assert: (s next: 100) equals: '89abcdef' utf8Encoded.
		self assert: s atEnd.
		#blockAnswer ].
	self assert: answer equals: #blockAnswer.

	host enqueueStatus: 200 headers: #() body: 'xyz' chunkSize: 2.
	collected := OrderedCollection new.
	(WebFetch request: 'http://example.test/do') stream: [ :s |
		s do: [ :b | collected add: b ] ].
	self assert: collected asByteArray equals: 'xyz' utf8Encoded
]

{ #category : 'tests' }
WebFetchStreamTest >> testNonLocalReturnClosesStream [
	self assert: self helperNonLocalReturn equals: #escaped.
	self assert: host openCount equals: 0.
	self assert: host closedCount equals: 1
]

{ #category : 'tests' }
WebFetchStreamTest >> testStreamNotBoundedByMaximumBodySize [
	| data |
	host enqueueStatus: 200 headers: #() body: (ByteArray new: 200 withAll: 42) chunkSize: 37.
	data := (WebFetch request: 'http://example.test/unbounded')
		maximumBodySize: 10;
		stream: [ :s | s upToEnd ].
	self assert: data size equals: 200
]

{ #category : 'tests' }
WebFetchStreamTest >> testStreamTerminatedReaderCloses [
	| proc |
	host enqueuePending.
	proc := [
		(WebFetch request: 'http://example.test/sterm') stream: [ :s | s upToEnd ] ] fork.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	proc terminate.
	self assert: (self waitUntil: [ host openCount = 0 ]).
	self assert: host closedCount equals: 1
]

{ #category : 'tests' }
WebFetchStreamTest >> testThreeMiBStreamAndBackpressure [
	| source received |
	source := ByteArray new: 3 * 1024 * 1024.
	1 to: source size do: [ :i | source at: i put: (i bitAnd: 255) ].
	host enqueueStatus: 200 headers: #() body: source chunkSize: 65536.
	received := (WebFetch request: 'http://example.test/3m') stream: [ :s | s upToEnd ].
	self assert: received equals: source.
	self assert: host maxBufferedBytes <= (WebFetchCall defaultStreamWindow + 65536)
]
