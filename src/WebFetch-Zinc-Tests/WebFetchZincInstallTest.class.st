"
I test installing and uninstalling the adapter, and what it leaves to the default before it.
"
Class {
	#name : 'WebFetchZincInstallTest',
	#superclass : 'WebFetchZincTestCase',
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'tests' }
WebFetchZincInstallTest >> testEveryMessageIsForwarded [
	"A message of ZnNetworkingUtils that the adapter inherits would not reach the default before it"

	| missing |
	missing := ZnNetworkingUtils selectors reject: [ :each | WebFetchNetworkingUtils includesSelector: each ].
	self assert: (missing copyWithout: #initialize) isEmpty
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testHandles [
	| utils |
	utils := ZnNetworkingUtils default.
	#( 'http://h/' 'https://h/' ) do: [ :each |
		self assert: (utils handles: each asZnUrl).
		host availability: 2.
		self assert: (utils handles: each asZnUrl).
		host availability: 0.
		self deny: (utils handles: each asZnUrl).
		host availability: 1 ].
	#( 'ws://h/' 'wss://h/' 'ftp://h/' ) do: [ :each |
		self deny: (utils handles: each asZnUrl) ].
	self deny: (utils handles: ZnUrl new)
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testInstallTwice [
	| installed |
	installed := ZnNetworkingUtils default.
	WebFetchZinc install.
	self assert: ZnNetworkingUtils default identicalTo: installed.
	self assert: WebFetchZinc isInstalled.
	WebFetchZinc uninstall.
	self assert: ZnNetworkingUtils default identicalTo: installed previous.
	self deny: WebFetchZinc isInstalled.
	WebFetchZinc uninstall.
	self assert: ZnNetworkingUtils default identicalTo: installed previous
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testMissingHost [
	self should: [ ZnNetworkingUtils socketStreamToUrl: (ZnUrl new scheme: #http; yourself) ] raise: ZnMissingHost
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testNoProxy [
	"The proxy of the image is not for the URLs of the adapter"

	| proxy |
	ZnNetworkingUtils default previous: WebFetchZincProxyUtils new.
	proxy := ZnNetworkingUtils default.
	self deny: (proxy shouldProxyUrl: 'http://h/' asZnUrl).
	self assert: (proxy proxyAuthorizationHeaderValueToUrl: 'http://h/' asZnUrl) isNil.
	self assert: (proxy shouldProxyUrl: 'ws://h/' asZnUrl).
	self assert: (proxy proxyAuthorizationHeaderValueToUrl: 'ws://h/' asZnUrl) equals: 'Basic x'.
	self should: [ ZnNetworkingUtils socketStreamToUrl: 'ws://h/' asZnUrl ] raise: ZnTooManyRedirects
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testUninstallLeavesAnother [
	| other |
	other := ZnNetworkingUtils new.
	ZnNetworkingUtils default: other.
	WebFetchZinc uninstall.
	self assert: ZnNetworkingUtils default identicalTo: other
]

{ #category : 'tests' }
WebFetchZincInstallTest >> testZincIsUnchanged [
	self assert: (WebFetchZinc package extensionMethods) isEmpty
]
