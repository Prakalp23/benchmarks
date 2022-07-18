#!/bin/bash
#
# Copyright (c) 2020, 2021 Red Hat, IBM Corporation and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
### Script to perform load test on multiple instances of renaissance benchmark on openshift/minikube###
#
CURRENT_DIR="$(dirname "$(realpath "$0")")"
source ${CURRENT_DIR}/../renaissance-common.sh
pushd "${CURRENT_DIR}" > /dev/null
pushd ".." > /dev/null
SCRIPT_REPO=${PWD}
pushd ".." > /dev/null
LOGFILE="${PWD}/setup.log"
K_CPU=2
K_MEM=6144
# checks if the previous command is executed successfully
# input:Return value of previous command
# output:Prompts the error message if the return value is not zero 
function err_exit() {
	if [ $? != 0 ]; then
		printf "$*"
		echo
		echo "The run failed. See setup.log for more details"
		oc get pods -n ${NAMESPACE} >> ${LOGFILE}
		oc get events -n ${NAMESPACE} >> ${LOGFILE}
		oc logs pod/`oc get pods | grep "${APP_NAME}" | cut -d " " -f1` -n ${NAMESPACE} >> ${LOGFILE}
		echo "1 , 99999 , 99999 , 99999 , 99999 , 99999 , 999999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999 , 99999" >> ${RESULTS_DIR_ROOT}/Metrics-prom.log
		echo ", 99999 , 99999 , 99999 , 99999 , 9999 , 0 , 0" >> ${RESULTS_DIR_ROOT}/Metrics-wrk.log
		paste ${RESULTS_DIR_ROOT}/Metrics-prom.log ${RESULTS_DIR_ROOT}/Metrics-wrk.log ${RESULTS_DIR_ROOT}/Metrics-config.log ${RESULTS_DIR_ROOT}/deploy-config.log
		cat ${RESULTS_DIR_ROOT}/app-calc-metrics-measure-raw.log
		cat ${RESULTS_DIR_ROOT}/server_requests-metrics-${TYPE}-raw.log
		## Cleanup all the deployments
		${SCRIPT_REPO}/renaissance-cleanup.sh -c ${CLUSTER_TYPE} -n ${NAMESPACE} >> ${LOGFILE}
		exit -1
	fi
}
# Run the benchmark as
# SCRIPT BENCHMARK_SERVER_NAME NAMESPACE RESULTS_DIR_PATH WARMUPS MEASURES TOTAL_INST TOTAL_ITR RE_DEPLOY
# Ex of ARGS : --clustertype=openshift -s example.in.com -e /tfb/results -w 5 -m 3 -i 1 --iter=1 -r
# Describes the usage of the script
function usage() {
	echo
	echo "Usage: $0 --clustertype=CLUSTER_TYPE -s BENCHMARK_SERVER -e RESULTS_DIR_PATH [-w WARMUPS] [-m MEASURES] [-i TOTAL_INST] [--iter=TOTAL_ITR] [-r= set redeploy to true] [-n NAMESPACE] [-g TFB_IMAGE] [--cpureq=CPU_REQ] [--memreq=MEM_REQ] [--cpulim=CPU_LIM] [--memlim=MEM_LIM] [-t THREAD] [-R REQUEST_RATE] [-d DURATION] [--connection=CONNECTIONS]"
	exit -1
}
# Check if java is installed and it is of version 11 or newer
function check_load_prereq() {
	echo
	echo -n "Info: Checking prerequisites..." >> ${LOGFILE}
	# check if java exists
	if [ ! `which java` ]; then
		echo " "
		echo "Error: java is not installed."
		exit 1
	else
		JAVA_VER=$(java -version 2>&1 >/dev/null | egrep "\S+\s+version" | awk '{print $3}' | tr -d '"')
		case "${JAVA_VER}" in 
			1[1-9].*.*)
				echo "done" >> ${LOGFILE}
				;;
			*)
				echo " "
				echo "Error: Hyperfoil requires Java 11 or newer and current java version is ${JAVA_VER}"
				exit 1
				;;
		esac
	fi
}
# Iterate through the commandline options
while getopts s:e:w:m:i:rg:n:t:R:d:-: gopts
do
	case ${gopts} in
	-)
		case "${OPTARG}" in
			clustertype=*)
				CLUSTER_TYPE=${OPTARG#*=}
				;;
			iter=*)
				TOTAL_ITR=${OPTARG#*=}
				;;
			dbtype=*)
				DB_TYPE=${OPTARG#*=}
				;;
			dbhost=*)
				DB_HOST=${OPTARG#*=}
				;;
			cpureq=*)
				CPU_REQ=${OPTARG#*=}
				;;
			memreq=*)
				MEM_REQ=${OPTARG#*=}
				;;
			cpulim=*)
				CPU_LIM=${OPTARG#*=}
				;;
			memlim=*)
				MEM_LIM=${OPTARG#*=}
				;;
			envoptions=*)
				ENV_OPTIONS=${OPTARG#*=}
				;;
			usertunables=*)
                                OPTIONS_VAR=${OPTARG#*=}
                                ;;
			connection=*)
				CONNECTIONS=${OPTARG#*=}
				;;
			quarkustpcorethreads=*)
				quarkustpcorethreads=${OPTARG#*=}
                                ;;
			quarkustpqueuesize=*)
				quarkustpqueuesize=${OPTARG#*=}
                                ;;
			quarkusdatasourcejdbcminsize=*)
				quarkusdatasourcejdbcminsize=${OPTARG#*=}
                                ;;
			quarkusdatasourcejdbcmaxsize=*)
				quarkusdatasourcejdbcmaxsize=${OPTARG#*=}
                                ;;
			FreqInlineSize=*)
                                FreqInlineSize=${OPTARG#*=}
                                ;;
                        MaxInlineLevel=*)
                                MaxInlineLevel=${OPTARG#*=}
                                ;;
                        MinInliningThreshold=*)
                                MinInliningThreshold=${OPTARG#*=}
                                ;;
                        CompileThreshold=*)
                                CompileThreshold=${OPTARG#*=}
                                ;;
                        CompileThresholdScaling=*)
                                CompileThresholdScaling=${OPTARG#*=}
                                ;;
                        InlineSmallCode=*)
                                InlineSmallCode=${OPTARG#*=}
                                ;;
                        LoopUnrollLimit=*)
                                LoopUnrollLimit=${OPTARG#*=}
                                ;;
                        LoopUnrollMin=*)
                                LoopUnrollMin=${OPTARG#*=}
                                ;;
                        MinSurvivorRatio=*)
                                MinSurvivorRatio=${OPTARG#*=}
                                ;;
                        NewRatio=*)
                                NewRatio=${OPTARG#*=}
                                ;;
                        TieredStopAtLevel=*)
                                TieredStopAtLevel=${OPTARG#*=}
                                ;;
                        ConcGCThreads=*)
                                ConcGCThreads=${OPTARG#*=}
                                ;;
                        TieredCompilation=*)
                                TieredCompilation=${OPTARG#*=}
                                ;;
                        AllowParallelDefineClass=*)
                                AllowParallelDefineClass=${OPTARG#*=}
                                ;;
                        AllowVectorizeOnDemand=*)
                                AllowVectorizeOnDemand=${OPTARG#*=}
				;;
                        AlwaysCompileLoopMethods=*)
                                AlwaysCompileLoopMethods=${OPTARG#*=}
                                ;;
                        AlwaysPreTouch=*)
                                AlwaysPreTouch=${OPTARG#*=}
                                ;;
                        AlwaysTenure=*)
                                AlwaysTenure=${OPTARG#*=}
                                ;;
                        BackgroundCompilation=*)
                                BackgroundCompilation=${OPTARG#*=}
                                ;;
                        DoEscapeAnalysis=*)
                                DoEscapeAnalysis=${OPTARG#*=}
                                ;;
                        UseInlineCaches=*)
                                UseInlineCaches=${OPTARG#*=}
                                ;;
                        UseLoopPredicate=*)
                                UseLoopPredicate=${OPTARG#*=}
                                ;;
                        UseStringDeduplication=*)
                                UseStringDeduplication=${OPTARG#*=}
                                ;;
                        UseSuperWord=*)
                                UseSuperWord=${OPTARG#*=}
                                ;;
                        UseTypeSpeculation=*)
                                UseTypeSpeculation=${OPTARG#*=}
                                ;;
			*)
		esac
		;;
	s)
		BENCHMARK_SERVER="${OPTARG}"
		;;
	e)
		RESULTS_DIR_PATH="${OPTARG}"	
		;;
	w)
		WARMUPS="${OPTARG}"		
		;;
	m)
		MEASURES="${OPTARG}"		
		;;
	i)
		TOTAL_INST="${OPTARG}"
		;;
	r)
		RE_DEPLOY="true"
		;;
	g)
		renaissance_IMAGE="${OPTARG}"		
		;;
	n)
		NAMESPACE="${OPTARG}"		
		;;
	t)
		THREAD="${OPTARG}"
		;;
	R)
		REQUEST_RATE="${OPTARG}"
		;;
	d)
		DURATION="${OPTARG}"
		;;
	esac
