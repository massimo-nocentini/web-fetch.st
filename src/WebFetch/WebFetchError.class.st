"
I am the root exception of WebFetch. My `kind` is a Symbol naming the wire or local failure kind (`#request`, `#network`, `#timeout`, `#aborted`, `#off`, `#redirect`, `#body`, `#unavailable`, `#tooLarge`, `#tooManyOpen`, `#inCallback`, `#sessionEnded`).
"
Class {
	#name : 'WebFetchError',
	#superclass : 'Error',
	#instVars : [
		'kind'
	],
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'instance creation' }
WebFetchError class >> classForKind: aSymbol [
	"Answer the error class for a wire or local kind symbol"

	aSymbol == #request ifTrue: [ ^ WebFetchBadRequest ].
	aSymbol == #redirect ifTrue: [ ^ WebFetchBadRequest ].
	aSymbol == #network ifTrue: [ ^ WebFetchNetworkError ].
	aSymbol == #body ifTrue: [ ^ WebFetchNetworkError ].
	aSymbol == #timeout ifTrue: [ ^ WebFetchTimeout ].
	aSymbol == #aborted ifTrue: [ ^ WebFetchAborted ].
	aSymbol == #off ifTrue: [ ^ WebFetchNetworkOff ].
	aSymbol == #unavailable ifTrue: [ ^ WebFetchUnavailable ].
	aSymbol == #tooLarge ifTrue: [ ^ WebFetchTooLarge ].
	aSymbol == #tooManyOpen ifTrue: [ ^ WebFetchTooManyOpen ].
	aSymbol == #inCallback ifTrue: [ ^ WebFetchInCallback ].
	aSymbol == #sessionEnded ifTrue: [ ^ WebFetchSessionEnded ].
	^ self
]

{ #category : 'accessing' }
WebFetchError class >> defaultKind [
	^ #error
]

{ #category : 'instance creation' }
WebFetchError class >> kind: aSymbol message: aString [
	"Create an unsignalled error instance of the right subclass for aSymbol"

	| errorClass text |
	errorClass := self classForKind: aSymbol.
	text := errorClass formatMessage: aString forKind: aSymbol.
	^ errorClass new
		kind: aSymbol;
		messageText: text;
		yourself
]

{ #category : 'formatting' }
WebFetchError class >> formatMessage: aString forKind: aSymbol [
	^ aString ifNil: [ '' ]
]

{ #category : 'accessing' }
WebFetchError >> kind [
	^ kind ifNil: [ self class defaultKind ]
]

{ #category : 'accessing' }
WebFetchError >> kind: aSymbol [
	kind := aSymbol
]
