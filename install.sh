#!/bin/bash
# ::=========================================================================:: 
# Cross platform dependency installer.
#
# Author: James L. Royalty ~ Sit Stay Games 
# Public domain.
# ::=========================================================================:: 

SCRIPTDIR=$(dirname $0)

function show_help() {
    echo "Usage: $(basename $0)"
}

function log_debug() {
    $DEBUG && [[ -n "$*" ]] && echo "[debug] $*"
}

function log_info() {
    [[ -n "$*" ]] && echo "$*"
}

function die_error() {
    echo "ERROR: $*"
    exit 1
}

function to_lowercase() {
    tr [:upper:] [:lower:] <<< "${*}"
}

function copy_or_symlink() {
    local my_from="$1"
    local my_to="$2"

    local cmd_args="-L"

    if $DEBUG ; then
	cmd_args="$cmd_args -v"
    fi

    if $VERIFY ; then
	cmd_args="$cmd_args -i"
    fi

    if [ -d "$my_from" ] ; then
	cmd_args="$cmd_args -R"
    fi

    # We only copy ATM.
    cp $cmd_args $my_from $my_to
}

####
# install_from_named_dist_dir [dependency source dir] [target dir]
#
# Installs a dependency from the given source dir whether it is 
# appropriate for this platform and architecture or not.  This is typically
# called by install_single_dep() once the dependency has been qualified
# for this platform and architecture.
####
function install_from_named_dist_dir() {
    local my_source_dir="$1"
    local my_target_dir="$2"

    log_info "Installing $my_source_dir to $my_target_dir ..."

    if $DRYRUN ; then
	return 0
    fi

    local my_target_include_dir="$my_target_dir/$_INCLUDE_DIR"
    if [ ! -d "$my_target_include_dir" ] ; then
	log_debug "    creating $my_target_include_dir"
	mkdir -p "$my_target_include_dir"
    fi

    local my_target_lib_dir="$my_target_dir/$_LIB_DIR"
    if [ ! -d "$my_target_lib_dir" ] ; then
	log_debug "    creating $my_target_lib_dir"
	mkdir -p "$my_target_lib_dir"
    fi

    local handled_any=false

    local my_source_include_dir="$my_source_dir/$_INCLUDE_DIR"
    if [ -d "$my_source_include_dir" ] ; then
	for item in $(find $my_source_include_dir -depth 1) ; do
	    copy_or_symlink "$item" "$my_target_include_dir"
	done

	handled_any=true
    else
	log_info "    directory \"$my_source_include_dir\" does not exist; skipping includes."
    fi

    local my_source_lib_dir="$my_source_dir/$_LIB_DIR"
    if [ -d "$my_source_lib_dir" ] ; then
	for item in $(find $my_source_lib_dir -depth 1) ; do
	    copy_or_symlink "$item" "$my_target_lib_dir"
	done

	handled_any=true
    else
	log_info "    directory \"$my_source_lib_dir\" does not exist; skipping libs."
    fi

    $handled_any || die_error "Declared, but unhandled dependency: \"$my_dep_name\""
}

