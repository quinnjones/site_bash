#!/bin/sh

tmpdir="${TMPDIR:-/tmp}"

# Function: cdsshfs
#
# Mount a directory using sshfs and a standardized set of options.
# Creates local directory if it doesn't exist, and cd's to the mounted
# directory.
#
# Example:
#
#     sshfs $server /remote/path/to/mount ~/local/path
#

function cdsshfs()
{
    local host=$1;        shift
    local remote_path=$1; shift
    local local_path=$1;  shift

    opts="-o idmap=user,follow_symlinks,transform_symlinks,ControlMaster=no,ControlPath=none"

    if [[ ! -d $local_path ]]; then
        echo creating ${local_path}...
        mkdir -p $local_path
    fi

    addkey

    if ( ! grep -q "[[:space:]]$local_path" /proc/mounts ); then
        echo "mounting ${local_path}..."
        echo sshfs $opts $host:$remote_path $local_path
        sshfs $opts $host:$remote_path $local_path
    fi

    cd2 $local_path $@
}

# Function: umountsshfs
#
# Unmount a directory mounted with sshfs, but only after checking to
# see if it's already mounted (making this idempotent).

function umountsshfs()
{
    local dir=$1

    if ( grep -q "[[:space:]]$dir" $MTAB ); then
        echo "unmounting ${dir}..."
        fusermount3 -u $dir
    fi
}

# Function: umountall
#
# Unmount all sshfs mounts.

function umountall()
{
    cd ~

    local sshfs_mounts=(`grep ' fuse.sshfs ' $MTAB | awk '{print $2}'`)

    for mntpt in ${sshfs_mounts[@]}; do
        umountsshfs $mntpt
    done
}

# Function: addkey
#
# Check to see if an SSH key has been added to the keyring, and call
# "ssh-add" if not

function addkey
{
    local key=$1

    if [[ $key == '' ]]; then
        key=~/.ssh/id_rsa
    fi

    added=`ssh-add -l | grep [[:space:]]$USER\@`

    if [[ ! $added ]]; then
        echo "adding $key to ssh-agent"
        ssh-add $key
    fi
}

# Function: rdp2
#
# Emulates "-via" from vncviewer, but with rdesktop.  Additionally
# calls "ssh-add" when needed.

function rdp2
{
    local rdphost=$1
    local bastion=$2
    local port=$3
    local offset=$4

    local local_port=$[ $port + $offset ]

    addkey

    ssh -f -L${local_port}:${rdphost}:${port} $bastion sleep 10;
    rdesktop localhost:${local_port}
}

# Function: vnc2
#
# Emulate "vncviewer -via intermediate_host host:display" but calling
# "ssh-add" when needed.

function vnc2
{
    local vnchost=$1
    local port=$2
    local bastion=$3
    local offset=$4

    local local_port=$[ $port + $offset ]

    addkey

    echo ssh -f -L${local_port}:${vnchost}:${port} $bastion sleep 20;
    ssh -f -L${local_port}:${vnchost}:${port} $bastion sleep 20;
    echo vncviewer localhost:${local_port}
    vncviewer localhost:${local_port}
}

# Function: cd2
#
# cd, but accepts a list of directory components instead of a
# complete path
#
# Example:
#
#     cd2 my new path
#

function cd2
{
    local dst=$1; shift

    while [[ $@ != '' ]]; do
        if [[ $1 != '' ]]; then
            local dst="$dst/$1"
        fi
        shift
    done

    echo cd $dst

    cd "$dst"
}

# Function: setcontrolpath
#
# Set an appropriate control path for ssh so that different terminal
# types don't share the same control path.

function setcontrolpath()
{
    # check to see if the terminal is Gnome, so that we can enable
    # connection sharing between just the gnome terminal tabs (and
    # delay running into the 10-connection limit defined on bastion)
    if [[ -v COLORTERM ]]; then
        GPPID=`ps -fp $PPID | awk "/$PPID/"' { print $3 } '`
        CONTROL_PATH="ControlPath=${tmpdir}/${GPPID}-ssh-colorterm-%r@%h:%p"
    else
        CONTROL_PATH="ControlPath=${tmpdir}/$USER-ssh-xterm-%r@%h:%p"
    fi
}

