"
I test `WebFetchRequest` defaults, reusability, encoding and input validation.
"
Class {
	#name : 'WebFetchRequestTest',
	#superclass : 'WebFetchTestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'tests' }
WebFetchRequestTest >> testBodyTypesAndDefaultContentType [
	| req |
	host enqueueStatus: 200 headers: #() body: 'ok'.
	req := (WebFetch request: 'http://example.test/p')
		method: #POST;
		body: 'hello';
		yourself.
	req fetch.
	self assert: (host lastRequest at: #body) equals: 'hello' utf8Encoded.
	self
		assert: ((host lastRequest at: #headers) anySatisfy: [ :a |
			a key asLowercase = 'content-type' and: [ a value = 'text/plain;charset=UTF-8' ] ]).
	self assert: req headers isEmpty.

	"ByteArray body gets no automatic Content-Type"
	host enqueueStatus: 200 headers: #() body: 'ok'.
	(WebFetch request: 'http://example.test/b')
		method: #POST;
		body: #[ 1 2 3 ];
		fetch.
	self assert: (host lastRequest at: #body) equals: #[ 1 2 3 ].
	self deny: ((host lastRequest at: #headers) anySatisfy: [ :a | a key asLowercase = 'content-type' ]).

	"Explicit Content-Type is kept"
	host enqueueStatus: 200 headers: #() body: 'ok'.
	WebFetch post: 'http://example.test/j' body: '{"a":1}' type: 'application/json'.
	self assert: (host lastRequest at: #method) equals: 'POST'.
	self assert: (host lastRequest at: #timeout) equals: 60000.
	self
		assert: ((host lastRequest at: #headers) detect: [ :a | a key asLowercase = 'content-type' ]) value
		equals: 'application/json'
]

{ #category : 'tests' }
WebFetchRequestTest >> testDefaultsForFetchStartAndStream [
	| call |
	host enqueueStatus: 200 headers: #() body: 'a'.
	WebFetch get: 'http://example.test/1'.
	self assert: (host lastRequest at: #method) equals: 'GET'.
	self assert: (host lastRequest at: #timeout) equals: 60000.
	self assert: (host lastRequest at: #window) equals: 67108865.
	self assert: (host lastRequest at: #flags) equals: 0.

	host enqueueStatus: 200 headers: #() body: 'b'.
	call := (WebFetch request: 'http://example.test/2') start.
	call response.
	self assert: (host lastRequest at: #timeout) equals: 0.
	self assert: (host lastRequest at: #window) equals: 67108865.

	host enqueueStatus: 200 headers: #() body: 'c'.
	(WebFetch request: 'http://example.test/3') stream: [ :s | s upToEnd ].
	self assert: (host lastRequest at: #timeout) equals: 0.
	self assert: (host lastRequest at: #window) equals: 1048576
]

{ #category : 'tests' }
WebFetchRequestTest >> testDontFollowRedirectsAndHeaderOrder [
	| req |
	host enqueueStatus: 200 headers: #() body: ''.
	req := (WebFetch request: 'http://example.test/r')
		method: 'put';
		headerAt: 'X-First' put: '1';
		headerAt: 'X-Second' put: '2';
		headerAt: 'x-first' put: '1b';
		dontFollowRedirects;
		yourself.
	req fetch.
	self assert: (host lastRequest at: #method) equals: 'PUT'.
	self assert: (host lastRequest at: #flags) equals: 1.
	self assert: (host lastRequest at: #headers) asArray equals: { 'x-first' -> '1b'. 'X-Second' -> '2' }
]

{ #category : 'tests' }
WebFetchRequestTest >> testHostRefusedStartLeavesNoLeaks [
	| before |
	before := self registeredSemaphoreCount.

	host availability: 0.
	self should: [ (WebFetch request: 'http://example.test/u') start ] raise: WebFetchUnavailable.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0.

	host availability: 2.
	self should: [ (WebFetch request: 'http://example.test/o') start ] raise: WebFetchNetworkOff.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0.

	host availability: 1.
	host maxOpen: 0.
	self should: [ (WebFetch request: 'http://example.test/m') start ] raise: WebFetchTooManyOpen.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'tests' }
WebFetchRequestTest >> testMaximumBodySizeValidation [
	| req |
	req := WebFetch request: 'http://example.test/m'.
	req maximumBodySize: 10e6.
	self assert: req maximumBodySize equals: 10000000.
	self assert: req maximumBodySize isInteger.
	req maximumBodySize: 0.
	self assert: req maximumBodySize equals: 0.
	req maximumBodySize: 2147483646.
	self assert: req maximumBodySize equals: 2147483646.
	self should: [ req maximumBodySize: -1 ] raise: WebFetchBadRequest.
	self should: [ req maximumBodySize: 2147483647 ] raise: WebFetchBadRequest.
	self should: [ req maximumBodySize: 1.5 ] raise: WebFetchBadRequest.
	self should: [ req maximumBodySize: Float nan ] raise: WebFetchBadRequest.
	self should: [ req maximumBodySize: '100' ] raise: WebFetchBadRequest
]

{ #category : 'tests' }
WebFetchRequestTest >> testRequestReusableAndZnUrl [
	| req r1 r2 |
	req := (WebFetch request: 'http://example.test/re?q=1' asZnUrl)
		headerAt: 'X-Key' put: 'val';
		yourself.
	host enqueueStatus: 200 headers: #() body: 'first'.
	host enqueueStatus: 200 headers: #() body: 'second'.
	r1 := req fetch.
	r2 := req fetch.
	self assert: r1 rawContents equals: 'first' utf8Encoded.
	self assert: r2 rawContents equals: 'second' utf8Encoded.
	self assert: host requests size equals: 2.
	self assert: (host lastRequest at: #url) equals: 'http://example.test/re?q=1'
]

{ #category : 'tests' }
WebFetchRequestTest >> testTimeoutEdgeValues [
	host enqueueStatus: 200 headers: #() body: ''.
	(WebFetch request: 'http://example.test/t1') timeout: nil; fetch.
	self assert: (host lastRequest at: #timeout) equals: 0.

	host enqueueStatus: 200 headers: #() body: ''.
	(WebFetch request: 'http://example.test/t2') timeout: Duration zero; fetch.
	self assert: (host lastRequest at: #timeout) equals: 0.

	host enqueueStatus: 200 headers: #() body: ''.
	(WebFetch request: 'http://example.test/t3') timeout: (Duration nanoSeconds: 100000); fetch.
	self assert: (host lastRequest at: #timeout) equals: 1.

	host enqueueStatus: 200 headers: #() body: ''.
	(WebFetch request: 'http://example.test/t4') timeout: 3000000 seconds; fetch.
	self assert: (host lastRequest at: #timeout) equals: 2147483647.

	host enqueueStatus: 200 headers: #() body: ''.
	(WebFetch request: 'http://example.test/t5') timeout: 5; fetch.
	self assert: (host lastRequest at: #timeout) equals: 5000.

	self
		should: [ (WebFetch request: 'http://example.test/t6') timeout: -1 seconds; fetch ]
		raise: WebFetchBadRequest
]

{ #category : 'tests' }
WebFetchRequestTest >> testValidationRefusalsRegisterNothing [
	| before nul |
	before := self registeredSemaphoreCount.
	nul := String with: (Character value: 0).
	self should: [ (WebFetch request: nil) start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: '') start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a' , String lf , 'b') start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a' , String cr , 'b') start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a' , nul , 'b') start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') method: ''; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') method: 'GET' , String lf; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') method: 'GET' , String cr; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') method: 'GET' , nul; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: '' put: 'v'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'A:B' put: 'v'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'A B' put: 'v'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'A' , String lf put: 'v'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'A' , nul put: 'v'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'X' put: 'a' , String cr , 'b'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'X' put: 'a' , String lf , 'b'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'X' put: 'a' , nul , 'b'; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') body: 42; start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') body: (ByteArray new: 67108865); start ] raise: WebFetchBadRequest.
	self should: [ (WebFetch request: 'http://a') headerAt: 'X-Big' put: (String new: 1048577 withAll: $a); start ] raise: WebFetchBadRequest.
	self assert: host requests isEmpty.
	self assert: self registeredSemaphoreCount equals: before.
	self assert: WebFetchCall openCount equals: 0
]
