"
I am the base of the tests of the Zinc adapter on the `WebFetchTestHost`: the adapter is installed in `setUp`, and what Zinc used before comes back in `tearDown`.
"
Class {
	#name : 'WebFetchZincTestCase',
	#superclass : 'WebFetchTestCase',
	#instVars : [
		'previousUtils'
	],
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'testing' }
WebFetchZincTestCase class >> isAbstract [
	^ self == WebFetchZincTestCase
]

{ #category : 'helpers' }
WebFetchZincTestCase >> headerOf: aName [
	"Answer the header of the last request, or nil"

	^ ((host lastRequest at: #headers)
		detect: [ :each | each key asLowercase = aName asLowercase ]
		ifNone: [ nil ]) ifNotNil: [ :found | found value ]
]

{ #category : 'helpers' }
WebFetchZincTestCase >> requestOf: aString [
	"Answer a stream on which aString, with LF for CRLF, was written"

	^ (WebFetchSocketStream on: 'http://host:8080/ignored' asZnUrl)
		timeout: 2;
		nextPutAll: (aString copyReplaceAll: String lf with: String crlf) asByteArray;
		flush;
		yourself
]

{ #category : 'running' }
WebFetchZincTestCase >> setUp [
	super setUp.
	previousUtils := ZnNetworkingUtils default.
	WebFetchZinc uninstall.
	WebFetchZinc install
]

{ #category : 'running' }
WebFetchZincTestCase >> tearDown [
	previousUtils ifNotNil: [ ZnNetworkingUtils default: previousUtils ].
	super tearDown
]
