
#Include config file
-include builder.conf

DIST_DOM0 ?= fc13
DISTS_VM ?= fc17

SRC_DIR := qubes-src

# Get rid of quotes
DISTS_VM := $(shell echo $(DISTS_VM))

DISTS_ALL := $(filter-out $(DIST_DOM0),$(DISTS_VM)) $(DIST_DOM0)



GIT_REPOS := $(SRC_DIR)/core $(SRC_DIR)/gui \
				$(SRC_DIR)/installer $(SRC_DIR)/kde-dom0 \
				$(SRC_DIR)/kernel $(SRC_DIR)/qubes-manager \
				$(SRC_DIR)/template-builder $(SRC_DIR)/xen \
				$(SRC_DIR)/xfce4-dom0 $(SRC_DIR)/yum \
				$(SRC_DIR)/dom0-updates \
				$(SRC_DIR)/antievilmaid \
				$(SRC_DIR)/gpg-split \
				$(SRC_DIR)/qubes-tor \
				$(SRC_DIR)/thunderbird-qubes \
				$(SRC_DIR)/docs \
				.

COMPONENTS := $(notdir $(filter-out .,$(GIT_REPOS)))

.ONESHELL:
help:
	@echo "make qubes            -- download and build all components"
	@echo "make get-sources      -- download/update all sources"
	@echo "make xen              -- compile xen packages (for both dom0 and VM)"
	@echo "make core             -- compile qubes-core packages (for both dom0 and VM)"
	@echo "make kernel-pvops     -- compile pvops kernel package (for Dom0 and VM)"
	@echo "make kernel           -- compile both kernel packages"
	@echo "make gui              -- compile gui packages (for both dom0 and VM)"
	@echo "make addons           -- compile addons packages (for both dom0 and VM)"
	@echo "make gpg-split        -- compile gpg-split addon packages (for both dom0 and VM)"
	@echo "make qubes-tor        -- compile qubes-tor addon packages"
	@echo "make thunderbird-qubes -- compile thunderbird-qubes addon packages"
	@echo "make template         -- build template of VM system (require: core, gui, xen, addons, to be built first)"
	@echo "make qubes-manager    -- compile xen packages (for dom0)"
	@echo "make kde-dom0         -- compile KDE packages for dom0 UI"
	@echo "make xfce4-dom0       -- compile XFCE4 window manager for dom0 UI (EXPERIMENTAL)"
	@echo "make antievilmaid     -- build optional Anti Evil Maid packages"
	@echo "make installer        -- compile installer packages (firstboot and anaconda)"
	@echo "make sign-all         -- sign all packages (useful with NO_SIGN=1 in builder.conf)"
	@echo "make clean-all        -- remove any downloaded sources and builded packages"
	@echo "make clean-rpms       -- remove any downloaded sources and builded packages"
	@echo "make iso              -- update installer repos, make iso"
	@echo "make check            -- check for any uncommited changes and unsiged tags"
	@echo "make push             -- do git push for all repos, including tags"

get-sources:
	set -a
	source builder.conf
	SCRIPT_DIR=$(PWD)
	SRC_ROOT=$(PWD)/$(SRC_DIR)
	REPOS="$(GIT_REPOS)"
	for REPO in $(GIT_REPOS); do
		$$SCRIPT_DIR/get-sources.sh || exit 1
	done

$(filter-out template kde-dom0 dom0-updates, $(COMPONENTS)): % : %-dom0 %-vm

%-vm:
	@for DIST in $(DISTS_VM); do \
		MAKE_TARGET="rpms-vm" ./build.sh $$DIST $* || exit 1; \
	done

%-dom0:
	@MAKE_TARGET="rpms-dom0" ./build.sh $(DIST_DOM0) $* || exit 1

# With generic rule it isn't handled correctly (xfce4-dom0 target isn't built
# from xfce4 repo...). "Empty" rule because real package are built by above
# generic rule as xfce4-dom0-dom0
xfce4-dom0:
	@true

# Some components requires custom rules
template:
	@for DIST in $(DISTS_VM); do \
		DIST=$$DIST NO_SIGN=$(NO_SIGN) make -C $(SRC_DIR)/template-builder rpms || exit 1; \
	done

kde-dom0:
	@set -e
	@MAKE_TARGET="rpms_stage_completed1" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed2" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed3" ./build.sh $(DIST_DOM0) kde-dom0
	@MAKE_TARGET="rpms_stage_completed4" ./build.sh $(DIST_DOM0) kde-dom0

dom0-updates:
	@set -e
	@MAKE_TARGET="stage0" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage1" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage2" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage3" ./build.sh $(DIST_DOM0) dom0-updates
	@MAKE_TARGET="stage4" ./build.sh $(DIST_DOM0) dom0-updates

# Sign only unsigend files (naturally we don't expext files with WRONG sigs to be here)
sign-all:
	@if ! [ $(NO_SIGN) ] ; then \
		if ! rpm -qa | grep gpg-pubkey-211093a7 ; then \
			echo "ERROR: Current Qubes signing key not in RPM db!" ;\
			echo "Please import it first, using rpm --import" ;\
			exit 1 ;\
		fi ;\
		echo Generating list of files to sign... ; \
		FILE_LIST=""; for RPM in $(shell ls $(SRC_DIR)/*/rpm/*/*.rpm); do \
			if ! qubes-src/installer/rpm_verify $$RPM > /dev/null; then \
				echo "Adding file $$RPM" ;\
				FILE_LIST="$$FILE_LIST $$RPM" ;\
			fi ;\
		done ; \
		sudo chmod go-rw /dev/tty ;\
		echo | rpmsign --addsign $$FILE_LIST ;\
		sudo chmod go+rw /dev/tty ;\
	else \
		echo  "NO_SIGN given, skipping package signing!" ;\
	fi
	sudo ./update-local-repo.sh

