function xss_eval(event) {
	console.log('origin['+event.origin +'] called @'+window.name+'.postMessage() -> req: '+event.data);

	if ( event.origin != "https://plus.google.com" ) return; //only handle messages from main frame
	args = event.data.slice();
	func = args.shift();
	if ( func != null && eval("typeof "+func+" === 'function'") ){
		console.log('@'+window.name+'.xss_eval() -> '+func+'() -> args: ' + args);
		func = eval(func)
		res = func.apply(this, args); //splat
		//event.source is origin's .window, could send result of func there with postMessage()
	}
}

if (window == top) {
	window.dispatchEvent(new Event('resize')); //resize the roster per styler.js on cold reloads in fullscreen
	document.querySelector('a[href="/stream"]').parentNode.remove(); // -G+ page selector tray list
	/* <script>window.jstiming.load.tick('streamStart');</script>
		delete all the junk nodes in between these
	<script>window.jstiming.load.tick('streamEnd');</script>*/

	var getRoster = function() { return document.getElementById('gtn-roster-iframe-id-b'); } 
	var xssRoster = function(req) { 
		// FIXME: check getRoster() and retry until it yields - timeout ~30s
		// ^ won't that stall the single JS thread? one per frame?
		getRoster().contentWindow.postMessage(req, '*');
	 }

	var myGAIA = function(){ return document.querySelector('a[aria-label^=Profile]').getAttribute('href').slice(1); }
	// this is your UID for G+: https://developers.google.com/apis-explorer/#p/plus/v1/plus.people.get?userId=me&_h=6&

	//addEventListener("message", xss_eval, false); // intercept new chat window dispositions in the main content pane

} else {
	var evalMain = function(req) { top.postMessage(req, '*'); }
	//addEventListener("message", xss_eval, false); // intercept loooots of data to individual chat iframes
	// https://github.com/tdryer/hangups/blob/master/hangups/pblite.py
	// https://github.com/tdryer/hangups/blob/master/hangups/schemas.py
	// http://protobuf.axo.io/#objc
}

