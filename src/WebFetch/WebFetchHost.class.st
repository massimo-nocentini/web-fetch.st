"
I am the low-level host bridge to `WebFetchPlugin` and `WebHostPlugin`. Each primitive has one method on me; failed primitives signal the matching `WebFetchError` (or `OutOfMemory` / `PrimitiveFailed`) rather than returning an ambiguous error symbol.

Off WebAssembly, `availability` answers `0` and `mayWait` answers `true`. Tests replace `WebFetchHost default` with `WebFetchTestHost`.
"
Class {
	#name : 'WebFetchHost',
	#superclass : 'Object',
	#classVars : [
		'Default'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'accessing' }
WebFetchHost class >> default [
	"The active host used by WebFetch"

	^ Default ifNil: [ Default := self new ]
]

{ #category : 'accessing' }
WebFetchHost class >> default: aHost [
	"Replace the active host (nil restores the default primitive host)"

	Default := aHost
]

{ #category : 'primitives' }
WebFetchHost >> availability [
	"0 unavailable, 1 ready, 2 network off"

	<primitive: 'primitiveFetchAvailability' module: 'WebFetchPlugin' error: ec>
	^ 0
]

{ #category : 'primitives' }
WebFetchHost >> close: handle [
	"Close handle in the host; answer true if it was open, else false"

	<primitive: 'primitiveFetchClose' module: 'WebFetchPlugin' error: ec>
	^ false
]

{ #category : 'primitives' }
WebFetchHost >> headOf: handle [
	"Answer the UTF-8 ByteArray head or error record, or nil in state 1"

	<primitive: 'primitiveFetchHead' module: 'WebFetchPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveFetchHead'
]

{ #category : 'primitives' }
WebFetchHost >> mayWait [
	"True when outside an FFI callback (or off WebAssembly)"

	<primitive: 'primitiveMayWait' module: 'WebHostPlugin' error: ec>
	^ true
]

{ #category : 'private' }
WebFetchHost >> queryFailed: errorCode operation: opName [
	errorCode == #'not found' ifTrue: [
		WebFetchSessionEnded signal: opName , ': handle not found in host' ].
	(errorCode == #'insufficient object memory' or: [ errorCode == #'insufficient C memory' ]) ifTrue: [
		OutOfMemory signal: opName , ': ' , errorCode asString ].
	PrimitiveFailed signal: opName , ' failed: ' , errorCode asString
]

{ #category : 'primitives' }
WebFetchHost >> read: handle into: aByteArray startingAt: startIndex count: count [
	"Copy up to count ready bytes into aByteArray at 1-based startIndex; answer bytes copied"

	<primitive: 'primitiveFetchRead' module: 'WebFetchPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveFetchRead'
]

{ #category : 'private' }
WebFetchHost >> startFailed: errorCode [
	errorCode == #'unsupported operation' ifTrue: [
		self availability = 2
			ifTrue: [ WebFetchNetworkOff signal: 'Network access is off in host settings' ]
			ifFalse: [ WebFetchUnavailable signal: 'WebFetch is not available' ] ].
	errorCode == #'resource limit exceeded' ifTrue: [
		WebFetchTooManyOpen signal: 'Too many open WebFetch requests (limit 64)' ].
	errorCode == #'bad argument' ifTrue: [
		WebFetchBadRequest signal: 'Invalid WebFetch request argument' ].
	(errorCode == #'insufficient C memory' or: [ errorCode == #'insufficient object memory' ]) ifTrue: [
		OutOfMemory signal: 'Insufficient memory for WebFetch start: ' , errorCode asString ].
	WebFetchUnavailable signal: 'WebFetchPlugin is not available'
]

{ #category : 'primitives' }
WebFetchHost >> startSemaphore: semIndex head: headBytes body: bodyBytesOrNil window: windowBytes timeout: timeoutMs flags: flags [
	"Start a host fetch and answer its positive SmallInteger handle"

	<primitive: 'primitiveFetchStart' module: 'WebFetchPlugin' error: ec>
	^ self startFailed: ec
]

{ #category : 'primitives' }
WebFetchHost >> stateOf: handle [
	"Answer state + 8 * readyBytes"

	<primitive: 'primitiveFetchState' module: 'WebFetchPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveFetchState'
]
