#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2019 Shivam Kumar Jha <jha.shivam3@gmail.com>
#
# Helper functions

# Store project path
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"

# Common stuff
source ${PROJECT_DIR}/helpers/common_script.sh

# Arguements check
if [ -z ${1} ] || [ -z ${2} ]; then
    echo -e "Usage: bash rebase_kernel.sh <kernel zip link/file> <repo name> <OPTIONAL: tag suffix>"
    exit 1
fi

# Download compressed kernel source
if [[ "$1" == *"http"* ]]; then
    URL=${1}
    dlrom
else
    URL=$( realpath "$1" )
    echo "Copying file"
    cp -a ${1} ${PROJECT_DIR}/input/
fi
FILE=${URL##*/}
EXTENSION=${URL##*.}
UNZIP_DIR=${FILE/.$EXTENSION/}
[[ -d ${PROJECT_DIR}/kernels/${UNZIP_DIR} ]] && rm -rf ${PROJECT_DIR}/kernels/${UNZIP_DIR}

# Extract file
echo "Extracting file"
mkdir -p ${PROJECT_DIR}/kernels/${UNZIP_DIR}
7z x ${PROJECT_DIR}/input/${FILE} -y -o${PROJECT_DIR}/kernels/${UNZIP_DIR} > /dev/null 2>&1
KERNEL_DIR="$(dirname "$(find ${PROJECT_DIR}/kernels/${UNZIP_DIR} -type f -name "AndroidKernel.mk" | head -1)")"
AUDIO_KERNEL_DIR="$(dirname "$(find ${PROJECT_DIR}/kernels/${UNZIP_DIR} -type d -name "audio-kernel" | head -1)")"
[[ ! -e ${KERNEL_DIR}/Makefile ]] && KERNEL_DIR="$(dirname "$(find ${PROJECT_DIR}/kernels/${UNZIP_DIR} -type f -name "build.config.goldfish.arm64" | head -1)")"
NEST="$( find ${PROJECT_DIR}/kernels/${UNZIP_DIR} -type f -size +50M -printf '%P\n' | head -1)"
if [ ! -z ${NEST} ] && [[ ! -e ${KERNEL_DIR}/Makefile ]]; then
    bash ${PROJECT_DIR}/tools/rebase_kernel.sh ${PROJECT_DIR}/kernels/${UNZIP_DIR}/${NEST} ${2} ${3}
    rm -rf ${PROJECT_DIR}/input/${NEST}
    rm -rf ${PROJECT_DIR}/kernels/${UNZIP_DIR}
    exit
fi
cd ${KERNEL_DIR}
[[ -d ${KERNEL_DIR}/.git/ ]] && rm -rf ${KERNEL_DIR}/.git/

# Find kernel version
KERNEL_VERSION="$( cat Makefile | grep VERSION | head -n 1 | sed "s|.*=||1" | sed "s| ||g" )"
KERNEL_PATCHLEVEL="$( cat Makefile | grep PATCHLEVEL | head -n 1 | sed "s|.*=||1" | sed "s| ||g" )"
[[ -z "$KERNEL_VERSION" ]] && echo -e "Error!" && exit 1
[[ -z "$KERNEL_PATCHLEVEL" ]] && echo -e "Error!" && exit 1
echo "${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}"

# Move to common msm kernel directory with fetched TAG's
if [[ ! -d ${PROJECT_DIR}/kernels/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL} ]]; then
    mkdir -p ${PROJECT_DIR}/kernels/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}
    cd ${PROJECT_DIR}/kernels/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}
    git init -q
    git config core.fileMode false
    git config merge.renameLimit 999999
    git remote add msm https://source.codeaurora.org/quic/la/kernel/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}
fi

