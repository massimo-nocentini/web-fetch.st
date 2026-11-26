Extension { #name : 'WebFetchEventParser' }

{ #category : '*WebFetch-Tests' }
WebFetchEventParser >> bufferSizes [
	"The sizes of the data buffer and of the buffer of id and event values"

	^ { data size. small size }
]
