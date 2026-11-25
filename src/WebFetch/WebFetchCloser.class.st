"
I am the finalizer of a `WebFetchCall`. I hold only the host, handle, semaphore and session (never the call) so that `FinalizationRegistry` can collect dropped calls and release their host handles and external semaphores.
"
Class {
	#name : 'WebFetchCloser',
	#superclass : 'Object',
	#instVars : [
		'host',
		'handle',
		'semaphore',
		'session'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'instance creation' }
WebFetchCloser class >> host: aHost semaphore: aSemaphore session: aSession [
	^ self new
		host: aHost
		semaphore: aSemaphore
		session: aSession;
		yourself
]

{ #category : 'closing' }
WebFetchCloser >> close [
	"Close the host handle and unregister the semaphore once, only in the session that created them."

	| h s |
	h := handle.
	handle := nil.
	s := semaphore.
	semaphore := nil.
	h ifNil: [ s ifNil: [ ^ false ] ].
	session == Smalltalk session ifFalse: [ ^ false ].
	h ifNotNil: [ [ host close: h ] on: Error do: [ :e | ] ].
	s ifNotNil: [ [ Smalltalk unregisterExternalObject: s ] on: Error do: [ :e | ] ].
	^ true
]

{ #category : 'finalization' }
WebFetchCloser >> finalize [
	"Release host resources on garbage collection without letting errors escape."

	[ self close ] on: Error do: [ :e | ]
]

{ #category : 'accessing' }
WebFetchCloser >> handle [
	^ handle
]

{ #category : 'initialization' }
WebFetchCloser >> host: aHost semaphore: aSemaphore session: aSession [
	host := aHost.
	handle := nil.
	semaphore := aSemaphore.
	session := aSession
]

{ #category : 'starting' }
WebFetchCloser >> startSemaphore: semIndex head: headBytes body: bodyBytesOrNil window: windowBytes timeout: timeoutMs flags: flags [
	"Start the host fetch and store the handle in the same statement so no process switch can lose it."

	handle := host
		startSemaphore: semIndex
		head: headBytes
		body: bodyBytesOrNil
		window: windowBytes
		timeout: timeoutMs
		flags: flags.
	^ handle
]
