"
I am signalled when an in-progress call survives into a new Smalltalk session or its handle is no longer present in the host.
"
Class {
	#name : 'WebFetchSessionEnded',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchSessionEnded class >> defaultKind [
	^ #sessionEnded
]
