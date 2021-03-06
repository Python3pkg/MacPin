/// MacPin BrowserViewController
///
/// A tabbed contentView for OSX

import WebKit // https://github.com/WebKit/webkit/blob/master/Source/WebKit/mac/ChangeLog
import WebKitPrivates
import Foundation
import JavaScriptCore //  https://github.com/WebKit/webkit/tree/master/Source/JavaScriptCore/API

// http://stackoverflow.com/a/24128149/3878712
struct WeakThing<T: AnyObject> {
  weak var value: T?
  init (value: T) {
    self.value = value
  }
}

// WK C API thunks for IconDatabase
func faviconChanged(iconDatabase: WKIconDatabaseRef, pageURL: WKURLRef, clientInfo: UnsafePointer<Void>) { // WKIconDatabaseDidChangeIconForPageURLCallback
	warn()
}
func faviconsCleared(iconDatabase: WKIconDatabaseRef, clientInfo: UnsafePointer<Void>) { //WKIconDatabaseDidRemoveAllIconsCallback
	warn()
}
func faviconReady(iconDB: WKIconDatabaseRef, pageURL: WKURLRef, clientInfo: UnsafePointer<Void>) { // WKIconDatabaseIconDataReadyForPageURLCallback
	let browser: BrowserViewControllerOSX = unsafeBitCast(clientInfo, BrowserViewControllerOSX.self) // translate pointer to browser instance
	WKIconDatabaseRetainIconForURL(iconDB, pageURL)
	let url = WKURLCopyCFURL(kCFAllocatorDefault, pageURL) as NSURL
	for tab in browser.tabs.filter({ $0.URL == url }) {
		//let iconurl = WKStringCopyCFString(CFAllocatorGetDefault().takeUnretainedValue(), WKURLCopyString(WKIconDatabaseCopyIconURLForPageURL(iconDB, WKURLCreateWithUTF8CString(url)))) as NSString
		let iconurl: NSURL = WKURLCopyCFURL(kCFAllocatorDefault, WKIconDatabaseCopyIconURLForPageURL(iconDB, pageURL))
		// ^^ FIXME: EXEC_BAD_ACCS on disappeared tabs?
		tab.favicon.url = iconurl
	}
}

@objc class TabViewController: NSTabViewController {
	required init?(coder: NSCoder) { super.init(coder: coder) } // required by NSCoder
	override init!(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) { super.init(nibName:nil, bundle:nil) } // calls loadView()

	let omnibox = OmniBoxController() // we could & should only present one of these at a time
	lazy var tabPopBtn = NSPopUpButton(frame: NSRect(x:0, y:0, width:400, height:24), pullsDown: false)
	let tabMenu = NSMenu() // list of all active web tabs
	let shortcutsMenu = NSMenu()
	//lazy var tabFlow = TabFlowController()
	/*
	lazy var tabFlow: NSCollectionView = {
		var grid = NSCollectionView()
		grid.selectable = true
		grid.allowsMultipleSelection = false
		grid.maxNumberOfRows = 0
		grid.maxNumberOfColumns = 10
		grid.minItemSize = NSSize(width: 0, height: 0)
		grid.maxItemSize = NSSize(width: 0, height: 0)
		//grid.itemPrototype = NSCollectionViewItem
		//grid.preferredContentSize = NSSize(width: 300, height: 300)
		return grid
	}() */

	enum BrowserButtons: String {
		case OmniBox		= "Search or Go To URL"
		case Share			= "Share URL"
		case Snapshot		= "Snapshot"
		case NewTab			= "Open New Tab"
		case CloseTab		= "Close Tab"
		case SelectedTab	= "Selected Tab"
		case Back			= "Back"
		case Forward		= "Forward"
		case ForwardBack	= "Forward & Back"
		case Refresh		= "Refresh"
		case TabList		= "Tabs"
	}

	var cornerRadius = CGFloat(0.0) // increment above 0.0 to put nice corners on the window FIXME userDefaults

