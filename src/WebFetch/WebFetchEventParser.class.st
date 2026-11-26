"
I parse an event stream (`text/event-stream`) as section 9.2.6 of the WHATWG HTML standard does, fed with the bytes of its bodies (`feed:count:`). I need no host and no process; `WebFetchEventSource` feeds me.

- Each body begins with `startConnection`, which drops one leading UTF-8 BOM (also cut across chunks), and ends with `endOfStream`, which drops an incomplete event.
- CR, LF and CR LF end lines, also when CR and LF come in two chunks.
- I keep no line: I read the name of each field (at most 5 bytes: `data`, `event`, `id`, `retry`), then put its value where it goes. The data goes straight into one ByteArray; the values of `event` and `id` into a buffer of `maximumFieldSize` bytes; `retry` is read as digits. Comments, unknown fields and their values are skipped and cost no memory.
- An empty line dispatches the event: a `WebFetchEvent` in `events`, which `nextEvent` answers. The data is decoded once, then, with `decodeUtf8:from:to:` (WHATWG UTF-8 decode: U+FFFD for invalid bytes, every U+FEFF kept).
- `lastEventId` is the last event ID of the stream; an `id` with U+0000 is ignored. It is kept across bodies, and each body starts its id buffer from it, as the browsers do.
- `takeRetry` answers the last valid `retry` (milliseconds, at most 2^31-1) and forgets it.

Data longer than `maximumEventSize` bytes (its UTF-8 with the line feeds between its lines), or an `id` or `event` longer than `maximumFieldSize` bytes, signal `WebFetchTooLarge` from `feed:count:`; the events dispatched before it stay in `events`. A data buffer that grew over 64 KiB is replaced by one of 1 KiB after its event.
"
Class {
	#name : 'WebFetchEventParser',
	#superclass : 'Object',
	#instVars : [
		'phase',
		'skipLf',
		'bom',
		'name',
		'nameSize',
		'field',
		'spacePending',
		'data',
		'dataSize',
		'small',
		'smallSize',
		'digits',
		'digitCount',
		'eventType',
		'idBuffer',
		'lastEventId',
		'retry',
		'events',
		'maximumEventSize',
		'origin'
	],
	#classVars : [
		'HighBytes',
		'LineEnds'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'decoding' }
WebFetchEventParser class >> decodeUtf8: aByteArray from: start to: stop [
	"Answer the String of the UTF-8 bytes start to stop of aByteArray, as WHATWG 'UTF-8 decode' without its BOM step: never fails, one U+FFFD for each maximal subpart of an invalid sequence, every U+FEFF kept. A ByteString when every character is below 256, else a WideString"

	| high size counted string |
	stop < start ifTrue: [ ^ '' ].
	size := stop - start + 1.
	high := ByteString findFirstInString: aByteArray inSet: self highBytes startingAt: start.
	(high = 0 or: [ high > stop ]) ifTrue: [
		^ (ByteString new: size)
			replaceFrom: 1 to: size with: aByteArray startingAt: start;
			yourself ].
	counted := self decodeUtf8: aByteArray from: high to: stop into: nil at: 0.
	string := (counted at: 2) > 255
		ifTrue: [ WideString new: high - start + (counted at: 1) ]
		ifFalse: [ ByteString new: high - start + (counted at: 1) ].
	start to: high - 1 do: [ :i | string at: i - start + 1 put: (Character value: (aByteArray at: i)) ].
	self decodeUtf8: aByteArray from: high to: stop into: string at: high - start.
	^ string
]

