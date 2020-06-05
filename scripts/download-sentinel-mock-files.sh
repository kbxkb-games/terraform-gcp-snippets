#!/bin/bash

# =======================================================================================
# Author: Koushik Biswas @Cloudreach
# Documentation of TFE REST API-s:
# 	Run: https://www.terraform.io/docs/cloud/api/run.html
# 	Plan-exports: https://www.terraform.io/docs/cloud/api/plan-exports.html
# Sample usage:
#	./si-download-sentinel-mockfiles.sh -t "token" -r "run-Ms2cDv3m8PTawAgt"
# =======================================================================================

#Check if jq is installed. We need jq for parsing JSON responses from Terraform API calls
hash jq 2>/dev/null
if [ $? -ne 0 ] ; then
	hash yum 2>/dev/null
	if [ $? -eq 0 ] ; then
		echo >&2 "Oops. \"jq\" is not installed. Run \"sudo yum install jq\". Aborting.";
		exit 1;
	fi
	hash apt-get 2>/dev/null
	if [ $? -eq 0 ] ; then
		echo >&2 "Oops. \"jq\" is not installed. Run \"sudo apt-get update\", followed by \"sudo apt-get install jq\". Aborting.";
		exit 1;
	fi
	echo >&2 "\"jq\" is not installed. Install \"jq\" and try again. Aborting.";
	exit 1;
fi

# Usage - prints usage and exits
usage()
{
	error=$'Usage:\nsi-download-sentinel-mockfiles.sh\n\t--token|-t <terraform bearer token>\n\t--planids|-p <comma separated list of plan ids>\n\t--runids|-r <comma separated list of run ids>\n(Note that either run id or plan id is needed. Specifying both will result in error)'
	echo >&2 "$error"
	exit 1;
}

token=""
planids=""
runids=""
readonly TF_HOSTNAME="app.terraform.io"
while [ $# -gt 0 ] ; do
	case $1 in
		-t | --token)
			token=$2
			if [[ "$token" == "-p" || "$token" == "--planid"* || \
				"$token" == "-r" || "$token" == "--runid"* || \
				-z "${token// }" ]] ; then
				usage
			fi
			shift;shift;continue
			;;
		-p | --planids | --planid)
			planids=$2
			if [[ -z "${planids// }" ]] ; then
				usage
			fi
			shift;shift;continue
			;;
		-r | --runids | --runid)
			runids=$2
			if [[ -z "${runids// }" ]] ; then
				usage
			fi
			shift;shift;continue
			;;
		*)
			usage
			;;
	esac
done

if [[ -z "${token// }" ]] ; then
	usage
fi

if [[ -z "${planids// }" && -z "${runids// }" ]] ; then
	echo >&2 "ERROR: Either plan id or run id is required"
	echo >&2 ""
	usage
fi

if [[ "$planids" && "$runids" ]] ; then
	echo >&2 "ERROR: Both plan id and run id is specified, please specify only one!"
	echo >&2 ""
	usage
fi

