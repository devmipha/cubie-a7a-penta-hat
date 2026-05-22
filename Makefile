VERSION := $(shell cat VERSION)
DIST_DIR := dist
PKG := cubie-a7a-penta-hat-v$(VERSION)

.PHONY: check package clean install uninstall verify

check:
	bash -n install.sh uninstall.sh verify.sh
	python3 -m py_compile files/fan.py files/oled.py
	@if command -v dtc >/dev/null 2>&1; then \
		for f in overlays/*.dts; do dtc -@ -I dts -O dtb -o /tmp/$$(basename $$f .dts).dtbo $$f; done; \
	else \
		echo "dtc not installed; skipping overlay compile check"; \
	fi

package: check
	rm -rf $(DIST_DIR)/$(PKG)
	mkdir -p $(DIST_DIR)
	rsync -a --exclude='dist' --exclude='.git' --exclude='__pycache__' ./ $(DIST_DIR)/$(PKG)/
	cd $(DIST_DIR) && zip -r $(PKG).zip $(PKG) >/dev/null
	cd $(DIST_DIR) && tar -czf $(PKG).tar.gz $(PKG)

install:
	sudo ./install.sh

uninstall:
	sudo ./uninstall.sh

verify:
	sudo ./verify.sh

clean:
	rm -rf $(DIST_DIR)
	find . -type d -name __pycache__ -prune -exec rm -rf {} +
	find . -type f \( -name '*.pyc' -o -name '*.dtbo' \) -delete
