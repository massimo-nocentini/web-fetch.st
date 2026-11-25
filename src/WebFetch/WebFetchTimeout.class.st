"
I am signalled when a request does not finish within its timeout.
"
Class {
	#name : 'WebFetchTimeout',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchTimeout class >> defaultKind [
	^ #timeout
]
