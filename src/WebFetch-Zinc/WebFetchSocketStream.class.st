"
I look like a connection to a server, for Zinc: what is written to me is gathered, the first read makes a `WebFetch` request of it, and the answer comes out as HTTP/1.1 text. I do one exchange; after it I am not connected.

A body comes out in chunks (Transfer-Encoding: chunked), whatever its encoding on the wire was: its length is not known, or is that of the compressed one. Its bytes are read straight into the buffer of the reader. The last chunk comes only when the body is complete, so that a broken one is never taken for a whole one.

- `outgoing`: what was written.
- `call`: the `WebFetchCall`, from the first read on.
- `segment`: text to give before anything else; `chunkLeft`: how many bytes of the body to give after it.
- `isHeadMade`, `isComplete`: whether the head, and all of the answer, went to `segment`.
- `isEnded`: all was given, or it failed, or I was closed.
"
Class {
	#name : 'WebFetchSocketStream',
	#superclass : 'ZdcSocketStream',
	#instVars : [
		'url',
		'followRedirects',
		'method',
		'outgoing',
		'call',
		'segment',
		'chunkLeft',
		'isHeadMade',
		'isComplete',
		'isEnded'
	],
	#category : 'WebFetch-Zinc',
	#package : 'WebFetch-Zinc'
}

