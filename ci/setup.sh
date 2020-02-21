#!/usr/bin/env bash

setup_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$setup_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$setup_sh_dir/.."

# shellcheck source=common.sh
source "$setup_sh_dir/common.sh"

# make sure the dir where some installs go is in the path
mkdir -p "$HOME/bin"
export PATH=$HOME/bin:$PATH

info "Installing some dependencies..."
download_exe "$EXE_KUBECTL" "$EXE_KUBECTL_URL" || abort "coult not install kubectl"
download_exe "$EXE_EDGECTL" "$EXE_EDGECTL_URL" || abort "coult not install edgectl"
download_exe "$EXE_OSDK" "$EXE_OSDK_URL" || abort "coult not install Operator SDK"
passed "... dependencies installed successfully"

info "Installing golangci-lint..."
curl -sSfL "$EXE_GOLINT_URL" | sh -s -- -b $(go env GOPATH)/bin "$GOLINT_VERSION" || abort "could not install golangci-lint"
passed "... golangci-lint installed successfully"

info "Installing shfmt..."
download_exe "$EXE_SHFMT" "$EXE_SHFMT_URL" || abort "could not install shfmt"
passed "... shfmt installed successfully"

info "Installing Helm..."
curl -L "$HELM_TAR_URL" | tar xvzO linux-amd64/helm >"$EXE_HELM" || abort "could not install Helm"
chmod +x "$EXE_HELM"
passed "... helm installed successfully"

info "Installing gen-crd-api-reference-docs (from $GEN_CRD_DOCS_URL)..."
curl -o gen.zip -L "$GEN_CRD_DOCS_URL" &&
	unzip -xU gen.zip &&
	cd gen-crd-api-reference-* &&
	go install . &&
	rm -rf gen-crd-api-reference-* gen.zip || abort "could not install gen-crd-api-reference-docs"
passed "... gen-crd-api-reference-docs installed successfully"

info "Setting default python to Python 3"
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 10
passed

info "Installing pip3"
sudo apt-get update || abort "could not update repository"
sudo apt-get -y install python3-pip || abort "could not install pip3"
passed "... installed pip3 successfully"

info "Installing awscli..."
sudo pip3 install awscli || abort "could not install awscli"
passed "... installed awscli successfully"