{ #category : 'private' }
WebFetchEventParser class >> decodeUtf8: aByteArray from: start to: stop into: aStringOrNil at: offset [
	"The decoder of WHATWG: put the characters of the bytes start to stop into aStringOrNil after index offset, or only count them when it is nil. Answer { the count. the largest code point }"

	| count max needed seen codePoint lower upper i |
	count := 0.
	max := 0.
	needed := 0.
	seen := 0.
	codePoint := 0.
	lower := 16r80.
	upper := 16rBF.
	i := start.
	[ i <= stop ] whileTrue: [
		| byte emit |
		byte := aByteArray at: i.
		emit := nil.
		needed = 0
			ifTrue: [
				i := i + 1.
				byte < 16r80
					ifTrue: [ emit := byte ]
					ifFalse: [
						byte < 16rC2
							ifTrue: [ emit := 16rFFFD ]
							ifFalse: [
								byte < 16rE0
									ifTrue: [
										needed := 1.
										codePoint := byte bitAnd: 16r1F ]
									ifFalse: [
										byte < 16rF0
											ifTrue: [
												byte = 16rE0 ifTrue: [ lower := 16rA0 ].
												byte = 16rED ifTrue: [ upper := 16r9F ].
												needed := 2.
												codePoint := byte bitAnd: 16rF ]
											ifFalse: [
												byte < 16rF5
													ifTrue: [
														byte = 16rF0 ifTrue: [ lower := 16r90 ].
														byte = 16rF4 ifTrue: [ upper := 16r8F ].
														needed := 3.
														codePoint := byte bitAnd: 16r7 ]
													ifFalse: [ emit := 16rFFFD ] ] ] ] ] ]
			ifFalse: [
				(byte >= lower and: [ byte <= upper ])
					ifTrue: [
						i := i + 1.
						lower := 16r80.
						upper := 16rBF.
						codePoint := (codePoint bitShift: 6) bitOr: (byte bitAnd: 16r3F).
						seen := seen + 1.
						seen = needed ifTrue: [
							emit := codePoint.
							needed := 0.
							seen := 0.
							codePoint := 0 ] ]
					ifFalse: [
						"the byte is read again as the start of a sequence"
						emit := 16rFFFD.
						needed := 0.
						seen := 0.
						codePoint := 0.
						lower := 16r80.
						upper := 16rBF ] ].
		emit ifNotNil: [
			count := count + 1.
			emit > max ifTrue: [ max := emit ].
			aStringOrNil ifNotNil: [ aStringOrNil at: offset + count put: (Character value: emit) ] ] ].
	needed = 0 ifFalse: [
		count := count + 1.
		max := max max: 16rFFFD.
		aStringOrNil ifNotNil: [ aStringOrNil at: offset + count put: (Character value: 16rFFFD) ] ].
	^ { count. max }
]

{ #category : 'private' }
WebFetchEventParser class >> highBytes [
	"The map of findFirstInString:inSet:startingAt: that finds a byte of 128 or more"

	HighBytes ifNil: [ self initialize ].
	^ HighBytes
]

{ #category : 'class initialization' }
WebFetchEventParser class >> initialize [
	LineEnds := (ByteArray new: 256)
		at: 10 + 1 put: 1;
		at: 13 + 1 put: 1;
		yourself.
	HighBytes := ByteArray new: 256.
	129 to: 256 do: [ :i | HighBytes at: i put: 1 ]
]

{ #category : 'private' }
WebFetchEventParser class >> lineEnds [
	"The map of findFirstInString:inSet:startingAt: that finds a CR or a LF"

	LineEnds ifNil: [ self initialize ].
	^ LineEnds
]

{ #category : 'constants' }
WebFetchEventParser class >> maximumFieldSize [
	"The most bytes of the value of an id or event field"

	^ 4096
]

{ #category : 'private' }
WebFetchEventParser >> addDigits: aByteArray from: start to: stop [
	digitCount := digitCount + (stop - start + 1).
	start to: stop do: [ :i |
		digits ifNotNil: [
			| byte |
			byte := aByteArray at: i.
			digits := (byte between: 48 and: 57)
				ifTrue: [ digits * 10 + (byte - 48) min: 2147483647 ]
				ifFalse: [ nil ] ] ]
]

{ #category : 'private' }
WebFetchEventParser >> appendData: aByteArray from: start to: stop [
	| count |
	count := stop - start + 1.
	count <= 0 ifTrue: [ ^ self ].
	dataSize + count > maximumEventSize ifTrue: [ self signalDataTooLarge ].
	self ensureData: dataSize + count.
	data replaceFrom: dataSize + 1 to: dataSize + count with: aByteArray startingAt: start.
	dataSize := dataSize + count
]

{ #category : 'private' }
WebFetchEventParser >> appendDataLf [
	"The line feed after each data line; the last one is dropped at the dispatch"

	dataSize > maximumEventSize ifTrue: [ self signalDataTooLarge ].
	self ensureData: dataSize + 1.
	dataSize := dataSize + 1.
	data at: dataSize put: 10
]

{ #category : 'private' }
WebFetchEventParser >> appendSmall: aByteArray from: start to: stop [
	| count |
	count := stop - start + 1.
	count <= 0 ifTrue: [ ^ self ].
	smallSize + count > small size ifTrue: [
		phase := #skip.
		WebFetchTooLarge signal: (field == #id
			ifTrue: [ 'id longer than ' ]
			ifFalse: [ 'event type longer than ' ]) , small size printString , ' bytes' ].
	small replaceFrom: smallSize + 1 to: smallSize + count with: aByteArray startingAt: start.
	smallSize := smallSize + count
]

{ #category : 'private' }
WebFetchEventParser >> decode: aByteArray size: anInteger [
	^ self class decodeUtf8: aByteArray from: 1 to: anInteger
]

{ #category : 'private' }
WebFetchEventParser >> dispatch [
	"An empty line: the event of the lines before it, if it has data"

	| type |
	lastEventId := idBuffer.
	dataSize = 0 ifTrue: [
		eventType := ''.
		^ self ].
	type := eventType isEmpty ifTrue: [ 'message' ] ifFalse: [ eventType ].
	events addLast: (WebFetchEvent
		type: type
		data: (self class decodeUtf8: data from: 1 to: dataSize - 1)
		lastEventId: lastEventId
		origin: origin).
	dataSize := 0.
	eventType := ''.
	data size > 65536 ifTrue: [ data := ByteArray new: 1024 ]
]

{ #category : 'parsing' }
WebFetchEventParser >> endLine [
	"A line ends: complete the field that it holds"

	phase == #start ifTrue: [ ^ self dispatch ].
	phase == #name ifTrue: [
		"a name without colon is a field with an empty value"
		self matchName.
		phase == #value ifTrue: [
			field == #data ifTrue: [ self appendDataLf ].
			field == #event ifTrue: [ eventType := '' ].
			field == #id ifTrue: [ idBuffer := '' ] ].
		^ phase := #start ].
	phase == #value ifTrue: [ self endValue ].
	phase := #start
]

{ #category : 'parsing' }
WebFetchEventParser >> endOfStream [
	"The body ended: the line not ended and the event not dispatched are dropped"

	phase := #start.
	skipLf := false.
	dataSize := 0.
	eventType := ''.
	smallSize := 0.
	idBuffer := lastEventId
]

{ #category : 'private' }
WebFetchEventParser >> endValue [
	field == #data ifTrue: [ ^ self appendDataLf ].
	field == #event ifTrue: [ ^ eventType := self decode: small size: smallSize ].
	field == #id ifTrue: [
		1 to: smallSize do: [ :i | (small at: i) = 0 ifTrue: [ ^ self ] ].
		^ idBuffer := self decode: small size: smallSize ].
	field == #retry ifTrue: [
		(digitCount > 0 and: [ digits notNil ]) ifTrue: [ retry := digits ] ]
]

{ #category : 'private' }
WebFetchEventParser >> ensureData: anInteger [
	| grown |
	anInteger <= data size ifTrue: [ ^ self ].
	grown := ByteArray new: ((data size * 2 max: anInteger) min: maximumEventSize + 1).
	grown replaceFrom: 1 to: dataSize with: data startingAt: 1.
	data := grown
]

{ #category : 'accessing' }
WebFetchEventParser >> events [
	"The events dispatched and not yet taken"

	^ events
]

{ #category : 'parsing' }
WebFetchEventParser >> feed: aByteArray count: anInteger [
	"Parse the bytes 1 to anInteger of aByteArray, the next ones of the body"

	| i |
	i := 1.
	bom == #done ifFalse: [
		i := self feedBom: aByteArray count: anInteger.
		i > anInteger ifTrue: [ ^ self ] ].
	self feedBytes: aByteArray from: i count: anInteger
]

{ #category : 'private' }
WebFetchEventParser >> feedBom: aByteArray count: anInteger [
	"Drop the bytes of one UTF-8 BOM at the start of the body, also cut across chunks. Answer the index of the first byte left to parse"

	| bomBytes i |
	bomBytes := #[ 16rEF 16rBB 16rBF ].
	i := 1.
	[ bom == #done or: [ i > anInteger ] ] whileFalse: [
		(aByteArray at: i) = (bomBytes at: bom + 1)
			ifTrue: [
				i := i + 1.
				bom := bom + 1.
				bom = 3 ifTrue: [ bom := #done ] ]
			ifFalse: [
				| matched |
				matched := bom.
				bom := #done.
				"the bytes that matched are no BOM: they begin the first line"
				matched > 0 ifTrue: [ self feedBytes: bomBytes from: 1 count: matched ] ] ].
	^ i
]

{ #category : 'private' }
WebFetchEventParser >> feedBytes: aByteArray from: start count: anInteger [
	| i |
	i := start.
	[ i <= anInteger ] whileTrue: [
		| byte |
		byte := aByteArray at: i.
		(skipLf and: [ byte = 10 ])
			ifTrue: [
				skipLf := false.
				i := i + 1 ]
			ifFalse: [
				skipLf := false.
				(phase == #value or: [ phase == #skip ])
					ifTrue: [ i := self scanValue: aByteArray from: i count: anInteger ]
					ifFalse: [
						self stepByte: byte.
						i := i + 1 ] ] ]
]

{ #category : 'testing' }
WebFetchEventParser >> hasEvents [
	^ events notEmpty
]

{ #category : 'initialization' }
WebFetchEventParser >> initialize [
	super initialize.
	maximumEventSize := 1048576.
	name := ByteArray new: 5.
	nameSize := 0.
	data := ByteArray new: 1024.
	dataSize := 0.
	small := ByteArray new: self class maximumFieldSize.
	smallSize := 0.
	eventType := ''.
	lastEventId := ''.
	idBuffer := ''.
	events := OrderedCollection new.
	self startConnection
]

{ #category : 'accessing' }
WebFetchEventParser >> lastEventId [
	"The last event ID of the stream: the id buffer at the last dispatch"

	^ lastEventId
]

{ #category : 'accessing' }
WebFetchEventParser >> lastEventId: aString [
	"The id to resume from, before the first body"

	lastEventId := aString.
	idBuffer := aString
]

{ #category : 'private' }
WebFetchEventParser >> matchName [
	"At the colon, or at the end of a line without one: the field of the name, or skip an unknown one"

	field := nil.
	nameSize = 4 ifTrue: [
		(self nameIs: #[ 100 97 116 97 ]) ifTrue: [ field := #data ] ].
	nameSize = 5 ifTrue: [
		(self nameIs: #[ 101 118 101 110 116 ]) ifTrue: [ field := #event ].
		(self nameIs: #[ 114 101 116 114 121 ]) ifTrue: [ field := #retry ] ].
	nameSize = 2 ifTrue: [
		(self nameIs: #[ 105 100 ]) ifTrue: [ field := #id ] ].
	field ifNil: [
		phase := #skip.
		^ self ].
	phase := #value.
	spacePending := true.
	smallSize := 0.
	digits := 0.
	digitCount := 0
]

{ #category : 'accessing' }
WebFetchEventParser >> maximumEventSize [
	^ maximumEventSize
]

{ #category : 'accessing' }
WebFetchEventParser >> maximumEventSize: anInteger [
	"The most bytes of the data of one event, with the line feeds between its lines"

	maximumEventSize := anInteger
]

{ #category : 'private' }
WebFetchEventParser >> nameIs: aByteArray [
	1 to: nameSize do: [ :i | (name at: i) = (aByteArray at: i) ifFalse: [ ^ false ] ].
	^ true
]

{ #category : 'accessing' }
WebFetchEventParser >> nextEvent [
	"Answer and remove the first dispatched event, or nil"

	events isEmpty ifTrue: [ ^ nil ].
	^ events removeFirst
]

{ #category : 'accessing' }
WebFetchEventParser >> origin [
	^ origin
]

{ #category : 'accessing' }
WebFetchEventParser >> origin: aStringOrNil [
	"The origin given to the events of the body"

	origin := aStringOrNil
]

{ #category : 'private' }
WebFetchEventParser >> scanValue: aByteArray from: start count: anInteger [
	"In a value or a skipped line: take the bytes up to the next line end as one run. Answer the index after them"

	| i end stop |
	i := start.
	spacePending ifTrue: [
		spacePending := false.
		(phase == #value and: [ (aByteArray at: i) = 32 ]) ifTrue: [
			i := i + 1.
			i > anInteger ifTrue: [ ^ i ] ] ].
	end := ByteString findFirstInString: aByteArray inSet: self class lineEnds startingAt: i.
	stop := (end = 0 or: [ end > anInteger ])
		ifTrue: [ anInteger ]
		ifFalse: [ end - 1 ].
	phase == #value ifTrue: [
		field == #data ifTrue: [ self appendData: aByteArray from: i to: stop ].
		(field == #event or: [ field == #id ]) ifTrue: [ self appendSmall: aByteArray from: i to: stop ].
		field == #retry ifTrue: [ self addDigits: aByteArray from: i to: stop ] ].
	stop = anInteger ifTrue: [ ^ anInteger + 1 ].
	self endLine.
	skipLf := (aByteArray at: end) = 13.
	^ end + 1
]

{ #category : 'private' }
WebFetchEventParser >> signalDataTooLarge [
	phase := #skip.
	WebFetchTooLarge signal: 'event data longer than ' , maximumEventSize printString , ' bytes'
]

{ #category : 'parsing' }
WebFetchEventParser >> startConnection [
	"Before each body: a new stream, whose id buffer starts from the last event ID"

	bom := 0.
	skipLf := false.
	phase := #start.
	spacePending := false.
	dataSize := 0.
	eventType := ''.
	smallSize := 0.
	idBuffer := lastEventId
]

{ #category : 'private' }
WebFetchEventParser >> stepByte: aByte [
	"A byte at the start of a line or in a field name"

	(aByte = 10 or: [ aByte = 13 ]) ifTrue: [
		self endLine.
		skipLf := aByte = 13.
		^ self ].
	phase == #start ifTrue: [
		aByte = 58 ifTrue: [
			"a comment"
			phase := #skip.
			^ self ].
		phase := #name.
		nameSize := 1.
		name at: 1 put: aByte.
		^ self ].
	aByte = 58 ifTrue: [ ^ self matchName ].
	nameSize = name size ifTrue: [
		"no field has a longer name"
		phase := #skip.
		^ self ].
	nameSize := nameSize + 1.
	name at: nameSize put: aByte
]

{ #category : 'accessing' }
WebFetchEventParser >> takeRetry [
	"Answer the last valid retry of the stream in milliseconds, or nil, and forget it"

	| value |
	value := retry.
	retry := nil.
	^ value
]
