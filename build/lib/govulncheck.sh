#!/usr/bin/env bash
# Copyright Amazon.com Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_ROOT}/common.sh"

rungovulncheck() {
    local -r goversion=$1
    local -r repo=$2

    build::common::use_go_version $goversion
    go install golang.org/x/vuln/cmd/govulncheck@latest
    govluncheckoutput=$($(go env GOPATH)/bin/govulncheck -C $repo -json ./...)
    detectedcves=$(echo $govluncheckoutput | jq '.osv | select( . != null ) | .aliases[0]')
    if [ "$detectedcves" == "" ];then
        echo "No CVEs detected "
        exit 0
    fi
    echo $detectedcves

    builderbasegoversion=$(getbuilderbasegoversion $goversion)
    cleanedbuilderbasegoversion="v${builderbasegoversion/-/-eks-}"
    cleanedbuilderbasegoversion="eks-distro-golang:${cleanedbuilderbasegoversion//./-}"
    echo "builder base golang version: $cleanedbuilderbasegoversion"

    fixedcves=$(getgolangvex | jq --arg v "$cleanedbuilderbasegoversion" '[.vulnerabilities[] | select( .product_status.fixed[] | contains($v)) | .cve'])
    if [ "$fixedcves" == "" ];then
        echo "No CVE fixes present"
    fi
    echo $fixedcves

    for cve in $detectedcves
    do
        cvefixed=$(echo $fixedcves | jq "index($cve) | select( . != null)")
        if [ "$cvefixed" == "" ]; then
            echo "CVE Detected: $cve is not addressed by a known patch to $goversion"
        fi
    done
}

getbuilderbasegoversion() {
    local -r goversion=$1
    local -r cleanedversion=${goversion//.}
    curl -s https://raw.githubusercontent.com/aws/eks-distro-build-tooling/main/builder-base/versions.yaml | yq ".GOLANG_VERSION_$cleanedversion"
}

getgolangvex() {
    curl -s https://raw.githubusercontent.com/aws/eks-distro-build-tooling/main/projects/golang/go/VulnerabilityManagement/eks-distro-golang-vex.json
}