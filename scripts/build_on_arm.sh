#!/bin/bash
# Based on a test script from avsm/ocaml repo https://github.com/avsm/ocaml

CHROOT_DIR=/tmp/arm-chroot
MIRROR=http://archive.raspbian.org/raspbian
VERSION=wheezy
CHROOT_ARCH=armhf

# Debian package dependencies for the host
HOST_DEPENDENCIES="debootstrap qemu-user-static binfmt-support sbuild"

# Debian package dependencies for the chrooted environment
GUEST_DEPENDENCIES="build-essential git m4 sudo python curl"

# Command used to run the tests
TEST_COMMAND="make test"

function setup_arm_chroot {
    # Host dependencies
    sudo apt-get update
    sudo apt-get install -qq -y ${HOST_DEPENDENCIES}

    # Create chrooted environment
    sudo mkdir ${CHROOT_DIR}
    sudo debootstrap --foreign --no-check-gpg --include=fakeroot,build-essential \
        --arch=${CHROOT_ARCH} ${VERSION} ${CHROOT_DIR} ${MIRROR}
    sudo cp /usr/bin/qemu-arm-static ${CHROOT_DIR}/usr/bin/
    sudo chroot ${CHROOT_DIR} ./debootstrap/debootstrap --second-stage
    sudo sbuild-createchroot --arch=${CHROOT_ARCH} --foreign --setup-only \
        ${VERSION} ${CHROOT_DIR} ${MIRROR}

    # Create file with environment variables which will be used inside chrooted
    # environment
    echo "export NODE_VERSION=${NODE_VERSION}" > envvars.sh
    echo "export TRAVIS_BUILD_DIR=${TRAVIS_BUILD_DIR}" >> envvars.sh
    chmod a+x envvars.sh

    # Install dependencies inside chroot
    sudo chroot ${CHROOT_DIR} apt-get update
    sudo chroot ${CHROOT_DIR} apt-get --allow-unauthenticated install \
        -qq -y ${GUEST_DEPENDENCIES}

    # Create build dir and copy travis build files to our chroot environment
    sudo mkdir -p ${CHROOT_DIR}/${TRAVIS_BUILD_DIR}
    sudo rsync -av ${TRAVIS_BUILD_DIR}/ ${CHROOT_DIR}/${TRAVIS_BUILD_DIR}/

    # Indicate chroot environment has been set up
    sudo touch ${CHROOT_DIR}/.chroot_is_done

    # mount /proc...
    sudo mount --bind /proc ${CHROOT_DIR}/proc
    sudo mount --bind /sys ${CHROOT_DIR}/sys
    sudo mount --bind /dev ${CHROOT_DIR}/dev
    sudo mount --bind /dev/pts ${CHROOT_DIR}/dev/pts

    # Call ourselves again which will cause builds to run
    sudo chroot ${CHROOT_DIR} bash -c "cd ${TRAVIS_BUILD_DIR} && ./scripts/build_on_arm.sh"
}

if [ -e "/.chroot_is_done" ]; then
  # We are inside ARM chroot
  echo "Running inside chrooted environment"
  . ./envvars.sh
  echo "Running build"
  echo "Environment: $(uname -a)"
  cd / && wget https://github.com/sweetpi/node-sqlite3-arm/releases/download/node/node-v0.10.30-linux-arm-pi.tar.gz
  tar xzvf /tmp/node-v0.10.30-linux-arm-pi.tar.gz --strip=1
  cd ${TRAVIS_BUILD_DIR}
  ls -al /usr/local/bin
  node --version
  npm --version
  # test installing from source
  npm install --build-from-source
  node-pre-gyp package testpackage
  npm test

else
  echo "Setting up chrooted ARM environment"
  setup_arm_chroot
fi