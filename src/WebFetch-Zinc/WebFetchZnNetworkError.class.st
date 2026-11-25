"
I am what Zinc sees when the network fails or is off below `WebFetch`: a `NetworkError`, which `ZnClient` may retry. My `cause` is the `WebFetchError`.
"
Class {
	#name : 'WebFetchZnNetworkError',
	#superclass : 'NetworkError',
	#instVars : [
		'cause'
	],
	#category : 'WebFetch-Zinc',
	#package : 'WebFetch-Zinc'
}

{ #category : 'instance creation' }
WebFetchZnNetworkError class >> cause: aWebFetchError [
	^ self new
		cause: aWebFetchError;
		messageText: aWebFetchError messageText;
		yourself
]

{ #category : 'accessing' }
WebFetchZnNetworkError >> cause [
	^ cause
]

{ #category : 'accessing' }
WebFetchZnNetworkError >> cause: aWebFetchError [
	cause := aWebFetchError
]
