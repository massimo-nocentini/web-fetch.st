"
I am signalled when a whole-body response exceeds the request's `maximumBodySize`.
"
Class {
	#name : 'WebFetchTooLarge',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchTooLarge class >> defaultKind [
	^ #tooLarge
]
