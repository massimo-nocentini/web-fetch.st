Extension { #name : 'WebFetchCall' }

{ #category : '*WebFetch-Tests' }
WebFetchCall >> closer [
	^ closer
]

{ #category : '*WebFetch-Tests' }
WebFetchCall >> semaphore [
	^ semaphore
]

{ #category : '*WebFetch-Tests' }
WebFetchCall >> session: aSession [
	session := aSession.
	closer ifNotNil: [ closer session: aSession ]
]