done
if [[ -z "${CLUSTER_TYPE}" || -z "${BENCHMARK_SERVER}" || -z "${RESULTS_DIR_PATH}" ]]; then
	echo "Do set the variables - CLUSTER_TYPE, BENCHMARK_SERVER and RESULTS_DIR_PATH "
	usage
fi

if [ -z "${WARMUPS}" ]; then
	WARMUPS=5
fi

if [ -z "${MEASURES}" ]; then
	MEASURES=3
fi

if [ -z "${TOTAL_INST}" ]; then
	TOTAL_INST=1
fi

if [ -z "${TOTAL_ITR}" ]; then
	TOTAL_ITR=1
fi

if [ -z "${RE_DEPLOY}" ]; then
	RE_DEPLOY=false
fi

if [ -z "${BENCHMARK_IMAGE}" ]; then
	BENCHMARK_IMAGE="${prakalp23/renaissance1041:latest"}"
fi

if [ -z "${NAMESPACE}" ]; then
	NAMESPACE="default"
fi

if [ -z "${REPETITIONS}" ]; then
	REPETITIONS="20"
fi

if [ -z "${RUN_SECONDS}" ]; then
	RUN_SECONDS="40"
fi

if [ -z "${DURATION}" ]; then
	DURATION="60"
fi