	func close() { // close all tabs, which will close the whole browser window
		dispatch_sync(dispatch_get_main_queue(), {
			self.tabViewItems.forEach {
				$0.view?.removeFromSuperviewWithoutNeedingDisplay()
				self.removeTabViewItem($0)
			}
		})
	}

	override func insertTabViewItem(tab: NSTabViewItem, atIndex: Int) {
		if let view = tab.view {
			tab.initialFirstResponder = view
			if let wvc = tab.viewController as? WebViewController {
				tab.bind(NSLabelBinding, toObject: wvc.webview, withKeyPath: "title", options: nil)
				tab.bind(NSToolTipBinding, toObject: wvc.webview, withKeyPath: "title", options: nil)
				tab.bind(NSImageBinding, toObject: wvc.webview.favicon, withKeyPath: "icon", options: nil)
			}
		}
		super.insertTabViewItem(tab, atIndex: atIndex)
	}

	override func removeTabViewItem(tab: NSTabViewItem) {
		if let _ = tab.view {
			tab.initialFirstResponder = nil
			if let _ = tab.viewController as? WebViewController {
				tab.unbind(NSLabelBinding)
				tab.unbind(NSToolTipBinding)
				tab.unbind(NSImageBinding)
			}
			tab.label = ""
			tab.toolTip = nil
			tab.image = nil
		}
		super.removeTabViewItem(tab)
	}

	override func tabView(tabView: NSTabView, willSelectTabViewItem tabViewItem: NSTabViewItem?) {
		super.tabView(tabView, willSelectTabViewItem: tabViewItem)
		omnibox.webview = tabViewItem?.view?.subviews.first as? MPWebView
	}

	override func tabView(tabView: NSTabView, didSelectTabViewItem tabViewItem: NSTabViewItem?) {
		super.tabView(tabView, didSelectTabViewItem: tabViewItem)
		if let window = view.window, view = tabViewItem?.view {
			window.makeFirstResponder(view) // steal app focus to whatever the tab represents
		}
	}

	override func tabViewDidChangeNumberOfTabViewItems(tabView: NSTabView) { warn("@\(tabView.tabViewItems.count)") }

	override func toolbarAllowedItemIdentifiers(toolbar: NSToolbar) -> [String] {
		let tabs = super.toolbarAllowedItemIdentifiers(toolbar) ?? []
		warn(tabs.description)
		return tabs + [
			NSToolbarSeparatorItemIdentifier,
			NSToolbarSpaceItemIdentifier,
			NSToolbarFlexibleSpaceItemIdentifier,
			NSToolbarShowColorsItemIdentifier,
			NSToolbarShowFontsItemIdentifier,
			NSToolbarCustomizeToolbarItemIdentifier,
			NSToolbarPrintItemIdentifier,
			BrowserButtons.OmniBox.rawValue,
			BrowserButtons.Share.rawValue,
			BrowserButtons.Snapshot.rawValue,
			BrowserButtons.NewTab.rawValue,
			BrowserButtons.CloseTab.rawValue,
			BrowserButtons.SelectedTab.rawValue,
			BrowserButtons.Back.rawValue,
			BrowserButtons.Forward.rawValue,
			BrowserButtons.ForwardBack.rawValue,
			BrowserButtons.Refresh.rawValue,
			BrowserButtons.TabList.rawValue
		]
	}

	override func toolbarDefaultItemIdentifiers(toolbar: NSToolbar) -> [String] {
		let tabs = super.toolbarDefaultItemIdentifiers(toolbar) ?? []
		return [BrowserButtons.Share.rawValue, BrowserButtons.NewTab.rawValue] + tabs + [BrowserButtons.OmniBox.rawValue] // [NSToolbarFlexibleSpaceItemIdentifier]
		//tabviewcontroller remembers where tabs was and keeps pushing new tabs to that position
	}

