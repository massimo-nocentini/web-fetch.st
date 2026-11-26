"
I test the life of the sockets of the image: the limit of open ones, lingering ones, `closeAll`, the session end and the save, the finalizer, the network turned off, and FFI callbacks.
"
Class {
	#name : 'WebFetchWebSocketLifecycleTest',
	#superclass : 'WebFetchWebSocketTestCase',
	#category : 'WebFetch-WebSocket-Tests-Tests',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchWebSocketLifecycleTest >> packageNamed: aString [
	^ PackageOrganizer default packageNamed: aString ifAbsent: [ nil ]
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testAbortAllOfWebFetchLeavesSocketsOpen [
	| ws |
	ws := self connect: '/abort-all'.
	WebFetch abortAll.
	self assert: ws isOpen.
	self assert: WebFetchWebSocket openCount equals: 1.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testCloseAllReleasesEverySocket [
	| sockets |
	sockets := (1 to: 3) collect: [ :i | self connect: '/all-' , i printString ].
	self assert: WebFetchWebSocket openCount equals: 3.
	WebFetchWebSocket closeAll.
	self assert: WebFetchWebSocket openCount equals: 0.
	self assert: host openCount equals: 0.
	sockets do: [ :each |
		self assert: each state equals: #failed.
		self assert: each error class equals: WebFetchAborted ]
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testConnectInACallbackSignalsInCallback [
	host autoOpen: false.
	self inCallback: [
		self should: [ WebFetchWebSocket connect: (self urlOf: '/callback') ] raise: WebFetchInCallback ].
	self assert: host openCount equals: 0.
	self assert: host releasedCount equals: 1
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testDroppedSocketIsReleasedByItsFinalizer [
	[ self connect: '/dropped' ] value.
	self assert: host openCount equals: 1.
	self assert: (self waitUntil: [
		Smalltalk garbageCollect.
		host openCount = 0 ] timeoutMs: 3000).
	self assert: host releasedCount equals: 1.
	self assert: self registeredSemaphoreCount equals: semaphoresBefore
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testInACallbackNextSignalsAndNextOrNilAndASendAnswer [
	"While another process waits in next, a callback reads with nextOrNil and sends with room at once; a wait of the callback itself signals WebFetchInCallback"

	| ws id box polled |
	ws := self connect: '/callback-io'.
	id := self idOf: ws.
	box := self background: [ ws next ].
	self settle.
	self inCallback: [
		self should: [ ws next ] raise: WebFetchInCallback.
		self should: [ ws nextTimeout: 1 second ] raise: WebFetchInCallback.
		polled := ws nextOrNil.
		ws sendText: 'from the callback'.
		self assert: ws state equals: #open ].
	self assert: polled equals: nil.
	self assert: host sent size equals: 1.
	host deliverText: 'after' to: id.
	self assert: (self waitUntil: [ self isDone: box ]).
	self assert: (box at: #value) equals: 'after'.
	host buffered: 16 * 1024 * 1024 for: id.
	self inCallback: [ self should: [ ws sendText: 'no room' ] raise: WebFetchInCallback ].
	self assert: ws isOpen.
	ws release
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testLingeringSocketsCount [
	host lingerOnRelease: true.
	host maxOpen: 2.
	(self connect: '/linger-1') release.
	(self connect: '/linger-2') release.
	self assert: host lingeringCount equals: 2.
	self should: [ self connect: '/linger-3' ] raise: WebFetchTooManyOpen.
	host endLingering.
	(self connect: '/linger-4') release
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testNetworkTurnedOff [
	| ws |
	ws := self connect: '/off'.
	host deliverText: 'before' to: (self idOf: ws).
	host networkOff.
	self assert: WebFetchWebSocket availability equals: #off.
	self assert: ws next equals: 'before'.
	self should: [ ws next ] raise: WebFetchNetworkOff.
	self assert: host closes last allButFirst equals: { 1000. 'network access is off' }.
	self should: [ self connect: '/off-again' ] raise: WebFetchNetworkOff.
	host availability: 0.
	self assert: WebFetchWebSocket availability equals: #unavailable.
	self should: [ self connect: '/none' ] raise: WebFetchUnavailable
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testSessionEndEndsOpenSocketsAndKeepsSettledOnes [
	| open closed waiter error |
	open := self connect: '/session-open'.
	closed := self connect: '/session-closed'.
	host deliverText: 'one' to: (self idOf: closed).
	host deliverText: 'two' to: (self idOf: closed).
	host deliverCloseTo: (self idOf: closed) code: 4000 reason: 'bye' clean: true.
	self assert: closed state equals: #closed.
	waiter := self background: [ open next ].
	self settle.
	host newSession.
	WebFetchWebSocket startUp: true.
	self assert: (self waitUntil: [ self isDone: waiter ]).
	self assert: (self errorOf: waiter) equals: WebFetchSessionEnded.
	self assert: open state equals: #failed.
	self should: [ open sendText: 'x' ] raise: WebFetchSessionEnded.
	self assert: WebFetchWebSocket openCount equals: 0.
	self assert: closed next equals: 'one'.
	self assert: closed next equals: 'two'.
	error := [ closed next. nil ] on: WebFetchWebSocketClosed do: [ :e | e ].
	self assert: error code equals: 4000.
	self assert: closed closeReason equals: 'bye'.
	self assert: closed wasClean
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testShutDownSettlesClosedSockets [
	| ws |
	ws := self connect: '/save'.
	host deliverText: 'kept' to: (self idOf: ws).
	host deliverCloseTo: (self idOf: ws) code: 1000 reason: '' clean: true.
	self assert: host openCount equals: 1.
	WebFetchWebSocket shutDown: false.
	self assert: host openCount equals: 0.
	self assert: WebFetchWebSocket openCount equals: 0.
	host newSession.
	self assert: ws next equals: 'kept'.
	self should: [ ws next ] raise: WebFetchWebSocketClosed
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testStyleNoForbiddenNilPatterns [
	| eqNil isNilTrue isNilFalse |
	eqNil := '==' , ' nil'.
	isNilTrue := 'isNil' , ' ifTrue:'.
	isNilFalse := 'isNil' , ' ifFalse:'.
	#( 'WebFetch-WebSocket' 'WebFetch-WebSocket-Tests' ) do: [ :pkgName |
		| pkg |
		pkg := self packageNamed: pkgName.
		self assert: pkg notNil.
		pkg definedClasses do: [ :cls |
			{ cls. cls class } do: [ :behavior |
				behavior methods do: [ :m |
					| src |
					src := m sourceCode.
					self deny: (src includesSubstring: eqNil) description: m printString , ' uses ' , eqNil.
					self deny: (src includesSubstring: isNilTrue) description: m printString , ' uses ' , isNilTrue.
					self deny: (src includesSubstring: isNilFalse) description: m printString , ' uses ' , isNilFalse ] ] ] ]
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testTheHostLosingASocketEndsItWithSessionEnded [
	| ws |
	ws := self connect: '/lost'.
	host newSession.
	self assert: ws state equals: #failed.
	self assert: ws error class equals: WebFetchSessionEnded.
	self should: [ ws next ] raise: WebFetchSessionEnded.
	self assert: WebFetchWebSocket openCount equals: 0
]

{ #category : 'tests' }
WebFetchWebSocketLifecycleTest >> testThirtyThirdOpenSignalsTooManyOpen [
	| sockets |
	sockets := OrderedCollection new.
	[
		32 timesRepeat: [ sockets add: (self connect: '/many') ].
		self assert: WebFetchWebSocket openCount equals: 32.
		self
			should: [ self connect: '/one-more' ]
			raise: WebFetchTooManyOpen
			whoseDescriptionIncludes: 'limit 32'
			description: 'the limit of open sockets'.
		self assert: WebFetchWebSocket openCount equals: 32 ] ensure: [ sockets do: [ :each | each release ] ].
	(self connect: '/again') release
]