if [ -z "${CONNECTIONS}" ]; then
	CONNECTIONS="512"
fi

if [[ ${CLUSTER_TYPE} == "openshift" ]]; then
        K_EXEC="oc"
elif [[ ${CLUSTER_TYPE} == "minikube" ]]; then
        K_EXEC="kubectl"
fi

RESULTS_DIR_ROOT=${RESULTS_DIR_PATH}/tfb-$(date +%Y%m%d%H%M)
mkdir -p ${RESULTS_DIR_ROOT}

#Adding 5 secs buffer to retrieve CPU and MEM info
CPU_MEM_DURATION=`expr ${DURATION} + 5`
# Check if the application is running
# output: Returns 1 if the application is running else returns 0
function check_app() {
	if [ "${CLUSTER_TYPE}" == "openshift" ]; then
                K_EXEC="oc"
        elif [ "${CLUSTER_TYPE}" == "minikube" ]; then
                K_EXEC="kubectl"
        fi
        CMD=$(${K_EXEC} get pods --namespace=${NAMESPACE} | grep "${APP_NAME}" | grep "Running" | cut -d " " -f1)
        for status in "${CMD[@]}"
        do
                if [ -z "${status}" ]; then
                        echo "Application pod did not come up" >> ${LOGFILE}
                        ${K_EXEC} get pods -n ${NAMESPACE} >> ${LOGFILE}
                        ${K_EXEC} get events -n ${NAMESPACE} >> ${LOGFILE}
                        ${K_EXEC} logs pod/`${K_EXEC} get pods | grep "${APP_NAME}" | cut -d " " -f1` -n ${NAMESPACE} >> ${LOGFILE}
                        echo "The run failed. See setup.log for more details"
                        exit -1;
                fi
        done
}

