"
I am signalled when a whole-body response exceeds the request's `maximumBodySize`, and by `WebFetchEventParser` when the data of an event exceeds its `maximumEventSize` or an `id` or `event` value its `maximumFieldSize`.
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
