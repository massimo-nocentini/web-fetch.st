"
I am the class-side facade of WebFetch.

Examples:
- `WebFetch isAvailable`
- `(WebFetch get: 'https://example.org/') contents`
- `WebFetch post: url body: '{}' type: 'application/json'`
- `(WebFetch request: url) headerAt: 'Accept' put: 'application/json'; fetch`
- `WebFetch abortAll`

In the UI process, `get:` and `post:body:type:` freeze the world until they finish or time out (default 60 seconds). Tools should use `(WebFetch request: url) start` with `whenDone:ifError:` and `UIManager default defer:`.
"
Class {
	#name : 'WebFetch',
	#superclass : 'Object',
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'control' }
WebFetch class >> abortAll [
	"Abort all in-progress WebFetch calls"

	WebFetchCall abortAll
]

{ #category : 'accessing' }
WebFetch class >> availability [
	"Answer #unavailable, #ready or #off"

	| code |
	code := WebFetchHost default availability.
	code = 1 ifTrue: [ ^ #ready ].
	code = 2 ifTrue: [ ^ #off ].
	^ #unavailable
]

{ #category : 'requests' }
WebFetch class >> get: aUrlOrString [
	"Perform a GET request and wait for its WebFetchResponse"

	^ (self request: aUrlOrString) fetch
]

{ #category : 'testing' }
WebFetch class >> isAvailable [
	^ self availability == #ready
]

{ #category : 'requests' }
WebFetch class >> post: aUrlOrString body: aByteArrayOrString type: contentType [
	"Perform a POST request with body and Content-Type and wait for its WebFetchResponse"

	^ (self request: aUrlOrString)
		method: #POST;
		headerAt: 'Content-Type' put: contentType;
		body: aByteArrayOrString;
		fetch
]

{ #category : 'requests' }
WebFetch class >> request: aUrlOrString [
	"Create a configurable WebFetchRequest for aUrlOrString"

	^ WebFetchRequest url: aUrlOrString
]
