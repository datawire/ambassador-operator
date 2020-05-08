#!/bin/bash

cm_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$cm_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $cm_dir/..)

# shellcheck source=common.sh
source "$cm_dir/common.sh"

#################################################################################################

REL_AMB_OPER_IMAGE=$1
ARTIFACTS_DIR=$2
shift 2

AMB_OPER_MANIF=$@

#################################################################################################

artifact_crds_manif=$ARTIFACTS_DIR/ambassador-operator-crds.yaml
artifact_oper_manif=$ARTIFACTS_DIR/ambassador-operator.yaml

info "Preparing release manifests in $ARTIFACTS_DIR"
rm -f $ARTIFACTS_DIR/*.yaml

info "Creating CRD"
cat $TOP_DIR/deploy/crds/*_crd.yaml >$artifact_crds_manif

info "Creating generic manifest"
cat $AMB_OPER_MANIF | sed -e "s|REPLACE_IMAGE|$REL_AMB_OPER_IMAGE|g" >$artifact_oper_manif

third_party_manifest_base=$ARTIFACTS_DIR/$(basename $artifact_oper_manif .yaml)
for d in deploy/third-party/*; do
	[ -d $d ] || continue
	db=$(basename $d)
	info "Creating manifests for $db"
	cat $artifact_oper_manif $d/*.yaml >${third_party_manifest_base}-${db}.yaml
done

info "Files generated in $ARTIFACTS_DIR: $(ls $ARTIFACTS_DIR | tr '\n' ' ')"
