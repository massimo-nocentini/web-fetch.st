"snapshot-webfetch.st - an image saved while processes wait for requests, then restarted

	pharo --headless X.image --no-default-preferences st snapshot-webfetch.st     (twice, on one copy)

 With the server of run-webfetch.st, on an image that has WebFetch.  The first run starts what waits,
 saves the image, and goes on: it prints

	saved, the slow request: tick0tick1tick2tick3tick4

 and exits.  The second one, in the image that was saved, prints what each of the waiting processes
 got, 'WebFetchSessionEnded' for all of them, and that the image fetches again:

	restarted: <n> of <n> WebFetchSessionEnded, open 0, then hello"

| out environment base fetch call names results wait deadline |
out := [ :text | Stdio stdout nextPutAll: text; nextPutAll: OSPlatform current lineEnding; flush ].
environment := OSEnvironment current.
base := environment at: 'WEB_FETCH_SERVER' ifAbsent: [ 'webfetch.lane' asFileReference contents substrings first ].
fetch := Smalltalk globals at: #WebFetch.
call := Smalltalk globals at: #WebFetchCall.
names := #( response get wait waitTimeout stream whenDone ).
(Smalltalk globals at: #WebFetchSnapshot ifAbsent: [ nil ])
	ifNil: [
		| slow session |
		results := Dictionary new.
		Smalltalk globals at: #WebFetchSnapshot put: results.
		wait := [ :name :block |
			[ results at: name put: ([ block value. 'nothing' ] on: Error do: [ :error | error class name asString ]) ] fork ].
		wait value: #response value: [ (fetch request: base , '/hang?snap1') start response ].
		wait value: #get value: [ fetch get: base , '/hang?snap2' ].
		wait value: #wait value: [ (fetch request: base , '/hang?snap3') start wait ].
		wait value: #waitTimeout value: [ (fetch request: base , '/hang?snap4') start waitTimeout: 100 seconds ].
		wait value: #stream value: [ (fetch request: base , '/endless?snap5') stream: [ :stream | [ stream next: 1000 ] repeat ] ].
		(fetch request: base , '/hang?snap6') start
			whenDone: [ :response | results at: #whenDone put: 'nothing' ]
			ifError: [ :error | results at: #whenDone put: error class name asString ].
		slow := (fetch request: base , '/dribble?ticks=5&ms=300') start.
		(Delay forMilliseconds: 500) wait.
		"in a process of its own, since the one of the command line ends the restarted image"
		session := Smalltalk session.
		[ Smalltalk snapshot: true andQuit: false.
		Smalltalk session == session ifTrue: [
			out value: 'saved, the slow request: ' , slow response contents.
			Smalltalk exit: 0 ] ] fork.
		Semaphore new wait ]
	ifNotNil: [ :saved |
		deadline := Time millisecondClockValue + 10000.
		[ (names allSatisfy: [ :each | saved includesKey: each ]) or: [ Time millisecondClockValue > deadline ] ]
			whileFalse: [ (Delay forMilliseconds: 50) wait ].
		names do: [ :each |
			(saved at: each ifAbsent: [ 'still waits' ]) = 'WebFetchSessionEnded' ifFalse: [
				out value: each , ': ' , (saved at: each ifAbsent: [ 'still waits' ]) ] ].
		out value: 'restarted: ' , (names count: [ :each | (saved at: each ifAbsent: [ nil ]) = 'WebFetchSessionEnded' ]) printString
			, ' of ' , names size printString , ' WebFetchSessionEnded, open ' , call openCount printString
			, ', then ' , (fetch get: base , '/hello') contents.
		Smalltalk exit: 0 ]
