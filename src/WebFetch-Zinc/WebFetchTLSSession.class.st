"
I stand for the TLS session that `ZnClient` sets up on an https connection: the host does the TLS, and verifies the certificates.
"
Class {
	#name : 'WebFetchTLSSession',
	#superclass : 'Object',
	#category : 'WebFetch-Zinc',
	#package : 'WebFetch-Zinc'
}

{ #category : 'accessing' }
WebFetchTLSSession >> certificateName: aString [
	"A client certificate of the image cannot be used"
]

{ #category : 'accessing' }
WebFetchTLSSession >> certificateVerificationState [
	"Verified: else there would be no answer"

	^ 0
]

{ #category : 'accessing' }
WebFetchTLSSession >> serverName: aString [
	"The host knows it from the URL"
]
