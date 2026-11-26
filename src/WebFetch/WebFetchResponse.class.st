"
I represent an HTTP response returned by `WebFetch`: status code, reason text (may be empty over HTTP/2), final URL, Fetch response type, redirected flag, ordered headers, and optional body bytes.

`contents` decodes textual bodies (text/*, JSON, XML, JavaScript) according to the Content-Type charset (UTF-8 by default, stripping a leading UTF-8 BOM) and falls back to `rawContents` (`ByteArray`) for binary types or undecodable bytes. `mediaType` is the essence of the Content-Type, lowercase and without its parameters (empty without one).
"
Class {
	#name : 'WebFetchResponse',
	#superclass : 'Object',
	#instVars : [
		'status',
		'reason',
		'url',
		'type',
		'isRedirected',
		'headers',
		'rawContents'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'instance creation' }
WebFetchResponse class >> fromHeadBytes: aByteArray [
	"Parse a UTF-8 answer head record (LF-separated lines)"

	| text lines response |
	text := [ aByteArray utf8Decoded ] on: Error do: [ :e | aByteArray asString ].
	lines := self splitOnLF: text.
	response := self new.
	response
		status: (lines size >= 1 ifTrue: [ (lines at: 1) asInteger ifNil: [ 0 ] ] ifFalse: [ 0 ]);
		reason: (lines size >= 2 ifTrue: [ lines at: 2 ] ifFalse: [ '' ]);
		url: (lines size >= 3 ifTrue: [ lines at: 3 ] ifFalse: [ '' ]);
		type: (lines size >= 4 ifTrue: [ lines at: 4 ] ifFalse: [ '' ]);
		isRedirected: (lines size >= 5 and: [ (lines at: 5) = '1' ]).
	6 to: lines size do: [ :i |
		| line colon name value |
		line := lines at: i.
		colon := line indexOf: $:.
		colon > 0 ifTrue: [
			name := line copyFrom: 1 to: colon - 1.
			value := line copyFrom: colon + 1 to: line size.
			(value notEmpty and: [ value first = Character space ]) ifTrue: [
				value := value allButFirst ].
			response addHeader: name value: value ] ].
	^ response
]

{ #category : 'private' }
WebFetchResponse class >> splitOnLF: aString [
	"Split aString strictly on LF (preserving empty lines and CR)"

	| result start lf |
	result := OrderedCollection new.
	lf := Character lf.
	start := 1.
	1 to: aString size do: [ :i |
		(aString at: i) = lf ifTrue: [
			result add: (aString copyFrom: start to: i - 1).
			start := i + 1 ] ].
	result add: (aString copyFrom: start to: aString size).
	^ result
]

{ #category : 'private' }
WebFetchResponse >> addHeader: name value: value [
	headers add: name -> value
]

{ #category : 'private' }
WebFetchResponse >> charsetFromContentType: contentType [
	"Extract optional charset parameter (quoted or unquoted), lowercased, or nil"

	| parts |
	parts := contentType splitOn: $;.
	2 to: parts size do: [ :i |
		| param eq key val |
		param := (parts at: i) trimBoth.
		eq := param indexOf: $=.
		eq > 0 ifTrue: [
			key := (param copyFrom: 1 to: eq - 1) trimBoth asLowercase.
			key = 'charset' ifTrue: [
				val := (param copyFrom: eq + 1 to: param size) trimBoth.
				(val size >= 2 and: [ val first = $" and: [ val last = $" ] ]) ifTrue: [
					val := val copyFrom: 2 to: val size - 1 ].
				val notEmpty ifTrue: [ ^ val asLowercase ] ] ] ].
	^ nil
]

{ #category : 'accessing' }
WebFetchResponse >> contents [
	"Decoded String for textual types, or rawContents ByteArray otherwise or on decode failure"

	| contentType mediaType charset decoded |
	rawContents ifNil: [ ^ nil ].
	contentType := self headerAt: 'Content-Type' ifAbsent: [ '' ].
	mediaType := self mediaTypeFromContentType: contentType.
	(self isTextualMediaType: mediaType) ifFalse: [ ^ rawContents ].
	charset := self charsetFromContentType: contentType.
	decoded := self decodeBytes: rawContents charset: charset.
	decoded ifNil: [ ^ rawContents ].
	^ decoded
]

{ #category : 'private' }
WebFetchResponse >> decodeBytes: bytes charset: charsetOrNil [
	"Decode bytes with charsetOrNil (UTF-8 default); answer nil on decoding error"

	| text isUtf8 |
	isUtf8 := charsetOrNil isNil or: [ charsetOrNil = 'utf-8' or: [ charsetOrNil = 'utf8' ] ].
	text := [
		isUtf8
			ifTrue: [ bytes utf8Decoded ]
			ifFalse: [ (ZnCharacterEncoder newForEncoding: charsetOrNil) decodeBytes: bytes ] ]
		on: Error
		do: [ :e | ^ nil ].
	(isUtf8 and: [ text notEmpty and: [ text first = (Character value: 16rFEFF) ] ]) ifTrue: [
		text := text allButFirst ].
	^ text
]

{ #category : 'accessing' }
WebFetchResponse >> headerAt: aName [
	^ self headerAt: aName ifAbsent: [ nil ]
]

{ #category : 'accessing' }
WebFetchResponse >> headerAt: aName ifAbsent: aBlock [
	"Case-insensitive lookup returning the first matching header value"

	| lower |
	lower := aName asLowercase.
	headers do: [ :assoc |
		assoc key asLowercase = lower ifTrue: [ ^ assoc value ] ].
	^ aBlock value
]

{ #category : 'enumerating' }
WebFetchResponse >> headersDo: aTwoArgBlock [
	"Iterate all headers in wire order, preserving duplicates"

	headers do: [ :assoc | aTwoArgBlock value: assoc key value: assoc value ]
]

{ #category : 'initialization' }
WebFetchResponse >> initialize [
	super initialize.
	status := 0.
	reason := ''.
	url := ''.
	type := ''.
	isRedirected := false.
	headers := OrderedCollection new
]

{ #category : 'testing' }
WebFetchResponse >> isRedirected [
	^ isRedirected
]

{ #category : 'accessing' }
WebFetchResponse >> isRedirected: aBoolean [
	isRedirected := aBoolean
]

{ #category : 'testing' }
WebFetchResponse >> isSuccess [
	^ status between: 200 and: 299
]

{ #category : 'private' }
WebFetchResponse >> isTextualMediaType: mediaType [
	mediaType isEmpty ifTrue: [ ^ false ].
	(mediaType beginsWith: 'text/') ifTrue: [ ^ true ].
	(mediaType = 'application/json' or: [ mediaType endsWith: '+json' ]) ifTrue: [ ^ true ].
	(mediaType = 'application/xml' or: [ mediaType endsWith: '+xml' ]) ifTrue: [ ^ true ].
	(#( 'application/javascript' 'application/x-javascript' 'application/ecmascript' ) includes: mediaType)
		ifTrue: [ ^ true ].
	^ false
]

{ #category : 'accessing' }
WebFetchResponse >> mediaType [
	"Answer the media type of Content-Type in lowercase, without its parameters (`text/event-stream` of `Text/Event-Stream; charset=utf-8`), or '' without one"

	^ self mediaTypeFromContentType: (self headerAt: 'Content-Type' ifAbsent: [ '' ])
]

{ #category : 'private' }
WebFetchResponse >> mediaTypeFromContentType: contentType [
	| semi |
	semi := contentType indexOf: $;.
	^ (semi > 0
		ifTrue: [ contentType copyFrom: 1 to: semi - 1 ]
		ifFalse: [ contentType ]) trimBoth asLowercase
]

{ #category : 'accessing' }
WebFetchResponse >> rawContents [
	^ rawContents
]

{ #category : 'accessing' }
WebFetchResponse >> rawContents: aByteArray [
	rawContents := aByteArray
]

{ #category : 'accessing' }
WebFetchResponse >> reason [
	^ reason
]

{ #category : 'accessing' }
WebFetchResponse >> reason: aString [
	reason := aString
]

{ #category : 'accessing' }
WebFetchResponse >> status [
	^ status
]

{ #category : 'accessing' }
WebFetchResponse >> status: anInteger [
	status := anInteger
]

{ #category : 'accessing' }
WebFetchResponse >> type [
	^ type
]

{ #category : 'accessing' }
WebFetchResponse >> type: aString [
	type := aString
]

{ #category : 'accessing' }
WebFetchResponse >> url [
	^ url
]

{ #category : 'accessing' }
WebFetchResponse >> url: aString [
	url := aString
]
