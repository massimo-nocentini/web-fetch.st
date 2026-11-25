"
I am signalled when `WebFetchPlugin` or the host `fetch` API is not available.
"
Class {
	#name : 'WebFetchUnavailable',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchUnavailable class >> defaultKind [
	^ #unavailable
]
