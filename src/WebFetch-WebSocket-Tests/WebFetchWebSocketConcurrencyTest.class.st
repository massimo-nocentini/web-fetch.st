"
I test the windows that only the fake host can force: readers and writers of one socket in several processes, each waking on the event that concerns it (three semaphores and the baton), and a release or a failure that comes between two primitive calls of one process.
"
Class {
	#name : 'WebFetchWebSocketConcurrencyTest',
	#superclass : 'WebFetchWebSocketTestCase',
	#category : 'WebFetch-WebSocket-Tests-Tests',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Tests'
}

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testAFailureBetweenTwoReceivesKeepsWhatWasTaken [
	| ws id |
	ws := self connect: '/fail-between'.
	id := self idOf: ws.
	host deliverText: 'a' to: id.
	host deliverText: 'b' to: id.
	host onNextPrimitive: [ host fail: id kind: #overflow message: 'full' ].
	self assert: ws next equals: 'a'.
	self assert: ws next equals: 'b'.
	self should: [ ws next ] raise: WebFetchWebSocketOverflow
]

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testAReleaseBetweenTwoPrimitivesIsAborted [
	"Another process releases the socket while the reader is in the middle of its look: the reader gets WebFetchAborted, never WebFetchSessionEnded"

	| ws box |
	ws := self connect: '/release-between'.
	host onNextPrimitive: [ ws release ].
	self should: [ ws next ] raise: WebFetchAborted.
	ws := self connect: '/release-between-2'.
	box := self background: [ ws next ].
	self settle.
	host onNextPrimitive: [ [ ws release ] forkAt: Processor activePriority ].
	host deliverText: 'gone' to: (self idOf: ws).
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: ((box at: #value ifAbsent: [ nil ]) = 'gone' or: [ (self errorOf: box) = WebFetchAborted ]).
	self assert: (self waitUntil: [ ws isOver ])
]

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testAReaderAndAWriterWakeOnTheirOwnEvents [
	| ws id reader writer |
	ws := self connect: '/two-ways'.
	id := self idOf: ws.
	host buffered: 16 * 1024 * 1024 for: id.
	reader := self background: [ ws next ].
	writer := self background: [ ws sendText: 'w' ].
	self settle.
	self deny: (self isDone: reader).
	self deny: (self isDone: writer).
	host drain: id.
	self assert: (self waitUntil: [ self isDone: writer ]).
	self assert: (self errorOf: writer) equals: nil.
	self settle.
	self deny: (self isDone: reader).
	host deliverText: 'r' to: id.
	self assert: (self waitUntil: [ self isDone: reader ] timeoutMs: 500).
	self assert: (reader at: #value) equals: 'r'.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testTwoReadersAndTwoMessagesOfOneTurn [
	"The host signals read once, when its queue goes from empty to one message: the baton wakes the second reader"

	| ws id first second |
	ws := self connect: '/two-readers'.
	id := self idOf: ws.
	first := self background: [ ws next ].
	second := self background: [ ws next ].
	self settle.
	host deliverText: '1' to: id.
	host deliverText: '2' to: id.
	self assert: (self waitUntil: [ (self isDone: first) and: [ self isDone: second ] ] timeoutMs: 500).
	self
		assert: { first at: #value. second at: #value } asSet
		equals: #( '1' '2' ) asSet.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testTwoWritersAndOneDrain [
	| ws id first second |
	ws := self connect: '/two-writers'.
	id := self idOf: ws.
	host buffered: 16 * 1024 * 1024 for: id.
	first := self background: [ ws sendText: 'first' ].
	second := self background: [ ws sendText: 'second' ].
	self settle.
	self assert: host sent isEmpty.
	host drain: id.
	self assert: (self waitUntil: [ (self isDone: first) and: [ self isDone: second ] ] timeoutMs: 500).
	self assert: (host sent collect: [ :each | (each at: 3) utf8Decoded ]) asSet equals: #( 'first' 'second' ) asSet.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketConcurrencyTest >> testWaitersOfTheEndAllWake [
	| ws id waiters |
	ws := self connect: '/end'.
	id := self idOf: ws.
	host buffered: 16 * 1024 * 1024 for: id.
	waiters := {
		self background: [ ws next ].
		self background: [ ws next ].
		self background: [ ws sendText: 'x' ].
		self background: [ ws waitForCloseTimeout: 5 seconds ] }.
	self settle.
	host deliverCloseTo: id code: 1001 reason: 'going away' clean: true.
	self assert: (self waitUntil: [ waiters allSatisfy: [ :each | self isDone: each ] ] timeoutMs: 1000).
	self assert: (self errorOf: waiters first) equals: WebFetchWebSocketClosed.
	self assert: (self errorOf: waiters second) equals: WebFetchWebSocketClosed.
	self assert: (self errorOf: waiters third) equals: WebFetchWebSocketClosed.
	self assert: (waiters fourth at: #value)
]
