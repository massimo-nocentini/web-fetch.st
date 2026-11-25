"
I test that nothing changes on a native VM: installed, the adapter leaves http to the sockets. I talk to a `ZnServer` of my own.
"
Class {
	#name : 'WebFetchZincNativeTest',
	#superclass : 'TestCase',
	#instVars : [
		'previousUtils'
	],
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'running' }
WebFetchZincNativeTest >> setUp [
	super setUp.
	previousUtils := ZnNetworkingUtils default.
	WebFetchZinc install
]

{ #category : 'running' }
WebFetchZincNativeTest >> tearDown [
	previousUtils ifNotNil: [ ZnNetworkingUtils default: previousUtils ].
	super tearDown
]

{ #category : 'tests' }
WebFetchZincNativeTest >> testSockets [
	| server client |
	WebFetch availability == #unavailable ifFalse: [ ^ self skip: 'WebFetchPlugin is present' ].
	server := ZnServer on: 0.
	server loggingOff; onRequestRespond: [ :request | ZnResponse ok: (ZnEntity text: request uri pathPrintString) ].
	server start.
	[
		self waitUntilRunning: server.
		client := ZnClient new timeout: 5; yourself.
		self assert: (client get: 'http://localhost:' , server port asString , '/a/b') equals: '/a/b'.
		self assert: client connection class equals: previousUtils socketStreamClass.
		self assert: client isConnected.
		self assert: (client get: 'http://localhost:' , server port asString , '/c') equals: '/c'.
		client close ] ensure: [ server stop ]
]

{ #category : 'helpers' }
WebFetchZincNativeTest >> waitUntilRunning: aServer [
	50 timesRepeat: [
		(aServer isRunning and: [ aServer isListening ]) ifTrue: [ ^ self ].
		(Delay forMilliseconds: 20) wait ]
]
