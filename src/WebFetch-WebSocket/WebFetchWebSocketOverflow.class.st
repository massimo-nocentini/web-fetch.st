"
I am signalled by a `WebFetchWebSocket` that failed because the messages that it received and the image did not read were more than its `maximumQueuedBytes` (or 65536), or because the queues of all the sockets of the VM were full (256 MiB). The messages queued before that stay readable: `next` answers them, then signals me.
"
Class {
	#name : 'WebFetchWebSocketOverflow',
	#superclass : 'WebFetchTooLarge',
	#category : 'WebFetch-WebSocket-Errors',
	#package : 'WebFetch-WebSocket',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchWebSocketOverflow class >> defaultKind [
	^ #overflow
]
