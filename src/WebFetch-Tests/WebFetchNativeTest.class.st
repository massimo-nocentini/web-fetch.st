"
I test the real `WebFetchHost default` on a native VM without `WebFetchPlugin`. I skip when WebFetch is available or explicitly turned off (`#ready` or `#off`).
"
Class {
	#name : 'WebFetchNativeTest',
	#superclass : 'TestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchNativeTest >> registeredSemaphoreCount [
	| table count |
	table := Smalltalk specialObjectsArray at: 39.
	count := 0.
	table do: [ :each | each ifNotNil: [ count := count + 1 ] ].
	^ count
]

{ #category : 'tests' }
WebFetchNativeTest >> testUnavailableWithoutPlugin [
	| before |
	(WebFetch isAvailable or: [ WebFetch availability == #off ]) ifTrue: [
		^ self skip: 'WebFetchPlugin is present' ].
	self assert: WebFetch availability equals: #unavailable.
	self deny: WebFetch isAvailable.
	self assert: WebFetchHost default mayWait.
	before := self registeredSemaphoreCount.
	self should: [ (WebFetch request: 'https://example.org/') start ] raise: WebFetchUnavailable.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0
]
