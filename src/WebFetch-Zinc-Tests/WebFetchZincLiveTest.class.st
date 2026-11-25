"
I test Zinc over the adapter against the local server of `WebFetchLiveTest` (`tests/wasm/lib/fetch-http.mjs`), when `WebFetch` is available and the server is known.
"
Class {
	#name : 'WebFetchZincLiveTest',
	#superclass : 'TestCase',
	#instVars : [
		'previousUtils'
	],
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'accessing' }
WebFetchZincLiveTest class >> defaultTimeLimit [
	^ 60 seconds
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> baseUrl [
	WebFetch isAvailable ifFalse: [ ^ self skip: 'WebFetch is not available' ].
	^ WebFetchLiveTest server ifNil: [ self skip: 'WEB_FETCH_SERVER is not set' ]
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> client: aPath [
	^ ZnClient new
		timeout: 10;
		maximumEntitySize: 100000000;
		url: self baseUrl , aPath;
		yourself
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> isClosed: aTag [
	"Answer whether the server saw the client go before the end of the answer"

	^ self requests anySatisfy: [ :each | ((each at: 'url') includesSubstring: aTag) and: [ each at: 'closed' ] ]
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> requests [
	"Answer those that the server saw"

	^ (STONJSON fromString: (WebFetch get: self baseUrl , '/_stats') contents) at: 'requests'
]

{ #category : 'running' }
WebFetchZincLiveTest >> setUp [
	super setUp.
	previousUtils := ZnNetworkingUtils default.
	WebFetchZinc install
]

{ #category : 'running' }
WebFetchZincLiveTest >> tearDown [
	previousUtils ifNotNil: [ ZnNetworkingUtils default: previousUtils ].
	super tearDown.
	self assert: WebFetchCall openCount equals: 0
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> tag [
	^ 'zinc' , Time microsecondClockValue asString
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testBig [
	| client bytes |
	client := self client: '/n?n=20000000'.
	bytes := client get.
	self assert: bytes size equals: 20000000.
	self assert: (bytes at: 12345679) equals: (12345678 bitAnd: 255).
	self should: [ (self client: '/n?n=20000000') maximumEntitySize: 1000; get ] raise: ZnEntityTooLarge.
	WebFetch abortAll
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testBodies [
	| client |
	client := self client: '/echo'.
	client entity: (ZnEntity json: '{"a":1}'); post.
	self assert: (client contents beginsWith: 'POST|/echo|application/json||').
	self assert: (client contents endsWith: '|7|{"a":1}').
	client := self client: '/echo'.
	client
		entity: (ZnStreamingEntity
			readFrom: (ByteArray new: 1000000 withAll: 65) readStream
			usingType: ZnMimeType applicationOctetStream
			andLength: 1000000);
		put.
	self assert: (client contents includesSubstring: '|1000000|AAAA').
	self assert: (((self client: '/echo') formAt: 'a' put: 'b c'; post) endsWith: 'a=b%20c').
	self assert: (((self client: '/echo') queryAt: 'q' put: 'x y'; get) beginsWith: 'GET|/echo?q=x%20y|').
	self assert: (((self client: '/echo') delete; contents) beginsWith: 'DELETE|').
	self assert: (((self client: '/echo') entity: (ZnEntity text: 'x'); patch; contents) beginsWith: 'PATCH|').
	self assert: (((self client: '/echo') username: 'u' password: 'p'; get) includesSubstring: '|Basic dTpw|')
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testClose [
	| client stream tag |
	tag := self tag.
	client := self client: '/endless?' , tag.
	stream := client streaming: true; get.
	self assert: (stream next: 10) size equals: 10.
	client close.
	self waitUntilClosed: tag.
	client streaming: false.
	self assert: (client get: self baseUrl , '/hello') equals: 'hello'
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testDownload [
	| file |
	file := FileLocator temp / self tag.
	[
		(self client: '/n?n=5000000') downloadTo: file.
		self assert: file size equals: 5000000 ] ensure: [ file ensureDelete ]
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testErrors [
	self should: [ (self client: '/trunc') get ] raise: WebFetchZnNetworkError.
	self should: [ ZnClient new get: 'http://127.0.0.1:2/' ] raise: WebFetchZnNetworkError.
	self should: [ (self client: '/x') enforceHttpSuccess: true; get ] raise: ZnHttpUnsuccessful.
	self assert: (self client: '/x') get equals: 'none'.
	self assert: ((self client: '/hello') get; get) equals: 'hello'
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testGet [
	| client |
	client := self client: '/hello'.
	self assert: client get equals: 'hello'.
	self assert: (client response headers at: 'X-A') equals: 'caf' , (Character value: 233) asString.
	self deny: client isConnected.
	self assert: (ZnEasy get: self baseUrl , '/hello') contents equals: 'hello'.
	self assert: (self baseUrl , '/hello') asZnUrl retrieveContents equals: 'hello'.
	self assert: ((self client: '/hello') beOneShot; get) equals: 'hello'.
	self assert: ((self client: '/gzip') get) size equals: 20000
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testManyClients [
	| base done sizes |
	base := self baseUrl.
	done := Semaphore new.
	sizes := OrderedCollection new.
	1 to: 20 do: [ :i |
		[ [ sizes add: (ZnClient new timeout: 10; get: base , '/n?n=' , (i * 1000) asString) size ] ensure: [ done signal ] ] fork ].
	20 timesRepeat: [ done waitTimeoutSeconds: 20 ].
	self assert: sizes asSortedCollection asArray equals: ((1 to: 20) collect: [ :i | i * 1000 ]) asArray
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testNoBody [
	| client |
	client := self client: '/hello'.
	client head.
	self assert: client response contentLength equals: 5.
	#( 204 205 304 ) do: [ :status |
		client := self client: '/status?code=' , status asString.
		client get.
		self assert: client response code equals: status ].
	client := self client: '/204'.
	client get.
	self assert: client response isNoContent
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testRedirect [
	| client |
	client := self client: '/redir'.
	self assert: client get equals: 'hello'.
	self assert: (client response headers at: 'X-Webfetch-Url') equals: self baseUrl , '/hello'.
	client := self client: '/redir'.
	client dontFollowRedirects.
	WebFetchLiveTest isBrowser
		ifTrue: [ self should: [ client get ] raise: WebFetchBadRequest ]
		ifFalse: [
			client get.
			self assert: client response code equals: 302.
			self assert: client response location asString equals: '/hello' ]
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testRetry [
	"/flaky closes the connection while it was asked at most fail times"

	| asked |
	asked := (self requests select: [ :each | (each at: 'path') = '/flaky' ]) size.
	self
		assert: ((self client: '/flaky?fail=' , (asked + 2) asString) numberOfRetries: 2; retryDelay: 0; get)
		equals: 'flaky ok'
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testStreaming [
	| client stream buffer count |
	client := self client: '/dribble'.
	self assert: (client streaming: true; get) upToEnd asString equals: 'tick0tick1tick2tick3tick4'.
	self deny: client isConnected.
	client := self client: '/n?n=20000000'.
	stream := client streaming: true; get.
	buffer := ByteArray new: 65536.
	count := 0.
	[ stream atEnd ] whileFalse: [
		count := count + (stream readInto: buffer startingAt: 1 count: 65536) ].
	self assert: count equals: 20000000
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testTerminate [
	| client process tag |
	tag := self tag.
	client := self client: '/hang?' , tag.
	process := [ client timeout: 60; get ] fork.
	(Delay forMilliseconds: 300) wait.
	process terminate.
	self waitUntilClosed: tag
]

{ #category : 'tests' }
WebFetchZincLiveTest >> testTimeout [
	| tag |
	tag := self tag.
	self should: [ (self client: '/hang?' , tag) timeout: 1; get ] raise: ConnectionTimedOut.
	self waitUntilClosed: tag
]

{ #category : 'helpers' }
WebFetchZincLiveTest >> waitUntilClosed: aTag [
	100 timesRepeat: [
		(self isClosed: aTag) ifTrue: [ ^ self ].
		(Delay forMilliseconds: 30) wait ].
	self fail: 'The server did not see the close'
]
