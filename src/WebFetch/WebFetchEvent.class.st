"
I am one event of an event stream (`text/event-stream`), as `WebFetchEventParser` dispatches it.

- `type`: the String of the field `event`, or `'message'` when the stream named none;
- `data`: a String, the values of the event's `data` fields joined by line feeds;
- `lastEventId`: the last event ID of the stream when I was dispatched, a String, possibly empty;
- `origin`: `scheme://host[:port]` of the final URL of the answer that carried me, or nil.
"
Class {
	#name : 'WebFetchEvent',
	#superclass : 'Object',
	#instVars : [
		'type',
		'data',
		'lastEventId',
		'origin'
	],
	#category : 'WebFetch-Core',
	#package : 'WebFetch',
	#tag : 'Core'
}

{ #category : 'instance creation' }
WebFetchEvent class >> type: aTypeString data: aDataString lastEventId: anIdString origin: anOriginStringOrNil [
	^ self new
		setType: aTypeString
		data: aDataString
		lastEventId: anIdString
		origin: anOriginStringOrNil;
		yourself
]

{ #category : 'accessing' }
WebFetchEvent >> data [
	^ data
]

{ #category : 'accessing' }
WebFetchEvent >> lastEventId [
	^ lastEventId
]

{ #category : 'accessing' }
WebFetchEvent >> origin [
	^ origin
]

{ #category : 'printing' }
WebFetchEvent >> printOn: aStream [
	"Show the type and the first 40 characters of the data"

	aStream
		nextPutAll: self class name;
		nextPut: $(;
		nextPutAll: type;
		space.
	data size > 40
		ifTrue: [ aStream print: (data first: 40) , '...' ]
		ifFalse: [ aStream print: data ].
	aStream nextPut: $)
]

{ #category : 'initialization' }
WebFetchEvent >> setType: aTypeString data: aDataString lastEventId: anIdString origin: anOriginStringOrNil [
	type := aTypeString.
	data := aDataString.
	lastEventId := anIdString.
	origin := anOriginStringOrNil
]

{ #category : 'accessing' }
WebFetchEvent >> type [
	^ type
]
