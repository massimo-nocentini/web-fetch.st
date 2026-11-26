# web-fetch.st

HTTP and HTTPS for Pharo 12 to 15 on WebAssembly, with the `fetch` of the browser or of node, Server-Sent Events over it, WebSocket client connections with the `WebSocket` of the host, and an adapter for Zinc.

The work is done by the WebFetchPlugin of the VM of [massimo-nocentini/pharo-vm](https://github.com/massimo-nocentini/pharo-vm) (its `docs/WebFetch.md` is the contract); the package waits as Smalltalk code does, on a semaphore, while the VM and the other processes go on.

- `WebFetch`: class-side facade (`get:`, `post:body:type:`, `request:`, `eventSource:`, `availability`, `isAvailable`, `abortAll`).
- `WebFetchRequest`: reusable request builder (`fetch`, `start`, `stream:`, `eventSource`).
- `WebFetchCall`: one exchange and its future (`wait`, `waitTimeout:`, `response`, `whenDone:ifError:`, `abort`).
- `WebFetchResponse`: status, reason, final URL, headers, `rawContents` and decoded `contents`.
- `WebFetchBodyStream`: binary read stream over a streaming response body.
- `WebFetchEventSource`: Server-Sent Events (`text/event-stream`), reconnecting, read with `next` or `do:`, or by a forked reader (`start`); its events are `WebFetchEvent`s.
- `WebFetchZinc`: opt-in `ZnNetworkingUtils` adapter (`WebFetch-Zinc`) that routes `ZnClient`, `ZnEasy` and `asZnUrl retrieveContents` through `WebFetch`.
- `WebFetchWebSocket`: WebSocket client connections (`WebFetch-WebSocket`) by the `WebSocket` of the browser or of node, through the WebSocketPlugin of the same VM (its `docs/WebSocket.md`): `connect:`, `next`, `sendText:`, `sendBytes:`, `whenMessage:whenClosed:`, `close`.

`WebFetch` and `WebFetch-WebSocket` depend on no package that is not in the image, and change no class of it; `WebFetch-Zinc` changes no method of Zinc or Zodiac.

## Try it

The site of the VM, <https://massimo-nocentini.github.io/pharo-vm/>, has WebFetch already loaded in the image "Pharo 15 (batteries)", the default of its world page: the packages of the groups `default`, `Zinc`, `ZincTests` and `WebSocket`, with the Zinc adapter loaded but not installed. In its Console, Notebook or world, evaluate:

```smalltalk
(WebFetch get: 'https://api.github.com/zen') contents
```

The Settings dialog of the pages has the switch "Smalltalk code may use the network", on by default. With it off, `WebFetch availability` answers `#off` and requests signal `WebFetchNetworkOff`, and so do the WebSockets of `WebFetch-WebSocket` (those open fail); git and the WebSockets of the SocketPlugin are refused too. While it is on, the WebSockets of an image talk to their servers with the cookies that the browser holds for them (see WebSocket, Security).

## Requirements

- Pharo 12, 13, 14 or 15.
- A WebAssembly Pharo VM built with `WebFetchPlugin` (Console, Notebook, World or the node VM), from the branch `pharo-12` of [massimo-nocentini/pharo-vm](https://github.com/massimo-nocentini/pharo-vm); `WebFetch-WebSocket` needs its `WebSocketPlugin` too, and on a VM without it answers `#unavailable`.
- On a native VM, the packages load normally; `WebFetch availability` answers `#unavailable` and every request signals `WebFetchUnavailable`. Unit tests run natively using `WebFetchTestHost`.

## Loading

From GitHub:

```smalltalk
Metacello new
	baseline: 'WebFetch';
	repository: 'github://massimo-nocentini/web-fetch.st:master/src';
	load: #( 'Core' )
```

From a local checkout of `web-fetch.st`:

```smalltalk
Metacello new
	baseline: 'WebFetch';
	repository: 'tonel:///path/to/web-fetch.st/src';
	load: #( 'Core' )
```

In the web pages, the `github://` form does not work: Metacello downloads a zip from `codeload.github.com`, which answers no CORS request. There, use the batteries image, or the `tonel://` form on a clone made with Iceberg.

Groups of `BaselineOfWebFetch`:

- `Core`: `WebFetch`
- `Tests`: `WebFetch-Tests` (includes `WebFetchTestHost`)
- `Zinc`: `WebFetch-Zinc`
- `ZincTests`: `WebFetch-Zinc-Tests`
- `WebSocket`: `WebFetch-WebSocket` (requires `WebFetch`)
- `WebSocketTests`: `WebFetch-WebSocket-Tests` (includes `WebFetchWebSocketTestHost`)
- `default`: `Core` and `Tests`

From the command line, `tests/load-webfetch.st` loads the groups named in `WEB_FETCH_GROUPS` (default `'Core Tests Zinc ZincTests'`; `'Core Tests WebSocket WebSocketTests'` for the WebSockets) from `WEB_FETCH_DIR` and checks for undeclared variables before saving:

```sh
WEB_FETCH_DIR=/path/to/web-fetch.st \
pharo --headless Pharo.image --no-default-preferences st --save --quit tests/load-webfetch.st
```

## API

### Availability and simple requests

```smalltalk
WebFetch availability
"=> #ready (or #off, or #unavailable)"

WebFetch isAvailable
"=> true"

(WebFetch get: 'https://api.github.com/zen') contents

WebFetch post: url body: '{"a":1}' type: 'application/json'
```

An HTTP error status (such as 404 or 500) is returned as a `WebFetchResponse` whose `isSuccess` is `false`.

`response contents` decodes textual content types (`text/*`, `application/json`, `*+json`, `application/xml`, `*+xml`, `application/javascript`, `application/x-javascript`, `application/ecmascript`) using the `Content-Type` charset (UTF-8 by default, stripping a leading UTF-8 BOM) and returns `rawContents` (`ByteArray`) for binary types or undecodable bytes.

### Requests with options

`WebFetchRequest` is reusable: starting or fetching it never mutates it.

```smalltalk
| req resp |
req := (WebFetch request: 'https://example.org/items/1')
	method: #PUT;
	headerAt: 'X-Token' put: 'abc';
	body: 'payload';
	timeout: 10 seconds;
	maximumBodySize: 10e6;
	dontFollowRedirects;
	yourself.
resp := req fetch.
resp status.
resp headerAt: 'Content-Type' ifAbsent: [ '' ].
resp headersDo: [ :name :value | ... ].
```

`headerAt:put:` replaces case-insensitively while preserving header order. A `String` body without an explicit `Content-Type` header is sent as UTF-8 with `Content-Type: text/plain;charset=UTF-8`; a `ByteArray` body adds no `Content-Type`.

### Asynchronous calls and futures

```smalltalk
| call |
call := (WebFetch request: url) start.
call isDone.
call waitTimeout: 5 seconds.
call response contents.
```

`whenDone:ifError:` forks one process at the caller's priority (`Processor activePriority`) and evaluates the blocks outside its own error handler:

```smalltalk
call := (WebFetch request: url) start.
call
	whenDone: [ :resp | UIManager default defer: [ ... ] ]
	ifError: [ :err | UIManager default defer: [ ... ] ].
```

`call abort` cancels a single call; `WebFetch abortAll` aborts all open calls.

TaskIt `future` works without extra glue on Pharo 12 to 15:

```smalltalk
([ WebFetch get: url ] future) synchronizeTimeout: 5 seconds
```

### Streaming

`stream:` opens a `WebFetchBodyStream` (a binary read stream with a 1 MiB back-pressure window, not bounded by `maximumBodySize`), passes it to the block, and closes the call when the block returns or unwinds:

```smalltalk
(WebFetch request: url) stream: [ :stream |
	stream response status.
	stream peek.
	stream next.
	stream next: 1024.
	stream upToEnd ]
```

`WebFetchBodyStream` also understands `atEnd`, `readInto:startingAt:count:`, `do:`, `isBinary`, `isStream` and `close`. Closing before EOF aborts the request and subsequent reads signal `WebFetchAborted`; closing after EOF leaves `next` answering `nil`.

### Server-Sent Events

`WebFetchEventSource` reads an event stream (`text/event-stream`) as the `EventSource` of a browser does: it parses its events as section 9.2 of the WHATWG HTML standard says, and connects again, with `Last-Event-ID`, when a body ends or breaks. Each connection is one streaming request, so it works in the pages and in node alike.

```smalltalk
"The first three events of a stream, in the process of the caller"
| source events |
source := WebFetch eventSource: 'https://echo.websocket.org/.sse'.
events := OrderedCollection new.
[ [ events size < 3 ] whileTrue: [ events add: source next ] ] ensure: [ source close ].
events collect: [ :each | each type -> each data ]

"A stream of answers of a POST: not reconnected, since it is no GET"
((WebFetch request: url)
	method: #POST;
	headerAt: 'Content-Type' put: 'application/json';
	body: '{"stream":true}';
	eventSource)
	do: [ :event | Transcript show: (STONJSON fromString: event data) printString; cr ]
```

A `WebFetchEvent` has a `type` (`'message'` when the stream named none), its `data` (its data lines joined by line feeds), the `lastEventId` of the stream when it came, and the `origin` of the answer.

- `next` answers the next event, waiting through reconnections; nil once the source is closed (by `close`, or by the end of a body when it does not reconnect); and signals the error that closed it, after the events that came before that error.
- `nextTimeout: aDuration` also answers nil when the time passes, and leaves the source as it was. `nextTimeout: 0 seconds` never waits: a stepping morph can poll with it.
- `do: aBlock` evaluates aBlock with each event until `next` answers nil, and closes the source when it returns or unwinds, as `stream:` closes its call.
- `open` connects and waits until the source is open; it is optional, since `next` connects.
- `close` comes from any process, and drops the events not yet read.
- `readyState` is `#connecting`, `#open` or `#closed`; `error` is the error that closed the source, `response` the answer of the last connection, `connections` how many were made.

One process reads. For tools and the UI, `start` forks the reader instead, at the priority of the caller, and answers its process:

```smalltalk
source := (WebFetch eventSource: url)
	onOpen: [ :response | ... ];
	onEvent: [ :event | UIManager default defer: [ list add: event data ] ];
	onReconnect: [ :reasonOrNil | ... ];
	onError: [ :error | UIManager default defer: [ self inform: error messageText ] ];
	start.
...
source close
```

`onOpen:` gets the response of each connection that opens, `onEvent:` each event, `onReconnect:` each interruption (nil at the end of a body, else the transient error), and `onError:`, once, the error that closed the source (none after `close`). The blocks run in the reader, outside its handlers: an error of `onEvent:` is the block's own, and opens a debugger. The reader reads the next bytes when a block returns, so a slow block slows the server down (the host stops reading at the window of 1 MiB); a block that defers each event to the UI gives that up, so coalesce there, for example one deferred update for the events of a step. Terminating the reader closes the source.

Settings, given before the first connection (after it they signal an Error); a Duration may also be a Number of seconds:

| Selector | Default | |
|---|---|---|
| `reconnectDelay:` | 3 seconds | the reconnection time, until the server sends `retry:` |
| `minimumReconnectDelay:` | 250 ms | the floor of every delay, `retry:` of the server included |
| `maximumReconnectDelay:` | 60 seconds | the cap of the backoff; a `retry:` above it is still honoured |
| `reconnects:` | nil | nil: a GET reconnects, another method does not; true: every method does; false: none |
| `retriesFirstConnection:` | false | false: an error before the first open is terminal; true: it is retried as later ones are |
| `connectTimeout:` | nil, or the `timeout` of the request | the longest wait for the head of a connection |
| `idleTimeout:` | nil | when no byte came for that long, the connection is dropped and made again (a comment of the server, such as `: ping`, counts) |
| `maximumEventSize:` | 1 MiB | the most bytes of the data of one event (1 to 2^31-2) |
| `lastEventId:` | `''`, or the `Last-Event-ID` of the request | the id to resume from, sent with the first connection already |

To each connection the source adds `Accept: text/event-stream`, unless the request has an `Accept`; `Last-Event-ID`, the UTF-8 of the last id, when it is not empty; and the cache mode `no-store`, so that no answer comes from the HTTP cache of a browser (a cacheable stream would be replayed from it at each reconnection). A VM that does not know that cache mode (flag 2 of `primitiveFetchStart`) refuses it once, and from then on the source sends `Cache-Control: no-cache` instead, which costs a preflight to another origin. A connection has no timeout: the `timeout` of the request becomes `connectTimeout`. The request is copied, never changed; a `Last-Event-ID` header of it becomes `lastEventId`.

**Reconnection.** After the end of a body, a network error, a broken body, `connectTimeout`, `idleTimeout` or `WebFetchTooManyOpen`, a source that reconnects connects again after the reconnection time, which the server changes with `retry:`. The delay is at least `minimumReconnectDelay`, and doubles with each connection in a row that gave no event, up to `maximumReconnectDelay`: 3, 6, 12, 24, 48, 60 seconds with the defaults for a server that is down. A source that does not reconnect closes at the clean end of a body (`next` answers nil), and fails at a broken one, so that a broken answer never looks complete. Before the first open every error is terminal, unless `retriesFirstConnection: true`: in a browser a CORS refusal, a wrong host and a network that is down are the same error, and retrying them for ever would hide the mistake.

**Errors.** These close a source, and `next` signals them (each time it is asked again), or `onError:` gets them:

| Cause | Error |
|---|---|
| a status other than 200 (the 204 with which a server stops its clients included), or a media type other than `text/event-stream` | `WebFetchBadResponse`; its `response` has the status, the headers and at most 64 KiB of the body |
| data over `maximumEventSize`, an `id` or an `event` over 4096 bytes | `WebFetchTooLarge` (it does not reconnect: the server would send the same event again) |
| a transient error when the source does not reconnect, or before its first open | that error |
| an invalid request, a redirect that a browser does not follow; in node, an id with a control character other than a tab, which the fetch of node does not send as `Last-Event-ID` (a browser does) | `WebFetchBadRequest` |
| the network turned off | `WebFetchNetworkOff` |
| the image resumed | `WebFetchSessionEnded` |
| its call aborted by `WebFetchCall abortAll` | `WebFetchAborted` |

`close`, `WebFetchEventSource closeAll` and `WebFetch abortAll` close sources without an error.

**Resuming.** `lastEventId` is the id of the last event that `next`, or the reader, delivered. A new source given it resumes where the code stopped, after `close`, after an error, or in an image that was saved and resumed: `(WebFetch eventSource: url) lastEventId: old lastEventId`.

**What a break loses.** When a body breaks, or a timeout or the network switch ends a connection, the bytes that the host received and the image had not read yet are dropped. A server that honours `Last-Event-ID` sends those events again; a POST API, or a server without ids, does not.

An older VM, one without flag 2, trims header values with `String.prototype.trim`: there an id whose UTF-8 ends with the byte A0 (`à`, `Р`, `†`) reaches the server without that byte.

### Example: the echo server of websocket.org

The [echo server of websocket.org](https://websocket.org/tools/websocket-echo-server/) is a public server for tests. Two of its endpoints are plain HTTP, which WebFetch uses.

`https://echo.websocket.org/.sse` sends Server-Sent Events without end: an event `server`, an event `request` (the request as the server got it), then an event `time` every second, numbered from 1 by their ids. It answers every origin, so this works in the pages and in node. The source reads the events until the third `time`, and `close` ends the request:

```smalltalk
| source events |
source := WebFetch eventSource: 'https://echo.websocket.org/.sse'.
events := OrderedCollection new.
[ [ (events count: [ :each | each type = 'time' ]) < 3 ] whileTrue: [ events add: source next ] ]
	ensure: [ source close ].
events collect: [ :each | each type -> each data ]
"=> an OrderedCollection('server'->'4d896d95b55478' 'request'->'GET /.sse HTTP/1.1

Host: echo.websocket.org
Accept: text/event-stream
...' 'time'->'2026-11-26T13:14:32Z' 'time'->'2026-11-26T13:14:33Z' 'time'->'2026-11-26T13:14:34Z')"
```

Any other path is an HTTP echo. Its `text/plain` answer shows the request: its line, its headers (with the address of the client, as the server sees it) and its body. It sends no CORS header, so a browser refuses its answer to the pages (`WebFetchNetworkError`); the node VM reads it:

```smalltalk
(WebFetch post: 'https://echo.websocket.org/webfetch' body: '{"greeting":"ciao"}' type: 'application/json') contents
"=> 'Request served by ...

POST /webfetch HTTP/1.1

Host: echo.websocket.org
...
Content-Type: application/json
...

{""greeting"":""ciao""}
...'"
```

Its third endpoint, `wss://echo.websocket.org`, is a WebSocket echo, which `WebFetchWebSocket` opens (in the pages too: WebSockets know no CORS). Its first message says which of its servers answered, then each message comes back as it went:

```smalltalk
| ws |
ws := WebFetchWebSocket connect: 'wss://echo.websocket.org'.
ws next.                  "=> 'Request served by 7811941c69e658'"
ws sendText: 'ciao, è WebSocket'.
ws next.                  "=> 'ciao, è WebSocket'"
ws sendBytes: #[1 2 3].
ws next.                  "=> #[1 2 3]"
ws close
```

The sockets of the WebAssembly VM do not reach it: Emscripten carries their TCP bytes over WebSockets of its own, for a proxy such as websockify, so a WebSocket client written on `Socket` (such as `ZnWebSocket` of Zinc-WebSocket, which the image does not have) does not work there.

`WebFetchEchoServerTest` (in `WebFetch-Tests`) checks both HTTP endpoints, the events with `WebFetchEventSource`; `WebFetchWebSocketEchoServerTest` (in `WebFetch-WebSocket-Tests`) checks the WebSocket one.

### Errors

All errors inherit from `WebFetchError` and carry a `kind` symbol:

- `WebFetchUnavailable` (`#unavailable`), subclass `WebFetchNetworkOff` (`#off`)
- `WebFetchBadRequest` (`#request`, `#redirect`)
- `WebFetchNetworkError` (`#network`, `#body`)
- `WebFetchTimeout` (`#timeout`)
- `WebFetchAborted` (`#aborted`)
- `WebFetchTooLarge` (`#tooLarge`)
- `WebFetchTooManyOpen` (`#tooManyOpen`)
- `WebFetchInCallback` (`#inCallback`)
- `WebFetchSessionEnded` (`#sessionEnded`)
- `WebFetchBadResponse` (`#response`): an answer that is no event stream, for `WebFetchEventSource`

`WebFetch-WebSocket` adds `WebFetchWebSocketClosed` (`#closed`, with `code`, `reason` and `wasClean`) and `WebFetchWebSocketOverflow` (`#overflow`, a `WebFetchTooLarge`).

## Waiting, Stop, UI process, sessions and callbacks

- **Stop and unwinding**: `fetch`, `get:`, `post:body:type:`, `stream:`, `wait`, `response` and `waitForHead` abort the host request when curtailed (Stop in Console/Notebook/World, process `terminate`, or exception unwinding). `waitTimeout:` and `whenDone:ifError:` do not abort on curtailment or timeout expiry.
- **UI process**: waiting messages (`fetch`, `get:`, `post:body:type:`, `stream:`, `wait`, `response`) freeze the world while waiting, as a socket does natively; Stop in the world opens a debugger on the process, and the request stays open until the debugger is closed. UI tools should use `start` with `whenDone:ifError:` and `UIManager default defer:`.
- **Sessions**: `WebFetchCall` registers with `SessionManager`. When a saved image resumes in a new session, in-progress calls fail with `WebFetchSessionEnded` and wake any waiting processes without hanging. Calls that already finished keep their cached response.
- **FFI callbacks**: while one runs, no event of the host comes. Starting and reading work inside it; a wait of the process that evaluates it signals `WebFetchInCallback` at once (`fetch` and `stream:` before they start a request), and leaves a call open. `whenDone:ifError:` works in a callback: its blocks are evaluated after it. Other processes start requests and wait as ever, their waits end after the callback. A callback that waits for another process which waits for a call never ends: this is not seen.
- **Streaming calls** (`startWithWindow:`): `response`, `wait` and `whenDone:ifError:` signal an error, since the body of such a call ends only when it is read.
- **Event sources**: `next`, `nextTimeout:`, `open` and `do:` wait as `stream:` does. Curtailed (Stop, `terminate`, unwinding), they close the source and abort its request; in the UI process they freeze the world, and `nextTimeout: 0 seconds` never waits. A started source survives Stop of the Console and the Notebook, which interrupts the evaluation only: `WebFetchEventSource openSources` lists the sources from their first connection to their close, and `WebFetchEventSource closeAll` or `WebFetch abortAll` closes them. The reader yields after each chunk that it read without waiting, so that a fast stream does not keep the processes of its priority, the UI process among them, from running. In an FFI callback, `next` answers the events already parsed from the bytes already there, and signals `WebFetchInCallback` where it would wait, leaving the source as it was; `open`, `do:` and the first `next` signal it before they make a request; `start` works in a callback. A source never goes on in a resumed image (`WebFetchSessionEnded`; one closed before keeps its end), nor after the network was turned off (`WebFetchNetworkOff`).

## Limits and defaults

- Default timeout: `60 seconds` for `fetch`, `get:` and `post:body:type:`; none for `start` and `stream:`. Explicit `timeout: nil` or `timeout: Duration zero` disables the timeout.
- Default `maximumBodySize`: 64 MiB (valid range `0` to `2^31 - 2`); applies to `fetch` and `start`, not `stream:`.
- Maximum request body: 64 MiB; maximum encoded request head: 1 MiB.
- Streaming window: 1 MiB.
- Maximum concurrent open requests per VM: 64 (the 65th signals `WebFetchTooManyOpen`).
- Event sources: at most `maximumEventSize` bytes of data in an event (1 MiB by default), 4096 bytes for an `id` or an `event`; the reconnection time 3 seconds, at least 250 ms, the backoff up to 60 seconds; a GET reconnects, another method does not. Each connected source holds one of the 64 requests.
- In a browser, other origins answer only with CORS, at most six requests at a time go to a host over HTTP/1.1 (an open event source is one of them), and Chromium lets simultaneous GETs of one URL wait for one another (its cache), unless their cache mode is `no-store`, as that of event sources is. `Last-Event-ID` costs a preflight to another origin, at each reconnection that sends it.
- The user can turn the network off (Settings of the pages; `PHARO_WASM_NETWORK=0` in node): `availability` is then `#off`, a start signals `WebFetchNetworkOff`, and the open calls fail with it.

## WebSocket (`WebFetch-WebSocket`)

`WebFetchWebSocket` is a WebSocket client connection made by the `WebSocket` of the host: of the worker in the pages, of node in the node VM. It sends and receives whole messages, text (a String) or binary (a ByteArray), and waits on semaphores as `WebFetch` does, while the VM and the other processes go on. Load the group `WebSocket`; `docs/WebSocket.md` of the VM is the contract.

```smalltalk
| ws |
ws := WebFetchWebSocket connect: 'wss://echo.websocket.org'.
ws next.                  "=> 'Request served by 7811941c69e658'"
ws sendText: 'ciao, è WebSocket'.
ws next.                  "=> 'ciao, è WebSocket'"
ws close.
```

```smalltalk
| ws |
ws := (WebFetchWebSocket url: 'wss://example.org/chat')
	protocols: #( 'v2.chat' 'v1.chat' );
	timeout: 10 seconds;
	maximumMessageSize: 1024 * 1024;
	maximumQueuedBytes: 8 * 1024 * 1024;
	start.                 "start does not wait for the handshake"
ws whenMessage: [ :message | UIManager default defer: [ Transcript crShow: message printString ] ]
	whenClosed: [ :socket | UIManager default defer: [ Transcript crShow: socket closeCode printString ] ].
ws waitForOpenTimeout: 10 seconds.
ws protocol.               "=> 'v2.chat'"
```

- Class side: `availability` (`#unavailable`, `#ready`, `#off`, independent of `WebFetch availability`) and `isAvailable`; `url:` (a socket to configure, not open), `connect:` and `connect:protocols:` (they wait until it is open, and signal the error of a failed handshake); `openSockets`, `openCount` and `closeAll`, which releases every socket. `WebFetch abortAll` does not touch WebSockets.
- Configure, before `start`: `protocols:` (tokens of RFC 7230, no two alike ignoring case, at most 32), `timeout:` (the handshake, and a send waiting for the open or for room; 30 seconds by default, nil or `Duration zero` for none), `maximumMessageSize:` and `maximumQueuedBytes:` (16 MiB each by default, 1 to 2^28: 256 MiB, what the host queues in all its sockets). A bad value signals `WebFetchBadRequest` when it is set.
- Open: `start` answers the socket in `#connecting`; `connect` starts it and waits; `waitForOpen` waits with no deadline of its own (the handshake timeout ends it) and signals the error of a socket that failed before it opened; `waitForOpenTimeout:` answers whether it is open, and leaves it as it is.
- State: `state` (`#new`, `#connecting`, `#open`, `#closing`, `#closed`, `#failed`), `isOpen`, `isOver`, `url`, `protocol`, `extensions`, `bufferedAmount`, `queuedCount`, `closeCode`, `closeReason`, `wasClean`, and `error`, the unsignalled error of a failed socket.
- Send: `sendText:` (its UTF-8), `sendBytes:`, `send:` (a String as text, anything else as binary). In `#connecting` they wait for the open, on a full send buffer (16 MiB) for room, both within `timeout`, after which they signal `WebFetchTimeout` and the socket stays as it is. On a closing or closed socket they signal `WebFetchWebSocketClosed`, on a failed one its error. `flushTimeout:` waits until every byte sent went to the network, and answers whether it did. A message of more than 64 MiB signals `WebFetchTooLarge`, and the socket stays open.
- Receive: `next` waits for the next message (in `#connecting` too); when the socket is over and nothing is left it signals `WebFetchWebSocketClosed` (`code`, `reason`, `wasClean`) after a close, the error after a failure. `nextTimeout:` answers nil when none came in time, `nextOrNil` never waits, `nextRaw` answers `{isText. utf8Bytes}`, so that a reader of JSON parses the bytes with no WideString in between. `atEnd` is true when the socket is over and nothing is left. `do:` evaluates a block with each message, ends quietly at any close, clean or not (`closeCode` says why), and signals the error of a failure.
- `whenMessage:whenClosed:` forks one reader at the caller's priority, named `WebFetchWebSocket reader`, and answers it: the first block gets each message in order, the second the socket at its end, a close, a failure, a session end or a `release` (`socket error` says why when it is not a close). An error in the first block is not caught: that process stops in a debugger, and the socket stays open and fills its queue until it overflows.
- Close: `close` (1000, no reason) and `close:reason:` (1000 or 3000..4999, a reason of at most 123 bytes of UTF-8, else `WebFetchBadRequest`) answer whether they began the closing handshake; the messages queued stay readable. `waitForCloseTimeout:` answers whether it is over. `release` forgets the socket at once: the host closes it with 1000 `released`, what is queued is lost, and a waiter gets `WebFetchAborted`.

**Ends.** A lost connection is no failure: the socket is `#closed` with 1006, not clean. A failure (`tooLarge`, `overflow`, the network turned off) makes it `#failed`, and closes it with 4009, 4008 or 1000. Either way the messages that came before stay readable: `next` answers them, then signals. When the socket first sees its end, it reads what is queued into the image and frees its host record (one of the 32), so that what it holds survives an image save. A close that has not ended 5 seconds after it began ends the socket with 1006 `closing handshake timed out`, not clean: a server that never answers it, and in node also one that answers it but ends TCP later, since node tells the close only when the server ends TCP (`wss://echo.websocket.org` ends TCP about 5.3 s after the close frames, measured with node 24).

**Waiting, Stop, the UI process, callbacks and sessions.**

- No Mutex is held while a process waits: one reader and one writer, or several of each, wait on their own semaphores, and each gets whole, distinct messages.
- A curtailed `connect`, `connect:` or `waitForOpen` (Stop, `terminate`, an unwinding) releases the socket, which is not yet the caller's. A curtailed `next`, a send or `flushTimeout:` leaves it open: a connection outlives a reader that was stopped. The process of `whenMessage:whenClosed:` releases nothing when it is terminated.
- In the UI process of the world, `connect:`, `next` and a send that waits freeze it, as a native socket does; Stop opens a debugger, and the socket stays open. Tools use `start` and `whenMessage:whenClosed:` with `UIManager default defer:`.
- In an FFI callback a wait signals `WebFetchInCallback` at once; `start`, `state`, `nextOrNil`, a send with room, `close` and `release` work there, also while another process waits in `next`.
- When a saved image resumes, the sockets that had not ended fail with `WebFetchSessionEnded` and wake their waiters; one that had ended keeps its messages, its close code, its reason and `wasClean`.

**Limits.** 32 sockets per VM, the closing ones counted (`WebFetchTooManyOpen`); 16 MiB per message received and 16 MiB queued unread per socket by default, at most 256 MiB each (`WebFetchTooLarge`, `WebFetchWebSocketOverflow`, which close the socket with 4009 and 4008), 256 MiB queued in all the sockets of a VM (`WebFetchWebSocketOverflow` for the socket whose message crosses it); 64 MiB per message sent; a send buffer of 16 MiB; a handshake of 30 seconds by default. When the image has no room for a message, the package collects garbage and grows the memory, then gives up that message: the socket fails with `WebFetchTooLarge`, and the earlier messages stay readable. A text message with a character above 255 becomes a WideString, 4 bytes a character: `nextRaw` avoids it.

**Errors.** `WebFetchBadRequest` (a URL that is not an absolute `ws:` or `wss:` one, with a user name, a password, a fragment, or a host of the site's domain in a browser; a bad subprotocol, close code or reason), `WebFetchNetworkError` (no connection, a refused handshake, a subprotocol that was not offered), `WebFetchTimeout`, `WebFetchNetworkOff`, `WebFetchAborted`, `WebFetchTooLarge`, `WebFetchWebSocketOverflow`, `WebFetchWebSocketClosed`, `WebFetchUnavailable` (no plugin, or no `WebSocket` in the host), `WebFetchTooManyOpen`, `WebFetchInCallback` and `WebFetchSessionEnded`.

**Security.**

- In a browser the handshake carries the cookies that the browser holds for the server's host (from the site to another site only `SameSite=None` ones, while third-party cookies are allowed), and may carry its HTTP authentication and client certificates: unlike `WebFetch`, there is no way to leave them out. The server sees the `Origin` of the site, so a server that checks `Origin` treats the image as the site; one that authenticates WebSockets by cookies and does not check `Origin` is open to the code of any image, as it is to any page.
- So a socket to a host of the site's domain is refused (`WebFetchBadRequest`, `a host of the domain of this site is refused: its cookies would be sent`), whatever its port: the site's hostname, a parent or a subdomain of it, or a hostname with the same last two labels (an IP address only when it is the site's). A handshake to such a host, which is of the same site, would carry every cookie that the site set with a `Domain` attribute, `Lax` and `Strict` ones too.
- The image sets no header (no `Authorization`): a token goes in the URL or in a subprotocol, and a URL may end up in the logs of servers.
- With the network on, the code of an image may talk to any WebSocket server; turn the network off in Settings before running an image that someone else made.

**In a browser.** There is no CORS. A refusal, a name that is not there and a TLS error are the same `WebFetchNetworkError`, without a reason. From an https: page only `wss:` URLs work (but to localhost). The browser makes one handshake at a time per address and port, so many sockets to one server open one after the other, and the timeout of each counts that wait. It answers the pings of the server by itself; the image cannot send one. While the Console prints more than it shows, the worker pauses the VM, and the messages wait in the queue meanwhile, which may overflow.

**In node.** There is no `Origin` and no cookie; node strips a leading BOM of a text message, as Chromium does, and gives no reason for a failed handshake. Node ends after the image ends, also with sockets that a server keeps open.

## Zinc adapter (`WebFetch-Zinc`)

Loading `WebFetch-Zinc` does not install it. Enable or disable it explicitly:

```smalltalk
WebFetchZinc install.
WebFetchZinc isInstalled. "=> true"
ZnClient new get: 'https://api.github.com/zen'.
WebFetchZinc uninstall.
```

`WebFetchZinc` sets `ZnNetworkingUtils default:` to a `WebFetchNetworkingUtils` that returns a `WebFetchSocketStream` (`< ZdcSocketStream`) for `http` and `https` whenever `WebFetch availability ~= #unavailable` (including `#off`, so disabled network produces a clean error). On native VMs, and for `ws`/`wss` or server sockets, everything forwards to the previous `ZnNetworkingUtils` unchanged. Unloading `WebFetch-Zinc` uninstalls it automatically.

Differences from a native socket:

- Redirects are followed by the host: Zinc sees the final response with `X-WebFetch-Url` set to the final URL, `request url` stays the first URL, and `maxNumberOfRedirects` does not apply. With `dontFollowRedirects`, node returns the 3xx response while browsers fail.
- No cookies, no image HTTP proxy, and no client certificates; TLS verification is performed by the host.
- `Accept-Encoding`, `Host`, `Connection` and (in browsers) `User-Agent` are controlled by the host; compressed answers arrive decompressed without `Content-Length`.
- In browsers, `Authorization`, JSON posts and custom headers trigger a CORS preflight, and CORS/network refusals carry no specific reason. GitHub API and raw endpoints allow browser CORS; `codeload.github.com` zip archives do not.
- Request bodies are gathered whole before sending (up to 64 MiB); `GET` with a body is refused.
- One exchange per connection (`isConnected` becomes `false` after the response). Streaming clients (`streaming: true`) or clients that fail mid-read (`ZnEntityTooLarge`) must be closed (`client close`), as with a socket.
- Errors: timeouts map to `ConnectionTimedOut`; network failures and network-off map to `WebFetchZnNetworkError` (`< NetworkError`); other `WebFetchError`s pass through without triggering Zinc retries.

## Tests

Native unit tests run without a WebAssembly VM using `WebFetchTestHost`; among them `WebFetchEventParserTest`, which feeds the parser of event streams every cut of its input, and `WebFetchEventSourceTest`. Live tests (`WebFetchLiveTest`, and `WebFetchEventSourceLiveTest` on the event streams of its `/sse`) run on a WebAssembly VM against `tests/wasm/lib/fetch-http.mjs` from the VM repository; `build-wasm/node/pharo` is the node VM that `make wasm` builds there:

```sh
node /path/to/pharo-vm/tests/wasm/lib/fetch-http.mjs
# prints http://127.0.0.1:<port>
WEB_FETCH_SERVER=http://127.0.0.1:<port> \
/path/to/pharo-vm/build-wasm/node/pharo --headless Pharo.image --no-default-preferences st --quit tests/run-webfetch.st
```

`tests/run-webfetch.st` also reads the server URL from a `webfetch.lane` file in the working directory when `WEB_FETCH_SERVER` is not set. Without a server URL, or off WebAssembly, live tests skip themselves. Each tag of the log of the server has the microseconds of the UTC clock, so that the tests may run again against the same server.

The tests of event sources need a server with `/sse`, and a VM that knows the cache mode no-store (flag 2 of `primitiveFetchStart`): `fetch-http.mjs` and the VM of a checkout that has them. Against an older server `/sse` answers 404, and `WebFetchEventSourceLiveTest`, `tests/callback-webfetch.st` and `tests/snapshot-webfetch.st` fail. Since the CI of the VM runs the tests of the master of this repository, a change here that needs a new server or VM lands after the VM's.

`WebFetchEchoServerTest` goes to the public echo server of websocket.org, so it runs only when asked to. Set `WEB_FETCH_ECHO_SERVER=https://echo.websocket.org` for the node VM, or evaluate `WebFetchEchoServerTest server: 'https://echo.websocket.org'` in the pages. In a browser, its test of the HTTP echo skips, since that answer has no CORS header.
`tests/callback-webfetch.st` makes requests and reads event sources while a real FFI callback runs (the node VM with the FFI).
`tests/snapshot-webfetch.st`, run twice on one copy of an image, saves it while processes wait for requests and an event source, and restarts it.

The tests of `WebFetch-WebSocket` run natively with the fake host `WebFetchWebSocketTestHost`. `tests/run-websocket.st` runs them on a WebAssembly VM with the live tests (`WebFetchWebSocketLiveTest`), against the WebSocket endpoints of the same server, which prints the port of a second listener that never answers with `--hang-port`:

```sh
node /path/to/pharo-vm/tests/wasm/lib/fetch-http.mjs --hang-port
# prints http://127.0.0.1:<port> <hang port>
WEB_FETCH_SERVER=http://127.0.0.1:<port> WEB_FETCH_HANG_PORT=<hang port> \
/path/to/pharo-vm/build-wasm/node/pharo --headless Pharo.image --no-default-preferences st --quit tests/run-websocket.st
```

or from a `websocket.lane` file of the working directory, whose two first words are what the server prints. `WebFetchWebSocketEchoServerTest` goes to `wss://echo.websocket.org` only with `WEB_FETCH_ECHO_SERVER` set, as `WebFetchEchoServerTest`. `tests/callback-websocket.st` waits in a real FFI callback, and `tests/snapshot-websocket.st`, run twice, saves an image while processes wait on sockets and restarts it. Like the event sources, these tests need what a VM of an older checkout lacks: the WebSocketPlugin, and the WebSocket endpoints of `fetch-http.mjs`; so the VM lands first here too.

In the VM repository, lane 81 runs all of these, and lane 84 those of the WebSockets, in the node VM and in the web VM, when `WEB_FETCH_DIR` names a checkout of this repository; `websocket.spec.mjs` runs them in Chromium too:

```sh
cd /path/to/pharo-vm
WEB_FETCH_DIR=/path/to/web-fetch.st sh tests/wasm/run-lanes.sh 81 84
```

The CI of the VM clones this repository and does the same on every push, and its batteries job loads it and runs its tests in the native VM.

## License

MIT (see `LICENSE`).
