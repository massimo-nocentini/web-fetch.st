"
I am signalled on a transport or body-reading failure (`#network` or `#body`). My message notes that a browser reports no specific cause (CORS, DNS, TLS or network).
"
Class {
	#name : 'WebFetchNetworkError',
	#superclass : 'WebFetchError',
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchNetworkError class >> defaultKind [
	^ #network
]

{ #category : 'formatting' }
WebFetchNetworkError class >> formatMessage: aString forKind: aSymbol [
	| base note |
	base := aString ifNil: [ '' ].
	note := 'a browser reports no cause: CORS, DNS, TLS or network'.
	(base includesSubstring: 'CORS') ifTrue: [ ^ base ].
	base isEmpty ifTrue: [ ^ note ].
	^ base , ' (' , note , ')'
]
