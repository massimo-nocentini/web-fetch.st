"
I am signalled when a call is aborted or closed before completing.
"
Class {
	#name : 'WebFetchAborted',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchAborted class >> defaultKind [
	^ #aborted
]
