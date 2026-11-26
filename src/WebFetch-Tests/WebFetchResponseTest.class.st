"
I test `WebFetchResponse` head parsing, header access, and `contents` decoding.
"
Class {
	#name : 'WebFetchResponseTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'tests' }
WebFetchResponseTest >> testContentsBinaryNoTypeEmptyAndUndecodable [
	| r1 r2 r3 r4 badUtf8 |
	r1 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: application/octet-stream') utf8Encoded.
	r1 rawContents: #[ 1 2 3 ].
	self assert: r1 contents equals: #[ 1 2 3 ].
	self assert: (r1 contents isKindOf: ByteArray).

	"No Content-Type answers raw ByteArray"
	r2 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0') utf8Encoded.
	r2 rawContents: 'abc' utf8Encoded.
	self assert: r2 contents equals: 'abc' utf8Encoded.
	self assert: (r2 contents isKindOf: ByteArray).

	"Empty textual body answers empty String"
	r3 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: text/plain') utf8Encoded.
	r3 rawContents: #[ ].
	self assert: r3 contents equals: ''.
	self assert: r3 contents isString.

	badUtf8 := #[ 16rFF 16rFE 16rFD ].
	r4 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: text/plain; charset=utf-8') utf8Encoded.
	r4 rawContents: badUtf8.
	self assert: r4 contents equals: badUtf8.
	self assert: (r4 contents isKindOf: ByteArray)
]

{ #category : 'tests' }
WebFetchResponseTest >> testContentsCharsetAccentsAndBom [
	| r1 r2 r3 bomBytes |
	bomBytes := #[ 16rEF 16rBB 16rBF ] , 'hello' utf8Encoded.
	r1 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: TEXT/PLAIN; charset="UTF-8"') utf8Encoded.
	r1 rawContents: bomBytes.
	self assert: r1 contents equals: 'hello'.

	r2 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: text/plain; charset=iso-8859-1') utf8Encoded.
	r2 rawContents: #[ 99 97 102 233 ].
	self assert: r2 contents equals: 'café'.

	r3 := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: text/plain') utf8Encoded.
	r3 rawContents: 'café' utf8Encoded.
	self assert: r3 contents equals: 'café'
]

{ #category : 'tests' }
WebFetchResponseTest >> testContentsTextualMediaTypes [
	#(
		'text/plain'
		'text/html; charset=utf-8'
		'application/json'
		'application/problem+json'
		'application/xml'
		'application/atom+xml'
		'application/javascript'
		'application/x-javascript'
		'application/ecmascript'
	) do: [ :ct |
		| resp |
		resp := WebFetchResponse fromHeadBytes: ('200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0' , String lf , 'Content-Type: ' , ct) utf8Encoded.
		resp rawContents: 'abc' utf8Encoded.
		self assert: resp contents equals: 'abc' ]
]

{ #category : 'tests' }
WebFetchResponseTest >> testParseHeadEdgeCasesAndHeaders [
	| raw resp seen |
	raw := String streamContents: [ :out |
		out
			nextPutAll: '200'; lf;
			nextPutAll: ''; lf;
			nextPutAll: 'https://example.test/final'; lf;
			nextPutAll: 'cors'; lf;
			nextPutAll: '1'; lf;
			nextPutAll: 'X-Dup: first'; lf;
			nextPutAll: 'X-Empty: '; lf;
			nextPutAll: 'X-Colon: a: b: c'; lf;
			nextPutAll: 'x-dup: second' ].
	resp := WebFetchResponse fromHeadBytes: raw utf8Encoded.
	self assert: resp status equals: 200.
	self assert: resp reason equals: ''.
	self assert: resp url equals: 'https://example.test/final'.
	self assert: resp type equals: 'cors'.
	self assert: resp isRedirected.
	self assert: resp isSuccess.
	self assert: (resp headerAt: 'x-dup' ifAbsent: [ nil ]) equals: 'first'.
	self assert: (resp headerAt: 'X-Empty' ifAbsent: [ nil ]) equals: ''.
	self assert: (resp headerAt: 'X-Colon' ifAbsent: [ nil ]) equals: 'a: b: c'.
	self assert: (resp headerAt: 'Missing' ifAbsent: [ #none ]) equals: #none.
	seen := OrderedCollection new.
	resp headersDo: [ :k :v | seen add: k -> v ].
	self
		assert: seen asArray
		equals: { 'X-Dup' -> 'first'. 'X-Empty' -> ''. 'X-Colon' -> 'a: b: c'. 'x-dup' -> 'second' }
]

{ #category : 'tests' }
WebFetchResponseTest >> testMediaTypeAndBadResponse [
	| head error |
	head := '200' , String lf , 'OK' , String lf , 'http://x' , String lf , 'basic' , String lf , '0'.
	self assert: (WebFetchResponse fromHeadBytes: head utf8Encoded) mediaType equals: ''.
	self
		assert: (WebFetchResponse fromHeadBytes: (head , String lf , 'Content-Type:  Text/Event-Stream ; charset=UTF-8') utf8Encoded) mediaType
		equals: 'text/event-stream'.
	self
		assert: (WebFetchResponse fromHeadBytes: (head , String lf , 'content-type: TEXT/PLAIN') utf8Encoded) mediaType
		equals: 'text/plain'.
	error := WebFetchError kind: #response message: 'status 500'.
	self assert: error class equals: WebFetchBadResponse.
	self assert: error kind equals: #response.
	self assert: error response isNil.
	self assert: WebFetchBadResponse new kind equals: #response.
	error response: (WebFetchResponse fromHeadBytes: head utf8Encoded).
	self assert: error copy response status equals: 200
]
