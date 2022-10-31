#!/bin/bash

# This script checks all RoleTemplates for cyclical dependencies using a Depth First Search algorithm.
# The script will only detect one depedency at a time.
set -ep
function usage {
    echo "This script checks all RoleTemplates for cyclical dependencies using a Depth First Search algorithm."
    echo "Only one cycle will be found each run."
    echo "Script requires bash, jq and tr."
    echo
    echo "options:"
    echo "h     Print this message."
    echo "f     Optionaly read output of 'kubectl get roleTemplate.management.cattle.io -o json' from a file."
    echo
    exit 0
}

TRUE=0
FALSE=1
FILE=""
while getopts "hf:" option; do
    case $option in
    h) # display Help
        usage
        exit 0
        ;;
    f) # read fromo file
        FILE=$OPTARG
        ;;
    esac
done

if [[ ! -z ${FILE} ]]; then
    ALL=$(cat ${FILE})
else
    # Get all RoleTemplates
    ALL=$(kubectl get roleTemplate.management.cattle.io -o json)
fi

# Find non builtin RoleTemplates and their inherited RoleTemplates
roles=$(jq -c '.items | .[]| {(.metadata.name):(.roleTemplateNames)}' <<<${ALL})

# print roles for user
jq -c <<<${roles}

# Create a map of nodes and edges
MAP=$(jq -sc '. | add' <<<${roles})

# init list for tracking state
visted=()
stack=()

# return true if the provided node name was visted
# if node is null we say it was already visited
function wasVisted {
    node_name=${1}
    if [ $node_name == "null" ]; then
        return $TRUE
    fi
    for name in ${visted[@]}; do
        if [[ ${node_name} == ${name} ]]; then
            return $TRUE
        fi
    done
    return $FALSE
}

# return true if the provided node is in the stack
# if node is null we say it is not in the stack
function inStack {
    node_name=${1}
    if [ $node_name == "null" ]; then
        return $FALSE
    fi
    for name in ${stack[@]}; do
        if [[ ${node_name} == ${name} ]]; then
            return $TRUE
        fi
    done
    return $FALSE
}

# remove the provide node from the stack
function removeFromStack {
    node_name=${1}
    i=0
    for name in ${stack[@]}; do
        if [[ ${node_name} == ${name} ]]; then
            unset stack[${i}]
            break
        fi
        i=$((i + 1))
    done
    return 0
}

# recursive function that visits a node and check for cycles
function traverse {
    node_name=${1}
    visted+=(${node_name})
    stack+=(${node_name})

    for edge in $(jq -c ".\"${node_name}\" | @sh" <<<${MAP} | tr -d "'\""); do
        if ! $(wasVisted ${edge}); then
            traverse ${edge}
        elif $(inStack ${edge}); then
            # if the node was already visted and a parent of this node we have a cycle
            # Get RoleTemplate Display names for the user.
            node_display=$(jq -c ".items | map(select(.metadata.name == \"${node_name}\" ))| .[] | .displayName" <<<${ALL})
            edge_display=$(jq -c ".items | map(select(.metadata.name == \"${edge}\" ))| .[] | .displayName" <<<${ALL})
            echo "Cyclic dependency found between ${node_display} (${node_name}) and ${edge_display} ($edge)" 1>&2
            exit 1
        fi
    done
    removeFromStack $node_name

}
# loop over each node and travers if it was not visted.
for node_name in $(jq -c 'keys | @sh' <<<${MAP} | tr -d "'\""); do
    if $(wasVisted ${node_name}); then
        continue
    fi
    traverse ${node_name}
done

echo "No Cycles detected"
exit 0
