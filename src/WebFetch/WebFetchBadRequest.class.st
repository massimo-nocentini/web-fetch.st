"
I am signalled when a request is rejected by validation (bad URL, scheme, method, headers, body, timeout or size limit) or when a manual-redirect fetch meets an opaque redirect.
"
Class {
	#name : 'WebFetchBadRequest',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchBadRequest class >> defaultKind [
	^ #request
]
