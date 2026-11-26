"
I test `WebFetchEventParser` and `WebFetchEvent` without a host. `eventsOf:` feeds each input in chunks of 1, 2 and 3 bytes and whole, each chunk followed in its ByteArray by line feeds beyond the count given, and checks that every cut gives the same events: so the cuts between CR and LF, inside a UTF-8 character and inside a BOM are all tested.
"
Class {
	#name : 'WebFetchEventParserTest',
	#superclass : 'TestCase',
	#category : 'WebFetch-Tests-Tests',
	#package : 'WebFetch-Tests',
	#tag : 'Tests'
}

{ #category : 'helpers' }
WebFetchEventParserTest >> bytes: aStringOrByteArray [
	aStringOrByteArray isString ifTrue: [ ^ aStringOrByteArray utf8Encoded ].
	^ aStringOrByteArray asByteArray
]

{ #category : 'helpers' }
WebFetchEventParserTest >> decode: aByteArray [
	^ WebFetchEventParser decodeUtf8: aByteArray from: 1 to: aByteArray size
]

{ #category : 'helpers' }
WebFetchEventParserTest >> eventsOf: anInput [
	^ self eventsOf: anInput with: [ :parser | ]
]

{ #category : 'helpers' }
WebFetchEventParserTest >> eventsOf: anInput with: aBlock [
	"Answer the events of anInput fed whole, after checking that chunks of 1, 2 and 3 bytes give the same ones and the same lastEventId"

	| bytes reference parser |
	bytes := self bytes: anInput.
	#( 1 2 3 0 ) do: [ :chunk |
		| summary |
		parser := WebFetchEventParser new.
		aBlock value: parser.
		self feed: bytes chunk: chunk into: parser.
		summary := (parser events collect: [ :each | { each type. each data. each lastEventId } ]) asArray
			copyWith: parser lastEventId.
		reference
			ifNil: [ reference := summary ]
			ifNotNil: [ self assert: summary equals: reference ] ].
	^ parser events asArray
]

{ #category : 'helpers' }
WebFetchEventParserTest >> feed: aByteArray chunk: chunkSize into: aParser [
	"Feed aByteArray in chunks of chunkSize bytes (0: whole). Each chunk is followed by line feeds in its buffer, which the parser must not read"

	| size |
	size := chunkSize = 0 ifTrue: [ aByteArray size max: 1 ] ifFalse: [ chunkSize ].
	1 to: aByteArray size by: size do: [ :start |
		| stop buffer |
		stop := start + size - 1 min: aByteArray size.
		buffer := ByteArray new: stop - start + 9 withAll: 10.
		buffer replaceFrom: 1 to: stop - start + 1 with: aByteArray startingAt: start.
		aParser feed: buffer count: stop - start + 1 ]
]

{ #category : 'helpers' }
WebFetchEventParserTest >> lf [
	^ String lf
]

{ #category : 'helpers' }
WebFetchEventParserTest >> text: lines [
	^ self text: lines eol: String lf
]

{ #category : 'helpers' }
WebFetchEventParserTest >> text: lines eol: aString [
	^ String streamContents: [ :stream |
		lines do: [ :each | stream nextPutAll: each; nextPutAll: aString ] ]
]

{ #category : 'tests' }
WebFetchEventParserTest >> testBom [
	| bom events parser |
	bom := #[ 16rEF 16rBB 16rBF ].
	events := self eventsOf: bom , (self text: #( 'data: x' '' )) utf8Encoded.
	self assert: (events collect: [ :each | each data ]) equals: #( 'x' ).
	"a second BOM makes the name of its line unknown"
	events := self eventsOf: bom , (self text: #( 'data: a' '' )) utf8Encoded , bom , (self text: #( 'data: x' '' 'data: b' '' )) utf8Encoded.
	self assert: (events collect: [ :each | each data ]) equals: #( 'a' 'b' ).
	"a partial BOM begins the first line"
	events := self eventsOf: #[ 16rEF 16rBB ] , (self text: #( 'data: x' '' 'data: y' '' )) utf8Encoded.
	self assert: (events collect: [ :each | each data ]) equals: #( 'y' ).
	events := self eventsOf: #[ 16rEF ] , (self text: #( 'data: x' '' )) utf8Encoded.
	self assert: events isEmpty.
	"one BOM at the start of each body"
	parser := WebFetchEventParser new.
	self feed: bom , (self text: #( 'data: 1' '' )) utf8Encoded chunk: 1 into: parser.
	parser endOfStream; startConnection.
	self feed: bom , (self text: #( 'data: 2' '' )) utf8Encoded chunk: 2 into: parser.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( '1' '2' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testBuffersShrinkAfterLargeEvent [
	| parser big event |
	parser := WebFetchEventParser new.
	self assert: parser bufferSizes equals: #( 1024 4096 ).
	big := ByteArray new: 1048576 withAll: 120.
	self feed: 'data: ' utf8Encoded , big , #[ 10 10 ] chunk: 16384 into: parser.
	event := parser nextEvent.
	self assert: event data size equals: 1048576.
	self assert: parser bufferSizes equals: #( 1024 4096 ).
	"an event below 64 KiB keeps its buffer"
	self feed: 'data: ' utf8Encoded , (ByteArray new: 5000 withAll: 121) , #[ 10 10 ] chunk: 0 into: parser.
	self assert: parser nextEvent data size equals: 5000.
	self assert: parser bufferSizes first >= 5001
]

{ #category : 'tests' }
WebFetchEventParserTest >> testComments [
	| parser comment |
	parser := WebFetchEventParser new.
	parser maximumEventSize: 1024.
	comment := ByteArray new: 10 * 1048576 withAll: 120.
	self feed: ': ' utf8Encoded , comment , (self text: #( '' 'data: ok' '' )) utf8Encoded chunk: 16384 into: parser.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( 'ok' ).
	self assert: parser bufferSizes equals: #( 1024 4096 ).
	self
		assert: ((self eventsOf: (self text: #( ':' ': ping' ':data: x' 'data: y' ': between' '' ))) collect: [ :each | each data ])
		equals: #( 'y' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testCrLfAcrossChunks [
	| parser |
	parser := WebFetchEventParser new.
	parser feed: ('data: a' , String cr) utf8Encoded count: 8.
	parser feed: (String lf , 'data: b' , String crlf) utf8Encoded count: 10.
	self deny: parser hasEvents.
	parser feed: String crlf utf8Encoded count: 2.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: { 'a' , self lf , 'b' }.
	"CR CR is a line end and an empty line"
	self
		assert: ((self eventsOf: 'data: a' , String cr , String cr , 'data: b' , String cr , String lf , String cr) collect: [ :each | each data ])
		equals: #( 'a' 'b' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testDecoder [
	| bytes |
	self assert: (self decode: 'plain ASCII' utf8Encoded) equals: 'plain ASCII'.
	self assert: (self decode: 'plain ASCII' utf8Encoded) class equals: ByteString.
	self assert: (self decode: #[ ]) equals: ''.
	self assert: (self decode: 'città è' utf8Encoded) equals: 'città è'.
	self assert: (self decode: 'città è' utf8Encoded) class equals: ByteString.
	self assert: (self decode: 'ok ✓' utf8Encoded) equals: 'ok ✓'.
	self assert: (self decode: 'ok ✓' utf8Encoded) isWideString.
	self assert: (self decode: #[ 16rF0 16r9F 16r99 16r82 ]) equals: (String with: (Character value: 16r1F642)).
	self assert: (self decode: #[ 16rF4 16r8F 16rBF 16rBF ]) equals: (String with: (Character value: 16r10FFFF)).
	bytes := 'xxcafé✓yy' utf8Encoded.
	self assert: (WebFetchEventParser decodeUtf8: bytes from: 3 to: bytes size - 2) equals: 'café✓'.
	self assert: (WebFetchEventParser decodeUtf8: bytes from: 3 to: 5) equals: 'caf'.
	self assert: (WebFetchEventParser decodeUtf8: bytes from: 3 to: 6) equals: 'caf' , (String with: (Character value: 16rFFFD)).
	self assert: (WebFetchEventParser decodeUtf8: bytes from: 3 to: 2) equals: ''.
	"as TextDecoder decodes them"
	self assert: (self decode: #[ 16rF0 16r80 16r80 16r80 ]) equals: (String new: 4 withAll: (Character value: 16rFFFD)).
	self assert: (self decode: #[ 16rE2 16r82 16r41 ]) equals: (String with: (Character value: 16rFFFD) with: $A).
	self assert: (self decode: #[ 16rF5 16r41 ]) equals: (String with: (Character value: 16rFFFD) with: $A).
	self assert: (self decode: #[ 16rFF 16rFE 16r41 ]) equals: (String with: (Character value: 16rFFFD) with: (Character value: 16rFFFD) with: $A).
	self assert: (self decode: #[ 16rC3 ]) equals: (String with: (Character value: 16rFFFD)).
	self assert: (self decode: #[ 16rEF 16rBB 16rBF 16r41 ]) equals: (String with: (Character value: 16rFEFF) with: $A)
]

{ #category : 'tests' }
WebFetchEventParserTest >> testEndOfStream [
	| parser |
	parser := WebFetchEventParser new.
	self feed: (self text: #( 'id: 1' 'data: a' '' 'id: 9' 'data: b' )) utf8Encoded chunk: 3 into: parser.
	parser endOfStream.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( 'a' ).
	self assert: parser lastEventId equals: '1'.
	parser startConnection.
	self feed: (self text: #( 'data: c' '' )) utf8Encoded chunk: 0 into: parser.
	self assert: parser events last data equals: 'c'.
	self assert: parser events last lastEventId equals: '1'.
	"a line cut by the end does not go on in the next body"
	parser := WebFetchEventParser new.
	self feed: 'data: a' utf8Encoded chunk: 0 into: parser.
	parser endOfStream; startConnection.
	self feed: (self text: #( 'b' 'data: c' '' )) utf8Encoded chunk: 0 into: parser.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( 'c' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testEventPrinting [
	| parser event long |
	parser := WebFetchEventParser new.
	parser origin: 'https://example.org:8443'.
	long := String new: 50 withAll: $x.
	self feed: (self text: { 'event: tick'. 'data: hello'. ''. 'data: ' , long. '' }) utf8Encoded chunk: 0 into: parser.
	event := parser nextEvent.
	self assert: event origin equals: 'https://example.org:8443'.
	self assert: event printString equals: 'WebFetchEvent(tick ''hello'')'.
	event := parser nextEvent.
	self assert: event type equals: 'message'.
	self assert: event printString equals: 'WebFetchEvent(message ''' , (long first: 40) , '...'')'.
	self assert: (WebFetchEvent type: 'a' data: 'b' lastEventId: 'c' origin: nil) origin isNil
]

{ #category : 'tests' }
WebFetchEventParserTest >> testEventTypeReset [
	| events |
	events := self eventsOf: (self text: #( 'event: a' 'data: 1' '' 'data: 2' '' 'event: b' '' 'data: 3' '' 'event: c' 'event' 'data: 4' '' )).
	self assert: (events collect: [ :each | each type -> each data ]) equals: { 'a' -> '1'. 'message' -> '2'. 'message' -> '3'. 'message' -> '4' }
]

{ #category : 'tests' }
WebFetchEventParserTest >> testExamplesOfTheStandard [
	"The examples of section 9.2.6 of the HTML standard"

	| events |
	events := self eventsOf: (self text: #( 'data: YHOO' 'data: +2' 'data: 10' '' )).
	self assert: events size equals: 1.
	self assert: events first type equals: 'message'.
	self assert: events first data equals: ('YHOO' , self lf , '+2' , self lf , '10').

	events := self eventsOf: (self text: #( ': test stream' '' 'data: first event' 'id: 1' '' 'data:second event' 'id' '' 'data:  third event' '' )).
	self assert: (events collect: [ :each | each data -> each lastEventId ]) equals: { 'first event' -> '1'. 'second event' -> ''. ' third event' -> '' }.

	events := self eventsOf: (self text: #( 'data' '' 'data' 'data' '' )) , 'data:'.
	self assert: (events collect: [ :each | each data ]) equals: { ''. self lf }.

	events := self eventsOf: (self text: #( 'data:test' '' 'data: test' '' )).
	self assert: (events collect: [ :each | each data ]) equals: #( 'test' 'test' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testFields [
	| events |
	events := self eventsOf: (self text: #( 'data' '' 'event' 'data: x' '' 'Data: no' 'foo: no' 'datas: no' 'dat: no' 'data: yes' '' 'data:  x' '' 'data:' 'data:' '' )).
	self assert: (events collect: [ :each | each type -> each data ]) equals: { 'message' -> ''. 'message' -> 'x'. 'message' -> 'yes'. 'message' -> ' x'. 'message' -> self lf }.
	"an event without data dispatches nothing"
	self assert: (self eventsOf: (self text: #( 'event: e' 'id: 1' '' ))) isEmpty
]

{ #category : 'tests' }
WebFetchEventParserTest >> testIds [
	| events parser id |
	events := self eventsOf: (self text: { 'id: 1'. 'data: a'. ''. 'data: b'. ''. 'id: x' , (String with: (Character value: 0)) , 'y'. 'data: c'. ''. 'id'. 'data: d'. ''. 'id: 5'. ''. 'id: 6'. 'data: e'. ''. 'id:'. 'data: f'. '' }).
	self assert: (events collect: [ :each | each data -> each lastEventId ]) equals: { 'a' -> '1'. 'b' -> '1'. 'c' -> '1'. 'd' -> ''. 'e' -> '6'. 'f' -> '' }.
	"an id without event sets the last event ID"
	parser := WebFetchEventParser new.
	self feed: (self text: #( 'data: a' '' 'id: 5' '' )) utf8Encoded chunk: 0 into: parser.
	self assert: parser events size equals: 1.
	self assert: parser lastEventId equals: '5'.
	"the id buffer of a new body starts from it"
	parser endOfStream; startConnection.
	self feed: (self text: #( 'data: b' '' )) utf8Encoded chunk: 0 into: parser.
	self assert: parser events last lastEventId equals: '5'.
	parser := WebFetchEventParser new.
	parser lastEventId: 'città'.
	self feed: (self text: #( 'data: b' '' 'id: é' 'data: c' '' )) utf8Encoded chunk: 1 into: parser.
	self assert: (parser events collect: [ :each | each lastEventId ]) asArray equals: #( 'città' 'é' ).
	"4096 bytes, not more"
	id := String new: 4096 withAll: $i.
	events := self eventsOf: (self text: { 'id: ' , id. 'event: ' , id. 'data: a'. '' }).
	self assert: events first lastEventId equals: id.
	self assert: events first type equals: id.
	self
		should: [ self eventsOf: (self text: { 'id: ' , id , 'i'. 'data: a'. '' }) ]
		raise: WebFetchTooLarge
		withExceptionDo: [ :error | self assert: error messageText equals: 'id longer than 4096 bytes' ].
	self
		should: [ self eventsOf: (self text: { 'event: ' , id , 'e'. 'data: a'. '' }) ]
		raise: WebFetchTooLarge
		withExceptionDo: [ :error |
			self assert: error messageText equals: 'event type longer than 4096 bytes'.
			self assert: error kind equals: #tooLarge ]
]

{ #category : 'tests' }
WebFetchEventParserTest >> testLineEnds [
	| lines expected |
	lines := #( 'event: a' 'data: 1' 'data: 2' '' ': c' 'id: 7' 'data: 3' '' ).
	expected := { 'a' -> ('1' , self lf , '2'). 'message' -> '3' }.
	{ String lf. String crlf. String cr } do: [ :eol |
		self
			assert: ((self eventsOf: (self text: lines eol: eol)) collect: [ :each | each type -> each data ])
			equals: expected ].
	self
		assert: ((self eventsOf: 'event: a' , String lf , 'data: 1' , String crlf , 'data: 2' , String crlf , String cr , ': c' , String crlf , 'id: 7' , String cr , 'data: 3' , String cr , String cr)
			collect: [ :each | each type -> each data ])
		equals: expected
]

{ #category : 'tests' }
WebFetchEventParserTest >> testMaximumEventSize [
	| limited parser |
	limited := [ :parser | parser maximumEventSize: 10 ].
	self
		assert: ((self eventsOf: (self text: #( 'data: 0123456789' '' )) with: limited) collect: [ :each | each data ])
		equals: #( '0123456789' ).
	self
		assert: ((self eventsOf: (self text: #( 'data: 0123' 'data: 01234' '' )) with: limited) collect: [ :each | each data ])
		equals: { '0123' , self lf , '01234' }.
	#( #( 'data: 01234567890' '' ) #( 'data: 0123' 'data: 012345' '' ) #( 'data: 0123456789' 'data:' '' ) #( 'data: 0123456789' 'data' '' ) ) do: [ :lines |
		self
			should: [ self eventsOf: (self text: lines) with: limited ]
			raise: WebFetchTooLarge
			withExceptionDo: [ :error | self assert: error messageText equals: 'event data longer than 10 bytes' ] ].
	"the events before it in the same chunk stay"
	parser := WebFetchEventParser new.
	parser maximumEventSize: 10.
	self
		should: [ self feed: (self text: #( 'data: a' '' 'data: b' '' 'data: 01234567890' '' 'data: c' '' )) utf8Encoded chunk: 0 into: parser ]
		raise: WebFetchTooLarge.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( 'a' 'b' )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testRetry [
	| retries |
	retries := [ :input |
		#( 1 2 3 0 ) collect: [ :chunk |
			| parser |
			parser := WebFetchEventParser new.
			self feed: (self bytes: input) chunk: chunk into: parser.
			parser takeRetry ] ].
	self assert: (retries value: (self text: #( 'retry: 1500' ))) equals: #( 1500 1500 1500 1500 ).
	self assert: (retries value: (self text: #( 'retry:0' ))) equals: #( 0 0 0 0 ).
	#( 'retry: 1.5' 'retry: -1' 'retry: 15x' 'retry:  15' 'retry:' 'retry' 'retry: ' 'Retry: 15' ) do: [ :line |
		self assert: (retries value: (self text: { line })) equals: #( nil nil nil nil ) ].
	self assert: (retries value: (self text: #( 'retry: 123456789012345678901234567890' ))) equals: #( 2147483647 2147483647 2147483647 2147483647 ).
	"the last valid one, taken once"
	self assert: (retries value: (self text: #( 'retry: 100' 'retry: x' 'retry: 200' 'retry: -' ))) equals: #( 200 200 200 200 ).
	self assert: (retries value: 'retry: 100') equals: #( nil nil nil nil ).
	self assert: (retries value: (self text: #( 'retry: 100' ) eol: String cr)) equals: #( 100 100 100 100 ).
	retries := WebFetchEventParser new.
	retries feed: (self text: #( 'retry: 300' )) utf8Encoded count: 11.
	self assert: retries takeRetry equals: 300.
	self assert: retries takeRetry isNil
]

{ #category : 'tests' }
WebFetchEventParserTest >> testUnknownLongFieldIgnored [
	| parser long |
	long := ByteArray new: 2 * 1048576 withAll: 120.
	parser := WebFetchEventParser new.
	parser maximumEventSize: 1024.
	self feed: 'foo: ' utf8Encoded , long , (self text: #( '' 'data: ok' '' )) utf8Encoded chunk: 16384 into: parser.
	self feed: long , (self text: #( '' 'data: ok2' '' )) utf8Encoded chunk: 16384 into: parser.
	self feed: 'datax' utf8Encoded , long , ': ' utf8Encoded , long , (self text: #( '' 'data: ok3' '' )) utf8Encoded chunk: 16384 into: parser.
	self assert: (parser events collect: [ :each | each data ]) asArray equals: #( 'ok' 'ok2' 'ok3' ).
	self assert: parser bufferSizes equals: #( 1024 4096 )
]

{ #category : 'tests' }
WebFetchEventParserTest >> testUtf8 [
	| replacement events cases |
	replacement := Character value: 16rFFFD.
	events := self eventsOf: (self text: #( 'data: é ✓ 🙂' 'event: café' 'id: città' '' )).
	self assert: events first data equals: 'é ✓ 🙂'.
	self assert: events first type equals: 'café'.
	self assert: events first lastEventId equals: 'città'.
	events := self eventsOf: 'data: ' utf8Encoded , #[ 16rEF 16rBB 16rBF ] , 'x' utf8Encoded , #[ 10 10 ].
	self assert: events first data equals: (String with: (Character value: 16rFEFF) with: $x).
	cases := {
		#[ 16rC0 16r80 ] -> 2.
		#[ 16rE0 16r80 16r80 ] -> 3.
		#[ 16rED 16rA0 16r80 ] -> 3.
		#[ 16rF4 16r90 16r80 16r80 ] -> 4.
		#[ 16r80 ] -> 1.
		#[ 16rE2 16r82 ] -> 1 }.
	cases do: [ :case |
		events := self eventsOf: 'data: ' utf8Encoded , case key , #[ 10 10 ].
		self assert: events size equals: 1.
		self assert: events first data equals: (String new: case value withAll: replacement) ].
	events := self eventsOf: 'data: ' utf8Encoded , #[ 16rEF 16rBB 16r41 ] , #[ 10 10 ].
	self assert: events first data equals: (String with: replacement with: $A)
]
