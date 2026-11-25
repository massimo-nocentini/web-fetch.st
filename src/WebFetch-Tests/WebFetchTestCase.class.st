"
I am the base SUnit test case for `WebFetch-Tests`. I install a fresh `WebFetchTestHost` as `WebFetchHost default` in `setUp`, restore the previous host in `tearDown`, and verify that no request remains open in the host or in `WebFetchCall`.
"
Class {
	#name : 'WebFetchTestCase',
	#superclass : 'TestCase',
	#instVars : [
		'host',
		'previousHost'
	],
	#category : 'WebFetch-Tests-Base',
	#package : 'WebFetch-Tests',
	#tag : 'Base'
}

{ #category : 'testing' }
WebFetchTestCase class >> isAbstract [
	^ self == WebFetchTestCase
]

{ #category : 'helpers' }
WebFetchTestCase >> inCallback: aBlock [
	"Evaluate aBlock as an FFI callback does"

	host mayWait: false.
	[ WebFetchTestCallback basicNew evaluate: aBlock ] ensure: [ host mayWait: true ]
]

{ #category : 'helpers' }
WebFetchTestCase >> registeredSemaphoreCount [
	| table count |
	table := Smalltalk specialObjectsArray at: 39.
	count := 0.
	table do: [ :each | each ifNotNil: [ count := count + 1 ] ].
	^ count
]

{ #category : 'running' }
WebFetchTestCase >> setUp [
	super setUp.
	previousHost := WebFetchHost default.
	host := WebFetchTestHost new.
	WebFetchHost default: host
]

{ #category : 'running' }
WebFetchTestCase >> tearDown [
	| leakedHost leakedCalls |
	leakedHost := host openCount.
	leakedCalls := WebFetchCall openCount.
	[
		WebFetchCall abortAll.
		WebFetchHost default: previousHost ] ensure: [ super tearDown ].
	self assert: leakedHost equals: 0.
	self assert: leakedCalls equals: 0
]

{ #category : 'helpers' }
WebFetchTestCase >> waitUntil: aBlock [
	^ self waitUntil: aBlock timeoutMs: 2000
]

{ #category : 'helpers' }
WebFetchTestCase >> waitUntil: aBlock timeoutMs: milliseconds [
	| deadline |
	deadline := Time millisecondClockValue + milliseconds.
	[ aBlock value ] whileFalse: [
		Time millisecondClockValue >= deadline ifTrue: [ ^ false ].
		(Delay forMilliseconds: 5) wait ].
	^ true
]