	override func toolbar(toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: String, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		if let btnType = BrowserButtons(rawValue: itemIdentifier) {
			let ti = NSToolbarItem(itemIdentifier: itemIdentifier)
			ti.minSize = CGSize(width: 24, height: 24)
			ti.maxSize = CGSize(width: 36, height: 36)
			ti.visibilityPriority = NSToolbarItemVisibilityPriorityLow
			ti.paletteLabel = itemIdentifier

			let btn = NSButton()
			//let btnCell = btn.cell
			//btnCell.controlSize = .SmallControlSize
			btn.toolTip = itemIdentifier
			btn.image = NSImage(named: NSImageNamePreferencesGeneral) // https://hetima.github.io/fucking_nsimage_syntax/
			btn.bezelStyle = .RecessedBezelStyle // RoundRectBezelStyle ShadowlessSquareBezelStyle
			btn.setButtonType(.MomentaryLightButton) //MomentaryChangeButton MomentaryPushInButton
			btn.target = nil // walk the Responder Chain
			btn.sendActionOn(Int(NSEventMask.LeftMouseDownMask.rawValue))
			ti.view = btn

			switch (btnType) {
				case .Share:
					btn.image = NSImage(named: NSImageNameShareTemplate)
					btn.action = Selector("shareButtonClicked:")
					return ti

					case .Snapshot:
					btn.image = NSImage(named: NSImageNameQuickLookTemplate)
					btn.action = Selector("snapshotButtonClicked:")
					return ti

				//case .Inspect: // NSMagnifyingGlass
				case .NewTab:
					btn.image = NSImage(named: NSImageNameAddTemplate)
					btn.action = Selector("newTabPrompt")
					return ti

				case .CloseTab:
					btn.image = NSImage(named: NSImageNameRemoveTemplate)
					btn.action = Selector("closeTab")
					return ti

				case .Forward:
					btn.image = NSImage(named: NSImageNameGoRightTemplate)
					btn.action = Selector("goForward:")
					return ti

				case .Back:
					btn.image = NSImage(named: NSImageNameGoLeftTemplate)
					btn.action = Selector("goBack:")
					return ti

				case .ForwardBack:
					let seg = NSSegmentedControl()
					seg.segmentCount = 2
					seg.segmentStyle = .Separated
					let segCell = seg.cell as! NSSegmentedCell
					seg.trackingMode = .Momentary
					seg.action = Selector("goBack:")

					seg.setImage(NSImage(named: NSImageNameGoLeftTemplate), forSegment: 0)
					//seg.setLabel(BackButton, forSegment: 0)
					//seg.setMenu(backMenu, forSegment: 0) // wvc.webview.backForwardList.backList (WKBackForwardList)
					segCell.setTag(0, forSegment: 0)

					seg.setImage(NSImage(named: NSImageNameGoRightTemplate), forSegment: 1)
					//seg.setLabel(ForwardButton, forSegment: 1)
					segCell.setTag(1, forSegment: 1)

					ti.maxSize = CGSize(width: 54, height: 36)
					ti.view = seg
					return ti

				case .Refresh:
					btn.image = NSImage(named: NSImageNameRefreshTemplate)
					btn.action = Selector("reload:")
					return ti

				case .SelectedTab:
					ti.minSize = CGSize(width: 70, height: 24)
					ti.maxSize = CGSize(width: 600, height: 36)
					tabPopBtn.menu = tabMenu
					//tabPopBtn.menu?.itemAtIndex(0).setView(tabFlow.view) // GridMenu display
					// https://developer.apple.com/library/mac/documentation/Cocoa/Reference/ApplicationKit/Classes/NSMenu_Class/index.html#//apple_ref/occ/instm/NSMenu/popUpMenuPositioningItem:atLocation:inView:
					ti.view = flag ? tabPopBtn : NSPopUpButton()
					return ti

				case .TabList:
					btn.image = NSImage(named: "ToolbarButtonTabOverviewTemplate.pdf")
					btn.action = Selector("tabListButtonClicked:")
					return ti

				case .OmniBox:
					ti.minSize = CGSize(width: 70, height: 24)
					ti.maxSize = CGSize(width: 600, height: 24)
					ti.view = flag ? omnibox.view : NSTextField()
					return ti
			}
		} else {
			// let NSTabViewController map a TabViewItem to this ToolbarItem
			let tvi = super.toolbar(toolbar, itemForItemIdentifier: itemIdentifier, willBeInsertedIntoToolbar: flag)
			return tvi
		}
	}

