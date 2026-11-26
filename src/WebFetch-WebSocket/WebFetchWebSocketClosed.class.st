"
I am signalled by `next` on a `WebFetchWebSocket` that is closed and has no message left, and by a send on one that is closing or closed. I have the close code, the reason and whether the close was clean, when they are known (nil while the socket is closing).
"
Class {
	#name : 'WebFetchWebSocketClosed',
	#superclass : 'WebFetchError',
	#instVars : [
		'code',
		'reason',
		'wasClean'
	],
	#category : 'WebFetch-WebSocket-Errors',
	#package : 'WebFetch-WebSocket',
	#tag : 'Errors'
}

{ #category : 'instance creation' }
WebFetchWebSocketClosed class >> code: anIntegerOrNil reason: aStringOrNil wasClean: aBooleanOrNil [
	"Answer an unsignalled instance for a close with that code, reason and cleanness"

	^ self new
		kind: #closed;
		code: anIntegerOrNil reason: aStringOrNil wasClean: aBooleanOrNil;
		yourself
]

{ #category : 'accessing' }
WebFetchWebSocketClosed class >> defaultKind [
	^ #closed
]

{ #category : 'accessing' }
WebFetchWebSocketClosed >> code [
	"The close code (1000 for a normal close, 1006 when the connection was lost), or nil while closing"

	^ code
]

{ #category : 'initialization' }
WebFetchWebSocketClosed >> code: anIntegerOrNil reason: aStringOrNil wasClean: aBooleanOrNil [
	code := anIntegerOrNil.
	reason := aStringOrNil.
	wasClean := aBooleanOrNil.
	self messageText: (String streamContents: [ :out |
		out nextPutAll: (code ifNil: [ 'The WebSocket is closing' ] ifNotNil: [ 'The WebSocket is closed' ]).
		code ifNotNil: [
			out nextPutAll: ' ('; print: code.
			(reason isNil or: [ reason isEmpty ]) ifFalse: [ out space; nextPutAll: reason ].
			wasClean == false ifTrue: [ out nextPutAll: ', not clean' ].
			out nextPut: $) ] ])
]

{ #category : 'accessing' }
WebFetchWebSocketClosed >> reason [
	^ reason
]

{ #category : 'accessing' }
WebFetchWebSocketClosed >> wasClean [
	^ wasClean
]
