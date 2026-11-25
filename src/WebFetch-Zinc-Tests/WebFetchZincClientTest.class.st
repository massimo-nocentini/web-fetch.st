"
I test `ZnClient` over the adapter, on the `WebFetchTestHost`.
"
Class {
	#name : 'WebFetchZincClientTest',
	#superclass : 'WebFetchZincTestCase',
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'accessing' }
WebFetchZincClientTest class >> defaultTimeLimit [
	"70 MB through a Debug VM took 24 s"

	^ 60 seconds
]

{ #category : 'helpers' }
WebFetchZincClientTest >> bytes: anInteger [
	| bytes |
	bytes := ByteArray new: anInteger.
	1 to: anInteger do: [ :i | bytes at: i put: (i * 7 bitAnd: 255) ].
	^ bytes
]

{ #category : 'helpers' }
WebFetchZincClientTest >> client [
	^ ZnClient new
		timeout: 3;
		url: 'http://host:81/a/b?c=d';
		yourself
]

{ #category : 'helpers' }
WebFetchZincClientTest >> enqueue: bytesOrString [
	host
		enqueueStatus: 200
		reason: 'OK'
		headers: { 'content-type' -> (bytesOrString isString ifTrue: [ 'text/plain' ] ifFalse: [ 'application/octet-stream' ]) }
		body: bytesOrString
]

{ #category : 'tests' }
WebFetchZincClientTest >> testAbortAll [
	"What aborts the call elsewhere is an error here, not the end of the answer"

	| client |
	host enqueuePending.
	client := self client.
	[ self waitUntil: [ host openCount = 1 ].
	WebFetchCall abortAll ] fork.
	self should: [ client get ] raise: WebFetchAborted.
	self deny: client isConnected
]

{ #category : 'tests' }
WebFetchZincClientTest >> testBigBody [
	"More than the window and than the chunks of the adapter"

	| bytes |
	bytes := self bytes: 3000000.
	self enqueue: bytes.
	self assert: self client get equals: bytes.
	self assert: host maxBufferedBytes <= WebFetchCall defaultStreamWindow.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testBigUploadIsRefused [
	| client chunk stream |
	stream := WebFetchSocketStream on: 'http://host/' asZnUrl.
	chunk := ByteArray new: 1048576.
	65 timesRepeat: [ stream nextPutAll: chunk ].
	self should: [ stream nextPutAll: #[ 1 ]; flush ] raise: WebFetchBadRequest.
	self deny: stream isConnected.
	stream close.
	self assert: host requests isEmpty.
	client := self client.
	client entity: (ZnStreamingEntity
		readFrom: (ByteArray new: 70000000) readStream
		usingType: ZnMimeType applicationOctetStream
		andLength: 70000000).
	self should: [ client numberOfRetries: 2; put ] raise: WebFetchBadRequest.
	self assert: host requests isEmpty.
	self deny: client isConnected.
	client close
]

{ #category : 'tests' }
WebFetchZincClientTest >> testBrokenBody [
	| client stream id |
	host enqueuePending.
	client := self client streaming: true; yourself.
	[ self waitUntil: [ host openCount = 1 ].
	id := host lastId.
	host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://host/' type: 'basic' redirected: false headers: {  }.
	host pushBytes: (ByteArray new: 40000) for: id ] fork.
	stream := client get.
	self assert: (stream next: 10) equals: (ByteArray new: 10).
	host fail: id kind: #body message: 'broken'.
	self
		should: [ stream upToEnd ]
		raise: WebFetchZnNetworkError
		whoseDescriptionIncludes: 'broken'
		description: 'the cause'.
	self deny: client isConnected
]

{ #category : 'tests' }
WebFetchZincClientTest >> testBrokenBodyInChunk [
	"The bytes announced by a chunk are gone when the body breaks off"

	| stream id |
	host enqueuePending.
	stream := self requestOf: 'GET /x HTTP/1.1

' withUnixLineEndings.
	self deny: stream isDataAvailable.
	id := host lastId.
	host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://host/' type: 'basic' redirected: false headers: {  }.
	host pushBytes: (ByteArray new: 40000) for: id.
	"the status, one header, the empty line and the size of the chunk"
	4 timesRepeat: [ stream upTo: 10 ].
	self assert: stream next equals: 0.
	host fail: id kind: #body message: 'broken'.
	self should: [ 40000 timesRepeat: [ stream next ] ] raise: WebFetchZnNetworkError.
	self deny: stream isConnected
]

{ #category : 'tests' }
WebFetchZincClientTest >> testBrokenBodyOfKnownSize [
	| client |
	host enqueuePending.
	client := self client.
	[ | id |
	self waitUntil: [ host openCount = 1 ].
	id := host lastId.
	host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://host/' type: 'basic' redirected: false headers: { 'Content-Length' -> '100' }.
	host pushBytes: (ByteArray new: 60) for: id.
	(Delay forMilliseconds: 50) wait.
	host fail: id kind: #body message: 'broken' ] fork.
	self should: [ client get ] raise: WebFetchZnNetworkError
]

{ #category : 'tests' }
WebFetchZincClientTest >> testCloseInTheMiddle [
	| client stream |
	self enqueue: (self bytes: 3000000).
	client := self client streaming: true; yourself.
	stream := client get.
	self assert: (stream next: 3) equals: (self bytes: 3).
	self assert: client isConnected.
	client close.
	self deny: client isConnected.
	self assert: host openCount equals: 0.
	client streaming: false.
	self enqueue: 'again'.
	self assert: client get equals: 'again'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testCloseWhileWaiting [
	| client |
	host enqueuePending.
	client := self client.
	[ self waitUntil: [ host openCount = 1 ].
	client close ] fork.
	self should: [ client get ] raise: WebFetchAborted
]

{ #category : 'tests' }
WebFetchZincClientTest >> testCloseWhileStarting [
	"The call that was being started is not left open"

	| stream |
	host enqueuePending.
	stream := self requestOf: 'GET /x HTTP/1.1

' withUnixLineEndings.
	host onStart: [ stream close ].
	self should: [ stream next ] raise: WebFetchAborted.
	self assert: host requests size equals: 1.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testDontFollowRedirects [
	| client |
	host enqueueStatus: 302 reason: 'Found' headers: { 'Location' -> '/x' } body: ''.
	client := self client dontFollowRedirects; yourself.
	client get.
	self assert: client response code equals: 302.
	self assert: client response location equals: '/x'.
	self assert: (host lastRequest at: #flags) equals: 1.
	self enqueue: 'x'.
	self client get.
	self assert: (host lastRequest at: #flags) equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testErrors [
	{ #network -> WebFetchZnNetworkError. #off -> WebFetchZnNetworkError. #body -> WebFetchZnNetworkError.
	#timeout -> ConnectionTimedOut. #request -> WebFetchBadRequest. #redirect -> WebFetchBadRequest.
	#aborted -> WebFetchAborted } do: [ :each |
		| client |
		host enqueueErrorKind: each key message: 'why'.
		client := self client.
		self should: [ client get ] raise: each value.
		self deny: client isConnected ].
	host availability: 2.
	[ self client get.
	self fail ] on: WebFetchZnNetworkError do: [ :error |
		self assert: error cause class equals: WebFetchNetworkOff ].
	host availability: 1; maxOpen: 0.
	self should: [ self client get ] raise: WebFetchTooManyOpen
]

{ #category : 'tests' }
WebFetchZincClientTest >> testHead [
	| client |
	host enqueueStatus: 200 reason: 'OK' headers: { 'Content-Length' -> '1234'. 'Content-Type' -> 'text/plain' } body: nil.
	client := self client.
	client head.
	self assert: client response code equals: 200.
	self assert: client response contentLength equals: 1234.
	self deny: client isConnected
]

{ #category : 'tests' }
WebFetchZincClientTest >> testHeadersOfAnswer [
	| client |
	host
		enqueueStatus: 200
		reason: ''
		headers: {
			'Content-Encoding' -> 'gzip'. 'Content-Length' -> '3'. 'Connection' -> 'close'.
			'X-B' -> ('caf' , (Character value: 233) asString).
			'X-C' -> (Character value: 8364) asString }
		body: 'not three'.
	client := self client.
	self assert: client get asByteArray equals: 'not three' asByteArray.
	self assert: client response statusLine reason isEmptyOrNil.
	self deny: (client response headers includesKey: 'Content-Encoding').
	self deny: (client response headers includesKey: 'X-WebFetch-Url').
	self assert: (client response headers at: 'X-B') equals: 'caf' , (Character value: 233) asString.
	self assert: (client response headers at: 'X-C') equals: '?'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testHttps [
	self enqueue: 'secure'.
	self assert: (ZnClient new get: 'https://host/x') equals: 'secure'.
	self assert: (host lastRequest at: #url) equals: 'https://host:443/x'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testIfFailAndEnforce [
	host enqueueErrorKind: #network message: 'why'.
	self
		assert: (self client ifFail: [ :error | error class ]; get)
		equals: WebFetchZnNetworkError.
	host enqueueStatus: 404 reason: 'Not Found' headers: {  } body: 'none'.
	self should: [ self client enforceHttpSuccess: true; get ] raise: ZnHttpUnsuccessful
]

{ #category : 'tests' }
WebFetchZincClientTest >> testInCallback [
	| client |
	host enqueuePending.
	host mayWait: false.
	client := self client.
	self should: [ client get ] raise: WebFetchInCallback.
	self deny: client isConnected.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testLongUrl [
	"Zinc writes a request line longer than the ones it reads"

	| url |
	url := 'http://host:81/' , (String new: 6000 withAll: $a).
	self enqueue: 'long'.
	self assert: (ZnClient new get: url) equals: 'long'.
	self assert: (host lastRequest at: #url) equals: url
]

{ #category : 'tests' }
WebFetchZincClientTest >> testManyClients [
	| done results |
	done := Semaphore new.
	results := Array new: 20.
	host onRequest: [ :request |
		| id |
		id := request at: #id.
		host deliverHeadFor: id status: 200 reason: 'OK' url: (request at: #url) type: 'basic' redirected: false headers: {  }.
		(Delay forMilliseconds: 10) wait.
		host pushBytes: ((request at: #url) asByteArray) for: id.
		host finish: id ].
	1 to: 20 do: [ :i |
		[ [ results at: i put: (ZnClient new get: 'http://host:81/' , i asString) asByteArray asString ] ensure: [ done signal ] ] fork ].
	20 timesRepeat: [ done waitTimeoutSeconds: 5 ].
	self
		assert: results
		equals: ((1 to: 20) collect: [ :i | 'http://host:81/' , i asString ]) asArray
]

{ #category : 'tests' }
WebFetchZincClientTest >> testNoBody [
	#( 204 205 304 ) do: [ :status |
		| client |
		host enqueueStatus: status reason: 'None' headers: {  } body: nil.
		client := self client.
		client get.
		self assert: client response code equals: status.
		self assert: client response contents isEmptyOrNil.
		self deny: client isConnected ]
]

{ #category : 'tests' }
WebFetchZincClientTest >> testNoReuse [
	"Each exchange has its connection, and its one request"

	| client |
	client := ZnClient new.
	1 to: 3 do: [ :i |
		self enqueue: i asString.
		self assert: (client get: 'http://host/' , i asString) equals: i asString.
		self deny: client isConnected ].
	self assert: host requests size equals: 3
]

{ #category : 'tests' }
WebFetchZincClientTest >> testPartialRequestIsNotSent [
	#( 'POST /x HTTP/1.1
Transfer-Encoding: chunked

2
ab
' 'POST /x HTTP/1.1
Transfer-Encoding: chunked

10

' 'POST /x HTTP/1.1
Transfer-Encoding: chunked

zz
0

' 'POST /x HTTP/1.1
Transfer-Encoding: chunked

2
ab
0

rest' 'GARBAGE

' 'GET /x

' 'POST /x HTTP/1.1
Content-Length: 5

abc' 'POST /x HTTP/1.1
Content-Length: 2

abc' 'GET /x HTTP/1.1
Host: h
' 'GET /x HTTP/1.1
no header

' ) do: [ :each |
		| stream |
		stream := self requestOf: (each withUnixLineEndings).
		self should: [ stream next ] raise: WebFetchBadRequest.
		self deny: stream isConnected.
		stream close ].
	self assert: host requests isEmpty
]

{ #category : 'tests' }
WebFetchZincClientTest >> testPolling [
	"Asking for data starts a whole request, and leaves a half written one"

	| stream |
	self enqueue: 'x'.
	stream := self requestOf: 'POST /x HTTP/1.1
Content-Length: 3

a' withUnixLineEndings.
	self deny: stream isDataAvailable.
	self deny: stream atEnd.
	self assert: host requests isEmpty.
	stream nextPutAll: #[ 98 99 ]; flush.
	self assert: (self waitUntil: [ stream isDataAvailable ]).
	self assert: (host lastRequest at: #body) equals: 'abc' asByteArray.
	self assert: (stream next: 8) equals: 'HTTP/1.1' asByteArray.
	stream close.
	self deny: stream isDataAvailable.
	self assert: stream atEnd
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRedirect [
	| client |
	host enqueueRedirectTo: 'http://other/z' status: 200 headers: { 'Content-Type' -> 'text/plain' } body: 'there'.
	client := self client.
	self assert: client get equals: 'there'.
	self assert: (client response headers at: 'X-Webfetch-Url') equals: 'http://other/z'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRequest [
	self enqueue: 'x'.
	self client
		headerAt: 'X-B' put: 'b';
		username: 'u' password: 'p';
		get.
	self assert: (host lastRequest at: #method) equals: 'GET'.
	self assert: (host lastRequest at: #url) equals: 'http://host:81/a/b?c=d'.
	self assert: (host lastRequest at: #body) isNil.
	self assert: (host lastRequest at: #timeout) equals: 0.
	self assert: (self headerOf: 'X-B') equals: 'b'.
	self assert: (self headerOf: 'Authorization') equals: 'Basic dTpw'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRequestBodies [
	"The bytes are those that Zinc wrote"

	| multipart |
	self enqueue: 'x'.
	self client entity: (ZnEntity json: '{"a":1}'); post.
	self assert: (host lastRequest at: #method) equals: 'POST'.
	self assert: (host lastRequest at: #body) equals: '{"a":1}' asByteArray.
	self assert: (self headerOf: 'Content-Type') equals: 'application/json'.
	self enqueue: 'x'.
	self client
		entity: (ZnStreamingEntity
			readFrom: (self bytes: 1000000) readStream
			usingType: ZnMimeType applicationOctetStream
			andLength: 1000000);
		put.
	self assert: (host lastRequest at: #body) equals: (self bytes: 1000000).
	self enqueue: 'x'.
	multipart := ZnMultiPartFormDataEntity new
		addPart: (ZnMimePart fieldName: 'f' value: 'v');
		addPart: (ZnMimePart fieldName: 'g' fileName: 'n' entity: (ZnEntity bytes: (self bytes: 300)));
		yourself.
	self client entity: multipart; post.
	self
		assert: (host lastRequest at: #body)
		equals: (ByteArray streamContents: [ :out | multipart writeOn: out ])
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRequestChunked [
	| stream |
	self enqueue: 'x'.
	stream := self requestOf: 'POST /up HTTP/1.1
Transfer-Encoding: chunked

3
abc
2
de
0

' withUnixLineEndings.
	self assert: stream next equals: $H asInteger.
	self assert: (host lastRequest at: #body) equals: 'abcde' asByteArray.
	self assert: (host lastRequest at: #url) equals: 'http://host:8080/up'.
	stream close
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRequestWithControlCharacter [
	"A CR that Zinc lets pass in a header is refused"

	| client |
	client := self client headerAt: 'X-B' put: 'a' , String cr , 'b'; yourself.
	self should: [ client get ] raise: WebFetchBadRequest.
	self assert: host requests isEmpty
]

{ #category : 'tests' }
WebFetchZincClientTest >> testRetry [
	"A network error is retried, a bad request is not"

	host enqueueErrorKind: #network message: 'why'.
	self enqueue: 'second'.
	self assert: (self client numberOfRetries: 1; retryDelay: 0; get) equals: 'second'.
	self assert: host requests size equals: 2.
	host enqueueErrorKind: #request message: 'why'.
	self should: [ self client numberOfRetries: 1; retryDelay: 0; get ] raise: WebFetchBadRequest.
	self assert: host requests size equals: 3
]

{ #category : 'tests' }
WebFetchZincClientTest >> testSessionEnd [
	| client |
	host enqueuePending.
	client := self client timeout: 20; yourself.
	[ self waitUntil: [ host openCount = 1 ].
	(client connection instVarNamed: #call) session: Object new; markSessionEnded.
	host reset ] fork.
	self should: [ client get ] raise: WebFetchSessionEnded.
	self enqueue: 'new session'.
	self assert: client get equals: 'new session'
]

{ #category : 'tests' }
WebFetchZincClientTest >> testStreaming [
	| client stream |
	host enqueueStatus: 200 reason: 'OK' headers: {  } body: (self bytes: 200000).
	client := self client streaming: true; yourself.
	stream := client get.
	self assert: stream upToEnd equals: (self bytes: 200000).
	self assert: stream atEnd.
	self deny: client isConnected.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testStreamingNextRequest [
	"A request while a body is unread takes a new connection, and closes the old one"

	| client stream |
	self enqueue: (self bytes: 3000000).
	client := self client streaming: true; yourself.
	stream := client get.
	stream next: 10.
	client streaming: false.
	self enqueue: 'next'.
	self assert: (client get: 'http://host:81/next') equals: 'next'.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testTerminate [
	| process |
	host enqueuePending.
	process := [ self client timeout: 60; get ] fork.
	self assert: (self waitUntil: [ host openCount = 1 ]).
	(Delay forMilliseconds: 20) wait.
	process terminate.
	self assert: (self waitUntil: [ host openCount = 0 ])
]

{ #category : 'tests' }
WebFetchZincClientTest >> testTimeout [
	| client time |
	host enqueuePending.
	client := self client timeout: 1; yourself.
	time := [ self should: [ client get ] raise: ConnectionTimedOut ] timeToRun.
	self assert: (time asMilliSeconds between: 900 and: 3000).
	self assert: host openCount equals: 0.
	self deny: client isConnected
]

{ #category : 'tests' }
WebFetchZincClientTest >> testTooLargeEntity [
	| client |
	self enqueue: (self bytes: 100000).
	client := self client maximumEntitySize: 1000; yourself.
	self should: [ client get ] raise: ZnEntityTooLarge.
	client close.
	self assert: host openCount equals: 0
]

{ #category : 'tests' }
WebFetchZincClientTest >> testWaitingForTheBody [
	"The timeout counts from the last data, not from the start"

	| client |
	host enqueuePending.
	client := self client timeout: 1; yourself.
	[ | id |
	self waitUntil: [ host openCount = 1 ].
	id := host lastId.
	host deliverHeadFor: id status: 200 reason: 'OK' url: 'http://host/' type: 'basic' redirected: false headers: { 'Content-Type' -> 'text/plain' }.
	4 timesRepeat: [
		(Delay forMilliseconds: 400) wait.
		host pushBytes: 'abc' asByteArray for: id ].
	host finish: id ] fork.
	self assert: client get equals: 'abcabcabcabc'
]