addons: gpg-split qubes-tor thunderbird-qubes

# Explicit build order
qubes: get-sources xen core kernel gui addons docs template kde-dom0 installer qubes-manager dom0-updates sign-all

clean-installer-rpms:
	rm -rf $(SRC_DIR)/installer/yum/dom0-updates/rpm/*.rpm || true
	rm -rf $(SRC_DIR)/installer/yum/qubes-dom0/rpm/*.rpm || true
	rm -rf $(SRC_DIR)/installer/yum/installer/rpm/*.rpm || true
	$(SRC_DIR)/installer/yum/update_repo.sh || true

clean-rpms: clean-installer-rpms
	sudo rm -rf all-qubes-pkgs/rpm/*.rpm || true
	createrepo --update all-qubes-pkgs || true
	sudo rm -fr qubes-src/*/rpm/*/*.rpm || true

clean:
	@for REPO in $(GIT_REPOS); do \
		echo "$$REPO" ;\
		if ! [ -d $$REPO ]; then \
			continue; \
		elif [ $$REPO == "$(SRC_DIR)/kernel" ]; then \
			make -C $$REPO clean; \
		elif [ $$REPO == "$(SRC_DIR)/template-builder" ]; then \
			for DIST in $(DISTS_VM); do \
				DIST=$$DIST make -C $$REPO clean || exit 1; \
			done ;\
		elif [ $$REPO == "$(SRC_DIR)/yum" ]; then \
			echo ;\
		elif [ $$REPO == "." ]; then \
			echo ;\
		else \
			make -C $$REPO clean || exit 1; \
		fi ;\
	done;

clean-all: clean-rpms clean
	for dir in $(DISTS_ALL); do \
		if ! [ -d $$dir ]; then continue; fi; \
		sudo umount $$dir/proc; \
		sudo umount $$dir/tmp/all-qubes-pkgs; \
	done || true
	sudo rm -rf $(DISTS_ALL) || true
	sudo rm -rf $(SRC_DIR) || true

.PHONY: iso
iso:
	for repo in $(filter-out template-builder,$(GIT_REPOS)); do \
	    if make -C $$repo -n update-repo-installer > /dev/null 2> /dev/null; then \
	        make -C $$repo update-repo-installer || exit 1; \
	    fi; \
	done
	for DIST in $(DISTS_VM); do \
		DIST=$$DIST make -C $(SRC_DIR)/template-builder update-repo-installer || exit 1; \
	done
	NO_SIGN=$(NO_SIGN) make -C $(SRC_DIR)/installer update-repo || exit 1
	sudo MAKE_TARGET="iso RELEASE=$(RELEASE)" NO_SIGN=$(NO_SIGN) ./build.sh $(DIST_DOM0) installer root || exit 1
	ln -f $(SRC_DIR)/installer/build/ISO/qubes-x86_64/iso/*.iso iso/ || exit 1
	@echo "The ISO can be found in iso/ subdirectory."
	@echo "Thank you for building Qubes. Have a nice day!"


check:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do
		pushd $$REPO > /dev/null
		git status | grep "^nothing to commit" > /dev/null
		if [ $$? -ne 0 ]; then
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Uncommited changes in:"; fi
			echo "> $$REPO"; fi
	    popd > /dev/null
	done
	HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do
		pushd $$REPO > /dev/null
		git tag --contains HEAD | grep ^. > /dev/null
		if [ $$? -ne 0 ]; then
			if [ X$$HEADER_PRINTED == X ]; then HEADER_PRINTED="1"; echo "Unsigned HEADs in:"; fi
			echo "> $$REPO"; fi
	    popd > /dev/null
	done

show-vtags:
	@for REPO in $(GIT_REPOS); do
		pushd $$REPO > /dev/null
		echo -n "$$REPO: "
		git tag --contains HEAD | grep "^[Rv]" | tr '\n' ' '
		echo
	    popd > /dev/null
	done

push:
	@HEADER_PRINTED="" ; for REPO in $(GIT_REPOS); do
		pushd $$REPO > /dev/null
		echo "Pushing changes from $$REPO to remote repo $(GIT_SUBDIR) $(BRANCH)..."
		git push $(GIT_SUBDIR) $(BRANCH)
		git push $(GIT_SUBDIR) $(BRANCH) --tags
		if [ $$? -ne 0 ]; then exit 1; fi
	    popd > /dev/null
	done
	echo "All stuff pushed succesfully."
	
# Force bash for some advanced substitution (eg ${!...})
SHELL = /bin/bash
prepare-merge:
	set -a
	source builder.conf
	SCRIPT_DIR=$(PWD)
	SRC_ROOT=$(PWD)/$(SRC_DIR)
	FETCH_ONLY=1
	REPOS="$(GIT_REPOS)"
	components_var="REMOTE_COMPONENTS_$${GIT_REMOTE/-/_}"
	[ -n "$${!components_var}" ] && REPOS="`echo $${!components_var} | sed 's@^\| @ $(SRC_DIR)/@g'`"
	for REPO in $$REPOS; do
		$$SCRIPT_DIR/get-sources.sh
	done
	echo "Changes to be merged:"
	for REPO in $$REPOS; do
		pushd $$REPO > /dev/null
		if [ -n "`git log ..FETCH_HEAD`" ]; then
			echo "> $$REPO: git merge FETCH_HEAD"
			git log --pretty=oneline --abbrev-commit ..FETCH_HEAD
		fi
		popd > /dev/null
	done
