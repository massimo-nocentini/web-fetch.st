"
I am signalled by `WebFetchEventSource` when an answer is no event stream: its status is not 200 (204 included, which a server sends to stop its clients), or the media type of its `Content-Type` is not `text/event-stream`. My `response` has the status and the headers, and in `rawContents` at most 64 KiB of the body.
"
Class {
	#name : 'WebFetchBadResponse',
	#superclass : 'WebFetchError',
	#instVars : [
		'response'
	],
	#category : 'WebFetch-Errors',
	#package : 'WebFetch',
	#tag : 'Errors'
}

{ #category : 'accessing' }
WebFetchBadResponse class >> defaultKind [
	^ #response
]

{ #category : 'accessing' }
WebFetchBadResponse >> response [
	"The WebFetchResponse that was refused, or nil"

	^ response
]

{ #category : 'accessing' }
WebFetchBadResponse >> response: aWebFetchResponse [
	response := aWebFetchResponse
]