	 //override func toolbarWillAddItem(notification: NSNotification) { warn(notification.description) }
	 //	if let ti = notification.userInfo?["item"] as? NSToolbarItem, tb = ti.toolbar, tgt = ti.target as? TabViewController, btn = t i.view as? NSButton { warn(ti.itermIdentifier) }
	 //override func toolbarDidRemoveItem(notification: NSNotification) { warn(notification.description) }

	override func loadView() {
		//tabView.autoresizesSubviews = false
		//tabView.translatesAutoresizingMaskIntoConstraints = false
		super.loadView()
	}

	override func viewDidLoad() {
		// note, .view != tabView, view wraps tabView + whatever tabStyle is selected
		tabView.tabViewType = .NoTabsNoBorder
		tabView.drawsBackground = false // let the window be the background
		identifier = "TabViewController"
		tabStyle = .Toolbar // this will reinit window.toolbar to mirror the tabview itembar
		//tabStyle = .Unspecified
		//tabStyle = .SegmentedControlOnTop
		//tabStyle = .SegmentedControlOnBottom

		// http://www.raywenderlich.com/2502/calayers-tutorial-for-ios-introduction-to-calayers-tutorial
		view.wantsLayer = true //use CALayer
		view.layer?.cornerRadius = cornerRadius
		view.layer?.masksToBounds = true // include layer contents in clipping effects
		view.canDrawSubviewsIntoLayer = true // coalesce all subviews' layers into this one

		view.autoresizingMask = [.ViewWidthSizable, .ViewHeightSizable] //resize tabview to match parent ContentView size
		view.autoresizesSubviews = true // resize tabbed subviews based on their autoresizingMasks
		transitionOptions = .None //.Crossfade .SlideUp/Down/Left/Right/Forward/Backward

		super.viewDidLoad()
		view.registerForDraggedTypes([NSPasteboardTypeString,NSURLPboardType,NSFilenamesPboardType]) //webviews already do this, this just enables openURL when tabless
	}

	override func viewWillAppear() {
		super.viewWillAppear()
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		if let window = view.window, toolbar = window.toolbar {
			//if #available(OSX 10.11, *) {
			if NSProcessInfo().isOperatingSystemAtLeastVersion(NSOperatingSystemVersion(majorVersion: 10, minorVersion: 11, patchVersion: 0)) &&
					// FIXME: toolbar delegation broken on El Capitan http://www.openradar.me/22348095
				!NSProcessInfo().isOperatingSystemAtLeastVersion(NSOperatingSystemVersion(majorVersion: 10, minorVersion: 11, patchVersion: 2)) {
					// fixed in 10.11.2 final https://forums.developer.apple.com/thread/14237#88260
			} else {
				toolbar.delegate = self
			}
			toolbar.allowsUserCustomization = true
			toolbar.displayMode = .IconOnly
			toolbar.sizeMode = .Small //favicons are usually 16*2
		}
		view.window?.excludedFromWindowsMenu = true
	}

	func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation { return NSDragOperation.Every }
	func performDragOperation(sender: NSDraggingInfo) -> Bool { return true } //should open the file:// url
}

class BrowserViewControllerOSX: TabViewController, BrowserViewController {

	var iconClient = WKIconDatabaseClientV1(
		base: WKIconDatabaseClientBase(),
		didChangeIconForPageURL: faviconChanged,
		didRemoveAllIcons: faviconsCleared,
		iconDataReadyForPageURL: faviconReady
	)

