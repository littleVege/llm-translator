.PHONY: build app run install zip dmg clean

build:
	swift build

app:
	bash ./scripts/package.sh

run: app
	open "dist/LLM Translator.app"

install: app
	rm -rf "/Applications/LLM Translator.app"
	cp -R "dist/LLM Translator.app" /Applications/
	@echo "Installed to /Applications/LLM Translator.app"

# Shareable archive. ditto (not zip) preserves the code signature and
# resource layout so the .app still runs after being sent to someone else.
zip: app
	rm -f "dist/LLM-Translator.zip"
	ditto -c -k --keepParent "dist/LLM Translator.app" "dist/LLM-Translator.zip"
	@echo "Created dist/LLM-Translator.zip — send this to your friends"

# Drag-to-Applications disk image for distribution.
dmg:
	bash ./scripts/make-dmg.sh

clean:
	rm -rf .build dist
