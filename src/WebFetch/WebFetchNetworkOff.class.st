"
I am signalled when network access is disabled in the host settings (`availability` is 2) or turned off while a request is in progress.
"
Class {
	#name : 'WebFetchNetworkOff',
	#superclass : 'WebFetchUnavailable',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchNetworkOff class >> defaultKind [
	^ #off
]
