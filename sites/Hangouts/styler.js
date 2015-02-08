if (~window.name.indexOf('h_gtn_')) { //this is an incoming phone call notifcation
	webkit.messageHandlers.unhideApp.postMessage([]); //get the app in the user's face right now!!
	window.addEventListener('DOMSubtreeModified', function(e){
		if (btn = document.querySelector('button + button')) { //answer button
			document.removeEventListener('DOMSubtreeModified', this, false);
			btn.autofocus = true //hafta apply this before .onload
		}
	});
	window.addEventListener("keypress", function (e) {
		switch (e.which) {
			case 13: //Enter
			case 32: //Space
				document.querySelector('button + button').click(); //Answer call
				break;
			case 27: //Esc
			case 9: //Tab
			case 8: //Bksp
				document.querySelector('button').click(); //Decline call
				break;
			default:
		}
	});
};

if (window == top)
(function(){
	function injectCSS() {
        if (document.head) {
			document.removeEventListener('DOMSubtreeModified', injectCSS, false);

			// E: Not allowed to load local resource
			/* wait until http://trac.webkit.org/changeset/174029/trunk lands in OSX */
			/* var cssf = document.createElement("link");
			cssf.setAttribute("rel", "stylesheet");
			cssf.setAttribute("type", "text/css");
			cssf.setAttribute("href", "file://restyle.css")
			document.head.appendChild(cssf);
			*/

			// allow correct zooming
			var vp = document.createElement("meta");
			vp.setAttribute("name", "viewport");
			vp.setAttribute("content", "initial-scale=1.0");
			document.head.appendChild(vp);
			//<meta name="viewport" content="initial-scale=1.0" />

			var css = document.createElement("style");
			css.type = 'text/css';
			css.id = 'unSocialSpam'
		    css.innerHTML = "\
			    body, #content { overflow: hidden; background-color: transparent !important; }\
			    #contentPane, #gb, #gba, #notify-widget-pane { display: none; }\
				div[title='Display Notifications'] { display: none; }\
				div[title='Add People'] { display: none; }\
				div[guidedhelpid='streamcontent'] { display: none; }\
				div[style='height: 60px;'] { display: none; }\
				div[style='top: 60px;'] { display: none; }\
				#content > div:first-of-type { display: none; }\
				div[guidedhelpid='chat_mole_icon'] { display: none; }\
				div[style='top: 104px;'] { top: 0px !important; }\
				#ozIdRtRibbonChatRoster { height: 800px; margin-left: 0px; }\
			";
			document.head.appendChild(css);
			//document.head.insertBefore(css,document.head.childNodes[0]); //prepend
		}
	}
	document.addEventListener('DOMSubtreeModified', injectCSS, false); //mutation events are deprecated
})()

if (window == top)
window.addEventListener('resize', function(e){
	//e.preventDefault();
	//e.stopPropagation();
	if (roster = document.getElementById('ozIdRtRibbonChatRoster'))
		roster.style.height = document.height - 1 + "px";
	//return false;
});