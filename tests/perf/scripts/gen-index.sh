#!/usr/bin/env bash

gen_index_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$gen_index_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$gen_index_dir/../../.."

########################################################################################################################

LATENCY_REPORTS_LINK=${LATENCY_REPORTS_LINK:-}
LATENCY_REPORTS_LINK_FILENAME="FILENAME"

########################################################################################################################
# main
########################################################################################################################

directory="$1"
[ -n "$directory" ] || abort "no directory provided"
[ -d "$directory" ] || abort "'$directory' is not a valid directory"
directory=$(realpath $directory)

ls_reports() { ls -1 $directory 2>/dev/null | grep -v index.html | tac; }
num_reports() { ls_reports | wc -l; }
first_report() { ls_reports | head -n1; }

get_report_link() {
	local report="$1"
	report_filename="$(basename $report)"

	if [ -n "$LATENCY_REPORTS_LINK" ]; then
		echo "$LATENCY_REPORTS_LINK" |
			sed -e "s|$LATENCY_REPORTS_LINK_FILENAME|$report_filename|g"
	else
		echo "$report_filename"
	fi
}

get_report_name() {
	local report="$1"
	report_filename="$(basename $report)"
	basename "$report_filename" ".html" |
		sed -e 's|results||g' |
		sed -e 's|--|-|g' |
		sed -e 's|-| |g' |
		sed -e 's|default||g'
}

first_report_link=$(get_report_link $(first_report))

cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {
            font-family: "Lato", sans-serif;
        }

        .sidenav {
            height: 100%;
            width: 160px;
            position: fixed;
            z-index: 1;
            top: 0;
            left: 0;
            background-color: #111;
            overflow-x: hidden;
            padding-top: 100px;
        }

        .sidenav a {
            padding: 6px 8px 6px 16px;
            text-decoration: none;
            font-size: 16px;
            color: #818181;
            display: block;
        }

        .sidenav a:hover {
            color: #f1f1f1;
        }

        .main {
            margin-left: 160px; /* Same as the width of the sidenav */
            font-size: 28px; /* Increased text to enable scrolling */
            padding: 0px 10px;
        }

        @media screen and (max-height: 450px) {
            .sidenav {padding-top: 15px;}
            .sidenav a {font-size: 18px;}
        }
    </style>

    <script type="text/javascript">
        function loadReport(url) {
            console.log('Loading ' + url)
            document.getElementsByName('report')[0].src = url;
        }
    </script>

    <script type="text/javascript">
        function loadReport(url) {
            console.log('Loading ' + url)
            document.getElementsByName('report')[0].src = url;
        }

        window.onload = function() {
            loadReport('$first_report_link');
        };
    </script>

</head>

<body>
    <div class="sidenav">

EOF

for report in $(ls_reports); do
	report="$(realpath $report)"
	report_name="$(get_report_name $report)"
	report_link="$(get_report_link $report)"
	cat <<EOF
<a href="javascript:void(0);" onClick="loadReport('$report_link')"> $report_name </a>
EOF
done

cat <<EOF

    </div>
    <div class="main">
        <h2>Latency Report</h2>
        <iframe src=""
                height="1000px" width="100%"
                frameborder=0
                name="report"
                style =""></iframe>
    </div>
</body>
</html>
EOF
