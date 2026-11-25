"
I am the default `ZnNetworkingUtils` while `WebFetchZinc` is installed. I answer a `WebFetchSocketStream` for http and https where `WebFetch` exists, also while the network is off (its error is then a clean one); all the rest I forward to `previous`, the default before me.
"
Class {
	#name : 'WebFetchNetworkingUtils',
	#superclass : 'ZnNetworkingUtils',
	#instVars : [
		'previous'
	],
	#category : 'WebFetch-Zinc',
	#package : 'WebFetch-Zinc'
}

{ #category : 'installing' }
WebFetchNetworkingUtils class >> install [
	self isInstalled ifFalse: [
		ZnNetworkingUtils default: (self on: ZnNetworkingUtils default) ]
]

{ #category : 'testing' }
WebFetchNetworkingUtils class >> isInstalled [
	^ ZnNetworkingUtils default isKindOf: self
]

{ #category : 'instance creation' }
WebFetchNetworkingUtils class >> on: aZnNetworkingUtils [
	"Not initialized: the inherited initialize sets the classes, and those are of the previous"

	^ self basicNew previous: aZnNetworkingUtils; yourself
]

{ #category : 'installing' }
WebFetchNetworkingUtils class >> uninstall [
	self isInstalled ifTrue: [
		ZnNetworkingUtils default: ZnNetworkingUtils default previous ]
]

{ #category : 'class initialization' }
WebFetchNetworkingUtils class >> unload [
	self uninstall.
	super unload
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> bufferSize [
	^ previous bufferSize
]

{ #category : 'private' }
WebFetchNetworkingUtils >> followsRedirectsFrom: aContext [
	"Answer what the ZnClient that asks for the connection wants; true when it is not a ZnClient"

	| context |
	context := aContext.
	8 timesRepeat: [
		context ifNil: [ ^ true ].
		(context receiver isKindOf: ZnClient) ifTrue: [ ^ context receiver followRedirects ].
		context := context sender ].
	^ true
]

{ #category : 'testing' }
WebFetchNetworkingUtils >> handles: aUrl [
	"Answer whether aUrl is mine. Not natively, and no web socket"

	^ (#( http https ) includes: aUrl scheme) and: [ WebFetch availability ~= #unavailable ]
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> httpProxyPassword [
	^ previous httpProxyPassword
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> httpProxyPort [
	^ previous httpProxyPort
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> httpProxyServer [
	^ previous httpProxyServer
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> httpProxyUser [
	^ previous httpProxyUser
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> isProxyAuthorizationRequired [
	^ previous isProxyAuthorizationRequired
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> isProxySet [
	^ previous isProxySet
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> previous [
	^ previous
]

{ #category : 'initialization' }
WebFetchNetworkingUtils >> previous: aZnNetworkingUtils [
	previous := aZnNetworkingUtils
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> proxyAuthorizationHeaderValueToUrl: aUrl [
	(self handles: aUrl) ifTrue: [ ^ nil ].
	^ previous proxyAuthorizationHeaderValueToUrl: aUrl
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> proxyUrl [
	^ previous proxyUrl
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> secureSocketStreamClass [
	^ previous secureSocketStreamClass
]

{ #category : 'initialization' }
WebFetchNetworkingUtils >> secureSocketStreamClass: anObject [
	previous secureSocketStreamClass: anObject
]

{ #category : 'public' }
WebFetchNetworkingUtils >> secureSocketStreamOn: socket [
	^ previous secureSocketStreamOn: socket
]

{ #category : 'public' }
WebFetchNetworkingUtils >> serverSocketOn: port [
	^ previous serverSocketOn: port
]

{ #category : 'public' }
WebFetchNetworkingUtils >> serverSocketOn: port interface: address [
	^ previous serverSocketOn: port interface: address
]

{ #category : 'private' }
WebFetchNetworkingUtils >> setServerSocketOptions: socket [
	previous setServerSocketOptions: socket
]

{ #category : 'private' }
WebFetchNetworkingUtils >> setSocketStreamParameters: stream [
	previous setSocketStreamParameters: stream
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> shouldProxyUrl: aUrl [
	"The host has its own proxy"

	^ (self handles: aUrl) not and: [ previous shouldProxyUrl: aUrl ]
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> socketStreamClass [
	^ previous socketStreamClass
]

{ #category : 'initialization' }
WebFetchNetworkingUtils >> socketStreamClass: anObject [
	previous socketStreamClass: anObject
]

{ #category : 'public' }
WebFetchNetworkingUtils >> socketStreamOn: socket [
	^ previous socketStreamOn: socket
]

{ #category : 'proxy' }
WebFetchNetworkingUtils >> socketStreamToProxy [
	^ previous socketStreamToProxy
]

{ #category : 'public' }
WebFetchNetworkingUtils >> socketStreamToUrl: aUrl [
	(self handles: aUrl) ifFalse: [ ^ previous socketStreamToUrl: aUrl ].
	aUrl hasHost ifFalse: [ ZnMissingHost signal ].
	^ (WebFetchSocketStream on: aUrl)
		timeout: self timeout;
		followRedirects: (self followsRedirectsFrom: thisContext sender);
		yourself
]

{ #category : 'public' }
WebFetchNetworkingUtils >> socketStreamToUrlDirectly: url [
	^ previous socketStreamToUrlDirectly: url
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> sslSessionClass [
	^ previous sslSessionClass
]

{ #category : 'initialization' }
WebFetchNetworkingUtils >> sslSessionClass: anObject [
	previous sslSessionClass: anObject
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> streamClassForScheme: scheme [
	^ previous streamClassForScheme: scheme
]

{ #category : 'accessing' }
WebFetchNetworkingUtils >> timeout [
	^ previous timeout
]
