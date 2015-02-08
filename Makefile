#!/usr/bin/make -f
# thanks to hints from:
#   http://stackoverflow.com/a/24154763/3878712
#   http://owensd.io/2015/01/14/compiling-swift-without-xcode.html
#   http://railsware.com/blog/2014/06/26/creation-of-pure-swift-module/

exec := macpin
appdir := apps
apps := Hangouts.app Trello.app Digg.app Vine.app
#apps := $(addsuffix .app, $(basename $(wildcard sites/*)))
#apps := $(patsubst %, %.app, $(basename $(wildcard sites/*)))
debug ?=
debug += -D APP2JSLOG -D SAFARIDBG
#^ need to make sure !release target

VERSION := 1.0.0
LAST_TAG != git describe --abbrev=0 --tags
USER := kfix
REPO := MacPin
ZIP := $(exec).zip
GH_RELEASE_JSON = '{"tag_name": "v$(VERSION)","target_commitish": "master","name": "v$(VERSION)","body": "MacPin build of version $(VERSION)","draft": false,"prerelease": false}'

all: $(apps)

swiftc		= xcrun -sdk macosx swiftc
sdkpath		= $(shell xcrun --show-sdk-path --sdk macosx)
frameworks	= -F $(sdkpath)/System/Library/Frameworks
bridgehdr	= $(exec)-objc-bridging.h
bridgeopt	= -import-objc-header $(bridgehdr)
bridgeincs	= $(filter %.h, $(shell clang -E -H -fmodules -ObjC $(bridgehdr) -o /dev/null 2>&1))
bridgecode	= $(wildcard $(patsubst %.h, %.m, $(bridgeincs)))
bridgeobj	= $(patsubst %.m, %.o, $(bridgecode))

srcs		= main.swift
modsrcs		= MacPin.swift
#^things that are @import'ed
objs		= $(patsubst %.swift, %.o, $(modsrcs) $(srcs))

%-objc-bridging.h:
	[ -f $@ ] || touch $@

$(exec): $(objs) $(bridgeobj)
	$(swiftc) -emit-executable -I "./" -o $@ $+

main.o: main.swift $(bridgehdr)
	$(swiftc) -emit-object $(debug) $(frameworks) $(bridgeopt) -I "./" -o $@ $<

%.o: %.swift $(bridgehdr)
	$(swiftc) -emit-object -emit-library -module-name $* -emit-module-path $*.swiftmodule $(debug) $(frameworks) $(bridgeopt) -I "./" -o $@ $<

%.o: %.m
	xcrun -sdk macosx clang -c -F $(shell xcrun --show-sdk-path)/System/Library/Frameworks -fmodules -o $@ $<

icons/%.icns: icons/%.png
	python icons/AppleIcnsMaker.py -p $<

icons/%.icns: icons/WebKit.icns
	cp $< $@

# https://developer.apple.com/library/mac/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html
# https://developer.apple.com/library/mac/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
%.app: $(exec) icons/%.icns sites/% entitlements.plist
	python2.7 -m bundlebuilder \
	--name=$* \
	--bundle-id=com.github.kfix.$(exec).$* \
	--builddir=$(appdir) \
	--executable=$(exec) \
	--iconfile=icons/$*.icns \
	--file=sites/$*:Contents/Resources \
	build
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(appdir)/$*.app/Contents/Info.plist 
	plutil -replace CFBundleVersion -string "0.0.0" $(appdir)/$*.app/Contents/Info.plist
	plutil -replace NSHumanReadableCopyright -string "built $(shell date) by $(shell id -F)" $(appdir)/$*.app/Contents/Info.plist
	#codesign -s - -f --entitlements entitlements.plist $(appdir)/$*.app && codesign -dv $(appdir)/$*.app
	asctl container acl list -file $(appdir)/$*.app || true

install: $(apps)
	cd $(appdir); cp -R $+ ~/Applications

clean:
	rm -rf $(exec) *.o *.swiftmodule *.swiftdoc *.d *.zip $(appdir)/*.app 

uninstall:
	defaults delete $(exec) || true
	rm -rf ~/Library/Caches/com.github.kfix.$(exec).* ~/Library/WebKit/com.github.kfix.$(exec).* ~/Library/WebKit/$(exec)
	rm -rf ~/Library/Saved\ Application\ State/com.github.kfix.macpin.*
	rm -rf ~/Library/Preferences/com.github.kfix.macpin.*
	cd ~/Applications; rm -rf $(apps)
	defaults read com.apple.spaces app-bindings | grep com.githib.kfix.macpin. || true
	# open ~/Library/Preferences/com.apple.spaces.plist

install_exec: $(exec)
	[ -z "$(DESTDIR)" ] || install $(exec) $(DESTDIR)/

test: $(exec)
	#defaults delete $(exec)
	$(exec) http://browsingtest.appspot.com

Xcode:
	cd $@
	cmake -G Xcode
	open MacPin.xcodeproj

tag:
	git tag -f -a v$(VERSION) -m 'release $(VERSION)'

$(ZIP): tag
	rm $(ZIP) || true
	zip -r $@ apps/*.app --exclude .DS_Store/

release: $(ZIP)
	git push -f --tags
	posturl=$$(curl --data $(GH_RELEASE_JSON) "https://api.github.com/repos/$(USER)/$(REPO)/releases?access_token=$(GITHUB_ACCESS_TOKEN)" | jq -r .upload_url | sed 's/[\{\}]//g') && \
	dload=$$(curl --fail -X POST -H "Content-Type: application/gzip" --data-binary "@$(ZIP)" "$$posturl=$(ZIP)&access_token=$(GITHUB_ACCESS_TOKEN)" | jq -r .browser_download_url | sed 's/[\{\}]//g') && \
	echo "$(REPO) now available for download at $$dload"

.PRECIOUS: icons/%.icns $(appdir)/%.app
.PHONY: clean install uninstall install_exec Xcode test all tag release