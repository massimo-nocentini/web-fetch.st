"
I test the real `WebFetchWebSocketHost default` on a VM without the `WebSocketPlugin` (a native one). I skip myself when WebSockets are available or turned off (`#ready` or `#off`).
"
Class {
	#name : 'WebFetchWebSocketNativeTest',
	#superclass : 'TestCase',
	#category : 'WebFetch-WebSocket-Tests-Tests',
	#package : 'WebFetch-WebSocket-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchWebSocketNativeTest >> registeredSemaphoreCount [
	^ (Smalltalk specialObjectsArray at: 39) count: [ :each | each notNil ]
]

{ #category : 'tests' }
WebFetchWebSocketNativeTest >> testUnavailableWithoutPlugin [
	| before socket |
	WebFetchWebSocket availability == #unavailable ifFalse: [ ^ self skip: 'WebSocketPlugin is present' ].
	self deny: WebFetchWebSocket isAvailable.
	self assert: WebFetchWebSocketHost default mayWait.
	before := self registeredSemaphoreCount.
	self should: [ WebFetchWebSocket connect: 'wss://echo.websocket.org' ] raise: WebFetchUnavailable.
	socket := WebFetchWebSocket url: 'wss://echo.websocket.org'.
	self should: [ socket start ] raise: WebFetchUnavailable.
	self assert: socket state equals: #failed.
	self assert: (socket error isKindOf: WebFetchUnavailable).
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchWebSocket openCount equals: 0
]
