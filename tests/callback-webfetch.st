"callback-webfetch.st - requests and event sources while a real FFI callback runs

	WEB_FETCH_SERVER=http://127.0.0.1:<port> pharo --headless X.image --no-default-preferences st --quit callback-webfetch.st

 With the server of run-webfetch.st, on a wasm VM with the FFI and an image that has WebFetch and
 WebFetch-Zinc. The callback is the comparison of qsort. It prints each check that fails, then

	callback: <passed> of <all>"

| out environment base fetch inCallback got passed all check done stream read zinc |
out := [ :text | Stdio stdout nextPutAll: text; nextPutAll: OSPlatform current lineEnding; flush ].
environment := OSEnvironment current.
base := environment at: 'WEB_FETCH_SERVER' ifAbsent: [ 'webfetch.lane' asFileReference contents substrings first ].
fetch := Smalltalk globals at: #WebFetch.
zinc := Smalltalk globals at: #WebFetchZinc.
((FFILibrary << #WebFetchCallbackLibC) package: 'WebFetchCallback') install.
(Smalltalk globals at: #WebFetchCallbackLibC) compile: 'unixLibraryName
	^ ''libc.so.6'''.
((Object << #WebFetchCallback) package: 'WebFetchCallback') install.
(Smalltalk globals at: #WebFetchCallback) compile: 'qsort: base count: n size: s with: c
	^ self ffiCall: #(void qsort(ByteArray base, size_t n, size_t s, FFICallback c)) library: WebFetchCallbackLibC'.
inCallback := [ :block |
	(Smalltalk globals at: #WebFetchCallback) new
		qsort: (ByteArray new: 8)
		count: 2
		size: 4
		with: (FFICallback signature: #( int #( void * a #, void * b ) ) block: [ :a :b | block value. 0 ]) ].
passed := all := 0.
check := [ :name :value :expected |
	all := all + 1.
	value = expected
		ifTrue: [ passed := passed + 1 ]
		ifFalse: [ out value: name , ': ' , value printString ] ].
got := [ :block | [ block value ] on: Error do: [ :error | error class name asString ] ].

inCallback value: [ read := got value: [ fetch get: base , '/hello' ] ].
check value: 'get: in the callback' value: read value: 'WebFetchInCallback'.
inCallback value: [ read := got value: [ (fetch request: base , '/hello') start response ] ].
check value: 'response in the callback' value: read value: 'WebFetchInCallback'.
fetch abortAll.

"an event source: next of a new one signals before it makes a request; start works, its events come
 after the callback (two events, then the 204 of the server)"
inCallback value: [
	read := (got value: [ (fetch eventSource: base , '/sse?key=callback-next&end=hang') next ])
		, ', open ' , (Smalltalk globals at: #WebFetchCall) openCount printString ].
check value: 'next of an event source in the callback' value: read value: 'WebFetchInCallback, open 0'.
done := Semaphore new.
read := OrderedCollection new.
inCallback value: [
	((fetch eventSource: base , '/sse?key=callback-start&n=2&until=2&retry=50')
		onEvent: [ :event | read add: event lastEventId ];
		onError: [ :error |
			read add: error class name asString.
			done signal ];
		yourself) start ].
done waitTimeoutSeconds: 5.
check value: 'start of an event source in the callback' value: read asArray value: #( '1' '2' 'WebFetchBadResponse' ).
fetch abortAll.

"whenDone: in a callback that lets its process run, and in one that does not"
{ 50. 0 } do: [ :milliseconds |
	done := Semaphore new.
	read := 'nothing'.
	inCallback value: [
		(fetch request: base , '/hello') start
			whenDone: [ :response | read := response contents. done signal ]
			ifError: [ :error | read := error class name asString. done signal ].
		milliseconds > 0 ifTrue: [ (Delay forMilliseconds: milliseconds) wait ] ].
	done waitTimeoutSeconds: 5.
	check value: 'whenDone: in a callback of ' , milliseconds printString , ' ms' value: read value: 'hello' ].

"other processes, that begin to wait in the callback"
{
	'get:' -> [ (fetch get: base , '/hello') contents ].
	'stream:' -> [ (fetch request: base , '/dribble?ticks=3&ms=20') stream: [ :each | each upToEnd asString ] ].
	'ZnClient' -> [
		zinc install.
		[ ZnClient new get: base , '/hello' ] ensure: [ zinc uninstall ] ] } do: [ :each |
	done := Semaphore new.
	read := 'nothing'.
	[
		(Delay forMilliseconds: 20) wait.
		read := got value: each value.
		done signal ] fork.
	inCallback value: [ (Delay forMilliseconds: 100) wait ].
	done waitTimeoutSeconds: 5.
	check value: each key , ' of another process' value: read value: (each key = 'stream:' ifTrue: [ 'tick0tick1tick2' ] ifFalse: [ 'hello' ]) ].

"others that wait already, while callbacks come and go"
{
	'get:' -> [ (fetch get: base , '/dribble?ticks=10&ms=50') contents size ].
	'stream:' -> [
		| size |
		size := 0.
		(fetch request: base , '/dribble?ticks=10&ms=50') stream: [ :each |
			[ each atEnd ] whileFalse: [
				size := size + (each next: 5) size.
				(Delay forMilliseconds: 7) wait ] ].
		size ] } do: [ :each |
	done := false.
	read := 'nothing'.
	[
		read := got value: each value.
		done := true ] fork.
	1 to: 200 do: [ :i |
		done ifFalse: [
			inCallback value: [ (Delay forMilliseconds: 10) wait ].
			(Delay forMilliseconds: 10) wait ] ].
	check value: each key , ' while callbacks come and go' value: read value: 50 ].
out value: 'callback: ' , passed printString , ' of ' , all printString