# Perform warmup and measure runs
# input: number of runs(warmup|measure), result directory 
# output: Cpu info, memory info, node info, wrk load for each runs(warmup|measure) in the form of jason files
function runItr()
{
	TYPE=$1
	RUNS=$2
	RESULTS_DIR_L=$3
	for (( run=0; run<"${RUNS}"; run++ ))
	do
		# Check if the application is running
		check_app 
		# Get CPU and MEM info through prometheus queries
		${SCRIPT_REPO}/getmetrics-promql.sh ${TYPE}-${run} ${CPU_MEM_DURATION} ${RESULTS_DIR_L} ${BENCHMARK_SERVER} ${APP_NAME} ${CLUSTER_TYPE} &
		# Sleep till the wrk load completes
		sleep ${DURATION}
		sleep 1
	done
}
# get the kruize recommendation for tfb application
# input: result directory
# output: kruize recommendations for tfb
function get_recommendations_from_kruize()
{
	if [[ ${CLUSTER_TYPE} == "openshift" ]]; then
		TOKEN=`${K_EXEC} whoami --show-token`
	fi
	APP_LIST=($(${K_EXEC} get deployments --namespace=${NAMESPACE} | grep "${APP_NAME}" | cut -d " " -f1))
	for app in "${APP_LIST[@]}"
	do
		curl --silent -k -H "Authorization: Bearer ${TOKEN}" http://kruize-openshift-monitoring.apps.${BENCHMARK_SERVER}/recommendations?application_name=${app} > ${RESULTS_DIR_I}/${app}-recommendations.log
		err_exit "Error: could not generate the recommendations for ${APP_NAME}" >> ${LOGFILE}
	done
}
function runIterations() {
	SCALING=$1
	TOTAL_ITR=$2
	WARMUPS=$3
	MEASURES=$4
	RESULTS_DIR_R=$5
	for (( itr=0; itr<"${TOTAL_ITR}"; itr++ ))
	do
		echo "***************************************" >> ${LOGFILE}
		echo "Starting iteration ${itr}" >> ${LOGFILE}
		echo "***************************************" >> ${LOGFILE}
		if [ ${RE_DEPLOY} == "true" ]; then
			echo "Deploying the application..." >> ${LOGFILE}
			${SCRIPT_REPO}/renaissance-deploy.sh --clustertype=${CLUSTER_TYPE} -s ${BENCHMARK_SERVER} -n ${NAMESPACE} -i ${SCALING} -g ${RENAISSANCE_IMAGE}  --cpureq=${CPU_REQ} --memreq=${MEM_REQ} --cpulim=${CPU_LIM} --memlim=${MEM_LIM} --envoptions="${ENV_OPTIONS}" --usertunables="${OPTIONS_VAR}"  >> ${LOGFILE}
			# err_exit "Error: ${APP_NAME} deployment failed" >> ${LOGFILE}
		fi
		# Add extra sleep time for the deployment to complete as few machines takes longer time.
		sleep 30
		
		##Debug
		#Extra sleep time
		#sleep 600
		
		# Start the load
		RESULTS_DIR_I=${RESULTS_DIR_R}/ITR-${itr}
		echo "Running ${WARMUPS} warmups" >> ${LOGFILE}
		# Perform warmup runs
		runItr warmup ${WARMUPS} ${RESULTS_DIR_I}
		echo "Running ${MEASURES} measures" >> ${LOGFILE}
		# Perform measure runs
		runItr measure ${MEASURES} ${RESULTS_DIR_I}
		sleep 15
		echo "***************************************" >> ${LOGFILE}
		echo "Completed iteration ${itr}..." >> ${LOGFILE}
		echo "***************************************" >> ${LOGFILE}
	done
}
echo "INSTANCES ,  CPU_USAGE , MEM_USAGE , CPU_MIN , CPU_MAX , MEM_MIN , MEM_MAX " > ${RESULTS_DIR_ROOT}/Metrics-prom.log
echo ", OPERATION_TIME, WEB_ERRORS , OPTIME_CI " > ${RESULTS_DIR_ROOT}/Metrics-renaissance.log
echo ", CPU_REQ , MEM_REQ , CPU_LIM , MEM_LIM " > ${RESULTS_DIR_ROOT}/Metrics-config.log
echo ", DEPLOYMENT_NAME , NAMESPACE , IMAGE_NAME , CONTAINER_NAME" > ${RESULTS_DIR_ROOT}/deploy-config.log