	convenience init() {
		self.init(nibName: nil, bundle: nil)

		// send browser all iconDB callbacks so it can update the tab.image's -> FavIcons
		// internally, webcore has a delegation model for grabbing icon URLs: https://bugs.webkit.org/show_bug.cgi?id=136059#c1
		iconClient.base = WKIconDatabaseClientBase(version: 1, clientInfo: unsafeAddressOf(self))
		tabMenu.delegate = self
	}

	deinit { warn(description) }
	override var description: String { return "<\(self.dynamicType))> `\(title ?? String())`" }

	func extend(mountObj: JSValue) {
		let browser = JSValue(object: self, inContext: mountObj.context)
		let helpers = // some helper code to smooth out some rough edges & wrinkles in the JSExported API
			"Object.assign(this, {" +
				"pushTab: function(tab) { this.tabs = this.tabs.concat(tab); }," +
				"popTab: function(tab) { if (this.tabs.indexOf(tab) != -1) this.tabs = this.tabs.splice(this.tabs.indexOf(tab), 1)}" +
			"})"
		browser.thisEval(helpers)
		mountObj.setValue(browser, forProperty: "browser")
	}

	var defaultUserAgent: String? = nil // {
	//	get { }
	//	set(ua) { NSUserDefaults.standardUserDefaults().setString(ua, forKey: "UserAgent") } //only works on IOS
	//} // https://github.com/WebKit/webkit/blob/master/Source/WebCore/page/NavigatorBase.cpp
	// https://github.com/WebKit/webkit/blob/master/Source/WebCore/page/mac/UserAgentMac.mm

	var isFullscreen: Bool {
		get { return view.window?.contentView?.inFullScreenMode ?? false }
		set(bool) { if bool != isFullscreen { view.window!.toggleFullScreen(nil) } }
	}

	var isToolbarShown: Bool {
		get { return view.window?.toolbar?.visible ?? true }
		set(bool) { if bool != isToolbarShown { view.window!.toggleToolbarShown(nil) } }
	}

	// really needs to be a NSHashTable or weaked swift Set
	// http://stackoverflow.com/questions/24127587/how-do-i-declare-an-array-of-weak-references-in-swift
	// https://lists.swift.org/pipermail/swift-evolution/Week-of-Mon-20151207/001581.html
	//var tabs: [WeakThing<MPWebView>] = [] {

/*
	var tabs: [MPWebView] = [] {
		willSet { // allow `$.browser.tabs = $.browser.tabs.slice(0)` to work by diffing newValue against childViewControllers
			warn()
			for webview in tabs { //removals
				if !newValue.contains(webview) {
					if let wvc = childViewControllers.filter({ ($0 as? WebViewControllerOSX)?.webview === webview }).first as? WebViewControllerOSX {
						wvc.removeFromParentViewController()
						// FIXME: not deiniting
					}
				}
			}
		}
		didSet {
			warn()
			for webview in tabs { //additions
				if !oldValue.contains(webview) {
					childViewControllers.append(WebViewControllerOSX(webview: webview))
				}
			}
		}
	}
*/
	var tabs: [MPWebView] {
		// FIXME: .count broken?
		// objc computed properties get added to JSContext as, not getter/setters
		get {
			return childViewControllers.flatMap({ $0 as? WebViewControllerOSX }).flatMap({ $0.webview })
			// returns mutable *copy*, which is why .push() can't work: https://opensource.apple.com/source/JavaScriptCore/JavaScriptCore-7537.77.1/API/JSValue.mm
		}

		set {
			// allow `$.browser.tabs = $.browser.tabs.slice(0)` to work by diffing newValue against childViewControllers
			// FIXME: crashes if you pass in a non [MPWebView] array from JS
			for webview in tabs { //removals
				if !newValue.contains(webview) {
					if let wvc = childViewControllers.flatMap({ $0 as? WebViewControllerOSX }).filter({ $0.webview === webview }).first {
						wvc.removeFromParentViewController()
						// ^ webview doesn't have a backref to its controller
						//childViewControllers.remove(wvc)
						/*
						dispatch_sync(dispatch_get_main_queue(), {
							wvc.removeFromParentViewController()
						})
						*/
					}
				}
			}
			for webview in newValue { //additions
				if !tabs.contains(webview) {
					childViewControllers.append(WebViewControllerOSX(webview: webview))
					/*
					dispatch_sync(dispatch_get_main_queue(), {
						//self.addChildViewController(WebViewControllerOSX(webview: webview))
					})
					*/
				}
			}
		}
	}

