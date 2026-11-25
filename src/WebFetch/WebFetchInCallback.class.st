"
I am signalled when code attempts to wait on a WebFetch call while inside an FFI callback (`WebFetchHost >> mayWait` is false).
"
Class {
	#name : 'WebFetchInCallback',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchInCallback class >> defaultKind [
	^ #inCallback
]