# Retrieve the plan id, given the run id
# =======================================================================================
# Parameters:
# -----------
# INPUTS:
#	$1 --> TFE Token for authentication and authorization by TFE
#	$2 --> run id
# OUTPUT:
#	$3 --> plan id if successful - works like output variable, set inside
#		(error message if not successful)
# =======================================================================================
get_plan_id_from_run_id()
{
	local __local_tfe_token=$1
	local __local_run_id=$2
	local __local_out_var_name=$3
	local __local_out_var_value=""

	if [[ ! "$__local_tfe_token" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": tfe token is required as first parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_run_id" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": run id is required as second parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_out_var_name" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": output variable is required as third parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	get_planid_curl_cmd="curl --request GET --silent --write-out %{http_code} --output delme-payload --header 'Authorization: Bearer "$__local_tfe_token"' \"https://"$TF_HOSTNAME"/api/v2/runs/"$__local_run_id"\""

	http_response_code=`eval "$get_planid_curl_cmd"`
	curl_retval=$?
	if [ $curl_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", run id input ["$__local_run_id"]: curl failed. Exit code from curl (interpret using https://ec.haxx.se/usingcurl/usingcurl-returns): "$curl_retval
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	get_planid_response=$(<delme-payload)
	__local_out_var_value=`echo $get_planid_response | jq '.data.relationships.plan.data.id' 2>/dev/null`
	jq_retval=$?
	if [ $jq_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", run id input ["$__local_run_id"]: jq failed to parse JSON response from TFE. jq exit status is "$jq_retval". Response received from TFE is ["$get_planid_response"]"
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ "$__local_out_var_value" == "null" ]] ; then
		__local_out_var_value=`echo $get_planid_response | jq -c '.errors' 2>/dev/null`
		if [[ "$__local_out_var_value" == "null" ]] ; then
			__local_out_var_value="ERROR in "${FUNCNAME[0]}", run id input ["$__local_run_id"]: TFE Response unrecognized - neither \"data\".\"relationships\".\"plan\".\"data\".\"id\" nor \"errors\" found. Exact response is inside the square brackets = ["$get_planid_response"]"
		fi
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ ! "$http_response_code" == "2"* ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", run id input ["$__local_run_id"]: Http response code received other than 2XX. HTTP Response Code: "$http_response_code
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	__local_out_var_value=`echo $__local_out_var_value | sed 's/^\"\(.*\)\"$/\1/'g`
	eval $__local_out_var_name="'$__local_out_var_value'"
	rm -f ./delme-payload
}

# Request a mock data plan export for a given plan id
# =======================================================================================
# Parameters:
# -----------
# INPUTS:
#	$1 --> TFE Token for authentication and authorization by TFE
#	$2 --> plan id to request mock data export
# OUTPUT:
#	$3 --> Plan export id if successful - works like output variable, set inside
#		(error message if not successful)
# =======================================================================================
request_plan_export()
{
	local __local_tfe_token=$1
	local __local_plan_id=$2
	local __local_out_var_name=$3
	local __local_out_var_value=""

	if [[ ! "$__local_tfe_token" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": tfe token is required as first parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_plan_id" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": plan id is required as second parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_out_var_name" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": output variable is required as third parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	payload="{\"data\": {\"type\": \"plan-exports\", \"attributes\": {\"data-type\": \"sentinel-mock-bundle-v0\"}, \"relationships\": {\"plan\": {\"data\": {\"id\": \""$__local_plan_id"\", \"type\": \"plans\"} } } }}"
	echo $payload > delme-payload

	request_mock_export_curl_cmd="curl --request POST --silent --write-out %{http_code} --output delme-payload --header 'Authorization: Bearer "$__local_tfe_token"' --header 'Content-Type: application/vnd.api+json' --data-binary '@./delme-payload' \"https://"$TF_HOSTNAME"/api/v2/plan-exports\""

	http_response_code=`eval "$request_mock_export_curl_cmd"`
	curl_retval=$?
	if [ $curl_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan id input ["$__local_plan_id"]: curl failed. Exit code from curl (interpret using https://ec.haxx.se/usingcurl/usingcurl-returns): "$curl_retval
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	request_mock_export_response=$(<delme-payload)
	__local_out_var_value=`echo $request_mock_export_response | jq '.data.id' 2>/dev/null`
	jq_retval=$?
	if [ $jq_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan id input ["$__local_plan_id"]: jq failed to parse JSON response from TFE. jq exit status is "$jq_retval". Response received from TFE is ["$request_mock_export_response"]"
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ "$__local_out_var_value" == "null" ]] ; then
		__local_out_var_value=`echo $request_mock_export_response | jq -c '.errors' 2>/dev/null`
		if [[ "$__local_out_var_value" == "null" ]] ; then
			__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan id input ["$__local_plan_id"]: TFE Response unrecognized - neither \"data\".\"id\" not \"errors\" found. Exact response is inside the square brackets = ["$request_mock_export_response"]"
		fi
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ ! "$http_response_code" == "2"* ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan id input ["$__local_plan_id"]: Http response code received other than 2XX. HTTP Response Code: "$http_response_code
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	__local_out_var_value=`echo $__local_out_var_value | sed 's/^\"\(.*\)\"$/\1/'g`
	eval $__local_out_var_name="'$__local_out_var_value'"
	rm -f ./delme-payload
}

# Retrieve the status of a plan export, given the plan export id
# =======================================================================================
# Parameters:
# -----------
# INPUTS:
#	$1 --> TFE Token for authentication and authorization by TFE
#	$2 --> plan export id
# OUTPUT:
#	$3 --> status of the export if successful - works like output variable, set inside
#		(error message if not successful)
# =======================================================================================
get_plan_export_status()
{
	local __local_tfe_token=$1
	local __local_plan_export_id=$2
	local __local_out_var_name=$3
	local __local_out_var_value=""

	if [[ ! "$__local_tfe_token" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": tfe token is required as first parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_plan_export_id" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": plan export id is required as second parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_out_var_name" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": output variable is required as third parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	request_status_curl_cmd="curl --request GET --silent --write-out %{http_code} --output delme-payload --header 'Authorization: Bearer "$__local_tfe_token"' --header 'Content-Type: application/vnd.api+json' \"https://"$TF_HOSTNAME"/api/v2/plan-exports/"$__local_plan_export_id"\""

	http_response_code=`eval "$request_status_curl_cmd"`
	curl_retval=$?
	if [ $curl_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: curl failed. Exit code from curl (interpret using https://ec.haxx.se/usingcurl/usingcurl-returns): "$curl_retval
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	request_status_response=$(<delme-payload)
	__local_out_var_value=`echo $request_status_response | jq '.data.attributes.status' 2>/dev/null`
	jq_retval=$?
	if [ $jq_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: jq failed to parse JSON response from TFE. jq exit status is "$jq_retval". Response received from TFE is ["$request_status_response"]"
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ "$__local_out_var_value" == "null" ]] ; then
		__local_out_var_value=`echo $request_status_response | jq -c '.errors' 2>/dev/null`
		if [[ "$__local_out_var_value" == "null" ]] ; then
			__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: TFE Response unrecognized - neither \"data\".\"id\" not \"errors\" found. Exact response is inside the square brackets = ["$request_status_response"]"
		fi
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	if [[ ! "$http_response_code" == "2"* ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: Http response code received other than 2XX. HTTP Response Code: "$http_response_code
		eval $__local_out_var_name="'$__local_out_var_value'"
		rm -f ./delme-payload
		return 1
	fi

	__local_out_var_value=`echo $__local_out_var_value | sed 's/^\"\(.*\)\"$/\1/'g`
	eval $__local_out_var_name="'$__local_out_var_value'"
	rm -f ./delme-payload
}

# Download the mock data, given the plan export id
# =======================================================================================
# Parameters:
# -----------
# INPUTS:
#	$1 --> TFE Token for authentication and authorization by TFE
#	$2 --> plan export id
# OUTPUT:
#	$3 --> path of the saved mock data file - works like output variable, set inside
#		(path of .tar.gz file is relative to cwd)
#		(error message if not successful)
# =======================================================================================
download_mock_data()
{
	local __local_tfe_token=$1
	local __local_plan_export_id=$2
	local __local_out_var_name=$3
	local __local_out_var_value=""

	if [[ ! "$__local_tfe_token" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": tfe token is required as first parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_plan_export_id" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": plan export id is required as second parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi
	if [[ ! "$__local_out_var_name" ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}": output variable is required as third parameter"
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	mock_data_file_name=$__local_plan_export_id"-export.tar.gz"
	download_mock_curl_cmd="curl --request GET --silent --write-out %{http_code} --output "$mock_data_file_name" --header 'Authorization: Bearer "$__local_tfe_token"' --header 'Content-Type: application/vnd.api+json' --location \"https://"$TF_HOSTNAME"/api/v2/plan-exports/"$__local_plan_export_id"/download\""

	http_response_code=`eval "$download_mock_curl_cmd"`
	curl_retval=$?
	if [ $curl_retval -ne 0 ] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: curl failed. Exit code from curl (interpret using https://ec.haxx.se/usingcurl/usingcurl-returns): "$curl_retval
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	if [[ ! "$http_response_code" == "2"* ]] ; then
		__local_out_var_value="ERROR in "${FUNCNAME[0]}", plan export id input ["$__local_plan_export_id"]: Http response code received other than 2XX. HTTP Response Code: "$http_response_code
		eval $__local_out_var_name="'$__local_out_var_value'"
		return 1
	fi

	__local_out_var_value=$mock_data_file_name
	eval $__local_out_var_name="'$__local_out_var_value'"
}

# Split on commas
# =======================================================================================
# Parameters:
# -----------
# INPUTS:
#	$1 --> comma-separated plan ids
# OUTPUT:
#	No output vars. Function prints each comma-separated plan id to stdout, use read
# =======================================================================================
split_by_comma()
{
	OLDIFS=$IFS
	local IFS=,
	local __local_plan_id_list=($1)
	for planid in "${__local_plan_id_list[@]}"; do
		echo "$planid"
	done
	IFS=$OLDIFS
}

if [[ "$runids" ]] ; then
	# Process all run ids passed as argument:
	split_by_comma "$runids" | while read this_run_id; do
		out_plan_id=""
		echo "Attempting to extract plan id from run id ["$this_run_id"]..."
		get_plan_id_from_run_id "$token" "$this_run_id" "out_plan_id"
		retval=$?
		if [ $retval -ne 0 ] ; then
			echo "Function get_plan_id_from_run_id returned ERROR, aborting...: ["$out_plan_id"]"
			exit 1
		else
			out_plan_export_id=""
			echo "Attempting to submit request to export mock data for plan id ["$out_plan_id"]..."
			request_plan_export "$token" "$out_plan_id" "out_plan_export_id"
			retval=$?
			if [ $retval -eq 0 ] ; then
				out_status=""
				echo "Looping to check if request to download mock data for plan id ["$out_plan_id"] is completed..."
				while [ "$out_status" != "finished" ]; do
					echo "Checking if request to download mock data for plan id ["$out_plan_id"] is completed..."
					get_plan_export_status "$token" "$out_plan_export_id" "out_status"
					retval=$?
					if [ $retval -ne 0 ] ; then
					        echo "Function get_plan_export_status returned ERROR, aborting...: ["$out_status"]"
						exit 1
					else
						echo "... Received status: ["$out_status"]"
					fi
					sleep 3
				done
				out_downloaded_mock_file_path_relative=""
				echo "Attempting to download the mock data for plan id ["$out_plan_id"]..."
				download_mock_data "$token" "$out_plan_export_id" "out_downloaded_mock_file_path_relative"
				retval=$?
				if [ $retval -eq 0 ] ; then
				        echo "Mock data for plan id ["$out_plan_id"] saved: ["$out_downloaded_mock_file_path_relative"]"
					continue
				else
				        echo "Fn download_mock_data returned ERROR, aborting: ["$out_downloaded_mock_file_path_relative"]"
					exit 1
				fi
			else
		        	echo "Function request_plan_export returned ERROR, aborting...: ["$out_plan_export_id"]"
				exit 1
			fi
		fi
	done
fi

if [[ "$planids" ]] ; then
	# Process all plan ids passed as argument:
	split_by_comma "$planids" | while read download_mock_for_plan_id; do
		out_plan_export_id=""
		echo "Attempting to submit request to export mock data for plan id ["$download_mock_for_plan_id"]..."
		request_plan_export "$token" "$download_mock_for_plan_id" "out_plan_export_id"
		retval=$?
		if [ $retval -eq 0 ] ; then
			out_status=""
			echo "Looping to check if request to download mock data for plan id ["$download_mock_for_plan_id"] is completed..."
			while [ "$out_status" != "finished" ]; do
				echo "Checking if request to download mock data for plan id ["$download_mock_for_plan_id"] is completed..."
				get_plan_export_status "$token" "$out_plan_export_id" "out_status"
				retval=$?
				if [ $retval -ne 0 ] ; then
				        echo "Function get_plan_export_status returned ERROR, aborting...: ["$out_status"]"
					exit 1
				else
					echo "... Received status: ["$out_status"]"
				fi
				sleep 3
			done
			out_downloaded_mock_file_path_relative=""
			echo "Attempting to download the mock data for plan id ["$download_mock_for_plan_id"]..."
			download_mock_data "$token" "$out_plan_export_id" "out_downloaded_mock_file_path_relative"
			retval=$?
			if [ $retval -eq 0 ] ; then
			        echo "Mock data @plan id ["$download_mock_for_plan_id"] saved: ["$out_downloaded_mock_file_path_relative"]"
				continue
			else
			        echo "Function download_mock_data returned ERROR, aborting...: ["$out_downloaded_mock_file_path_relative"]"
				exit 1
			fi
		else
	        	echo "Function request_plan_export returned ERROR, aborting...: ["$out_plan_export_id"]"
			exit 1
		fi
	done
fi