	var tabSelected: AnyObject? { // FIXME: make protocol
		get {
			if selectedTabViewItemIndex == -1 { return nil } // no tabs? bupkiss!
			let vc = childViewControllers[selectedTabViewItemIndex]
			if let obj: AnyObject = vc.representedObject { return obj } // try returning an actual model first
			return vc
		}
		set(obj) {
			switch (obj) {
				case let vc as NSViewController:
					if tabViewItemForViewController(vc) == nil { childViewControllers.append(vc) } // add the given vc as a child if it isn't already
					tabView.selectTabViewItem(tabViewItemForViewController(vc))
				case let wv as MPWebView: // find the view's existing controller or else make one and re-assign
					self.tabSelected = childViewControllers.filter({ ($0 as? WebViewControllerOSX)?.webview === wv }).first as? WebViewControllerOSX ?? WebViewControllerOSX(webview: wv)
					//FIXME: a backref in the wv to wvc would be helpful
				//case let js as JSValue: guard let wv = js.toObjectOfClass(MPWebView.self) { self.tabSelected = wv } //custom bridging coercion
				default:
					warn("invalid object")
			}
		}
	}


	override func insertChildViewController(childViewController: NSViewController, atIndex index: Int) {
		warn("#\(index)")
		super.insertChildViewController(childViewController, atIndex: index)

		if let wvc = childViewController as? WebViewController {
			//let gridItem = tabFlow.newItemForRepresentedObject(wvc)
			//gridItem.imageView = wv.favicon.icon
			//gridItem.textField = wv.title

			// set the browser as the new webview's iconClient
			wvc.webview.iconClient = iconClient
			// FIXME: should only do this once per unique processPool, tabs.filter( { $0.configuration.processProol == wvc.webview.configuration.processPool } ) ??
		}
	}

	func menuSelectedTab(sender: AnyObject?) {
		if let mi = sender as? NSMenuItem, let ti = mi.representedObject as? NSTabViewItem { tabView.selectTabViewItem(ti) }
	}

/*
	func selectedTabButtonClicked(sender: AnyObject?) {
		let omnibox = OmniBoxController(webViewController: self)

		if let btn = sender? as? NSView {
			presentViewController(omnibox, asPopoverRelativeToRect: btn.bounds, ofView: btn, preferredEdge:NSMinYEdge, behavior: .Semitransient)
		} else {
			presentViewControllerAsSheet(omnibox) //Keyboard shortcut
		}
	}
*/
/*
	func tabListButtonClicked(sender: AnyObject?) {
		if let sender = sender? as? NSView { //OpenTab toolbar button
			presentViewController(tabFlow, asPopoverRelativeToRect: sender.bounds, ofView: sender, preferredEdge:NSMinYEdge, behavior: .Semitransient)
		} else { //keyboard shortcut
			//presentViewControllerAsSheet(tabFlow) // modal, yuck
			var poprect = view.bounds
			poprect.size.height -= tabFlow.preferredContentSize.height + 12 // make room at the top to stuff the popover
			presentViewController(tabFlow, asPopoverRelativeToRect: poprect, ofView: view, preferredEdge: NSMaxYEdge, behavior: .Semitransient)
		}
	}
*/
	override func removeChildViewControllerAtIndex(index: Int) {
		warn("#\(index)")
		super.removeChildViewControllerAtIndex(index)
	}