echo "INSTANCES , CLUSTER_CPU% , C_CPU_REQ% , C_CPU_LIM% , CLUSTER_MEM% , C_MEM_REQ% , C_MEM_LIM% " > ${RESULTS_DIR_ROOT}/Metrics-cluster.log
echo "RUN , CPU_REQ , MEM_REQ , CPU_LIM , MEM_LIM , CPU , CPU_MIN , CPU_MAX , MEM , MEM_MIN , MEM_MAX" > ${RESULTS_DIR_ROOT}/Metrics-raw.log
echo "INSTANCES ,  MEM_RSS , MEM_USAGE " > ${RESULTS_DIR_ROOT}/Metrics-mem-prom.log
echo "INSTANCES ,  CPU_USAGE" > ${RESULTS_DIR_ROOT}/Metrics-cpu-prom.log


echo "INSTANCES , CPU_MAXSPIKE , MEM_MAXSPIKE "  >> ${RESULTS_DIR_ROOT}/Metrics-spikes-prom.log


echo ", ${CPU_REQ} , ${MEM_REQ} , ${CPU_LIM} , ${MEM_LIM} " >> ${RESULTS_DIR_ROOT}/Metrics-config.log
echo ", renaissance-sample , ${NAMESPACE} , ${renaissance_IMAGE} , renaissance" >> ${RESULTS_DIR_ROOT}/deploy-config.log
if [ ${CLUSTER_TYPE} == "minikube" ]; then
#	reload_minikube ${K_CPU} ${K_MEM}
	fwd_prometheus_port_minikube
fi
#TODO Create a function on how many DB inst required for a server. For now,defaulting it to 1
# Scale the instances and run the iterations
for (( scale=1; scale<=${TOTAL_INST}; scale++ ))
do
	RESULTS_SC=${RESULTS_DIR_ROOT}/scale_${scale}
	echo "Run in progress..."
	echo "***************************************" >> ${LOGFILE}
	echo "Run logs are placed at... " ${RESULTS_DIR_ROOT} >> ${LOGFILE}
	echo "***************************************" >> ${LOGFILE}
	echo "Running the benchmark with ${scale}  instances with ${TOTAL_ITR} iterations having ${WARMUPS} warmups and ${MEASURES} measurements" >> ${LOGFILE}
	# Perform warmup and measure runs
	runIterations ${scale} ${TOTAL_ITR} ${WARMUPS} ${MEASURES} ${RESULTS_SC}
	echo "Parsing results for ${scale} instances" >> ${LOGFILE}
	# Parse the results
	# ${REPO}/parsemetrics-wrk.sh ${TOTAL_ITR} ${RESULTS_SC} ${scale} ${WARMUPS} ${MEASURES} ${NAMESPACE} ${SCRIPT_REPO} ${CLUSTER_TYPE} ${APP_NAME}
	sleep 5
	# ${REPO}/parsemetrics-promql.sh ${TOTAL_ITR} ${RESULTS_SC} ${scale} ${WARMUPS} ${MEASURES} ${SCRIPT_REPO}
	
done

## Cleanup all the deployments
#${REPO}/renaissance-cleanup.sh -c ${CLUSTER_TYPE} -n ${NAMESPACE} >> ${LOGFILE}
sleep 10
echo " "
# Display the Metrics log file
paste ${RESULTS_DIR_ROOT}/Metrics-prom.log ${RESULTS_DIR_ROOT}/Metrics-wrk.log ${RESULTS_DIR_ROOT}/Metrics-config.log ${RESULTS_DIR_ROOT}/deploy-config.log
#paste ${RESULTS_DIR_ROOT}/Metrics-quantiles-prom.log

paste ${RESULTS_DIR_ROOT}/Metrics-prom.log ${RESULTS_DIR_ROOT}/Metrics-wrk.log ${RESULTS_DIR_ROOT}/deploy-config.log > ${RESULTS_DIR_ROOT}/output.csv
