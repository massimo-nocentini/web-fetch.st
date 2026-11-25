"
I stand for an FFI callback that is being evaluated: my context is what `WebFetchCall class>>isInCallback` looks for.
"
Class {
	#name : 'WebFetchTestCallback',
	#superclass : 'TFCallbackInvocation',
	#category : 'WebFetch-Tests-Host',
	#package : 'WebFetch-Tests',
	#tag : 'Host'
}

{ #category : 'evaluating' }
WebFetchTestCallback >> evaluate: aBlock [
	^ aBlock value
]
