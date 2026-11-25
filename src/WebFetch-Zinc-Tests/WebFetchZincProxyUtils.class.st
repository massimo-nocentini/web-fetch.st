"
I am a `ZnNetworkingUtils` with a proxy, whose connections are recognized by an unlikely error.
"
Class {
	#name : 'WebFetchZincProxyUtils',
	#superclass : 'ZnNetworkingUtils',
	#category : 'WebFetch-Zinc-Tests',
	#package : 'WebFetch-Zinc-Tests'
}

{ #category : 'proxy' }
WebFetchZincProxyUtils >> proxyAuthorizationHeaderValueToUrl: url [
	^ 'Basic x'
]

{ #category : 'proxy' }
WebFetchZincProxyUtils >> shouldProxyUrl: url [
	^ true
]

{ #category : 'public' }
WebFetchZincProxyUtils >> socketStreamToUrl: url [
	ZnTooManyRedirects signal
]