	override func presentViewController(viewController: NSViewController, animator: NSViewControllerPresentationAnimator) {
		warn()
		super.presentViewController(viewController, animator: animator)
	}

	override func transitionFromViewController(fromViewController: NSViewController, toViewController: NSViewController,
		options: NSViewControllerTransitionOptions, completionHandler completion: (() -> Void)?) {

		super.transitionFromViewController(fromViewController, toViewController: toViewController,
			options: options, completionHandler: completion)

		//view.layer?.addSublayer(toViewController.view.layer?)

		if let window = view.window {
			window.makeFirstResponder(toViewController.view) // steal app focus to whatever the tab represents
			warn("focus is on `\(view.window?.firstResponder)`")
		}

		//warn("browser title is now `\(title ?? String())`")
	}

    //var matchedAddressOptions: [String:String] { //alias to global singleton from WebViewDelegates
    //    get { return MatchedAddressOptions }
    //    set { MatchedAddressOptions = newValue }
    //}

	//MARK: menu & shortcut selectors

	func switchToPreviousTab() { tabView.selectPreviousTabViewItem(self) }
	func switchToNextTab() { tabView.selectNextTabViewItem(self) }

	func loadSiteApp() { AppScriptRuntime.shared.loadSiteApp() }
	func editSiteApp() { NSWorkspace.sharedWorkspace().openFile(NSBundle.mainBundle().resourcePath!) }

	func newTabPrompt() {
		//tabSelected = WebViewControllerOSX(url: NSURL(string: "about:blank")!)
		tabSelected = MPWebView(url: NSURL(string: "about:blank")!)
		revealOmniBox()
	}

	func newIsolatedTabPrompt() {
		tabSelected = MPWebView(url: NSURL(string: "about:blank")!, agent: nil, isolated: true)
		revealOmniBox()
	}

	func newPrivateTabPrompt() {
		tabSelected = MPWebView(url: NSURL(string: "about:blank")!, agent: nil, isolated: true, privacy: true)
		revealOmniBox()
	}

	func revealOmniBox() {
		if omnibox.view.window != nil {
			// if omnibox is already visible somewhere in the window, move key focus there
			view.window?.makeFirstResponder(omnibox.view)
		} else {
			//let omnibox = OmniBoxController(webViewController: self)
			// otherwise, present it as a sheet or popover aligned under the window-top/toolbar
			//presentViewControllerAsSheet(omnibox) // modal, yuck
			var poprect = view.bounds
			poprect.size.height -= omnibox.preferredContentSize.height + 12 // make room at the top to stuff the popover
			presentViewController(omnibox, asPopoverRelativeToRect: poprect, ofView: view, preferredEdge: NSRectEdge.MaxY, behavior: NSPopoverBehavior.Transient)
		}
	}

	func pushTab(webview: AnyObject) { if let webview = webview as? MPWebView { addChildViewController(WebViewControllerOSX(webview: webview)) } }

	override func removeTabViewItem(tab: NSTabViewItem) {
		super.removeTabViewItem(tab)
		if tabView.tabViewItems.count != 0 {
			tabView.selectNextTabViewItem(self) //safari behavior
			// previous webview should be released and deinit'd now
		} else {
			// just closed the last item, self destruct the browser
			omnibox.webview = nil
			view.window?.makeFirstResponder(nil)
			// last webview should be released and deinit'd now
			self.view.window?.windowController?.close() // kicks off automatic app termination
		}
	}

	func focusOnBrowser() {  // un-minimizes app, switches to its screen/space, and steals key focus to the window
		//NSApplication.sharedApplication().activateIgnoringOtherApps(true)
		let app = NSRunningApplication.currentApplication()
		app.unhide() // un-minimize app
		app.activateWithOptions(.ActivateIgnoringOtherApps) // brings up key window
		view.window?.makeKeyAndOrderFront(nil) // steals key focus
		// CoreProcess stealer: https://github.com/gnachman/iTerm2/commit/c2a79333da01116ce84ec38d573fd95e3f632e4f
	}

