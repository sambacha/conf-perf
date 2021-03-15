#!/bin/bash

bold=$(tput bold)
normal=$(tput sgr0)

while true
do
    echo -e "---------------------------------------------------------------------------------------------------------------"
    echo -e "\n::::::::::${bold} current Nginx Status ${normal}::::::::::\n"

    numberOfActiveConnections=""
    ConnectionDetails=""
    numberOfTotalAcceptedConnections=""
    numberOfTotalhandledConnections=""
    numberOfTotaldroppedConnections=""

    #Number of Requests / Second
    numberOfRequestsPerSecond=""

    nginxURL='http://localhost/status'
    nginxFile="nginx_state"

    curl -s $nginxURL -o $nginxFile

    numberOfActiveConnections=$(cat $nginxFile | awk '/Active /' | awk '{print $3}')
    printf "%-50s %d\n\n" "Active Connections:" $numberOfActiveConnections

    ConnectionDetails=$(cat $nginxFile | grep -E -o 'Reading:\s[0-9]+' | awk '$1 == "Reading:" {print $2}')
    printf "%-50s %d\n" "Reading Connections:" $ConnectionDetails
    ConnectionDetails=$(cat $nginxFile | grep -E -o 'Writing:\s[0-9]+' | awk '$1 == "Writing:" {print $2}')
    printf "%-50s %d\n" "Writing Connections:" $ConnectionDetails
    ConnectionDetails=$(cat $nginxFile | grep -E -o 'Waiting:\s[0-9]+' | awk '$1 == "Waiting:" {print $2}')
    printf "%-50s %d\n\n" "Waiting Connections:" $ConnectionDetails

    numberOfTotalAcceptedConnections=$(cat $nginxFile | grep -A 1 server | tail -1 | awk '{print $1}')
    printf "%-50s %d\n" "Total Accepted Connections:" $numberOfTotalAcceptedConnections
    numberOfTotalhandledConnections=$(cat $nginxFile | grep -A 1 server | tail -1 | awk '{print $2}')
    printf "%-50s %d\n" "Total Handled Connections:" $numberOfTotalhandledConnections
    numberOfTotaldroppedConnections=$(echo 'scale=2;'$numberOfTotalAcceptedConnections-$numberOfTotalhandledConnections | bc -l)
    printf "%-50s %d\n" "Total Dropped Connections:" $numberOfTotaldroppedConnections
    totalRequests=$(cat $nginxFile | grep -A 1 server | tail -1 | awk '{print $3}')
    printf "%-50s %d\n\n" "Total Requests:" $totalRequests

    numberOfRequestsPerSecond=$(echo 'scale=2;'$totalRequests/$numberOfTotalAcceptedConnections | bc -l)
    printf "%-50s %.2f\n" "Currently Server is serving [req/s]:" $numberOfRequestsPerSecond

    echo -e "\n\n::::::::::${bold} current PHP-FPM Status ${normal}::::::::::\n"

    phpURL="http://localhost/fpm-status"
    phpFile="phpfpm_state"

    curl -s $phpURL -o $phpFile
    cat $phpFile
    echo -e "---------------------------------------------------------------------------------------------------------------"

    sleep 10
done