if (window.name == 'gtn-roster-iframe-id-b') {
	var getTopConversation = function() { return document.querySelector('button[cpar]'); } //gets 1st convers in roster
	// cpar=<SenderGAIA>_<ReceiverGAIA>
	// SMS forwarded messages have ephermeral GAIA's (persist for length of conversation history?)
	// cathartic messages just have cpar=<YourGAIA>

	var notifyMessages = function(msgs) { 
		for (el of msgs) { // el should be a <button>
			msg = el.innerText.split('\n').filter( function(v) { return (v.length > 0) }) //filter blank lines
			var from = msg.shift();
			var rcvd = msg.shift();
			// naked sms: '(NNN) NNN-NNNN'
			// shortcode sms: NNNNNN
			// sms from number in your Gmail Contacts: 'Firstname Lastname \U2022 (NNN) NNN-NNNN'
			// pure hangout messages can be named anything -- fixme: must differentiate these with hangouts:<foo@gmail>
			var body = msg.join('\n');

			//var replyTo = (el.parentNode.querySelector('div[title="This user may not be on Hangouts"]') != null) ?
			//	 'sms:' + from.replace(/[^[0-9]/g, '') : // could discriminate with https://github.com/googlei18n/libphonenumber
			//	 'hangouts:' + from; //user is available/ user may be unavailable

			var digits = from.replace(/[^[0-9]/g, '');
			if (digits.length == 10 || digits.length == 5) { // could discriminate with https://github.com/googlei18n/libphonenumber
				 replyTo = 'sms:' + digits;
			} else {
				 replyTo = 'hangouts:' + from;
			}
			if (body == "is video calling you" || body == "is calling you" || body == "You're in a call" || body == "You're in a video call") {
				webkit.messageHandlers.unhideApp.postMessage([]); //get in the user's face right now!!
			} else {
				webkit.messageHandlers.receivedHangoutsMessage.postMessage([from, replyTo, body]);
			}
		}
	}

	var findParentNodeOfTag = function(tagName, childObj) {
		var testObj = childObj.parentNode;
		var count = 1;
		while(testObj.tagName != tagName) {
			testObj = testObj.parentNode;
			count++;
		}
		return testObj
	}

	var WatchForRoster = function() {
		var cfg = { attributes: false, childList: true, characterData: false, subtree: true };
		var watch = new MutationObserver(function(muts) { 
			for (var mut of muts) {
				if (mut.type === 'childList')
					//if (mut.addedNodes.length > 0)
						if (roster = mut.target.querySelector('div[tabindex="-1"]')) {
							console.log("Found Hangouts chat roster, dispatching HangoutsRosterReady event");
							setTimeout(function(){
								window.dispatchEvent(new window.CustomEvent('HangoutsRosterReady',{'detail':{'roster': roster}}));
							}, 10000); //need a little lag so hangouts can load up the contacts
							window.rosterWatcher.unobserve(); // FIXME: use 'this'
							break;
						}
			}
		});
		watch.observe(document.body, cfg);
		return watch
	}

	var WatchForNewMessages = function(roster) {
		//look for changed element attributes in the chat list representing new messages and send them to the notifier
		var cfg = { attributes: true, childList: false, attributeFilter: ['aria-label'], attributeOldValue: true, characterData: false, subtree: true };
		var watch = new MutationObserver(function(muts) {
			for (var mut of muts) {
				if (mut.type === 'attributes')
					if (mut.target.nodeName == 'DIV') 
						if (mut.target.getAttribute('aria-label') != mut.oldValue) //prevent duplicate notifications of fed-back identical messages from chats with myself
							if (mut.target.getAttribute('aria-label').match(/ ([1-9]\d?) unread message/) != null) { //if more than 0 unreads, notify
								console.log(Date() + ' [new message seen from:] ' + mut.target.innerText);
								//console.log('aria-label=' + mut.target.getAttribute('aria-label') + '!=' + mut.oldValue) //debug
								notifyMessages([findParentNodeOfTag('BUTTON', mut.target)])
							}
			}
			
		});
		watch.observe(roster, cfg);
		return watch;
	}

	var getCallBox = function() { return document.querySelector('input[spellcheck]'); }
	var getRosterDiv = function() { return document.querySelector('div > div > div > div'); } //this captures all of the keyevents

	var inputAddress = function(addr, endkeys) {
		if (addr == null || addr == '') return;
		addr = decodeURI(addr);
		var cb = window.getCallBox();
		cb.blur();
		cb.value = '';
		cb.focus();
		//cb.value = addr;
		var tev = document.createEvent("TextEvent");
		tev.initTextEvent('textInput', true, true, null, addr);
		cb.dispatchEvent(tev);
		if (endkeys != null) // Enter will open a direct hangout/call, Tab will add to recipent list
			sendkeys(cb, endkeys);
	};

	var sendkeys = function(el, keys) {
		//for (var i = 1; i < arguments.length; i++) {
			//var key = arguments[i];
		var keyids = { // https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent.keyCode
			8: 'backspace',
			9: 'tab',
			13: 'enter',
			27: 'esc',
			32: 'space',
			38: 'up',
			40: 'down',
			46: 'Period', //wtf webkit?!
			108: '.'
		};
		for (key of keys) {
			var keycode = key.charCodeAt(0);
			var keyid = keyids[keycode];
			for (kt of ["keydown", "keypress", "keyup"]) {
				var kev = new KeyboardEvent(kt, { bubbles: true, cancelable: true, view: window, detail: 0, keyIdentifier: keyid, location: KeyboardEvent.DOM_KEY_LOCATION_STANDARD, ctrlKey: false, altKey: false, shiftKey: false, metaKey: false }); //key: keycode 
				if (kt == 'keypress') {
					Object.defineProperty(kev, 'charCode', {'value': keycode, 'enumerable': true});
				} else {
					Object.defineProperty(kev, 'charCode', {'value': 0, 'enumerable': true});
				}
				// .which??
				Object.defineProperty(kev, 'keyCode', {'value': keycode, 'enumerable': true});

				setTimeout(function(){ el.dispatchEvent(kev); }, 10000); //add a bit of lag
			}
		}
		if (typeof el.value == 'string') el.value += key;
	};

	var openSMS = function() { document.querySelector('a[title="Click to send SMS"]').click(); } // a='Send SMS' -> @main window.frames['gtn_96gm6a']
	var openHangout = function() { document.querySelector('button[title="Message"]').click(); } // ||'Video call' -> @main window.frames['gtn_96gm6a']
	var checkFirstFoundContact = function() { document.querySelector('input[type="checkbox"]').click(); } //input[name=select_result]
	var getFirstFoundContact = function() { document.querySelector('li[oid]'); } //click, mouseover, mouseout
	var evClick = new MouseEvent('click', {'view': window, 'bubbles': true, 'cancelable': true  });
	var evUIclick = new UIEvent('click', {'view': window, 'bubbles': true, 'cancelable': true  });
	//var openAVchat = function() { document.querySelector('a[title="Click to send SMS"]').previousSibling.previousSibling.children[0].dispatchEvent(evClick); } // Phone icon is second div before SMS link
	//var openAVchat = function() { document.querySelector('img[src$="/phone-avatar.png"]').dispatchEvent(evClick); } // Phone icon is second div before SMS link
	//var openAVchat = function() { document.querySelector('li[title="Call"]').dispatchEvent(evClick); } // Phone icon is second div before SMS link
	var newAVChat = function() { document.querySelector('button[tabindex="-1"]').click() }; //Start a video Hangout

	addEventListener("message", xss_eval, false);

	/* var chatWatcher;
	setTimeout(function(){
		window.chatWatcher = window.WatchForNewMessages(window.getTopConversation().parentNode.parentNode); //watch the whole roster
	}, 10000); */
	//var rosterWatcher = window.WatchForNewMessages(); //watch the whole roster

	var rosterWatcher;
	window.addEventListener("HangoutsRosterReady", function(event) {
		console.log("Caught HangoutsRosterReady event, dispatching message watcher");
		webkit.messageHandlers.HangoutsRosterReady.postMessage([]); //callback JSCore to accept queued new message URLs
		var chatWatcher = window.WatchForNewMessages(event.detail['roster']); //watch the whole roster
		rosterWatcher.disconnect();
	}, false);
	rosterWatcher = window.WatchForRoster();


} // -gtn-roster-iframe-id-b?

if (~window.name.indexOf('gtn_') && false) { // chat convo
	// need to un-redirect recv'd urls. "do no evil?" quit harvesting conversations google.
}