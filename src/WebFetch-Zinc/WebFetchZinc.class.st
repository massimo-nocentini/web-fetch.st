"
I install the Zinc adapter: after `WebFetchZinc install`, `ZnClient` and all that use it (`ZnEasy`, `asZnUrl retrieveContents`, ...) do their http and https exchanges with `WebFetch` where it exists, and with sockets as before elsewhere. Loading my package does not install it; `WebFetchZinc uninstall` restores what was before.

It changes no method of Zinc or Zodiac: `WebFetchNetworkingUtils` becomes the default of `ZnNetworkingUtils`, and gives Zinc a `WebFetchSocketStream` as its connection.

What differs from a socket:

- The browser follows the redirects: Zinc sees the last answer, with its URL in the header `X-WebFetch-Url`; `request url` stays the first, and `maxNumberOfRedirects` does not apply. With `dontFollowRedirects` node gives the 3xx answer, a browser fails.
- No cookies and no proxy of the image; a client certificate is ignored; the certificates are checked by the host.
- The host sets Accept-Encoding, Host, Connection and, in a browser, User-Agent; those of Zinc are dropped. A compressed answer comes decompressed, without Content-Length.
- In a browser Authorization, a JSON body or a custom header cost a CORS preflight, and a refusal has no reason. The API and raw servers of GitHub allow it, the zip archives of codeload do not.
- An upload is gathered whole before it is sent, at most 64 MiB; a GET with a body is refused.
- One exchange per connection.
- Waiting in an FFI callback signals `WebFetchInCallback`. In the UI process it freezes the world, as a socket does.

Errors: `ConnectionTimedOut` after the timeout of the client without data, `WebFetchZnNetworkError` (a `NetworkError`) when the network fails or is off, other `WebFetchError`s as they are.
"
Class {
	#name : 'WebFetchZinc',
	#superclass : 'Object',
	#category : 'WebFetch-Zinc',
	#package : 'WebFetch-Zinc'
}

{ #category : 'installing' }
WebFetchZinc class >> install [
	"Let Zinc use WebFetch. Twice is once"

	WebFetchNetworkingUtils install
]

{ #category : 'testing' }
WebFetchZinc class >> isInstalled [
	^ WebFetchNetworkingUtils isInstalled
]

{ #category : 'installing' }
WebFetchZinc class >> uninstall [
	"Restore what Zinc used before. Does nothing when something else was set since"

	WebFetchNetworkingUtils uninstall
]
