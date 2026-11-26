"
I am the finalizer of a `WebFetchWebSocket`. I hold only the host, the id of the socket in the host (`handle`), the three external semaphores and the session, never the socket, so that `FinalizationRegistry` can collect a dropped socket and release its host record and its semaphores.

`close` releases the host record and then unregisters the three semaphores, once, and only in the session that made them: after a resume the ids and the indexes belong to the VM that saved the image. I am not a `WebFetchCloser`: a socket has three semaphores, and its host has `release:`, never `close:`, which there is the closing handshake.
"
Class {
	#name : 'WebFetchWebSocketCloser',
	#superclass : 'Object',
	#instVars : [
		'host',
		'handle',
		'semaphores',
		'session'
	],
	#category : 'WebFetch-WebSocket-Core',
	#package : 'WebFetch-WebSocket',
	#tag : 'Core'
}

{ #category : 'instance creation' }
WebFetchWebSocketCloser class >> host: aHost semaphores: anArray session: aSession [
	^ self new
		host: aHost
		semaphores: anArray
		session: aSession;
		yourself
]

{ #category : 'closing' }
WebFetchWebSocketCloser >> close [
	"Release the host record and unregister the semaphores once, only in the session that made them. Answer whether it did."

	| h s |
	h := handle.
	handle := nil.
	s := semaphores.
	semaphores := nil.
	(h isNil and: [ s isNil ]) ifTrue: [ ^ false ].
	session == Smalltalk session ifFalse: [ ^ false ].
	h ifNotNil: [ [ host release: h ] on: Error do: [ :e | ] ].
	s ifNotNil: [
		s do: [ :each | [ Smalltalk unregisterExternalObject: each ] on: Error do: [ :e | ] ] ].
	^ true
]

{ #category : 'finalization' }
WebFetchWebSocketCloser >> finalize [
	"Release the host record of a dropped socket without letting errors escape"

	[ self close ] on: Error do: [ :e | ]
]

{ #category : 'accessing' }
WebFetchWebSocketCloser >> handle [
	^ handle
]

{ #category : 'initialization' }
WebFetchWebSocketCloser >> host: aHost semaphores: anArray session: aSession [
	host := aHost.
	handle := nil.
	semaphores := anArray.
	session := aSession
]

{ #category : 'opening' }
WebFetchWebSocketCloser >> openSemaphores: indexes record: recordBytes maxMessage: maxMessage maxQueued: maxQueued timeout: timeoutMs [
	"Open the host socket and store its id in the same statement, so that no process switch can lose it"

	handle := host
		openState: (indexes at: 1)
		read: (indexes at: 2)
		write: (indexes at: 3)
		record: recordBytes
		maxMessage: maxMessage
		maxQueued: maxQueued
		timeout: timeoutMs.
	^ handle
]
