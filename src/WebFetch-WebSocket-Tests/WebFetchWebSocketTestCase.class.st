"
I am the base of the unit tests of `WebFetch-WebSocket`. I install a fresh `WebFetchWebSocketTestHost` as `WebFetchWebSocketHost default` in `setUp`, restore the previous host in `tearDown`, and check that no socket is left in the host or in `WebFetchWebSocket`, and that no semaphore of a socket stays registered.
"
Class {
	#name : 'WebFetchWebSocketTestCase',
	#superclass : 'TestCase',
	#instVars : [
		'host',
		'previousHost',
		'semaphoresBefore'
	],
	#category : 'WebFetch-WebSocket-Tests-Base',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Base'
}

{ #category : 'testing' }
WebFetchWebSocketTestCase class >> isAbstract [
	^ self == WebFetchWebSocketTestCase
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> background: aBlock [
	"Evaluate aBlock in a process of the priority of the test; answer a Dictionary that gets #value or #error, then #done"

	| box |
	box := Dictionary new.
	box
		at: #process
		put: ([
			[ box at: #value put: aBlock value ]
				on: Error
				do: [ :e | box at: #error put: e ].
			box at: #done put: true ] forkAt: Processor activePriority).
	^ box
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> connect: path [
	^ WebFetchWebSocket connect: (self urlOf: path)
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> errorOf: aBox [
	"The class of the error of a background block, nil if none"

	^ (aBox at: #error ifAbsent: [ nil ]) ifNotNil: [ :e | e class ]
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> idOf: aSocket [
	^ aSocket instVarNamed: 'handle'
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> inCallback: aBlock [
	"Evaluate aBlock as an FFI callback does"

	host mayWait: false.
	[ WebFetchTestCallback basicNew evaluate: aBlock ] ensure: [ host mayWait: true ]
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> isDone: aBox [
	^ aBox includesKey: #done
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> registeredSemaphoreCount [
	^ (Smalltalk specialObjectsArray at: 39) count: [ :each | each notNil ]
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> settle [
	"Let the processes of the same priority run (the deliveries of the host, the waiters)"

	(Delay forMilliseconds: 20) wait
]

{ #category : 'running' }
WebFetchWebSocketTestCase >> setUp [
	super setUp.
	previousHost := WebFetchWebSocketHost default.
	host := WebFetchWebSocketTestHost new.
	WebFetchWebSocketHost default: host.
	semaphoresBefore := self registeredSemaphoreCount
]

{ #category : 'running' }
WebFetchWebSocketTestCase >> tearDown [
	| leakedHost leakedSockets |
	leakedHost := host openCount.
	leakedSockets := WebFetchWebSocket openCount.
	[
		WebFetchWebSocket closeAll.
		WebFetchWebSocketHost default: previousHost ] ensure: [ super tearDown ].
	self assert: leakedHost equals: 0.
	self assert: leakedSockets equals: 0.
	self assert: self registeredSemaphoreCount equals: semaphoresBefore
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> urlOf: path [
	^ 'ws://example.test' , path
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> waitUntil: aBlock [
	^ self waitUntil: aBlock timeoutMs: 2000
]

{ #category : 'helpers' }
WebFetchWebSocketTestCase >> waitUntil: aBlock timeoutMs: milliseconds [
	| deadline |
	deadline := Time millisecondClockValue + milliseconds.
	[ aBlock value ] whileFalse: [
		Time millisecondClockValue >= deadline ifTrue: [ ^ false ].
		(Delay forMilliseconds: 5) wait ].
	^ true
]
