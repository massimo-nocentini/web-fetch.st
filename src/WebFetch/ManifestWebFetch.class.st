"
`WebFetch` provides asynchronous and blocking HTTP(S) fetch for Pharo 12 to 15 running on WebAssembly, backed by `WebFetchPlugin` and `WebHostPlugin` in the VM.

It has no external package dependency. Off WebAssembly, `WebFetch availability` answers `#unavailable` and `WebFetchHost default:` can be replaced by `WebFetchTestHost` for pure-Smalltalk tests.

In the UI process, blocking messages (`fetch`, `get:`, `post:body:type:`, `stream:`, `wait`, `response`) freeze the world until they finish or time out, just as a native socket does; tools should use `start` with `whenDone:ifError:` and `UIManager default defer:` for UI updates.

## Tags

- `Core`: `WebFetch` facade, `WebFetchRequest`, `WebFetchCall`, `WebFetchResponse`, `WebFetchBodyStream`, `WebFetchHost`, `WebFetchCloser`, `WebFetchEventSource` (Server-Sent Events), `WebFetchEventParser` (the parser of event streams) and `WebFetchEvent`.
- `Errors`: `WebFetchError` and its subclasses.
"
Class {
	#name : 'ManifestWebFetch',
	#superclass : 'PackageManifest',
	#category : 'WebFetch-Manifest',
	#package : 'WebFetch',
	#tag : 'Manifest'
}
