"
I am a binary read stream over the body of a streaming `WebFetchCall`.

`response` answers the `WebFetchResponse` (status and headers; `rawContents` is nil). Waiting reads abort the call if curtailed. Closing before EOF drops any buffered bytes, aborts the call, and subsequent reads signal `WebFetchAborted`; closing after EOF leaves `next` answering `nil`.
"
Class {
	#name : 'WebFetchBodyStream',
	#superclass : 'Object',
	#instVars : [
		'call',
		'response',
		'buffer',
		'position',
		'limit',
		'atEnd',
		'closed'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'instance creation' }
WebFetchBodyStream class >> on: aWebFetchCall response: aWebFetchResponse [
	^ self new
		call: aWebFetchCall response: aWebFetchResponse;
		yourself
]

{ #category : 'testing' }
WebFetchBodyStream >> atEnd [
	position <= limit ifTrue: [ ^ false ].
	atEnd ifTrue: [ ^ true ].
	closed ifTrue: [ ^ true ].
	^ self fillBuffer not
]

{ #category : 'initialization' }
WebFetchBodyStream >> call: aWebFetchCall response: aWebFetchResponse [
	call := aWebFetchCall.
	response := aWebFetchResponse.
	buffer := ByteArray new: 16384.
	position := 1.
	limit := 0.
	atEnd := false.
	closed := false
]

{ #category : 'closing' }
WebFetchBodyStream >> close [
	closed ifTrue: [ ^ self ].
	closed := true.
	position := 1.
	limit := 0.
	atEnd
		ifTrue: [ call finishStream ]
		ifFalse: [ call close ]
]

{ #category : 'enumerating' }
WebFetchBodyStream >> do: aBlock [
	[ self atEnd ] whileFalse: [ aBlock value: self next ]
]

{ #category : 'private' }
WebFetchBodyStream >> fillBuffer [
	"Ensure at least one buffered byte. Answer false at EOF or signal on failure or early close."

	| n |
	position <= limit ifTrue: [ ^ true ].
	atEnd ifTrue: [ ^ false ].
	closed ifTrue: [ WebFetchAborted signal: 'WebFetchBodyStream is closed' ].
	n := self waitAndReadInto: buffer startingAt: 1 count: buffer size.
	n > 0 ifTrue: [
		position := 1.
		limit := n.
		^ true ].
	^ false
]

{ #category : 'testing' }
WebFetchBodyStream >> isBinary [
	^ true
]

{ #category : 'testing' }
WebFetchBodyStream >> isStream [
	^ true
]

{ #category : 'reading' }
WebFetchBodyStream >> next [
	"Answer the next byte (0..255), or nil at EOF."

	| byte |
	self fillBuffer ifFalse: [ ^ nil ].
	byte := buffer at: position.
	position := position + 1.
	^ byte
]

{ #category : 'reading' }
WebFetchBodyStream >> next: anInteger [
	"Answer a ByteArray of up to anInteger bytes."

	| result offset |
	anInteger <= 0 ifTrue: [ ^ #[ ] ].
	result := ByteArray new: anInteger.
	offset := 1.
	[ offset <= anInteger ] whileTrue: [
		| n |
		n := self readInto: result startingAt: offset count: anInteger - offset + 1.
		n = 0 ifTrue: [ ^ result copyFrom: 1 to: offset - 1 ].
		offset := offset + n ].
	^ result
]

{ #category : 'reading' }
WebFetchBodyStream >> peek [
	"Answer the next byte without consuming it, or nil at EOF."

	self fillBuffer ifFalse: [ ^ nil ].
	^ buffer at: position
]

{ #category : 'reading' }
WebFetchBodyStream >> readInto: aByteArray startingAt: startIndex count: count [
	"Wait for at least one byte and copy up to count bytes into aByteArray. Answer 0 at EOF."

	count <= 0 ifTrue: [ ^ 0 ].
	position <= limit ifTrue: [
		| n |
		n := count min: limit - position + 1.
		aByteArray
			replaceFrom: startIndex
			to: startIndex + n - 1
			with: buffer
			startingAt: position.
		position := position + n.
		^ n ].
	atEnd ifTrue: [ ^ 0 ].
	closed ifTrue: [ WebFetchAborted signal: 'WebFetchBodyStream is closed' ].
	^ self waitAndReadInto: aByteArray startingAt: startIndex count: count
]

{ #category : 'accessing' }
WebFetchBodyStream >> response [
	^ response
]

{ #category : 'reading' }
WebFetchBodyStream >> upToEnd [
	"Read all remaining bytes directly into a growing ByteArray."

	| result size initial |
	initial := ((call isClosed ifTrue: [ 0 ] ifFalse: [ call availableBytes ]) max: 16384)
		min: WebFetchCall defaultStreamWindow.
	result := ByteArray new: initial.
	size := 0.
	[
		| n |
		size = result size ifTrue: [
			| grown |
			grown := ByteArray new: result size * 2.
			grown replaceFrom: 1 to: size with: result startingAt: 1.
			result := grown ].
		n := self readInto: result startingAt: size + 1 count: result size - size.
		n = 0 ifTrue: [ ^ result copyFrom: 1 to: size ].
		size := size + n ] repeat
]

{ #category : 'private' }
WebFetchBodyStream >> waitAndReadInto: aByteArray startingAt: startIndex count: count [
	| ready |
	ready := [
		call refreshState >= 3
			or: [ call recordedAvailableBytes > 0
			or: [ call recordedState = 0 ] ] ].
	[
		| s |
		ready value ifFalse: [
			"refused in a callback, the call is not aborted"
			call checkMayWait.
			[ call waitUntil: ready timeout: nil ] ifCurtailed: [ call abort ] ].
		s := call recordedState.
		(s = 4 or: [ s = 0 ]) ifTrue: [ call signalErrorOfEnded ].
		call recordedAvailableBytes > 0 ifTrue: [
			| n |
			n := call readInto: aByteArray startingAt: startIndex count: count.
			n > 0 ifTrue: [ ^ n ] ].
		s = 3 ifTrue: [
			atEnd := true.
			call finishStream.
			^ 0 ] ] repeat
]