	func unhideApp() { // un-minimizes app, but doesn't steal key focus or screen or menubar
		let app = NSRunningApplication.currentApplication()
		app.unhide() // un-minimize app
		app.activateWithOptions(.ActivateIgnoringOtherApps) // brings up key window
		view.window?.makeKeyAndOrderFront(nil) // steals key focus
/*
		//windowController.showWindow(self)
		NSApplication.sharedApplication().unhide(self)
		NSApplication.sharedApplication().arrangeInFront(self)
		view.window?.makeKeyAndOrderFront(nil)
*/
	}

	func indicateTab(vc: NSViewController) {
		// if VC has a tab, flash a popover pointed at its toolbar button to indicate its location
		//if let tvi = tabViewItemForViewController(vc) { }
	}

	func bounceDock() { NSApplication.sharedApplication().requestUserAttention(.InformationalRequest) } //Critical keeps bouncing

	func addShortcut(title: String, _ obj: AnyObject?) {
		if title.isEmpty {
			warn("title not provided")
			return
		}
		var mi: NSMenuItem
		switch (obj) {
			//case is String: fallthrough
			//case is [String:AnyObject]: fallthrough
            //case is [String]: shortcutsMenu.addItem(MenuItem(title, "gotoShortcut:", target: self, represents: obj))
            case let str as String: mi = MenuItem(title, "gotoShortcut:", target: self, represents: str)
            case let dict as [String:AnyObject]: mi = MenuItem(title, "gotoShortcut:", target: self, represents: dict)
            case is [AnyObject]: mi = MenuItem(title, "gotoShortcut:", target: self, represents: obj)
			default:
				warn("invalid shortcut object type!")
				return
		}
        shortcutsMenu.addItem(mi)
		mi.parentItem?.hidden = false
	}

	func gotoShortcut(sender: AnyObject?) {
		if let shortcut = sender as? NSMenuItem {
			switch (shortcut.representedObject) {
				case let urlstr as String: AppScriptRuntime.shared.jsdelegate.tryFunc("launchURL", urlstr)
				// FIXME: fire event in jsdelegate if string, only NSURLs should do launchURL
				case let dict as [String:AnyObject]: tabSelected = MPWebView(object: dict) // FIXME: do a try here
                case let arr as [AnyObject] where arr.count > 0 && arr.first is String:
                	var args = Array(arr.dropFirst())
                	if let wv = tabSelected as? MPWebView { args.append(wv) }
                	AppScriptRuntime.shared.jsdelegate.tryFunc((arr.first as! String), argv: args)
				default: warn("invalid shortcut object type!")
			}
		}
	}
}

extension BrowserViewControllerOSX: NSMenuDelegate {
	func menuHasKeyEquivalent(menu: NSMenu, forEvent event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector>) -> Bool {
		return false // no numeric index shortcuts for tabz (unlike Safari)
	}

	func menuNeedsUpdate(menu: NSMenu) {
		switch menu.title {
			//case "Shortcuts":
			case "Tabs":
				menu.removeAllItems()
				for tab in tabViewItems {
					let mi = NSMenuItem(title: tab.label, action:Selector("menuSelectedTab:"), keyEquivalent:"")
					mi.toolTip = tab.toolTip
					mi.image = tab.image
					mi.image?.size = NSSize(width: 16, height: 16)
					mi.representedObject = tab
					mi.target = self
					mi.state = (tab.tabState == .SelectedTab) ? NSOnState : NSOffState
					menu.addItem(mi)
				}
			default: return
		}
	}

	func menu(menu: NSMenu, willHighlightItem item: NSMenuItem?) {
		// popup thumbnail snapshot?
	}
}