# Create release branch
echo "Creating release branch"
cd ${PROJECT_DIR}/kernels/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}
git checkout -b release -q
rm -rf *
cp -a ${KERNEL_DIR}/* ${PROJECT_DIR}/kernels/msm-${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}
[[ -d ${AUDIO_KERNEL_DIR}/audio-kernel/ ]] && mkdir -p techpack/ && mv ${AUDIO_KERNEL_DIR}/audio-kernel/ techpack/audio
git add --all > /dev/null 2>&1
git commit -sm "OEM Release" > /dev/null 2>&1
rm -rf ${PROJECT_DIR}/kernels/${UNZIP_DIR}

# Hardcode best CAF TAG
CAF_TAG="LA.UM.8.11.r1-02400-NICOBAR.0"
git fetch msm "refs/tags/$CAF_TAG:$CAF_TAG" > /dev/null 2>&1

# Rebase to best CAF tag
git checkout -q "refs/tags/${CAF_TAG}" -b "release-${CAF_TAG}"

# Apply OEM modifications
echo "Applying OEM modifications"
git diff "release-${CAF_TAG}" release | git apply --reject > /dev/null 2>&1
DIFFPATHS=(
    "Documentation/"
    "arch/arm/boot/dts/"
    "arch/arm64/boot/dts/"
    "arch/arm/configs/"
    "arch/arm64/configs/"
    "arch/"
    "block/"
    "crypto/"
    "drivers/android/"
    "drivers/base/"
    "drivers/block/"
    "drivers/media/platform/msm/camera/"
    "drivers/media/platform/msm/camera_v2/"
    "drivers/media/platform/msm/vidc/"
    "drivers/media/platform/msm/"
    "drivers/char/"
    "drivers/clk/"
    "drivers/cpufreq/"
    "drivers/cpuidle/"
    "drivers/gpu/drm/msm/sde/"
    "drivers/gpu/drm/msm/"
    "drivers/gpu/drm/"
    "drivers/gpu/msm/"
    "drivers/gpu/"
    "drivers/input/touchscreen/"
    "drivers/input/fingerprint/"
    "drivers/input/misc/"
    "drivers/input/"
    "drivers/irqchip/"
    "drivers/leds/"
    "drivers/media/"
    "drivers/misc/"
    "drivers/mmc/"
    "drivers/nfc/"
    "drivers/power/supply/qcom/"
    "drivers/power/supply/"
    "drivers/power/"
    "drivers/scsi/ufs/"
    "drivers/scsi/"
    "drivers/soc/"
    "drivers/spi/"
    "drivers/staging/"
    "drivers/thermal/"
    "drivers/usb/"
    "drivers/video/"
    "drivers/"
    "firmware/"
    "fs/f2fs"
    "fs/pstore/"
    "fs/"
    "init/"
    "include/"
    "kernel/sched/"
    "kernel/"
    "mm/"
    "net/"
    "security/"
    "sound/"
    "techpack/audio/"
    "techpack/camera/"
    "techpack/display/"
    "techpack/stub/"
    "techpack/video/"
    "techpack/"
    "tools/"
)
for ELEMENT in ${DIFFPATHS[@]}; do
    [[ -d $ELEMENT ]] && git add $ELEMENT > /dev/null 2>&1
    git commit -sm "${ELEMENT::-1}: Import Xiaomi changes" > /dev/null 2>&1
done
# Remaining OEM modifications
git add --all > /dev/null 2>&1
git commit -sm "treewide: Import remaining Xiaomi changes" > /dev/null 2>&1

# Push to GitHub
if [[ ${ORGMEMBER} == "y" ]] && [[ ! -z ${GIT_TOKEN} ]]; then
    echo "Pushing to GitHub"
    curl -s -X POST -H "Authorization: token ${GIT_TOKEN}" -d '{"name": "'"$2"'","description": "'"CAF Rebased kernel source"'","private": false,"has_issues": true,"has_projects": false,"has_wiki": true}' "https://api.github.com/orgs/AndroidBlobs/repos" > /dev/null 2>&1
    git push https://"$GIT_TOKEN"@github.com/AndroidBlobs/"$2".git "release-${CAF_TAG}" --force > /dev/null 2>&1
elif [[ ! -z ${GITHUB_USER} ]] && [[ ! -z ${GIT_TOKEN} ]]; then
    echo "Pushing to GitHub"
    curl https://api.github.com/user/repos\?access_token=$GIT_TOKEN -d '{"name": "'"$2"'","description": "'"CAF Rebased kernel source"'","private": false,"has_issues": true,"has_projects": false,"has_wiki": true}' > /dev/null 2>&1
    git push https://"$GIT_TOKEN"@github.com/"$GITHUB_USER"/"$2".git "release-${CAF_TAG}" --force > /dev/null 2>&1
fi

# Telegram
if [ ! -z ${GIT_TOKEN} ] && [ ! -z ${TG_API} ] && [[ ${ORGMEMBER} == "y" ]]; then
    printf "<b>Repo: $2</b>" > ${PROJECT_DIR}/working/tg.html
    printf "\n<b>Base CAF tag: $CAF_TAG</b>" >> ${PROJECT_DIR}/working/tg.html
    printf "\n<b>Kernel: ${KERNEL_VERSION}.${KERNEL_PATCHLEVEL}</b>" >> ${PROJECT_DIR}/working/tg.html
    [[ "$1" == *"http"* ]] && printf "\n<a href=\"$1\">Kernel source</a>" >> ${PROJECT_DIR}/working/tg.html
    printf "\n<a href=\"https://github.com/AndroidBlobs/$2/tree/release-${CAF_TAG}\">Kernel tree</a>" >> ${PROJECT_DIR}/working/tg.html
    CHAT_ID="@dummy_dt"
    HTML_FILE=$(cat ${PROJECT_DIR}/working/tg.html)
    curl -s "https://api.telegram.org/bot${TG_API}/sendmessage" --data "text=${HTML_FILE}&chat_id=${CHAT_ID}&parse_mode=HTML&disable_web_page_preview=True" > /dev/null 2>&1
    rm -rf ${PROJECT_DIR}/working/tg.html
fi

# Delete and rename branches
git branch -D release > /dev/null 2>&1
git branch -D "$( echo ${2} | sed "s|kernel_||g" | tr '_' '/' )-${CAF_TAG}" > /dev/null 2>&1
git branch -m "release-${CAF_TAG}" "$( echo ${2} | sed "s|kernel_||g" | tr '_' '/' )-${CAF_TAG}"