{ #category : 'private - request' }
WebFetchSocketStream >> bodyOf: rest headers: headers [
	"Answer the body that Zinc wrote, without its chunks. A part of it is never sent"

	| length |
	(headers anySatisfy: [ :each |
		each key = 'transfer-encoding' and: [ each value asLowercase = 'chunked' ] ]) ifTrue: [
			"ZnChunkedReadStream does not see that the last chunk is missing"
			(rest endsWith: self lastChunk) ifFalse: [
				WebFetchBadRequest signal: 'The body has no last chunk' ].
			^ (ZnChunkedReadStream on: rest readStream) upToEnd ].
	length := headers detect: [ :each | each key = 'content-length' ] ifNone: [ ^ rest ].
	length value = rest size asString ifFalse: [
		WebFetchBadRequest signal: 'The body has ' , rest size asString , ' bytes, its Content-Length is ' , length value ].
	^ rest
]

{ #category : 'private - answer' }
WebFetchSocketStream >> checkCall [
	"Signal the error of a call that failed, or was aborted by another"

	(call recordedState = 4 or: [ call recordedState = 0 ]) ifTrue: [ call error copy signal ]
]

{ #category : 'networking' }
WebFetchSocketStream >> connect [
	"The TLS handshake is the host's"
]

{ #category : 'private' }
WebFetchSocketStream >> end [
	"Nothing more goes in or out"

	isEnded := true.
	outgoing := nil.
	segment := #[] readStream.
	chunkLeft := 0.
	writeBuffer reset.
	call ifNotNil: [ call close ]
]

{ #category : 'private' }
WebFetchSocketStream >> fetchDo: aBlock [
	"Evaluate aBlock. An error ends me, and the network errors become those Zinc knows.
	None becomes a ConnectionClosed: Zodiac takes it for the end of the answer"

	^ aBlock
		on: WebFetchError
		do: [ :error |
			self end.
			(error isKindOf: WebFetchTimeout) ifTrue: [
				ConnectionTimedOut signal: error messageText ].
			((error isKindOf: WebFetchNetworkError) or: [ error isKindOf: WebFetchNetworkOff ])
				ifTrue: [ (WebFetchZnNetworkError cause: error) signal ].
			error pass ]
]

{ #category : 'initialization' }
WebFetchSocketStream >> followRedirects: aBoolean [
	followRedirects := aBoolean
]

{ #category : 'private - answer' }
WebFetchSocketStream >> hasBody: status [
	^ method ~= 'HEAD' and: [ status >= 200 and: [ (#( 204 205 304 ) includes: status) not ] ]
]

{ #category : 'private - request' }
WebFetchSocketStream >> headerOf: aLine [
	"Answer the lower case name -> the value"

	| colon |
	colon := aLine indexOf: $:.
	colon > 1 ifFalse: [ WebFetchBadRequest signal: 'Not a header: ' , aLine ].
	^ (aLine first: colon - 1) asLowercase -> (aLine allButFirst: colon) trimBoth
]

{ #category : 'initialization' }
WebFetchSocketStream >> initialize [
	super initialize.
	followRedirects := true.
	outgoing := WriteStream on: (ByteArray new: 4096).
	segment := #[] readStream.
	chunkLeft := 0.
	isHeadMade := isComplete := isEnded := false
]

{ #category : 'initialization' }
WebFetchSocketStream >> initializeBuffers [
	readBuffer := ZdcIOBuffer onByteArrayOfSize: 16384.
	writeBuffer := ZdcIOBuffer onByteArrayOfSize: 4096
]

{ #category : 'private - answer' }
WebFetchSocketStream >> isReady [
	"Answer whether there is something to give, and prepare it. Do not wait"

	(segment atEnd not or: [ chunkLeft > 0 ]) ifTrue: [ ^ true ].
	isEnded ifTrue: [ ^ false ].
	call ifNil: [ self startCall ].
	call state = 1 ifTrue: [ ^ false ].
	self checkCall.
	isHeadMade ifFalse: [
		self makeHead.
		^ true ].
	call recordedAvailableBytes > 0 ifTrue: [
		self makeChunk.
		^ true ].
	call recordedState = 3 ifTrue: [
		self makeLastChunk.
		^ true ].
	^ false
]

{ #category : 'private' }
WebFetchSocketStream >> lastChunk [
	^ ('0' , String crlf , String crlf) asByteArray
]

{ #category : 'private - answer' }
WebFetchSocketStream >> latin1: aString [
	"Answer the bytes of aString"

	^ ByteArray streamContents: [ :out |
		aString do: [ :each | out nextPut: (each asInteger < 256 ifTrue: [ each asInteger ] ifFalse: [ $? asInteger ]) ] ]
]

{ #category : 'private - answer' }
WebFetchSocketStream >> makeChunk [
	"The line before the bytes of the body that are here. The line end after them is part of the next text"

	chunkLeft := call recordedAvailableBytes min: 65536.
	segment := ((chunkLeft printStringBase: 16) , String crlf) asByteArray readStream
]

{ #category : 'private - answer' }
WebFetchSocketStream >> makeHead [
	| response hasBody text |
	response := call headResponse.
	hasBody := self hasBody: response status.
	text := String streamContents: [ :out |
		out << 'HTTP/1.1 ' << response status asString << ' ' << response reason << String crlf.
		response headersDo: [ :name :value |
			(self passes: name hasBody: hasBody) ifTrue: [
				out << name << ': ' << value << String crlf ] ].
		response isRedirected ifTrue: [
			out << 'X-WebFetch-Url: ' << response url << String crlf ].
		hasBody ifTrue: [ out << 'Transfer-Encoding: chunked' << String crlf ].
		out << String crlf ].
	segment := (self latin1: text) readStream.
	isHeadMade := true.
	hasBody ifFalse: [
		isComplete := true.
		call close ]
]

{ #category : 'private - answer' }
WebFetchSocketStream >> makeLastChunk [
	segment := self lastChunk readStream.
	isComplete := true.
	call close
]

{ #category : 'initialization' }
WebFetchSocketStream >> on: aUrl [
	"I am my own socket"

	super on: self.
	url := aUrl
]

{ #category : 'private - answer' }
WebFetchSocketStream >> passes: aName hasBody: aBoolean [
	"The headers about the form of the body are of no use: it comes decoded, in chunks of mine"

	| name |
	name := aName asLowercase.
	name = 'content-length' ifTrue: [ ^ method = 'HEAD' ].
	^ (#( 'content-encoding' 'transfer-encoding' 'connection' 'keep-alive' ) includes: name) not
]

{ #category : 'private - answer' }
WebFetchSocketStream >> readBodyInto: bytes startingAt: offset count: count [
	| read |
	read := call readInto: bytes startingAt: offset count: (count min: chunkLeft).
	read = 0 ifTrue: [
		"The bytes announced are gone: the call failed since"
		call state.
		self checkCall ].
	chunkLeft := chunkLeft - read.
	chunkLeft = 0 ifTrue: [ segment := String crlf asByteArray readStream ].
	^ read
]

{ #category : 'networking' }
WebFetchSocketStream >> remoteAddress [
	"For the log of ZnClient: not known"

	^ nil
]

{ #category : 'networking' }
WebFetchSocketStream >> remotePort [
	^ nil
]

{ #category : 'private - request' }
WebFetchSocketStream >> linesOfHead: aStream [
	"Answer the lines up to the empty one. No limit of a reader of Zinc applies to them"

	| lines line |
	lines := OrderedCollection new.
	[
		line := aStream upTo: 10.
		line = #[ 13 ] ] whileFalse: [
			aStream atEnd ifTrue: [ WebFetchBadRequest signal: 'No whole HTTP request was written' ].
			lines add: (line copyWithout: 13) asString ].
	^ lines
]

{ #category : 'private - request' }
WebFetchSocketStream >> requestFrom: aStream [
	"Answer the WebFetchRequest of the HTTP request on aStream. The target is taken as it is written, not encoded again"

	| lines target headers body request |
	lines := self linesOfHead: aStream.
	lines ifEmpty: [ WebFetchBadRequest signal: 'No HTTP request line' ].
	method := lines first copyUpTo: Character space.
	target := (lines first copyAfter: Character space) copyUpToLast: Character space.
	headers := lines allButFirst collect: [ :each | self headerOf: each ].
	body := self bodyOf: aStream upToEnd headers: headers.
	request := WebFetch request: (String streamContents: [ :out |
		out << url scheme << '://' << url host.
		url hasPort ifTrue: [ out << ':' << url port asString ].
		out << target ]).
	request method: method.
	request headers addAll: headers.
	body ifNotEmpty: [ request body: body ].
	followRedirects ifFalse: [ request dontFollowRedirects ].
	^ request
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketClose [
	self end
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketIsConnected [
	^ isEnded not
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketIsDataAvailable [
	"Before the first read the request may be half written: then it does not start"

	call ifNil: [
		isEnded ifTrue: [ ^ false ].
		[ self requestFrom: outgoing contents readStream ] on: WebFetchBadRequest do: [ ^ false ] ].
	^ self fetchDo: [ self isReady ]
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketReceiveDataInto: bytes startingAt: offset count: count [
	^ self fetchDo: [
		| read |
		(count = 0 or: [ self isReady not ])
			ifTrue: [ 0 ]
			ifFalse: [
				read := segment atEnd
					ifTrue: [ self readBodyInto: bytes startingAt: offset count: count ]
					ifFalse: [ segment readInto: bytes startingAt: offset count: count ].
				(isComplete and: [ segment atEnd ]) ifTrue: [ self end ].
				read ] ]
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketSendData: bytes startingAt: offset count: count [
	"Gather count bytes. Once the answer has begun nothing is sent any more: ZnClient then takes a new connection"

	call ifNotNil: [
		writeBuffer reset.
		ConnectionClosed signal: 'One request per connection' ].
	outgoing position + count > WebFetchRequest maxRequestBodySize ifTrue: [
		self end.
		WebFetchBadRequest signal: 'Request exceeds 64 MiB limit' ].
	outgoing next: count putAll: bytes startingAt: offset.
	^ count
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketWaitForData [
	"Wait at most timeout seconds for something to give"

	| ready |
	ready := false.
	[ ready := self fetchDo: [ self waitForData ] ] ifCurtailed: [ self end ].
	ready ifTrue: [ ^ self ].
	isEnded ifTrue: [ WebFetchAborted signal: 'The connection was closed' ].
	self end.
	ConnectionTimedOut signal: 'Data receive timed out.'
]

{ #category : 'private - socket' }
WebFetchSocketStream >> socketWaitForSendDone [
	^ true
]

{ #category : 'networking' }
WebFetchSocketStream >> sslSession [
	^ WebFetchTLSSession new
]

{ #category : 'private - request' }
WebFetchSocketStream >> startCall [
	| request |
	request := self requestFrom: outgoing contents readStream.
	outgoing := nil.
	call := request startWithWindow: WebFetchCall defaultStreamWindow
]

{ #category : 'private' }
WebFetchSocketStream >> waitForData [
	^ self isReady or: [
		isEnded not and: [ call waitUntil: [ self isReady ] timeout: (timeout * 1000) rounded ] ]
]
