VESC_TOOL ?= $(if $(wildcard ./vesc_tool),./vesc_tool,vesc_tool)
# the build runs from $(BUILD), so a relative path has to be resolved first - a
# bare command name must be left alone for PATH to find it
VESC_TOOL_CMD = $(if $(findstring /,$(VESC_TOOL)),$(abspath $(VESC_TOOL)),$(VESC_TOOL))

PKG = vesc_scooter_support.vescpkg
BUILD = build
SRC = pkgdesc.qml ui.qml scooter_support.lisp README.md version

all: $(PKG)

# The packager stores the script as source text, so comments and indentation are
# charged against the Lisp data budget. Build from a stripped copy.
$(PKG): $(SRC) tools/minify_lisp.py tools/check_qml.py tools/pkg_readme.py
	@mkdir -p $(BUILD)
	python3 tools/check_qml.py ui.qml
	python3 tools/minify_lisp.py scooter_support.lisp $(BUILD)/scooter_support.lisp
	python3 tools/pkg_readme.py README.md $(BUILD)/README.md
	@cp pkgdesc.qml ui.qml version $(BUILD)/
	cd $(BUILD) && $(VESC_TOOL_CMD) --buildPkgFromDesc pkgdesc.qml \
		--testPkgDesc 'vesc:maxim 120' --testPkgDesc 'vesc:pronto'
	@mv $(BUILD)/$(PKG) $(PKG)

clean:
	rm -rf $(BUILD) $(PKG)

.PHONY: all clean
