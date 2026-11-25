"
I describe an HTTP request to be executed by `WebFetch`. I am reusable: starting or fetching me never mutates my state.

Defaults: method `#GET`, `maximumBodySize` 64 MiB (for `fetch` and `start`; it does not bound `stream:`), redirects followed, timeout unset (60 seconds for `fetch`/`get:`/`post:body:type:`, none for `start`/`stream:`).
"
Class {
	#name : 'WebFetchRequest',
	#superclass : 'Object',
	#instVars : [
		'url',
		'method',
		'headers',
		'body',
		'timeout',
		'timeoutSet',
		'maximumBodySize',
		'followRedirects',
		'host'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'constants' }
WebFetchRequest class >> defaultFetchTimeout [
	^ 60 seconds
]

{ #category : 'constants' }
WebFetchRequest class >> defaultMaximumBodySize [
	"64 MiB"

	^ 67108864
]

{ #category : 'constants' }
WebFetchRequest class >> maxHeadBytes [
	"1 MiB"

	^ 1048576
]

{ #category : 'constants' }
WebFetchRequest class >> maxRequestBodySize [
	"64 MiB"

	^ 67108864
]

{ #category : 'constants' }
WebFetchRequest class >> maxWindowSize [
	"2^31 - 1"

	^ 2147483647
]

{ #category : 'instance creation' }
WebFetchRequest class >> url: aUrlOrString [
	^ self new
		url: aUrlOrString;
		yourself
]

{ #category : 'accessing' }
WebFetchRequest >> body [
	^ body
]

{ #category : 'accessing' }
WebFetchRequest >> body: aByteArrayOrStringOrNil [
	body := aByteArrayOrStringOrNil
]

{ #category : 'building' }
WebFetchRequest >> buildForDefaultTimeout: defaultDuration [
	"Validate and encode { headBytes. bodyBytesOrNil. timeoutMs. flags } without mutating self"

	| methodStr urlStr bodyBytes effectiveHeaders hasContentType headText headBytes timeoutMs flags |
	methodStr := self validatedMethod.
	urlStr := self validatedUrl.
	bodyBytes := self validatedBodyBytes.
	timeoutMs := self validatedTimeoutMillisecondsForDefault: defaultDuration.
	self validatedMaximumBodySize.
	effectiveHeaders := OrderedCollection new: headers size + 1.
	hasContentType := false.
	headers do: [ :assoc |
		self validateHeaderName: assoc key value: assoc value.
		assoc key asLowercase = 'content-type' ifTrue: [ hasContentType := true ].
		effectiveHeaders add: assoc ].
	(body isString and: [ hasContentType not ]) ifTrue: [
		effectiveHeaders add: 'Content-Type' -> 'text/plain;charset=UTF-8' ].
	headText := String streamContents: [ :stream |
		stream
			nextPutAll: methodStr;
			lf;
			nextPutAll: urlStr.
		effectiveHeaders do: [ :assoc |
			stream
				lf;
				nextPutAll: assoc key;
				nextPutAll: ': ';
				nextPutAll: assoc value ] ].
	headBytes := [ headText utf8Encoded ]
		on: Error
		do: [ :e | WebFetchBadRequest signal: 'Request head UTF-8 encoding failed: ' , e messageText ].
	(headBytes isEmpty or: [ headBytes size > self class maxHeadBytes ]) ifTrue: [
		WebFetchBadRequest signal: 'Request head exceeds 1 MiB limit' ].
	flags := followRedirects ifTrue: [ 0 ] ifFalse: [ 1 ].
	^ { headBytes. bodyBytes. timeoutMs. flags }
]

{ #category : 'configuration' }
WebFetchRequest >> dontFollowRedirects [
	followRedirects := false
]

{ #category : 'accessing' }
WebFetchRequest >> effectiveHost [
	^ host ifNil: [ WebFetchHost default ]
]

{ #category : 'executing' }
WebFetchRequest >> fetch [
	"Execute the request and wait for its WebFetchResponse (default timeout 60 s)"

	| call |
	self effectiveHost mayWait ifFalse: [
		WebFetchInCallback signal: 'Cannot fetch inside an FFI callback' ].
	call := WebFetchCall startWholeRequest: self defaultTimeout: self class defaultFetchTimeout.
	^ call response
]

{ #category : 'configuration' }
WebFetchRequest >> followRedirects [
	followRedirects := true
]

{ #category : 'accessing' }
WebFetchRequest >> headerAt: aName put: aValue [
	"Set header case-insensitively, replacing in place to preserve header order"

	| lower index |
	lower := aName asLowercase.
	index := 0.
	1 to: headers size do: [ :i |
		(index = 0 and: [ (headers at: i) key asLowercase = lower ]) ifTrue: [ index := i ] ].
	index > 0
		ifTrue: [ headers at: index put: aName -> aValue ]
		ifFalse: [ headers add: aName -> aValue ]
]

{ #category : 'accessing' }
WebFetchRequest >> headers [
	^ headers
]

{ #category : 'accessing' }
WebFetchRequest >> host [
	^ host
]

{ #category : 'accessing' }
WebFetchRequest >> host: aHost [
	host := aHost
]

{ #category : 'initialization' }
WebFetchRequest >> initialize [
	super initialize.
	method := #GET.
	headers := OrderedCollection new.
	timeoutSet := false.
	maximumBodySize := self class defaultMaximumBodySize.
	followRedirects := true
]

{ #category : 'testing' }
WebFetchRequest >> isFollowRedirects [
	^ followRedirects
]

{ #category : 'accessing' }
WebFetchRequest >> maximumBodySize [
	^ maximumBodySize
]

{ #category : 'accessing' }
WebFetchRequest >> maximumBodySize: aNumber [
	"Set whole-body size limit in 0..2^31-2 (does not bound stream:)"

	| size |
	aNumber isNumber ifFalse: [
		WebFetchBadRequest signal: 'maximumBodySize must be an integer or whole float' ].
	(aNumber isFloat and: [ aNumber isNaN or: [ aNumber isInfinite or: [ aNumber fractionPart ~= 0 ] ] ])
		ifTrue: [ WebFetchBadRequest signal: 'maximumBodySize must be a whole number' ].
	size := aNumber rounded.
	(size < 0 or: [ size > (self class maxWindowSize - 1) ]) ifTrue: [
		WebFetchBadRequest signal: 'maximumBodySize out of range 0..2^31-2' ].
	maximumBodySize := size
]

{ #category : 'accessing' }
WebFetchRequest >> method [
	^ method
]

{ #category : 'accessing' }
WebFetchRequest >> method: aSymbolOrString [
	method := aSymbolOrString
]

{ #category : 'executing' }
WebFetchRequest >> start [
	"Start a whole-body call without waiting (default timeout none)"

	^ WebFetchCall startWholeRequest: self defaultTimeout: nil
]

{ #category : 'executing' }
WebFetchRequest >> startWithWindow: windowBytes [
	"Start a streaming call with windowBytes (default timeout none); body stays unread"

	^ WebFetchCall startRequest: self window: windowBytes
]

{ #category : 'executing' }
WebFetchRequest >> stream: aBlock [
	"Stream the response body through a WebFetchBodyStream (1 MiB window; not bounded by maximumBodySize)"

	| call headResp stream result |
	self effectiveHost mayWait ifFalse: [
		WebFetchInCallback signal: 'Cannot stream inside an FFI callback' ].
	call := WebFetchCall startRequest: self window: WebFetchCall defaultStreamWindow.
	headResp := call waitForHead.
	stream := WebFetchBodyStream on: call response: headResp.
	[ result := aBlock value: stream ] ensure: [ stream close ].
	^ result
]

{ #category : 'accessing' }
WebFetchRequest >> timeout [
	^ timeout
]

{ #category : 'accessing' }
WebFetchRequest >> timeout: aDurationOrSecondsOrNil [
	"Set timeout (Duration, Number of seconds, or nil/Duration zero for no timeout)"

	timeoutSet := true.
	aDurationOrSecondsOrNil ifNil: [
		timeout := nil.
		^ self ].
	timeout := aDurationOrSecondsOrNil isNumber
		ifTrue: [ Duration seconds: aDurationOrSecondsOrNil ]
		ifFalse: [ aDurationOrSecondsOrNil ]
]

{ #category : 'accessing' }
WebFetchRequest >> url [
	^ url
]

{ #category : 'accessing' }
WebFetchRequest >> url: aUrlOrString [
	url := aUrlOrString
]

{ #category : 'private' }
WebFetchRequest >> validateControlCharsIn: aString label: label [
	| cr lf nul |
	cr := Character cr.
	lf := Character lf.
	nul := Character value: 0.
	aString do: [ :ch |
		(ch = cr or: [ ch = lf or: [ ch = nul ] ]) ifTrue: [
			WebFetchBadRequest signal: label , ' must not contain CR, LF or NUL' ] ]
]

{ #category : 'private' }
WebFetchRequest >> validateHeaderName: name value: value [
	(name isString and: [ name notEmpty ]) ifFalse: [
		WebFetchBadRequest signal: 'Header name must be a non-empty String' ].
	self validateControlCharsIn: name label: 'Header name'.
	name do: [ :ch |
		(ch = $: or: [ ch = Character space ]) ifTrue: [
			WebFetchBadRequest signal: 'Header name must not contain colon or space' ] ].
	value isString ifFalse: [
		WebFetchBadRequest signal: 'Header value must be a String' ].
	self validateControlCharsIn: value label: 'Header value'
]

{ #category : 'private' }
WebFetchRequest >> validatedBodyBytes [
	| bytes |
	body ifNil: [ ^ nil ].
	body isString
		ifTrue: [
			bytes := [ body utf8Encoded ]
				on: Error
				do: [ :e | WebFetchBadRequest signal: 'Request body UTF-8 encoding failed: ' , e messageText ] ]
		ifFalse: [
			(body isKindOf: ByteArray)
				ifTrue: [ bytes := body ]
				ifFalse: [ WebFetchBadRequest signal: 'Request body must be nil, String or ByteArray' ] ].
	bytes size > self class maxRequestBodySize ifTrue: [
		WebFetchBadRequest signal: 'Request body exceeds 64 MiB limit' ].
	^ bytes
]

{ #category : 'private' }
WebFetchRequest >> validatedMaximumBodySize [
	(maximumBodySize isInteger and: [ maximumBodySize between: 0 and: self class maxWindowSize - 1 ])
		ifFalse: [ WebFetchBadRequest signal: 'maximumBodySize out of range' ]
]

{ #category : 'private' }
WebFetchRequest >> validatedMethod [
	| str |
	(method isString and: [ method notEmpty ]) ifFalse: [
		WebFetchBadRequest signal: 'HTTP method must be a non-empty String or Symbol' ].
	str := method asString asUppercase.
	self validateControlCharsIn: str label: 'HTTP method'.
	^ str
]

{ #category : 'private' }
WebFetchRequest >> validatedTimeoutMillisecondsForDefault: defaultDuration [
	| effective ms |
	effective := timeoutSet ifTrue: [ timeout ] ifFalse: [ defaultDuration ].
	effective ifNil: [ ^ 0 ].
	(effective isKindOf: Duration) ifFalse: [
		WebFetchBadRequest signal: 'Timeout must be a Duration, Number, or nil' ].
	effective < Duration zero ifTrue: [
		WebFetchBadRequest signal: 'Timeout must not be negative' ].
	effective = Duration zero ifTrue: [ ^ 0 ].
	ms := effective asMilliSeconds truncated.
	ms < 1 ifTrue: [ ms := 1 ].
	ms > self class maxWindowSize ifTrue: [ ms := self class maxWindowSize ].
	^ ms
]

{ #category : 'private' }
WebFetchRequest >> validatedUrl [
	| str |
	url ifNil: [ WebFetchBadRequest signal: 'Request URL must not be nil' ].
	str := url asString.
	str isEmpty ifTrue: [ WebFetchBadRequest signal: 'Request URL must not be empty' ].
	self validateControlCharsIn: str label: 'Request URL'.
	^ str
]