####
# install_single_dep [distribution dir] [architecture target dir]
#
# Install a dependency from the given distribution dir iff it's suitable
# for this platform and architecture.
####
function install_single_dep() {
    local my_dist_dir="$1"
    local my_target_dir="$2"

    local dist_filename="$(basename $my_dist_dir)"
    local file_arch="$(echo $dist_filename | awk -F- '{ print $(NF-1) }')"
    local file_type="$(echo $dist_filename | awk -F- '{ print $NF }')"

    log_debug "Trying to install \"$dist_filename\": arch=$file_arch, type=$file_type"

    local _is_supported_arch=false
    for _arch in ${ALL_ARCH[@]} ; do
	if [ "$_arch" == "$file_arch" ] ; then
	    _is_supported_arch=true
	fi
    done

    if ! $_is_supported_arch ; then
	log_debug "$dist_filename is not from a supported architecture: \"$file_arch\"."
	return 1
    fi

    local _type_target_dir="$my_target_dir"

    if [ -z "$file_type" ] ; then
	_type_target_dir="$_type_target_dir/$_COMMON_DIR"
    elif [ "$file_type" == "$_DEBUG_SUFFIX" ] ; then
	_type_target_dir="$_type_target_dir/$_DEBUG_DIR"
    elif [ "$file_type" == "$_RELEASE_SUFFIX" ] ; then
	_type_target_dir="$_type_target_dir/$_RELEASE_SUFFIX"
    else
	log_info "Dependency \"$my_dist_dir\" has an invalid type \"${file_type}\". Maybe the filename is incorrect?"
	return 1
    fi

    install_from_named_dist_dir "$my_dist_dir" "${_type_target_dir}"
}

# ::-------------------------------------------------------------------------:: 

# Log debug messages?
DEBUG=false

# When true then we only report what would be done.
DRYRUN=false

# Verify each item installed.
VERIFY=false

# If true then we do a clean of installed dependencies and then exit.
CLEAN_ONLY=false

# The directory contains the dependencies we are to install.
PLATFORM=$(uname -s)

# The architecture to install for.
ARCH=$(uname -m)

declare -r _DEBUG_DIR="debug"
declare -r _DEBUG_SUFFIX="debug"

declare -r _RELEASE_DIR="release"
declare -r _RELEASE_SUFFIX="release"

declare -r _COMMON_DIR="common"

declare -r _INCLUDE_DIR="include"
declare -r _LIB_DIR="lib"

# The directory below PLATFORM that contains the dependencies distribution directories.
declare -r _DIST_DIR="_dist"

while [ -n "$*" ] ; do
    arg="$1" ; shift
    case "$arg" in
	-p|--platform)
	    PLATFORM="$1" ; shift
	;;

	-a|--arch)
	    ARCH="$1" ; shift
	;;

	-c|--clean)
	    CLEAN_ONLY=true
	;;

	-n|--dryrun)
	    DRYRUN=true
	;;

	-d|--debug)
	    DEBUG=true
	;;

	-v|--verify)
	    VERIFY=true
	;;

	-h|--help)
	    show_help
	    exit 1
	;;
    esac
done

# Platform and architecture settings are required.  Assert these settings first 
# because we create file system path based on these later.
[[ -n "$PLATFORM" ]] || die_error "You must specify a platform to install for (--platform)."
PLATFORM=$(to_lowercase $PLATFORM)

[[ -n "$ARCH" ]] || die_error "You must specify a processor architecture to install for (--arch)."
ARCH=$(to_lowercase $ARCH)

PLATFORM_DIST_DIR="$PLATFORM/$_DIST_DIR"
[[ -d "$PLATFORM_DIST_DIR" ]] || die_error "Platform directory \"$PLATFORM\" does not contain a distribution directory \"$_DIST_DIR\"."

ALL_ARCH=($ARCH)
if [ "$PLATFORM" == "darwin" ] ; then
    ALL_ARCH=(universal ${ALL_ARCH[*]})
fi

log_info "Using platform: $PLATFORM; including architectures: ${ALL_ARCH[*]}"

TARGET_DIR="$PLATFORM/$ARCH"
log_info "Top-level target directory: $TARGET_DIR"

if [ -d "$TARGET_DIR" ] ; then
    log_info "Removing existing install directory in $TARGET_DIR"
    $DRYRUN || rm -rf $TARGET_DIR
fi

if $CLEAN_ONLY ; then
    exit 0
fi

log_info "Looking for distributions in $PLATFORM_DIST_DIR"

log_info "::-------------------------------------------------------------------------::"

for _dist_dir in $(find $PLATFORM_DIST_DIR -type d -depth 1) ; do
    install_single_dep $_dist_dir $TARGET_DIR
done

