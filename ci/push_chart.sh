#!/bin/bash

CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$CURR_DIR" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$CURR_DIR/..

# shellcheck source=common.sh
source "$CURR_DIR/common.sh"

#########################################################################################

HELM_DIR="$TOP_DIR/deploy/helm/ambassador-operator"

HELM_CHART_YAML="$HELM_DIR/Chart.yaml"

HELM_REPO="https://getambassador.io/helm/"
HELM_REPO_INDEX="https://getambassador.io/helm/index.yaml"

#########################################################################################

if [ -z "$TRAVIS_TAG" ]; then
	info "No TRAVIS_TAG in environment: no Helm package will be built..."
	exit 0
fi

info "Setting appVersion:"
sed -i -e "s/^appVersion:.*/appVersion: $TRAVIS_TAG/g" "$HELM_CHART_YAML"
grep appVersion "$HELM_CHART_YAML"

info "Pushing Helm Chart"
helm package $HELM_DIR/

# Get name of package
export CHART_PACKAGE=$(ls *.tgz)

info "Getting current index"
curl -o tmp.yaml -k -L "$HELM_REPO_INDEX" || abort "could not merge with download index"

info "Adding to index..."
helm repo index . --url "$HELM_REPO" --merge tmp.yaml || abort "could not merge with current index"

[ -n "$AWS_ACCESS_KEY_ID" ] || abort "AWS_ACCESS_KEY_ID is not set"
[ -n "$AWS_SECRET_ACCESS_KEY" ] || abort "AWS_SECRET_ACCESS_KEY is not set"
[ -n "$AWS_BUCKET" ] || abort "AWS_BUCKET is not set"

if [ -z "$PUSH_CHART" ] || [ "$PUSH_CHART" = "false" ]; then
	info "PUSH_CHART is undefined (or defined as false) in environment: the chart will not be pushed..."
	exit 0
fi

info "Pushing chart to S3 bucket $AWS_BUCKET"
for f in "$CHART_PACKAGE" "index.yaml"; do
	aws s3api put-object \
		--bucket "$AWS_BUCKET" \
		--key "ambassador/$f" \
		--body "$f" && passed "... ambassador/$f pushed"
done

info "Cleaning up..."
rm tmp.yaml index.yaml "$CHART_PACKAGE"

exit 0
