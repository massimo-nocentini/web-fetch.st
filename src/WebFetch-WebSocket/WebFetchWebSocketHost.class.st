"
I am the bridge to the `WebSocketPlugin` of the VM (and to `primitiveMayWait` of the `WebHostPlugin`): one method per primitive, and one failure method per primitive, since a code means different things for different primitives.

| Primitive | Code | Becomes |
|---|---|---|
| Open | `unsupported operation` | `WebFetchNetworkOff` when the availability is 2, else `WebFetchUnavailable` |
| Open | `resource limit exceeded` | `WebFetchTooManyOpen` (limit 32, closing sockets count) |
| Open | `bad argument` | `WebFetchBadRequest` |
| Open, Send | `insufficient C memory` | `OutOfMemory` |
| State, Info, Receive, Drop, Buffered, Send, Close | `not found` | `WebFetchSessionEnded`, which the socket turns into its recorded end when it was released |
| Info, Receive | `insufficient object memory` | answered: `#noMemory` |
| Send | `resource limit exceeded` | answered: `#full` (the send buffer is full: wait for the write semaphore) |
| Send | `inappropriate operation` | answered: `#notOpen` (the socket looks at its state again) |
| Send | `bad argument` | `WebFetchBadRequest` (not UTF-8 text, or more than 64 MiB) |
| Close | `bad argument` | `WebFetchBadRequest` (a code that is not 1000 nor in 3000..4999, a reason of more than 123 bytes or not UTF-8) |
| any | the primitive is missing | `WebFetchUnavailable` |

Off WebAssembly, or on a VM without the plugin, `availability` answers 0 and `mayWait` true. The tests replace `WebFetchWebSocketHost default` with a fake host.
"
Class {
	#name : 'WebFetchWebSocketHost',
	#superclass : 'Object',
	#classVars : [
		'Default'
	],
	#category : 'WebFetch-WebSocket-Core',
	#package : 'WebFetch-WebSocket',
	#tag : 'Core'
}

{ #category : 'accessing' }
WebFetchWebSocketHost class >> default [
	"The host that the sockets use"

	^ Default ifNil: [ Default := self new ]
]

{ #category : 'accessing' }
WebFetchWebSocketHost class >> default: aHost [
	"Replace the host (nil restores the primitives)"

	Default := aHost
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> availability [
	"0 no WebSocket here, 1 ready, 2 the network is off"

	<primitive: 'primitiveWebSocketAvailability' module: 'WebSocketPlugin' error: ec>
	^ 0
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> bufferedOf: id [
	"Answer the bufferedAmount of the socket"

	<primitive: 'primitiveWebSocketBuffered' module: 'WebSocketPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveWebSocketBuffered'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> close: id code: code reason: reasonBytesOrNil [
	"Start the closing handshake; answer true when it started it, false when the socket was closing or over"

	<primitive: 'primitiveWebSocketClose' module: 'WebSocketPlugin' error: ec>
	^ self closeFailed: ec
]

{ #category : 'failures' }
WebFetchWebSocketHost >> closeFailed: errorCode [
	errorCode == #'bad argument' ifTrue: [
		WebFetchBadRequest signal: 'A close code of 1000 or 3000..4999, a reason of at most 123 bytes of UTF-8' ].
	^ self queryFailed: errorCode operation: 'primitiveWebSocketClose'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> drop: id [
	"Drop the next message without copying it (the socket then fails with tooLarge unless it is over); answer its size, or nil when none is queued"

	<primitive: 'primitiveWebSocketDrop' module: 'WebSocketPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveWebSocketDrop'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> infoOf: id [
	"Answer the info record (a ByteArray), nil in state 1, or #noMemory"

	<primitive: 'primitiveWebSocketInfo' module: 'WebSocketPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveWebSocketInfo'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> mayWait [
	"True when outside an FFI callback (or off WebAssembly)"

	<primitive: 'primitiveMayWait' module: 'WebHostPlugin' error: ec>
	^ true
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> openState: stateIndex read: readIndex write: writeIndex record: recordBytes maxMessage: maxMessage maxQueued: maxQueued timeout: timeoutMs [
	"Open a socket with the three external semaphore indexes and the open record (the URL, then one subprotocol per line); answer its id"

	<primitive: 'primitiveWebSocketOpen' module: 'WebSocketPlugin' error: ec>
	^ self openFailed: ec
]

{ #category : 'failures' }
WebFetchWebSocketHost >> openFailed: errorCode [
	errorCode == #'unsupported operation' ifTrue: [
		self availability = 2
			ifTrue: [ WebFetchNetworkOff signal: 'Network access is off in host settings' ]
			ifFalse: [ WebFetchUnavailable signal: 'The host has no WebSocket' ] ].
	errorCode == #'resource limit exceeded' ifTrue: [
		WebFetchTooManyOpen signal: 'Too many open WebSockets (limit 32, closing sockets count)' ].
	errorCode == #'bad argument' ifTrue: [
		WebFetchBadRequest signal: 'Invalid WebSocket open argument' ].
	errorCode == #'insufficient C memory' ifTrue: [
		OutOfMemory signal: 'Insufficient memory for the WebSocket open record' ].
	WebFetchUnavailable signal: 'WebSocketPlugin is not available'
]

{ #category : 'failures' }
WebFetchWebSocketHost >> queryFailed: errorCode operation: opName [
	errorCode == #'not found' ifTrue: [
		WebFetchSessionEnded signal: opName , ': no such socket in the host' ].
	errorCode == #'insufficient object memory' ifTrue: [ ^ #noMemory ].
	errorCode ifNil: [ WebFetchUnavailable signal: 'WebSocketPlugin is not available' ].
	PrimitiveFailed signal: opName , ' failed: ' , errorCode asString
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> receive: id [
	"Answer the next message as {isText. bytes}, which leaves the queue; nil when none is queued, or #noMemory (the message stays queued)"

	<primitive: 'primitiveWebSocketReceive' module: 'WebSocketPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveWebSocketReceive'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> release: id [
	"Forget the socket at once (its semaphores are not signalled any more); answer whether it was known"

	<primitive: 'primitiveWebSocketRelease' module: 'WebSocketPlugin' error: ec>
	^ false
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> send: id bytes: aByteArray isText: aBoolean [
	"Send one message; answer bufferedAmount after it, #full when the send buffer is full (nothing was sent), or #notOpen"

	<primitive: 'primitiveWebSocketSend' module: 'WebSocketPlugin' error: ec>
	^ self sendFailed: ec
]

{ #category : 'failures' }
WebFetchWebSocketHost >> sendFailed: errorCode [
	errorCode == #'resource limit exceeded' ifTrue: [ ^ #full ].
	errorCode == #'inappropriate operation' ifTrue: [ ^ #notOpen ].
	errorCode == #'bad argument' ifTrue: [
		WebFetchBadRequest signal: 'A WebSocket message of not UTF-8 text, or of more than 64 MiB' ].
	errorCode == #'insufficient C memory' ifTrue: [
		OutOfMemory signal: 'Insufficient memory to copy the WebSocket message' ].
	^ self queryFailed: errorCode operation: 'primitiveWebSocketSend'
]

{ #category : 'primitives' }
WebFetchWebSocketHost >> stateOf: id [
	"Answer the state + 8 * the number of messages queued"

	<primitive: 'primitiveWebSocketState' module: 'WebSocketPlugin' error: ec>
	^ self queryFailed: ec operation: 'primitiveWebSocketState'
]
