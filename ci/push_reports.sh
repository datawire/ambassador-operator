#!/bin/bash

push_rep_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$push_rep_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$push_rep_dir/..

# shellcheck source=common.sh
source "$push_rep_dir/common.sh"

#########################################################################################

# the performance runner (used for generating the index)
EXE_REPORTS_INDEX="$TOP_DIR/tests/perf/scripts/gen-index.sh"

# arguments for gcloud rsync (see https://cloud.google.com/storage/docs/gsutil/commands/rsync)
RSYNC_ARGS="-d -R -J"

# the URL-pattern used in the index.html (where FILENAME is replaced by the real file name)
PERF_REPORTS_LNK="https://storage.cloud.google.com/$GKE_PERF_REPORT_BUCKET/FILENAME?authuser=1"

# maimum number of reports in the HTML page
MAX_REPORTS=25

# gsutil
EXE_GSUTIL="gsutil"
GSUTIL_RSYNC_ARGS="-m"

#########################################################################################

# travis version of gsutil does not support "-m"
[ -n "$IS_CI" ] && GSUTIL_RSYNC_ARGS=""

tmp_dir=$(mktemp -d -t gke-reports-XXXXXXXXXX)
trap_add "rm -rf '$tmp_dir'" EXIT

ls_reports() { ls -1 $tmp_dir 2>/dev/null | grep -v index.html | tac; }
num_reports() { ls_reports | wc -l; }

reports_dir="$1"
[ -n "$reports_dir" ] || abort "no directory specief in first argument"
[ -d "$reports_dir" ] || abort "$reports_dir does not seem a directory"

info "Login into GKE"
[ "$CLUSTER_PROVIDER" == "gke" ] || abort "GKE is not set in the CLUSTER_PROVIDER env var"
[ -n "$GKE_PERF_REPORT_BUCKET" ] || abort "no GKE bucket specified in GKE_PERF_REPORT_BUCKET"
$TOP_DIR/ci/infra/providers.sh login || abort "could not login into GKE"

info "Downloading current reports to $tmp_dir"
cd "$tmp_dir" &&
	$EXE_GSUTIL $GSUTIL_RSYNC_ARGS rsync $RSYNC_ARGS "gs://$GKE_PERF_REPORT_BUCKET" . ||
	abort "could not download the current performance reports to $tmp_dir"
passed "... current reports downloaded to $tmp_dir"
rm -f "$tmp_dir/index.html"

if [ $(num_reports) -gt $MAX_REPORTS ]; then
	info "Getting rid of old reports..."
	# TODO
fi

info "Copying latest report from $reports_dir to $tmp_dir"
cp -f $reports_dir/* $tmp_dir/ ||
	abort "could not download the current performance reports from $reports_dir to $tmp_dir"

info "Generating new index.html at $tmp_dir"
export LATENCY_REPORTS_LINK="$PERF_REPORTS_LNK"
$EXE_REPORTS_INDEX "$tmp_dir" >"$tmp_dir/index.html" || abort "could not generate index in $tmp_dir"
[ -f "$tmp_dir/index.html" ] || abort "no $tmp_dir/index.html found after generating the index"
info "Current contents of $tmp_dir"
ls_reports

info "Uploading reports from $tmp_dir"
cd "$tmp_dir" &&
	$EXE_GSUTIL $GSUTIL_RSYNC_ARGS rsync $RSYNC_ARGS . "gs://$GKE_PERF_REPORT_BUCKET" ||
	abort "could not upload the current performance reports to $tmp_dir"

info "Making the gs://$GKE_PERF_REPORT_BUCKET bucket public"
$EXE_GSUTIL iam ch allUsers:objectViewer gs://$GKE_PERF_REPORT_BUCKET ||
	abort "could not modify permissions"

passed "Report available at https://storage.cloud.google.com/$GKE_PERF_REPORT_BUCKET/index.html?authuser=1"
