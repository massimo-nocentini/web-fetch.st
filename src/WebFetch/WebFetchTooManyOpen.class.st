"
I am signalled when starting a request would exceed the host's limit of 64 concurrent open requests.
"
Class {
	#name : 'WebFetchTooManyOpen',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchTooManyOpen class >> defaultKind [
	^ #tooManyOpen
]
